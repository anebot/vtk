module files

import math
import os
import vtk

// Drag carries the payload between Files windows while the button is held.
struct Drag {
mut:
	active     bool
	origin     int = -1
	paths      []string
	x          int
	y          int
	copy       bool
	target     int = -1
	target_dir string
	target_col int = -1
	target_row int = -1
	valid      bool
}

// ---------------------------------------------------------------------------
// Overlay: the floating drag ghost
// ---------------------------------------------------------------------------

fn drag_label(drag Drag, ascii bool) string {
	noun := if drag.paths.len == 1 { '1 item' } else { '${drag.paths.len} items' }
	arrow := if ascii { '>' } else { '→' }
	if drag.target < 0 || drag.target_dir == '' {
		return '${noun} · drop on a folder'
	}
	if !drag.valid {
		return '${noun} · cannot drop here'
	}
	verb := if drag.copy { 'Copy' } else { 'Move' }
	return '${verb} ${noun} ${arrow} ${os.base(drag.target_dir)}'
}

fn ghost_rect(x int, y int, width int, height int) vtk.Rect {
	w := vtk.clamp(width, 8, math.max(8, width))
	return vtk.Rect{vtk.clamp(x + 2, 0, math.max(0, width - 12)), vtk.clamp(y - 1, 1, math.max(1, height - 5)), w, 3}
}

fn draw_overlay(mut app vtk.App, mut s vtk.Screen) {
	mut shared := ?&Shared(none)
	for w in app.window_list() {
		if !files_window(w) { continue }
		if p := pane_from(w) {
			shared = p.shared
			break
		}
	}
	sh := shared or { return }
	drag := sh.drag
	if !drag.active { return }
	t := app.theme
	width, height := app.size()
	label := drag_label(drag, s.ascii)
	w := math.min(math.max(14, vtk.text_width(label) + 8), math.max(8, width - 4))
	mut card := ghost_rect(drag.x, drag.y, width, height)
	card.w = w
	card.x = vtk.clamp(card.x, 0, math.max(0, width - w - 1))
	mut back := vtk.Rect{card.x + 1, card.y - 1, card.w, card.h}
	if back.y < 0 { back.y = 0 }
	frame := if drag.target_dir != '' && drag.valid { t.accent } else { vtk.red }
	s.fill(vtk.Rect{card.x + 2, card.y + 1, card.w, card.h}, ` `, vtk.black, vtk.black)
	s.fill(back, ` `, t.menu_fg, t.menu_bg)
	s.frame(back, false, t.dim, t.menu_bg)
	s.fill(card, ` `, t.menu_fg, t.menu_bg)
	s.frame(card, true, frame, t.menu_bg)
	s.text(card.x + 2, card.y + 1, if drag.copy {
		'+'
	} else if s.ascii {
		'>'
	} else {
		'▸'
	},
		frame, t.menu_bg, vtk.bold)
	s.text(card.x + 4, card.y + 1, clip_text(label, card.w - 5, ellipsis(&s)), t.menu_fg,
		t.menu_bg, vtk.bold)
}

// ---------------------------------------------------------------------------
// Drag and drop
// ---------------------------------------------------------------------------

// files_owned reports whether a control lives in a Files window.
fn files_owned(c &vtk.Ctl) bool {
	if c.kind == .window { return files_window(c) }
	parent := c.parent_ctl() or { return false }
	return files_owned(parent)
}

fn pane_at_ctl(c &vtk.Ctl) ?&Pane {
	if !files_owned(c) { return none }
	if c.kind == .canvas {
		if p := pane_from(c) { return p }
	}
	parent := c.parent_ctl() or { return none }
	return pane_at_ctl(parent)
}

fn pane_under(mut app vtk.App, x int, y int) ?&Pane {
	windows := app.window_list()
	for i := windows.len - 1; i >= 0; i-- {
		w := windows[i]
		if w.is_closed() || w.is_minimized() || !w.rect().contains(x, y) { continue }
		if c := w.hit(x, y) { return pane_at_ctl(c) }
	}
	return none
}

fn hit_entry(p &Pane, x int, y int) (int, int) {
	if x < 0 || y < 0 { return -1, -1 }
	match p.view {
		.list {
			if y < header_rows { return -1, -1 }
			index := p.top + y - header_rows
			if index >= p.entries.len { return -1, -1 }
			return -1, index
		}
		.icons {
			cols := p.icon_cols()
			start := (p.top / cols) * cols
			index := start + (y / tile_height) * cols + x / tile_width
			if index >= p.entries.len { return -1, -1 }
			return -1, index
		}
		.columns {
			first, cw := p.column_layout()
			column := first + x / cw
			if column >= p.cols.len { return -1, -1 }
			if y < 1 { return -1, -1 }
			col := p.cols[column]
			rows := math.max(1, p.canvas.rect().h - 1)
			top := if column == p.cols.len - 1 { p.top } else { math.max(0, col.cursor - rows + 1) }
			index := top + y - 1
			if index >= p.column_entries(column).len { return -1, -1 }
			return column, index
		}
	}
}

fn entry_at(p &Pane, column int, row int) ?Entry {
	if column >= p.cols.len { return none }
	entries := if column < 0 { p.entries } else { p.column_entries(column) }
	if row < 0 || row >= entries.len { return none }
	return entries[row]
}

fn update_drag(mut app vtk.App, mut p Pane, e vtk.Event) {
	mut sh := p.shared
	sh.drag.x = e.x
	sh.drag.y = e.y
	sh.drag.copy = e.ctrl
	app.invalidate_area(vtk.Rect{e.x - 2, e.y - 4, 70, 10})
	mut pane_id := -1
	mut dir := ''
	mut column := -1
	mut row := -1
	if over := pane_under(mut app, e.x, e.y) {
		pane_id = over.id
		area := over.canvas.rect()
		col, index := hit_entry(over, e.x - area.x, e.y - area.y)
		if found := entry_at(over, col, index) {
			if found.dir {
				dir = found.path
				column = col
				row = index
			} else {
				dir = if col >= 0 && col < over.cols.len { over.cols[col].path } else { over.path }
			}
		} else {
			dir = if col >= 0 && col < over.cols.len { over.cols[col].path } else { over.path }
		}
	}
	old_pane := sh.drag.target
	sh.drag.target = pane_id
	sh.drag.target_dir = dir
	sh.drag.target_col = column
	sh.drag.target_row = row
	sh.drag.valid = drop_allowed(sh.drag.paths, dir, sh.drag.copy)
	for other in sh.panes {
		if other.id == old_pane || other.id == pane_id { other.canvas.invalidate_paint() }
	}
	app.invalidate_area(vtk.Rect{e.x - 2, e.y - 4, 70, 10})
}

fn begin_drag(mut app vtk.App, mut p Pane, e vtk.Event) {
	mut paths := []string{}
	for entry in p.chosen() { paths << entry.path }
	if paths.len == 0 { return }
	p.pressing = false
	p.shared.drag = Drag{
		active: true
		origin: p.id
		paths:  paths
		x:      e.x
		y:      e.y
	}
	update_drag(mut app, mut p, e)
	app.invalidate()
}

fn cancel_drag(mut app vtk.App, mut p Pane) {
	mut sh := p.shared
	if !sh.drag.active { return }
	old := sh.drag
	sh.drag = Drag{}
	for other in sh.panes {
		if other.id == old.origin || other.id == old.target { other.canvas.invalidate_paint() }
	}
	app.invalidate_area(vtk.Rect{old.x - 2, old.y - 4, 70, 10})
}

fn finish_drag(mut app vtk.App, mut p Pane, e vtk.Event) {
	update_drag(mut app, mut p, e)
	drag := p.shared.drag
	for other in p.shared.panes {
		if other.id == drag.origin || other.id == drag.target { other.canvas.invalidate_paint() }
	}
	app.invalidate_area(vtk.Rect{drag.x - 2, drag.y - 4, 70, 10})
	if drag.target < 0 || !drag.valid {
		p.shared.drag = Drag{}
		return
	}
	transfer(mut app, mut p, drag.paths, drag.target_dir, drag.copy)
	p.shared.drag = Drag{}
}

fn transfer(mut app vtk.App, mut p Pane, paths []string, dest string, copy bool) {
	sh := p.shared
	mut moved := 0
	mut failures := []string{}
	for path in paths {
		target := unique_target(path, dest)
		if copy {
			os.cp_all(path, target, false) or {
				failures << '${os.base(path)}: ${err.msg()}'
				continue
			}
		} else {
			os.mv(path, target, overwrite: false) or {
				failures << '${os.base(path)}: ${err.msg()}'
				continue
			}
		}
		moved++
	}
	for other in sh.panes {
		if other.path == dest || paths.any(os.dir(it) == other.path) { other.refresh() }
	}
	if failures.len > 0 {
		app.notify(failures[0], 4000)
	}
	if moved > 0 {
		verb := if copy { 'Copied' } else { 'Moved' }
		noun := if moved == 1 { '1 item' } else { '${moved} items' }
		app.notify('${verb} ${noun} to ${os.base(dest)}', 2500)
	}
	p.update_status()
}

fn (mut p Pane) drag_motion(x int, y int, e vtk.Event, mut app vtk.App) {
	dx := e.x - p.press_x
	dy := e.y - p.press_y
	if p.press_empty {
		if dx * dx + dy * dy < 4 { return }
		p.marquee = true
		p.marquee_select(x, y)
		return
	}
	if !p.marquee && dx * dx + dy * dy >= 4 {
		begin_drag(mut app, mut p, e)
	}
}

fn (mut p Pane) marquee_select(x int, y int) {
	area := p.canvas.rect()
	lo_x := math.min(p.press_x - area.x, x)
	lo_y := math.min(p.press_y - area.y, y)
	hi_x := math.max(p.press_x - area.x, x)
	hi_y := math.max(p.press_y - area.y, y)
	p.mq_x, p.mq_y, p.mq_x2, p.mq_y2 = lo_x, lo_y, hi_x, hi_y
	p.selected = map[string]bool{}
	match p.view {
		.icons {
			cols := p.icon_cols()
			start := (p.top / cols) * cols
			for index, entry in p.entries {
				slot := index - start
				if slot < 0 { continue }
				tx := (slot % cols) * tile_width
				ty := (slot / cols) * tile_height
				if tx + tile_width > lo_x && tx <= hi_x && ty + tile_height > lo_y && ty <= hi_y {
					p.selected[entry.path] = true
				}
			}
		}
		.list {
			for index, entry in p.entries {
				row_y := index - p.top + header_rows
				if row_y >= lo_y && row_y <= hi_y { p.selected[entry.path] = true }
			}
		}
		.columns {}
	}
	p.update_status()
	p.canvas.invalidate_paint()
}
