// VTK Slides: a Markdown presentation editor with slide previews, templates,
// full-screen presenting, and drawable shapes/charts/images inside Markdown.
module slides

import math
import os
import vtk
import vtk.app.programs.common

const app_name = 'VtkSlides'

const app_version = '0.1.0'

const thumbnail_height = 12

const default_sidebar_share = 260

enum SlideAction {
	new_slide
	open
	save
	save_as
	quit
	clone_slide
	delete_slide
	move_up
	move_down
	toggle_sidebar
	toggle_notes
	source
	settings
	present
	present_start
	bold
	italic
	code
	strike
	font
	image
	chart_columns
	chart_bars
	chart_lines
	shape_rect
	shape_line
	shape_circle
	table
	bullet
	heading
	undo
	redo
	help
	about
}

struct TemplatePicker {
mut:
	picked int      = -1
}

struct SettingsDialog {
mut:
	deck   &Deck @[required]
	window &vtk.Ctl @[required]
	radio  &vtk.Ctl @[required]
}

fn (mut deck Deck) select(index int, mut app vtk.App) {
	if deck.slides.len == 0 {
		return
	}
	deck.current = vtk.clamp(index, 0, deck.slides.len - 1)
	deck.editor.set_text(deck.slides[deck.current].body)
	deck.editor.cursor = 0
	deck.editor.anchor = -1
	deck.editor.top = 0
	deck.editor.markdown_mode(if deck.source { .source } else { .edit })
	deck.notes.set_text(deck.slides[deck.current].notes)
	deck.notes.cursor = 0
	deck.notes.anchor = -1
	deck.notes.top = 0
	deck.refresh()
	app.set_focus(deck.editor)
	app.invalidate()
}

fn (mut deck Deck) refresh() {
	name := if deck.path == '' { '[Untitled]' } else { os.file_name(deck.path) }
	deck.window.set_text('${name}${if deck.dirty { ' *' } else { '' }} - VTK Slides')
	if deck.current < 0 || deck.current >= deck.slides.len {
		deck.status.set_text('No slides')
		return
	}
	slide := deck.slides[deck.current]
	mode := if deck.source { 'Source' } else { 'Edit' }
	sidebar := if deck.sidebar_visible { 'Sidebar' } else { 'No sidebar' }
	notes := if slide.notes.trim_space() == '' { '' } else { ' · notes' }
	notes_view := if deck.notes_visible { 'Notes' } else { 'No notes' }
	deck.status.set_text('Slide ${deck.current + 1}/${deck.slides.len} · ${plain_title(slide.body)} · ${slide.body.len} bytes${notes} · ${mode} · ${sidebar} · ${notes_view} · F5 present')
}

fn (mut deck Deck) rebuild_thumbnails(mut app vtk.App) {
	for mut thumb in deck.thumbnails {
		app.destroy_ctl(mut thumb)
	}
	deck.thumbnails = []
	deck.sidebar_list.clear()
	for slide in deck.slides {
		mut thumb := vtk.canvas(20, thumbnail_height, paint_thumbnail)
		thumb.set_context(&deck)
		thumb.data = i64(slide.id)
		thumb.min_w = 12
		thumb.min_h = thumbnail_height
		thumb.focusable = false
		thumb.mousefn = thumbnail_mouse
		deck.sidebar_list.add(mut thumb)
		deck.thumbnails << thumb
	}
	deck.sidebar_list.measure()
	app.invalidate()
}

fn thumbnail_mouse(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut deck := c.context[Deck]() or { return false }
	if e.button != .left {
		return false
	}
	index := find_slide(deck, int(c.data))
	if index < 0 {
		return false
	}
	if e.pressed && !e.motion {
		deck.drag_id = int(c.data)
		deck.drag_from = index
		deck.drag_to = index
		deck.select(index, mut app)
		return true
	}
	if e.pressed && e.motion && deck.drag_id >= 0 {
		for thumb in deck.thumbnails {
			if thumb.rect().contains(e.x, e.y) {
				deck.drag_to = find_slide(deck, int(thumb.data))
				break
			}
		}
		app.invalidate()
		return true
	}
	if !e.pressed {
		from := deck.drag_from
		to := deck.drag_to
		deck.drag_id = -1
		deck.drag_from = -1
		deck.drag_to = -1
		if from >= 0 && to >= 0 && from != to && from < deck.slides.len {
			slide := deck.slides[from]
			deck.slides.delete(from)
			deck.slides.insert(vtk.clamp(to, 0, deck.slides.len), slide)
			deck.current = vtk.clamp(to, 0, deck.slides.len - 1)
			deck.dirty = true
			deck.rebuild_thumbnails(mut app)
			deck.refresh()
		}
		app.invalidate()
		return true
	}
	return false
}

fn notes_changed(mut c vtk.Ctl, mut app vtk.App) {
	mut deck := c.context[Deck]() or { return }
	if deck.current >= 0 && deck.current < deck.slides.len {
		deck.slides[deck.current].notes = c.text
		deck.dirty = true
		deck.refresh()
	}
	app.invalidate()
}

fn editor_changed(mut c vtk.Ctl, mut app vtk.App) {
	mut deck := c.context[Deck]() or { return }
	if deck.current >= 0 && deck.current < deck.slides.len {
		deck.slides[deck.current].body = c.text
		deck.dirty = true
		deck.refresh()
		for thumb in deck.thumbnails {
			thumb.invalidate()
		}
	}
	app.invalidate()
}

fn closing(mut w vtk.Ctl, mut app vtk.App) bool {
	mut deck := w.context[Deck]() or { return true }
	if !deck.dirty {
		return true
	}
	return match common.ask_unsaved(mut app, w, 'Unsaved slides') {
		.save { deck.save(false, mut app) }
		.discard { true }
		.cancel { false }
	}
}

fn (mut deck Deck) insert_slide(body string, notes string, at int, mut app vtk.App) {
	index := vtk.clamp(at, 0, deck.slides.len)
	deck.slides.insert(index, Slide{
		id:    deck.next_id
		body:  body
		notes: notes
	})
	deck.next_id++
	deck.current = index
	deck.dirty = true
	deck.rebuild_thumbnails(mut app)
	deck.select(index, mut app)
}

fn (mut deck Deck) clone_slide(mut app vtk.App) {
	if deck.current < 0 || deck.current >= deck.slides.len {
		return
	}
	slide := deck.slides[deck.current]
	deck.insert_slide(slide.body, slide.notes, deck.current + 1, mut app)
	app.notify('Cloned slide', 1200)
}

fn (mut deck Deck) delete_slide(mut app vtk.App) {
	if deck.slides.len <= 1 {
		app.notify('A deck needs at least one slide', 1800)
		return
	}
	if deck.current < 0 || deck.current >= deck.slides.len {
		return
	}
	if !app.confirm_for(deck.window, 'Delete slide', 'Delete slide ${deck.current + 1}?') {
		return
	}
	deck.slides.delete(deck.current)
	deck.current = vtk.clamp(deck.current, 0, deck.slides.len - 1)
	deck.dirty = true
	deck.rebuild_thumbnails(mut app)
	deck.select(deck.current, mut app)
}

fn (mut deck Deck) move(delta int, mut app vtk.App) {
	target := deck.current + delta
	if deck.current < 0 || target < 0 || target >= deck.slides.len {
		return
	}
	slide := deck.slides[deck.current]
	deck.slides.delete(deck.current)
	deck.slides.insert(target, slide)
	deck.current = target
	deck.dirty = true
	deck.rebuild_thumbnails(mut app)
	deck.refresh()
	app.invalidate()
}

fn insert_text(mut deck Deck, text string, mut app vtk.App) {
	if deck.editor.readonly {
		app.notify('Switch to an editable mode first', 1800)
		return
	}
	deck.editor.replace_selection(text)
	deck.editor.invalidate()
	app.set_focus(deck.editor)
	app.invalidate()
}

fn insert_block(mut deck Deck, text string, mut app vtk.App) {
	a, _ := deck.editor.selection()
	before := if a == 0 { '' } else { deck.editor.text[a - 1..a] }
	prefix := if before == '' || before == '\n' { '' } else { '\n' }
	insert_text(mut deck, prefix + text + '\n', mut app)
}

fn wrap_selection(mut deck Deck, prefix string, suffix string, mut app vtk.App) {
	a, b := deck.editor.selection()
	if a == b {
		app.notify('Select text first', 1500)
		app.set_focus(deck.editor)
		return
	}
	text := deck.editor.text[a..b]
	deck.editor.replace_range(a, b, prefix + text + suffix)
	deck.editor.cursor = a + prefix.len + text.len
	app.set_focus(deck.editor)
	app.invalidate()
}

fn choose_font(mut deck Deck, mut app vtk.App) {
	a, b := deck.editor.selection()
	if a == b {
		app.notify('Select text to restyle', 1600)
		app.set_focus(deck.editor)
		return
	}
	style := common.pick_font_style(mut app, deck.window) or { return }
	if style == .underline {
		wrap_selection(mut deck, '<u>', '</u>', mut app)
	} else if style == .strikethrough {
		wrap_selection(mut deck, '~~', '~~', mut app)
	} else {
		text := deck.editor.text[a..b]
		deck.editor.replace_range(a, b, vtk.font_convert(text, style))
		deck.editor.cursor = a + vtk.font_convert(text, style).len
		app.set_focus(deck.editor)
		app.invalidate()
	}
}

fn stored_image_path(deck &Deck, path string) string {
	if deck.path == '' {
		return path
	}
	directory := os.dir(os.abs_path(deck.path))
	absolute := os.abs_path(path)
	prefix := directory + os.path_separator
	if absolute.starts_with(prefix) {
		return absolute[prefix.len..]
	}
	return path
}

fn insert_image(mut deck Deck, mut app vtk.App) {
	directory := if deck.path == '' { os.getwd() } else { os.dir(deck.path) }
	path := app.file_pick_for(deck.window, directory) or { return }
	alt := app.prompt_for(deck.window, 'Image caption', 'Caption (optional):', '') or { '' }
	stored := stored_image_path(deck, path)
	insert_block(mut deck, '![${alt}](${stored})', mut app)
}

fn insert_chart(mut deck Deck, kind string, mut app vtk.App) {
	block := '```chart ${kind}|Chart title\n|A|B|C\nSeries 1|10|20|15\nSeries 2|8|14|18\n```'
	insert_block(mut deck, block, mut app)
}

fn insert_shape(mut deck Deck, kind string, mut app vtk.App) {
	label, initial := match kind {
		'rect' { 'Rectangle: x y width height (percent)', '10 10 40 30' }
		'line' { 'Line: x1 y1 x2 y2 (percent)', '10 80 90 80' }
		else { 'Circle: center x, center y, radius (percent)', '75 25 10' }
	}
	spec := app.prompt_for(deck.window, 'Insert shape', '${label}:', initial) or { return }
	fields := spec.trim_space().fields()
	if fields.len < 3 {
		app.notify('Enter shape coordinates', 1800)
		return
	}
	rgb := app.color_pick(deck.window, 'Shape color', 0x59adff) or { return }
	color := '#${rgb:06x}'
	directive := match kind {
		'rect' {
			if fields.len < 4 { return }
			'rect ${fields[0]} ${fields[1]} ${fields[2]} ${fields[3]} ${color}'
		}
		'line' {
			if fields.len < 4 { return }
			'line ${fields[0]} ${fields[1]} ${fields[2]} ${fields[3]} ${color}'
		}
		else { 'circle ${fields[0]} ${fields[1]} ${fields[2]} ${color}' }
	}
	insert_block(mut deck, '```slide\n${directive}\n```', mut app)
}

fn new_slide_dialog(mut deck Deck, mut app vtk.App) {
	picker := &TemplatePicker{}
	mut body := vtk.box(true)
	mut heading := vtk.label('Choose a template for the new slide:')
	body.add(mut heading)
	mut grid := vtk.grid()
	items := templates()
	for i, item in items {
		mut button := vtk.button(item.name)
		button.set_context(picker)
		button.data = i64(i)
		button.changed = template_pick
		button.col = i % 2
		button.row = i / 2
		grid.add(mut button)
	}
	body.add(mut grid)
	mut row := vtk.button_bar()
	mut cancel := vtk.button('Cancel')
	cancel.changed = template_cancel
	row.add(mut cancel)
	body.add(mut row)
	mut window := app.dialog('New slide', mut body)
	app.modal_for(mut window, deck.window)
	picked := picker.picked
	app.destroy_ctl(mut window)
	if picked >= 0 && picked < items.len {
		deck.insert_slide(items[picked].body, '', deck.current + 1, mut app)
	}
}

fn template_pick(mut c vtk.Ctl, mut app vtk.App) {
	mut picker := c.context[TemplatePicker]() or { return }
	picker.picked = int(c.data)
	mut window := c.owner_window() or { return }
	app.close(mut window)
}

fn template_cancel(mut c vtk.Ctl, mut app vtk.App) {
	mut window := c.owner_window() or { return }
	app.close(mut window)
}

fn settings_ok(mut c vtk.Ctl, mut app vtk.App) {
	mut dialog := c.context[SettingsDialog]() or { return }
	dialog.deck.transition = SlideTransition.from(dialog.radio.value) or { return }
	save_prefs(dialog.deck)
	dialog.deck.refresh()
	app.close(mut dialog.window)
}

fn settings_cancel(mut c vtk.Ctl, mut app vtk.App) {
	mut dialog := c.context[SettingsDialog]() or { return }
	app.close(mut dialog.window)
}

fn settings_dialog(mut deck Deck, mut app vtk.App) {
	mut body := vtk.box(true)
	mut heading := vtk.label('Presentation transition')
	body.add(mut heading)
	mut radio := vtk.radio()
	for name in transition_names() {
		radio.add_item(name)
	}
	radio.value = int(deck.transition)
	body.add(mut radio)
	mut hint := vtk.label('Current: ${transition_label(deck.transition)}. Used when moving between slides in presentation mode.')
	body.add(mut hint)
	mut row := vtk.button_bar()
	mut ok := vtk.button(' OK ')
	mut cancel := vtk.button('Cancel')
	row.add(mut ok)
	row.add(mut cancel)
	body.add(mut row)
	mut window := app.dialog('Slides settings', mut body)
	dialog := &SettingsDialog{
		deck:   &deck
		window: window
		radio:  radio
	}
	ok.set_context(dialog)
	ok.changed = settings_ok
	cancel.set_context(dialog)
	cancel.changed = settings_cancel
	app.set_default_button(mut window, ok)
	app.set_focus(radio)
	app.modal_for(mut window, deck.window)
	app.destroy_ctl(mut window)
}

fn (mut deck Deck) toggle_sidebar(mut app vtk.App) {
	deck.sidebar_visible = !deck.sidebar_visible
	deck.sidebar_pane.hidden = !deck.sidebar_visible
	if !deck.sidebar_visible {
		app.set_focus(deck.editor)
	}
	deck.refresh()
	app.invalidate()
}

fn (mut deck Deck) toggle_notes(mut app vtk.App) {
	deck.notes_visible = !deck.notes_visible
	deck.notes_sep.hidden = !deck.notes_visible
	deck.notes.hidden = !deck.notes_visible
	if !deck.notes_visible {
		app.set_focus(deck.editor)
	}
	deck.refresh()
	app.invalidate()
}

fn (mut deck Deck) toggle_source(mut app vtk.App) {
	deck.source = !deck.source
	deck.editor.markdown_mode(if deck.source { .source } else { .edit })
	deck.refresh()
	app.set_focus(deck.editor)
	app.invalidate()
}

fn window_key(mut w vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut deck := w.context[Deck]() or { return false }
	if e.key == int(vtk.Key.f5) {
		deck.action(if e.shift { .present_start } else { .present }, mut app)
		return true
	}
	if e.key == int(vtk.Key.f9) {
		deck.action(.toggle_sidebar, mut app)
		return true
	}
	if !e.ctrl || e.alt {
		return false
	}
	action := match e.key {
		`n` {
			if e.shift { SlideAction.toggle_notes } else { SlideAction.new_slide }
		}
		`o` { SlideAction.open }
		`s` {
			if e.shift { SlideAction.save_as } else { SlideAction.save }
		}
		`q` { SlideAction.quit }
		`d` {
			if e.shift { SlideAction.delete_slide } else { SlideAction.clone_slide }
		}
		`e` { SlideAction.source }
		`,` { SlideAction.settings }
		else { return false }
	}
	deck.action(action, mut app)
	return true
}

fn editor_key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut deck := c.context[Deck]() or { return false }
	if e.key == int(vtk.Key.f5) {
		deck.action(if e.shift { .present_start } else { .present }, mut app)
		return true
	}
	if e.key == int(vtk.Key.f9) {
		deck.action(.toggle_sidebar, mut app)
		return true
	}
	if !e.ctrl || e.alt {
		return false
	}
	action := match e.key {
		`n` {
			if e.shift { SlideAction.toggle_notes } else { SlideAction.new_slide }
		}
		`o` { SlideAction.open }
		`s` {
			if e.shift { SlideAction.save_as } else { SlideAction.save }
		}
		`q` { SlideAction.quit }
		`d` {
			if e.shift { SlideAction.delete_slide } else { SlideAction.clone_slide }
		}
		`b` { SlideAction.bold }
		`i` { SlideAction.italic }
		`k` { SlideAction.code }
		`e` { SlideAction.source }
		`,` { SlideAction.settings }
		`z` { SlideAction.undo }
		`y` { SlideAction.redo }
		else { return false }
	}
	deck.action(action, mut app)
	return true
}

fn menu_item(mut menu vtk.Ctl, deck &Deck, title string, action SlideAction) {
	mut item := menu.menu_item(title, deck_action)
	item.set_context(deck)
	item.data = i64(action)
}

fn add_action_button(mut parent vtk.Ctl, deck &Deck, title string, action SlideAction) {
	mut button := vtk.toolbutton(title)
	button.set_context(deck)
	button.data = i64(action)
	button.changed = deck_action
	parent.add(mut button)
}

fn deck_action(mut c vtk.Ctl, mut app vtk.App) {
	mut deck := c.context[Deck]() or { return }
	cmd := SlideAction.from(c.data) or { return }
	deck.action(cmd, mut app)
}

fn (mut deck Deck) action(action SlideAction, mut app vtk.App) {
	match action {
		.new_slide { new_slide_dialog(mut deck, mut app) }
		.open { deck.open(mut app) }
		.save { deck.save(false, mut app) }
		.save_as { deck.save(true, mut app) }
		.quit {
			app.close(mut deck.window)
			return
		}
		.clone_slide { deck.clone_slide(mut app) }
		.delete_slide { deck.delete_slide(mut app) }
		.move_up { deck.move(-1, mut app) }
		.move_down { deck.move(1, mut app) }
		.toggle_sidebar { deck.toggle_sidebar(mut app) }
		.toggle_notes { deck.toggle_notes(mut app) }
		.source { deck.toggle_source(mut app) }
		.settings { settings_dialog(mut deck, mut app) }
		.present { present_slide(mut deck, deck.current, mut app) }
		.present_start { present_slide(mut deck, 0, mut app) }
		.bold { wrap_selection(mut deck, '**', '**', mut app) }
		.italic { wrap_selection(mut deck, '*', '*', mut app) }
		.code { wrap_selection(mut deck, '`', '`', mut app) }
		.strike { wrap_selection(mut deck, '~~', '~~', mut app) }
		.font { choose_font(mut deck, mut app) }
		.image { insert_image(mut deck, mut app) }
		.chart_columns { insert_chart(mut deck, 'columns', mut app) }
		.chart_bars { insert_chart(mut deck, 'bars', mut app) }
		.chart_lines { insert_chart(mut deck, 'lines', mut app) }
		.shape_rect { insert_shape(mut deck, 'rect', mut app) }
		.shape_line { insert_shape(mut deck, 'line', mut app) }
		.shape_circle { insert_shape(mut deck, 'circle', mut app) }
		.table {
			insert_block(mut deck, '| Column | Column | Column |\n|---|---|---|\n| Cell | Cell | Cell |',
				mut app)
		}
		.bullet { insert_block(mut deck, '- New point', mut app) }
		.heading { insert_block(mut deck, '## New heading', mut app) }
		.undo {
			deck.editor.undo()
			app.invalidate()
		}
		.redo {
			deck.editor.redo()
			app.invalidate()
		}
		.about { app.about_for(deck.window, app_name, app_version) }
		.help {
			app.msgbox_for(deck.window, 'VTK Slides',
				'Edit slides as Markdown. **bold**, *italic*, `code`, lists, tables and images are rendered in previews and presentations.\n\nShape blocks:\n```slide\nrect 10 10 40 30 #59adff\nline 10 80 90 80 #ffd114\ncircle 75 25 10 #79c942\n```\n\nCoordinates are percentages of the slide. Shapes accept #rrggbb or named colors.\n\nChart blocks:\n```chart columns|Revenue\n|Q1|Q2|Q3|Q4\nRevenue|12|18|15|24\nPlan|10|14|18|20\n```\n\nImages are Markdown image links: ![caption](image.png). PNG and JPEG are decoded.\n\nDecks save as Markdown separated by <!-- slide -->. Speaker notes live below the slide editor and are saved in hidden HTML comments, so they never appear in previews or presentations. File > Settings chooses the presentation transition: none, slide (direction follows next/previous), or fade out/in. F5 presents, F9 toggles the sidebar, Ctrl-E shows source, Ctrl-Shift-N toggles notes.')
		}
	}
	deck.refresh()
	app.invalidate()
}

fn new_deck_state(window &vtk.Ctl) &Deck {
	return &Deck{
		window: window
		sidebar_pane: vtk.box(true)
		sidebar: vtk.scroll()
		sidebar_list: vtk.box(true)
		editor: vtk.markdown('')
		notes_sep: vtk.separator()
		notes: vtk.multiline('')
		status: vtk.statusbar('')
	}
}

fn new_deck(mut app vtk.App, path string) {
	transition := load_prefs()
	slides := if path == '' {
		demo_deck()
	} else {
		text := os.read_file(path) or {
			app.notify(err.msg(), 3000)
			return
		}
		parse_deck(text)
	}
	width, height := app.size()
	mut deck := new_deck_state(app.window('VTK Slides', if width > 20 { width } else { 100 },
		if height > 10 { height - 1 } else { 30 }))
	deck.slides = slides
	deck.path = path
	deck.transition = transition
	for slide in slides {
		deck.next_id = math.max(deck.next_id, slide.id + 1)
	}
	deck.window.set_context(deck)
	deck.window.closing = closing
	deck.window.keyfn = window_key
	mut body := vtk.box(true)
	mut toolbar := vtk.toolbar()
	add_action_button(mut toolbar, deck, '+ Slide', .new_slide)
	add_action_button(mut toolbar, deck, 'Clone', .clone_slide)
	add_action_button(mut toolbar, deck, 'Delete', .delete_slide)
	add_action_button(mut toolbar, deck, '↑', .move_up)
	add_action_button(mut toolbar, deck, '↓', .move_down)
	add_action_button(mut toolbar, deck, 'Present', .present)
	add_action_button(mut toolbar, deck, 'Sidebar', .toggle_sidebar)
	add_action_button(mut toolbar, deck, 'Notes', .toggle_notes)
	add_action_button(mut toolbar, deck, 'Source', .source)
	body.add(mut toolbar)
	mut split := vtk.split(false, default_sidebar_share)
	split.resizable = true
	deck.sidebar_pane.min_w = 14
	mut sidebar_tools := vtk.flow()
	add_action_button(mut sidebar_tools, deck, '+', .new_slide)
	add_action_button(mut sidebar_tools, deck, '⧉', .clone_slide)
	add_action_button(mut sidebar_tools, deck, '✕', .delete_slide)
	add_action_button(mut sidebar_tools, deck, '↑', .move_up)
	add_action_button(mut sidebar_tools, deck, '↓', .move_down)
	deck.sidebar_pane.add(mut sidebar_tools)
	deck.sidebar.scrollbar = true
	deck.sidebar.add(mut deck.sidebar_list)
	deck.sidebar_pane.add(mut deck.sidebar)
	split.add(mut deck.sidebar_pane)
	deck.editor.set_context(deck)
	deck.editor.changed = editor_changed
	deck.editor.keyfn = editor_key
	deck.editor.scrollbar = true
	deck.editor.line_numbers = true
	deck.editor.md.hide_status = true
	deck.editor.set_wrap_mode(.word)
	deck.editor.markdown_mode(.edit)
	mut editor_pane := vtk.box(true)
	editor_pane.add(mut deck.editor)
	editor_pane.add(mut deck.notes_sep)
	deck.notes.set_context(deck)
	deck.notes.changed = notes_changed
	deck.notes.expand = false
	deck.notes.min_h = 4
	deck.notes.scrollbar = true
	deck.notes.set_wrap_mode(.word)
	deck.notes.padding = vtk.Insets{ left: 1, right: 1 }
	editor_pane.add(mut deck.notes)
	split.add(mut editor_pane)
	body.add(mut split)
	body.add(mut deck.status)
	deck.window.add(mut body)
	mut file := deck.window.add_menu('File')
	menu_item(mut file, deck, 'New slide   Ctrl-N', .new_slide)
	menu_item(mut file, deck, 'Open...   Ctrl-O', .open)
	menu_item(mut file, deck, 'Save   Ctrl-S', .save)
	menu_item(mut file, deck, 'Save as...   Ctrl-Shift-S', .save_as)
	file.menu_separator()
	menu_item(mut file, deck, 'Settings...   Ctrl-,', .settings)
	file.menu_separator()
	menu_item(mut file, deck, 'Present   F5', .present)
	menu_item(mut file, deck, 'Present from start', .present_start)
	file.menu_separator()
	menu_item(mut file, deck, 'Quit   Ctrl-Q', .quit)
	mut edit := deck.window.add_menu('Edit')
	menu_item(mut edit, deck, 'Undo   Ctrl-Z', .undo)
	menu_item(mut edit, deck, 'Redo   Ctrl-Y', .redo)
	edit.menu_separator()
	menu_item(mut edit, deck, 'Clone slide   Ctrl-D', .clone_slide)
	menu_item(mut edit, deck, 'Delete slide   Ctrl-Shift-D', .delete_slide)
	menu_item(mut edit, deck, 'Move slide up', .move_up)
	menu_item(mut edit, deck, 'Move slide down', .move_down)
	mut view := deck.window.add_menu('View')
	menu_item(mut view, deck, 'Sidebar   F9', .toggle_sidebar)
	menu_item(mut view, deck, 'Speaker notes   Ctrl-Shift-N', .toggle_notes)
	menu_item(mut view, deck, 'Source mode   Ctrl-E', .source)
	view.menu_separator()
	menu_item(mut view, deck, 'Present   F5', .present)
	mut insert := deck.window.add_menu('Insert')
	menu_item(mut insert, deck, 'Image...', .image)
	menu_item(mut insert, deck, 'Table', .table)
	menu_item(mut insert, deck, 'Bullet list', .bullet)
	menu_item(mut insert, deck, 'Heading', .heading)
	insert.menu_separator()
	mut charts := insert.add_menu('Chart')
	menu_item(mut charts, deck, 'Columns', .chart_columns)
	menu_item(mut charts, deck, 'Bars', .chart_bars)
	menu_item(mut charts, deck, 'Lines', .chart_lines)
	mut shapes := insert.add_menu('Shape')
	menu_item(mut shapes, deck, 'Rectangle...', .shape_rect)
	menu_item(mut shapes, deck, 'Line...', .shape_line)
	menu_item(mut shapes, deck, 'Circle...', .shape_circle)
	mut format := deck.window.add_menu('Format')
	menu_item(mut format, deck, 'Bold   Ctrl-B', .bold)
	menu_item(mut format, deck, 'Italic   Ctrl-I', .italic)
	menu_item(mut format, deck, 'Code   Ctrl-K', .code)
	menu_item(mut format, deck, 'Strikethrough', .strike)
	menu_item(mut format, deck, 'Font...', .font)
	mut slide_menu := deck.window.add_menu('Slide')
	menu_item(mut slide_menu, deck, 'New slide...   Ctrl-N', .new_slide)
	menu_item(mut slide_menu, deck, 'Clone slide', .clone_slide)
	menu_item(mut slide_menu, deck, 'Delete slide', .delete_slide)
	menu_item(mut slide_menu, deck, 'Move up', .move_up)
	menu_item(mut slide_menu, deck, 'Move down', .move_down)
	slide_menu.menu_separator()
	menu_item(mut slide_menu, deck, 'Present from here   F5', .present)
	menu_item(mut slide_menu, deck, 'Present from start', .present_start)
	mut help := deck.window.add_menu('Help')
	menu_item(mut help, deck, 'Markdown and shapes', .help)
	help.menu_separator()
	menu_item(mut help, deck, 'About', .about)
	deck.rebuild_thumbnails(mut app)
	deck.select(0, mut app)
	app.maximize(mut deck.window)
	deck.refresh()
	app.set_focus(deck.editor)
}

pub fn launch(mut app vtk.App) {
	new_deck(mut app, '')
}

pub fn open_file(mut app vtk.App, path string) { new_deck(mut app, path) }

pub fn run() {
	mut app := vtk.new_app()
	app.ctrl_c = .copy
	app.native_clipboard = true
	launch_cli := fn (mut app vtk.App) {
		mut path := ''
		for arg in os.args[1..] {
			if arg.starts_with('--') {
				continue
			}
			path = arg
			break
		}
		new_deck(mut app, path)
	}
	common.run(mut app, launch_cli)
}
