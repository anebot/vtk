// A cell-canvas paint example. Drawings are editable, versioned .vtkdraw JSON files.
module main

import json2
import os
import strconv
import vtk

const palette_colors = [0x000000, 0xffffff, 0x808080, 0xc0c0c0, 0xe53935, 0xff8c00, 0xffd114, 0x79c942,
	0x008f48, 0x00c8c8, 0x59adff, 0x2850c8, 0x843dcc, 0xee60a8, 0x8b5028, 0xffc99b]
const palette_names = ['Black', 'White', 'Gray', 'Silver', 'Red', 'Orange', 'Yellow', 'Lime', 'Green',
	'Cyan', 'Sky blue', 'Blue', 'Purple', 'Pink', 'Brown', 'Peach']
const pencil_names = ['Round', 'Square', 'Diamond', 'Horizontal', 'Vertical']

enum PencilShape {
	round
	square
	diamond
	horizontal
	vertical
}

enum Action {
	new_drawing
	open
	save
	save_as
	quit
	undo
	redo
	clear
	color
	grid
	help
	hex_color
	pencil
	eraser
}

struct Point {
	x int
	y int
}

struct Stroke {
	rgb   int
	shape PencilShape
	size  int
	erase bool
mut:
	points []Point
}

struct DrawingFile {
	format  string
	version int
	strokes []Stroke
}

@[heap]
struct Drawing {
mut:
	strokes    []Stroke
	undone     []Stroke
	saved      []Stroke
	path       string
	rgb        int = 0x59adff
	shape      PencilShape
	size       int = 1
	erase      bool
	grid       bool = true
	active     bool
	window     &vtk.Ctl = unsafe { nil }
	canvas     &vtk.Ctl = unsafe { nil }
	pencil     &vtk.Ctl = unsafe { nil }
	width      &vtk.Ctl = unsafe { nil }
	color      &vtk.Ctl = unsafe { nil }
	paint_tool &vtk.Ctl = unsafe { nil }
	eraser     &vtk.Ctl = unsafe { nil }
	status     &vtk.Ctl = unsafe { nil }
}

fn rgb_color(rgb int) int {
	return vtk.color_rgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)
}

fn pencil_cell(shape PencilShape, size int, x int, y int) bool {
	r := size - 1
	return match shape {
		.round { x * x + y * y <= r * r }
		.square { true }
		.diamond { abs(x) + abs(y) <= r }
		.horizontal { y == 0 }
		.vertical { x == 0 }
	}
}

fn abs(n int) int { return if n < 0 { -n } else { n } }

fn erase_cell(mut screen vtk.Screen, c &vtk.Ctl, x int, y int) {
	drawing := unsafe { &Drawing(c.user) }
	glyph := if drawing.grid && y % 3 == 0 {
		`─`
	} else if drawing.grid && x % 5 == 0 {
		`│`
	} else {
		` `
	}
	fg := if glyph == ` ` { vtk.white } else { vtk.gray }
	screen.put(c.x + x, c.y + y, glyph, fg, vtk.color_rgb(13, 15, 20), 0)
}

fn stamp(mut screen vtk.Screen, c &vtk.Ctl, stroke Stroke, x int, y int) {
	r := stroke.size - 1
	color := rgb_color(stroke.rgb)
	for dy in -r .. r + 1 {
		for dx in -r .. r + 1 {
			if pencil_cell(stroke.shape, stroke.size, dx, dy) {
				if stroke.erase {
					erase_cell(mut screen, c, x + dx, y + dy)
				} else {
					screen.put(c.x + x + dx, c.y + y + dy, `█`, color, color, 0)
				}
			}
		}
	}
}

// Interpolate mouse samples so fast drags do not leave holes in a stroke.
fn paint_segment(mut screen vtk.Screen, c &vtk.Ctl, stroke Stroke, from Point, to Point) {
	mut x, mut y := from.x, from.y
	dx, dy := abs(to.x - x), -abs(to.y - y)
	sx, sy := if x < to.x { 1 } else { -1 }, if y < to.y { 1 } else { -1 }
	mut err := dx + dy
	for {
		stamp(mut screen, c, stroke, x, y)
		if x == to.x && y == to.y { break }
		e := 2 * err
		if e >= dy {
			err += dy
			x += sx
		}
		if e <= dx {
			err += dx
			y += sy
		}
	}
}

fn paint(mut c vtk.Ctl, mut screen vtk.Screen) {
	drawing := unsafe { &Drawing(c.user) }
	bg := vtk.color_rgb(13, 15, 20)
	clip := screen.set_clip(c.rect())
	screen.fill(c.rect(), ` `, vtk.white, bg)
	if drawing.grid {
		for x := 0; x < c.w; x += 5 {
			screen.line(c.x + x, c.y, c.x + x, c.y + c.h - 1, `│`, vtk.gray, bg)
		}
		for y := 0; y < c.h; y += 3 {
			screen.line(c.x, c.y + y, c.x + c.w - 1, c.y + y, `─`, vtk.gray, bg)
		}
	}
	for stroke in drawing.strokes {
		for i, point in stroke.points {
			paint_segment(mut screen, c, stroke, if i == 0 { point } else { stroke.points[i - 1] }, point)
		}
	}
	screen.restore_clip(clip)
}

fn paint_palette(mut c vtk.Ctl, mut screen vtk.Screen) {
	drawing := unsafe { &Drawing(c.user) }
	for i, rgb in palette_colors {
		color := rgb_color(rgb)
		x := c.x + i * 4
		screen.fill(vtk.Rect{x, c.y, 3, 1}, `█`, color, color)
		if rgb == drawing.rgb {
			fg := if ((rgb >> 16) & 255) + ((rgb >> 8) & 255) + (rgb & 255) > 380 {
				vtk.black
			} else {
				vtk.bright_white
			}
			screen.put(x, c.y, `[`, fg, color, 0)
			screen.put(x + 2, c.y, `]`, fg, color, 0)
		}
	}
}

fn paint_color(mut c vtk.Ctl, mut screen vtk.Screen) {
	drawing := unsafe { &Drawing(c.user) }
	color := rgb_color(drawing.rgb)
	screen.fill(c.rect(), `█`, color, color)
}

fn update(mut drawing Drawing) {
	name := if drawing.path == '' { '[Untitled]' } else { os.file_name(drawing.path) }
	drawing.window.text = name + (if drawing.strokes != drawing.saved { ' *' } else { '' }) + ' - VTK Draw'
	drawing.pencil.value = int(drawing.shape)
	drawing.width.value = drawing.size
	drawing.color.text = '#${drawing.rgb:06x}'
	drawing.paint_tool.value = int(!drawing.erase)
	drawing.eraser.value = int(drawing.erase)
	tool := if drawing.erase { 'Eraser' } else { pencil_names[int(drawing.shape)] }
	span := drawing.size * 2 - 1
	w := if !drawing.erase && drawing.shape == .vertical { 1 } else { span }
	h := if !drawing.erase && drawing.shape == .horizontal { 1 } else { span }
	drawing.status.text = '${tool} ${w}x${h} | #${drawing.rgb:06x} | ${drawing.strokes.len} strokes | P: paint E: erase; F10 menus'
}

fn mouse(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut drawing := unsafe { &Drawing(c.user) }
	if e.button != .left || !e.pressed {
		drawing.active = false
		return false
	}
	if !e.motion || !drawing.active {
		drawing.strokes << Stroke{
			rgb:   drawing.rgb
			shape: if drawing.erase { .square } else { drawing.shape }
			size:  drawing.size
			erase: drawing.erase
		}
		drawing.undone.clear()
	}
	drawing.active = true
	point := Point{e.x - c.x, e.y - c.y}
	at := drawing.strokes.len - 1
	if drawing.strokes[at].points.len == 0 || drawing.strokes[at].points.last() != point {
		drawing.strokes[at].points << point
	}
	app.set_focus(c)
	update(mut drawing)
	app.dirty = true
	return true
}

fn palette_mouse(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	if e.button != .left || !e.pressed || e.motion { return false }
	at := (e.x - c.x) / 4
	if at < 0 || at >= palette_colors.len || (e.x - c.x) % 4 == 3 { return false }
	mut drawing := unsafe { &Drawing(c.user) }
	drawing.active = false
	drawing.rgb = palette_colors[at]
	update(mut drawing)
	app.set_focus(drawing.canvas)
	app.dirty = true
	return true
}

fn pencil_changed(mut c vtk.Ctl, mut app vtk.App) {
	mut drawing := unsafe { &Drawing(c.user) }
	drawing.active = false
	if c.kind != .spin { drawing.erase = false }
	drawing.shape = unsafe { PencilShape(drawing.pencil.value) }
	drawing.size = drawing.width.value
	update(mut drawing)
	app.dirty = true
}

fn pick_shape(mut c vtk.Ctl, mut app vtk.App) {
	mut drawing := unsafe { &Drawing(c.user) }
	drawing.pencil.value = int(c.data)
	pencil_changed(mut c, mut app)
}

fn pick_color(mut c vtk.Ctl, mut app vtk.App) {
	mut drawing := unsafe { &Drawing(c.user) }
	drawing.active = false
	drawing.rgb = int(c.data)
	update(mut drawing)
	app.dirty = true
}

fn encode_drawing(strokes []Stroke) string {
	// Version 1 remains readable; eraser operations require version 2 readers.
	version := if strokes.any(it.erase) { 2 } else { 1 }
	return json2.encode(DrawingFile{ format: 'vtk-drawing', version: version, strokes: strokes },
		prettify: true
	)
}

fn decode_drawing(text string) ![]Stroke {
	file := json2.decode[DrawingFile](text)!
	if file.format != 'vtk-drawing' || file.version !in [1, 2] {
		return error('Not a supported VTK drawing (expected version 1 or 2).')
	}
	for stroke in file.strokes {
		if stroke.rgb < 0 || stroke.rgb > 0xffffff || stroke.size < 1 || stroke.size > 5 || stroke.points.len == 0 {
			return error('Invalid pencil color, size or empty stroke.')
		}
		for point in stroke.points {
			if point.x < 0 || point.y < 0 || point.x > 10000 || point.y > 10000 {
				return error('Invalid drawing coordinates.')
			}
		}
	}
	return file.strokes
}

fn save(mut drawing Drawing, save_as bool, mut app vtk.App) bool {
	drawing.active = false
	mut path := drawing.path
	if path == '' || save_as {
		initial := if path == '' { 'untitled.vtkdraw' } else { path }
		path = app.prompt_for(drawing.window, 'Save drawing', 'File path (.vtkdraw):', initial) or { return false }
	}
	if path.trim_space() == '' { return false }
	if path != drawing.path && os.exists(path) {
		if !app.confirm_for(drawing.window, 'Replace file', 'Replace ${path}?') { return false }
	}
	os.write_file(path, encode_drawing(drawing.strokes)) or {
		app.msgbox_for(drawing.window, 'Cannot save drawing', err.msg())
		return false
	}
	drawing.path = path
	// Finished strokes are immutable; only a new stroke can receive more points.
	drawing.saved = drawing.strokes.clone()
	update(mut drawing)
	app.notify('Saved ${path}', 1500)
	return true
}

fn may_discard(mut drawing Drawing, mut app vtk.App) bool {
	drawing.active = false
	if drawing.strokes == drawing.saved { return true }
	choice := app.choice_for(drawing.window, 'Unsaved drawing', ['Save', 'Discard', 'Cancel'], 3)
	if choice == 0 { return save(mut drawing, false, mut app) }
	return choice == 1
}

fn closing(mut w vtk.Ctl, mut app vtk.App) bool {
	mut drawing := unsafe { &Drawing(w.user) }
	return may_discard(mut drawing, mut app)
}

fn open_drawing(mut drawing Drawing, path string, mut app vtk.App) bool {
	text := os.read_file(path) or {
		app.msgbox_for(drawing.window, 'Cannot open drawing', err.msg())
		return false
	}
	mut strokes := decode_drawing(text) or {
		app.msgbox_for(drawing.window, 'Cannot open drawing', err.msg())
		return false
	}
	was_dirty := drawing.strokes != drawing.saved
	if !may_discard(mut drawing, mut app) { return false }
	// Saving in the prompt may have updated the file we are about to reopen.
	if was_dirty && drawing.strokes == drawing.saved && drawing.path != '' && os.abs_path(path) == os.abs_path(drawing.path) {
		strokes = drawing.saved.clone()
	}
	drawing.strokes = strokes
	drawing.saved = strokes.clone()
	drawing.undone.clear()
	drawing.path = path
	update(mut drawing)
	app.dirty = true
	return true
}

fn action(mut c vtk.Ctl, mut app vtk.App) {
	mut drawing := unsafe { &Drawing(c.user) }
	drawing.active = false
	match unsafe { Action(c.data) } {
		.new_drawing {
			if may_discard(mut drawing, mut app) {
				drawing.strokes.clear()
				drawing.saved.clear()
				drawing.undone.clear()
				drawing.path = ''
			}
		}
		.open {
			directory := if drawing.path == '' { '.' } else { os.dir(drawing.path) }
			if path := app.file_pick_for(drawing.window, directory) {
				open_drawing(mut drawing, path, mut app)
			}
		}
		.save { save(mut drawing, false, mut app) }
		.save_as { save(mut drawing, true, mut app) }
		.quit { app.quit() }
		.undo {
			if drawing.strokes.len > 0 { drawing.undone << drawing.strokes.pop() }
		}
		.redo {
			if drawing.undone.len > 0 { drawing.strokes << drawing.undone.pop() }
		}
		.clear {
			if drawing.strokes.len > 0 && app.confirm_for(drawing.window, 'Clear canvas', 'Clear all strokes?') {
				drawing.strokes.clear()
				drawing.undone.clear()
			}
		}
		.color {
			if rgb := app.color_pick(drawing.window, 'Pencil RGB color', drawing.rgb) {
				drawing.rgb = rgb
			}
		}
		.hex_color {
			if text := app.prompt_for(drawing.window, 'Pencil RGB color', 'RGB hex (RRGGBB):', '${drawing.rgb:06x}') {
				hex := text.trim_space().trim_string_left('#')
				if hex.len != 6 {
					app.msgbox_for(drawing.window, 'Invalid color', 'Enter six hex digits, for example ff8800.')
				} else {
					rgb := strconv.parse_uint(hex, 16, 32) or {
						app.msgbox_for(drawing.window, 'Invalid color', 'Enter six hex digits, for example ff8800.')
						return
					}
					drawing.rgb = int(rgb)
				}
			}
		}
		.grid { drawing.grid = !drawing.grid }
		.pencil { drawing.erase = false }
		.eraser { drawing.erase = true }
		.help {
			app.msgbox_for(drawing.window, 'Drawing help', 'Drag the left mouse button to paint or erase.\nP: Paint; E: Eraser (also on the toolbar/Pencil menu).\nChoose a shape and size (1-5); size 1 is one cell.\nClick a palette swatch or RGB... for a custom color.\nClick the #RRGGBB button to enter an exact color.\nFile saves editable .vtkdraw drawings, including erasing.\nCtrl-N/O/S: New / Open / Save; Ctrl-Shift-S: Save as.\nCtrl-Z/Y: Undo / Redo stroke; Ctrl-Q: Quit.\nF10 opens menus; arrows and Enter select items.\nView toggles the grid; resize/maximize for more space.')
		}
	}
	update(mut drawing)
	app.set_focus(drawing.canvas)
	app.dirty = true
}

fn key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	code := if e.key >= int(`A`) && e.key <= int(`Z`) { e.key + 32 } else { e.key }
	if !e.ctrl && !e.alt && code in [int(`p`), int(`e`)] {
		id := if code == int(`e`) { Action.eraser } else { Action.pencil }
		mut trigger := vtk.Ctl{ user: c.user, data: i64(id) }
		action(mut trigger, mut app)
		return true
	}
	if e.key == int(vtk.Key.f1) {
		mut trigger := vtk.Ctl{ user: c.user, data: i64(Action.help) }
		action(mut trigger, mut app)
		return true
	}
	if !e.ctrl { return false }
	id := match code {
		int(`n`) { Action.new_drawing }
		int(`o`) { Action.open }
		int(`s`) {
			if e.shift { Action.save_as } else { Action.save }
		}
		int(`q`) { Action.quit }
		int(`z`) {
			if e.shift { Action.redo } else { Action.undo }
		}
		int(`y`) { Action.redo }
		else { return false }
	}
	mut trigger := vtk.Ctl{ user: c.user, data: i64(id) }
	action(mut trigger, mut app)
	return true
}

fn menu_item(mut menu vtk.Ctl, drawing &Drawing, title string, id Action) {
	mut item := menu.menu_item(title, action)
	item.user = drawing
	item.data = i64(id)
}

fn new_drawing(mut app vtk.App) &Drawing {
	mut drawing := &Drawing{}
	drawing.window = app.window('VTK Draw', 78, 23)
	drawing.window.y = 0
	drawing.window.user = drawing
	drawing.window.closing = closing
	drawing.window.keyfn = key
	mut file := drawing.window.add_menu('File')
	menu_item(mut file, drawing, 'New       Ctrl-N', .new_drawing)
	menu_item(mut file, drawing, 'Open...   Ctrl-O', .open)
	menu_item(mut file, drawing, 'Save      Ctrl-S', .save)
	menu_item(mut file, drawing, 'Save as... Ctrl-Shift-S', .save_as)
	file.menu_separator()
	menu_item(mut file, drawing, 'Quit      Ctrl-Q', .quit)
	mut edit := drawing.window.add_menu('Edit')
	menu_item(mut edit, drawing, 'Undo stroke   Ctrl-Z', .undo)
	menu_item(mut edit, drawing, 'Redo stroke   Ctrl-Y', .redo)
	edit.menu_separator()
	menu_item(mut edit, drawing, 'Clear canvas...', .clear)
	mut pencil := drawing.window.add_menu('Pencil')
	for i, name in pencil_names {
		mut item := pencil.menu_item(name, pick_shape)
		item.user = drawing
		item.data = i
	}
	pencil.menu_separator()
	menu_item(mut pencil, drawing, 'Paint    P', .pencil)
	menu_item(mut pencil, drawing, 'Eraser   E', .eraser)
	mut color := drawing.window.add_menu('Color')
	menu_item(mut color, drawing, 'RGB picker...', .color)
	menu_item(mut color, drawing, 'RGB hex...', .hex_color)
	color.menu_separator()
	for i, name in palette_names {
		mut item := color.menu_item('${name}  #${palette_colors[i]:06x}', pick_color)
		item.user = drawing
		item.data = palette_colors[i]
	}
	mut view := drawing.window.add_menu('View')
	menu_item(mut view, drawing, 'Show / hide grid', .grid)
	mut help := drawing.window.add_menu('Help')
	menu_item(mut help, drawing, 'Drawing help   F1', .help)
	mut body := vtk.box(true)
	mut bar := vtk.toolbar()
	for i, name in ['New', 'Open', 'Save', 'Save as', 'Quit', 'Undo', 'Redo', 'Clear'] {
		mut button := vtk.toolbutton(name)
		button.user = drawing
		button.changed = action
		button.keyfn = key
		button.data = i
		bar.add(mut button)
	}
	drawing.paint_tool = vtk.toolbutton('Paint')
	drawing.paint_tool.user = drawing
	drawing.paint_tool.changed = action
	drawing.paint_tool.keyfn = key
	drawing.paint_tool.data = i64(Action.pencil)
	bar.add(mut drawing.paint_tool)
	drawing.eraser = vtk.toolbutton('Eraser')
	drawing.eraser.user = drawing
	drawing.eraser.changed = action
	drawing.eraser.keyfn = key
	drawing.eraser.data = i64(Action.eraser)
	bar.add(mut drawing.eraser)
	body.add(mut bar)
	mut tools := vtk.toolbar()
	mut pencil_label := vtk.label('Pencil:')
	tools.add(mut pencil_label)
	drawing.pencil = vtk.combo()
	for name in pencil_names { drawing.pencil.add_item(name) }
	drawing.pencil.user = drawing
	drawing.pencil.changed = pencil_changed
	drawing.pencil.keyfn = key
	tools.add(mut drawing.pencil)
	mut size_label := vtk.label('Size:')
	tools.add(mut size_label)
	drawing.width = vtk.spin(1, 5)
	drawing.width.user = drawing
	drawing.width.changed = pencil_changed
	drawing.width.keyfn = key
	tools.add(mut drawing.width)
	mut picker := vtk.toolbutton('RGB...')
	picker.user = drawing
	picker.data = i64(Action.color)
	picker.changed = action
	picker.keyfn = key
	tools.add(mut picker)
	mut preview := vtk.canvas(3, 1, paint_color)
	preview.user = drawing
	tools.add(mut preview)
	drawing.color = vtk.toolbutton('')
	drawing.color.user = drawing
	drawing.color.data = i64(Action.hex_color)
	drawing.color.changed = action
	drawing.color.keyfn = key
	tools.add(mut drawing.color)
	body.add(mut tools)
	mut colors := vtk.box(false)
	mut palette_label := vtk.label('Palette:')
	colors.add(mut palette_label)
	mut palette := vtk.canvas(palette_colors.len * 4 - 1, 1, paint_palette)
	palette.user = drawing
	palette.mousefn = palette_mouse
	colors.add(mut palette)
	body.add(mut colors)
	drawing.canvas = vtk.canvas(64, 8, paint)
	drawing.canvas.expand = true
	drawing.canvas.focusable = true
	drawing.canvas.user = drawing
	drawing.canvas.mousefn = mouse
	drawing.canvas.keyfn = key
	body.add(mut drawing.canvas)
	drawing.status = vtk.statusbar('')
	body.add(mut drawing.status)
	drawing.window.add(mut body)
	update(mut drawing)
	app.set_focus(drawing.canvas)
	return drawing
}

fn main() {
	mut app := vtk.new_app()
	mut drawing := new_drawing(mut app)
	app.init() or {
		eprintln(err)
		return
	}
	defer { app.fini() }
	if os.args.len > 1 { open_drawing(mut drawing, os.args[1], mut app) }
	app.run() or { eprintln(err) }
}
