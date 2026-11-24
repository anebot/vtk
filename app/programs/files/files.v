// VTK Files is a file manager for the VTK desktop. It offers Windows Explorer
// style list, icon and column views, sorting, Shift/Ctrl multi-selection and
// drag and drop between its own windows and from the host terminal.
module files

import math
import os
import time
import vtk
import vtk.app.programs.common

struct SortEntry {
	label string
	by    SortBy
}

const sort_entries = [SortEntry{'Name', .name}, SortEntry{'Size', .size}, SortEntry{'Type', .kind},
	SortEntry{'Modified', .date}]

const title_prefix = 'Files - '

// Shared state is heap allocated once and referenced by every Files window, so
// any window can read the drag state without module globals.
struct Shared {
mut:
	app   &vtk.App @[required]
	panes []&Pane
	next  int
	drag  Drag
}

@[heap]
struct Pane {
mut:
	id          int
	shared      &Shared @[required]
	win         &vtk.Ctl @[required]
	canvas      &vtk.Ctl @[required]
	status      &vtk.Ctl @[required]
	path_field  &vtk.Ctl @[required]
	hidden_btn  &vtk.Ctl @[required]
	path        string
	issue       string
	scan_capped bool
	entries     []Entry
	selected    map[string]bool
	cursor      int = -1
	cursor_path string
	anchor      int = -1
	anchor_path string
	top         int
	view        View
	sort        SortBy
	descending  bool
	show_hidden bool
	history     []string
	ahead       []string
	cols        []Column
	pressing    bool
	press_row   int = -1
	press_empty bool
	press_x     int
	press_y     int
	marquee     bool
	mq_x        int
	mq_y        int
	mq_x2       int
	mq_y2       int
	last_click  i64
	last_path   string
	typed       string
	typed_at    i64
}

// pane_from resolves the window or control that owns a Pane.
fn pane_from(c &vtk.Ctl) ?&Pane {
	return c.context[Pane]()
}

// files_window identifies the windows Files created.
fn files_window(w &vtk.Ctl) bool {
	return w.kind == .window && pane_from(w) != none
}

// ---------------------------------------------------------------------------
// Pane state
// ---------------------------------------------------------------------------

fn (mut p Pane) refresh() {
	p.issue = ''
	p.entries, p.scan_capped = read_entries(p.path, p.show_hidden) or {
		p.issue = err.msg()
		[]Entry{}, false
	}
	mut keep := map[string]bool{}
	for e in p.entries {
		if p.selected[e.path] { keep[e.path] = true }
	}
	p.selected = keep
	p.sort_listing()
	if p.cursor < 0 && p.entries.len > 0 {
		p.cursor = 0
		p.cursor_path = p.entries[0].path
	}
	if p.cursor < 0 { p.cursor_path = '' }
	if p.view == .columns { p.build_columns() }
	p.hidden_btn.value = int(p.show_hidden)
	p.path_field.set_text(p.path)
	p.path_field.cursor = 0
	p.win.set_text(title_prefix + os.base(p.path))
	p.ensure_visible()
	p.update_status()
	p.canvas.invalidate()
}

fn (mut p Pane) navigate(path string, remember bool) {
	target := os.real_path(path)
	if !os.is_dir(target) {
		p.issue = 'Not a folder: ${path}'
		p.canvas.invalidate_paint()
		return
	}
	if target == p.path {
		p.refresh()
		return
	}
	if remember {
		p.history << p.path
		p.ahead = []string{}
	}
	p.path = target
	p.selected = map[string]bool{}
	p.cursor = -1
	p.cursor_path = ''
	p.anchor = -1
	p.anchor_path = ''
	p.top = 0
	p.refresh()
}

fn (mut p Pane) ensure_visible() {
	if p.entries.len == 0 {
		p.top = 0
		return
	}
	if p.view == .icons {
		cols := p.icon_cols()
		rows := p.icon_rows()
		row := math.max(0, p.cursor) / cols
		first := p.top / cols
		if row < first { p.top = row * cols }
		if row >= first + rows { p.top = (row - rows + 1) * cols }
		p.top = vtk.clamp(p.top, 0, math.max(0, p.entries.len - 1))
		return
	}
	rows := p.list_rows()
	cursor := math.max(0, p.cursor)
	if cursor < p.top { p.top = cursor }
	if cursor >= p.top + rows { p.top = cursor - rows + 1 }
	p.top = vtk.clamp(p.top, 0, math.max(0, p.entries.len - rows))
}

fn (mut p Pane) scroll(delta int) {
	if p.entries.len == 0 { return }
	if p.view == .icons {
		step := delta * p.icon_cols()
		p.top = vtk.clamp(p.top + step, 0, math.max(0, p.entries.len - 1))
	} else {
		p.top = vtk.clamp(p.top + delta, 0, math.max(0, p.entries.len - p.list_rows()))
	}
	p.canvas.invalidate_paint()
}

fn (mut p Pane) update_status() {
	mut parts := []string{}
	if p.scan_capped {
		parts << 'Scan capped at ${scan_limit} names'
	} else if p.view == .columns && p.cols.any(it.scan_capped) {
		parts << 'Column scan capped at ${scan_limit} names'
	}
	if p.issue != '' {
		parts << p.issue
	} else {
		parts << '${p.entries.len} items'
		mut chosen := []Entry{}
		mut total := i64(0)
		for e in p.entries {
			if p.selected[e.path] {
				chosen << e
				total += e.size
			}
		}
		if chosen.len > 0 {
			parts << '${chosen.len} selected (${size_text(total)})'
		}
		if p.view == .list {
			parts << 'List'
		} else if p.view == .icons {
			parts << 'Icons'
		} else {
			parts << 'Columns'
		}
		parts << 'Sort: ${p.sort} ${if p.descending { 'desc' } else { 'asc' }}'
	}
	p.status.set_text(parts.join(' · '))
}

fn (mut p Pane) select_only(index int) {
	p.selected = map[string]bool{}
	if index >= 0 && index < p.entries.len {
		p.selected[p.entries[index].path] = true
		p.anchor = index
		p.anchor_path = p.entries[index].path
	}
}

fn (mut p Pane) range_to(index int) {
	from := if p.anchor >= 0 { p.anchor } else { index }
	lo, hi := if from <= index { from, index } else { index, from }
	p.selected = map[string]bool{}
	for i in lo .. hi + 1 {
		if i >= 0 && i < p.entries.len { p.selected[p.entries[i].path] = true }
	}
}

fn (mut p Pane) toggle(index int) {
	if index < 0 || index >= p.entries.len { return }
	path := p.entries[index].path
	if p.selected[path] { p.selected.delete(path) } else { p.selected[path] = true }
	p.anchor = index
	p.anchor_path = path
}

fn (mut p Pane) chosen() []Entry {
	mut list := []Entry{}
	for e in p.entries {
		if p.selected[e.path] { list << e }
	}
	return list
}

fn (mut p Pane) chosen_paths() []string {
	mut paths := []string{}
	for e in p.entries {
		if p.selected[e.path] { paths << e.path }
	}
	if paths.len == 0 {
		if p.cursor >= 0 && p.cursor < p.entries.len { paths << p.entries[p.cursor].path }
	}
	return paths
}

fn (mut p Pane) cursor_entry() ?Entry {
	if p.cursor < 0 || p.cursor >= p.entries.len { return none }
	return p.entries[p.cursor]
}

fn (mut p Pane) set_cursor(index int, extend bool) {
	if p.entries.len == 0 { return }
	next := vtk.clamp(index, 0, p.entries.len - 1)
	p.cursor = next
	p.cursor_path = p.entries[next].path
	if extend {
		if p.anchor_path == '' {
			p.anchor = next
			p.anchor_path = p.entries[next].path
		}
		p.range_to(next)
	} else {
		p.select_only(next)
	}
	p.ensure_visible()
	p.update_status()
	p.canvas.invalidate_paint()
}

fn (mut p Pane) move_cursor(delta int, extend bool) {
	if p.entries.len == 0 { return }
	base := if p.cursor < 0 { 0 } else { p.cursor + delta }
	p.set_cursor(base, extend)
}

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

fn (mut p Pane) press(x int, y int, e vtk.Event, mut app vtk.App) {
	column, row := hit_entry(p, x, y)
	p.pressing = true
	p.press_x = e.x
	p.press_y = e.y
	p.press_row = row
	p.press_empty = row < 0
	p.marquee = false
	if row < 0 {
		p.press_empty = true
		if !e.ctrl && !e.shift {
			p.selected = map[string]bool{}
			p.anchor = -1
			p.anchor_path = ''
			p.update_status()
			p.canvas.invalidate_paint()
		}
		return
	}
	entry := entry_at(p, column, row) or { return }
	now := time.ticks()
	double := now - p.last_click < 400 && p.last_path == entry.path
	p.last_click = now
	p.last_path = entry.path
	if double {
		p.open(mut app, entry)
		p.pressing = false
		return
	}
	if column >= 0 && column < p.cols.len - 1 {
		// Ancestor column: jump to that folder.
		dir := if entry.dir { entry.path } else { p.cols[column].path }
		p.navigate(dir, true)
		p.pressing = false
		return
	}
	index := if column < 0 { row } else { row }
	if column >= 0 && column < p.cols.len {
		// Rows in an ancestor column are mapped through that column's entries.
		p.selected = map[string]bool{
			entry.path: true
		}
		p.anchor = -1
		p.anchor_path = entry.path
		p.update_status()
		p.canvas.invalidate_paint()
		return
	}
	if e.ctrl {
		p.toggle(index)
		p.cursor = index
		p.cursor_path = entry.path
	} else if e.shift && p.anchor >= 0 {
		p.range_to(index)
		p.cursor = index
		p.cursor_path = entry.path
	} else if !p.selected[entry.path] {
		p.select_only(index)
		p.cursor = index
		p.cursor_path = entry.path
	} else {
		p.cursor = index
		p.cursor_path = entry.path
	}
	p.ensure_visible()
	p.update_status()
	p.canvas.invalidate_paint()
}

fn (mut p Pane) release(x int, y int, mut app vtk.App) {
	p.pressing = false
	p.marquee = false
	_ = x
	_ = y
	_ = app
}

fn pane_mouse(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut p := pane_from(c) or { return false }
	if e.button == .wheel_up || e.button == .wheel_down {
		if e.button == .wheel_up { p.scroll(-3) } else { p.scroll(3) }
		return true
	}
	area := c.rect()
	lx, ly := e.x - area.x, e.y - area.y
	if e.pressed && !e.motion && e.button == .left {
		if p.shared.drag.active {
			cancel_drag(mut app, mut p)
			return true
		}
		p.press(lx, ly, e, mut app)
		return true
	}
	if p.shared.drag.active {
		if !e.pressed && !e.motion && e.button == .left {
			finish_drag(mut app, mut p, e)
		} else {
			update_drag(mut app, mut p, e)
		}
		return true
	}
	if p.pressing {
		if e.motion {
			p.drag_motion(lx, ly, e, mut app)
		} else if !e.pressed && !e.motion {
			p.release(lx, ly, mut app)
		}
		return true
	}
	return true
}

// ---------------------------------------------------------------------------
// Opening, renaming, deleting
// ---------------------------------------------------------------------------

fn (mut p Pane) open(mut app vtk.App, e Entry) {
	if e.dir {
		p.navigate(e.path, true)
		return
	}
	spawn open_path(e.path)
	app.notify('Opening ${e.name}', 1500)
}

fn (mut p Pane) activate(mut app vtk.App) {
	if entry := p.cursor_entry() { p.open(mut app, entry) }
}

fn (mut p Pane) rename_cursor(mut app vtk.App) {
	entry := p.cursor_entry() or { return }
	name := app.prompt_for(none, 'Rename', 'New name for ${entry.name}', entry.name) or { return }
	if name == '' || name == entry.name { return }
	target := os.join_path(p.path, name)
	if os.exists(target) {
		app.msgbox_for(none, 'Rename', '${name} already exists')
		return
	}
	os.mv(entry.path, target) or {
		app.msgbox_for(none, 'Rename', err.msg())
		return
	}
	p.cursor_path = target
	p.refresh()
}

fn (mut p Pane) delete_selection(mut app vtk.App) {
	paths := p.chosen_paths()
	if paths.len == 0 { return }
	question := if paths.len == 1 {
		'Delete ${os.base(paths[0])}?'
	} else {
		'Delete ${paths.len} items?'
	}
	if !app.confirm_for(none, 'Delete', question) { return }
	mut failed := ''
	for path in paths {
		if os.is_dir(path) {
			os.rmdir_all(path) or { failed = err.msg() }
		} else {
			os.rm(path) or { failed = err.msg() }
		}
	}
	if failed != '' { app.msgbox_for(none, 'Delete', failed) }
	p.selected = map[string]bool{}
	p.refresh()
}

fn (mut p Pane) new_folder(mut app vtk.App) {
	name := app.prompt_for(none, 'New folder', 'Folder name', 'untitled') or { return }
	if name == '' { return }
	path := os.join_path(p.path, name)
	os.mkdir(path) or {
		app.msgbox_for(none, 'New folder', err.msg())
		return
	}
	p.cursor_path = path
	p.refresh()
}

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

fn pane_key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut p := pane_from(c) or { return false }
	if e.kind == .paste {
		return p.import_text(mut app, e.text)
	}
	if e.kind != .key { return false }
	key := e.key
	if p.shared.drag.active && key == int(vtk.Key.escape) {
		cancel_drag(mut app, mut p)
		return true
	}
	if key == int(vtk.Key.escape) {
		if p.selected.len > 0 {
			p.selected = map[string]bool{}
			p.update_status()
			p.canvas.invalidate_paint()
			return true
		}
		return false
	}
	if e.ctrl {
		match key {
			`a` {
				p.selected = map[string]bool{}
				for entry in p.entries { p.selected[entry.path] = true }
				p.update_status()
				p.canvas.invalidate_paint()
				return true
			}
			`h` {
				p.show_hidden = !p.show_hidden
				p.refresh()
				return true
			}
			`n` {
				new_files_window(mut app, p.shared, p.path)
				return true
			}
			`q` {
				app.close(mut p.win)
				return true
			}
			`r` {
				p.refresh()
				return true
			}
			`l` {
				app.set_focus(p.path_field)
				return true
			}
			`v` {
				return p.import_text(mut app, app.clipboard_text())
			}
			else {}
		}
	}
	if e.alt && key == int(vtk.Key.left) {
		p.go_back()
		return true
	}
	if e.alt && key == int(vtk.Key.right) {
		p.go_forward()
		return true
	}
	match key {
		int(vtk.Key.up) {
			step := if p.view == .icons { -p.icon_cols() } else { -1 }
			p.move_cursor(step, e.shift)
			return true
		}
		int(vtk.Key.down) {
			step := if p.view == .icons { p.icon_cols() } else { 1 }
			p.move_cursor(step, e.shift)
			return true
		}
		int(vtk.Key.left) {
			if p.view == .icons && !e.shift {
				p.move_cursor(-1, false)
			} else {
				p.go_up()
			}
			return true
		}
		int(vtk.Key.right) {
			if p.view == .icons && !e.shift {
				p.move_cursor(1, false)
			} else {
				p.activate(mut app)
			}
			return true
		}
		int(vtk.Key.home) {
			p.set_cursor(0, e.shift)
			return true
		}
		int(vtk.Key.end) {
			p.set_cursor(p.entries.len - 1, e.shift)
			return true
		}
		int(vtk.Key.page_up) {
			step := if p.view == .icons { -p.icon_cols() * p.icon_rows() } else { -p.list_rows() }
			p.move_cursor(step, e.shift)
			return true
		}
		int(vtk.Key.page_down) {
			step := if p.view == .icons { p.icon_cols() * p.icon_rows() } else { p.list_rows() }
			p.move_cursor(step, e.shift)
			return true
		}
		int(vtk.Key.enter) {
			p.activate(mut app)
			return true
		}
		int(vtk.Key.backspace) {
			p.go_up()
			return true
		}
		int(vtk.Key.delete) {
			p.delete_selection(mut app)
			return true
		}
		int(vtk.Key.space) {
			if p.cursor >= 0 {
				p.toggle(p.cursor)
				p.update_status()
				p.canvas.invalidate_paint()
			}
			return true
		}
		int(vtk.Key.f2) {
			p.rename_cursor(mut app)
			return true
		}
		int(vtk.Key.f3) {
			p.cycle_view()
			return true
		}
		int(vtk.Key.f5) {
			p.refresh()
			return true
		}
		else {
			if !e.ctrl && !e.alt && key >= 32 && key < 127 {
				p.type_ahead(rune(key).str())
				return true
			}
		}
	}
	return false
}

fn (mut p Pane) type_ahead(text string) {
	if time.ticks() - p.typed_at > 900 { p.typed = '' }
	p.typed += text.to_lower()
	p.typed_at = time.ticks()
	for i, entry in p.entries {
		if entry.name.to_lower().starts_with(p.typed) {
			p.set_cursor(i, false)
			p.scroll_cursor()
			return
		}
	}
}

fn (mut p Pane) scroll_cursor() {
	p.ensure_visible()
	p.canvas.invalidate_paint()
}

fn (mut p Pane) cycle_view() {
	p.view = match p.view {
		.list { View.icons }
		.icons { View.columns }
		.columns { View.list }
	}
	p.top = 0
	if p.view == .columns { p.build_columns() }
	p.update_status()
	p.canvas.invalidate()
}

fn (mut p Pane) go_up() {
	parent := os.dir(p.path)
	if parent != p.path { p.navigate(parent, true) }
}

fn (mut p Pane) go_back() {
	if p.history.len == 0 { return }
	previous := p.history.pop()
	p.ahead << p.path
	p.navigate(previous, false)
}

fn (mut p Pane) go_forward() {
	if p.ahead.len == 0 { return }
	next := p.ahead.pop()
	p.history << p.path
	p.navigate(next, false)
}

// ---------------------------------------------------------------------------
// Toolbar and window creation
// ---------------------------------------------------------------------------

fn toolbar_back(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.go_back()
}

fn toolbar_forward(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.go_forward()
}

fn toolbar_up(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.go_up()
}

fn toolbar_home(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.navigate(os.home_dir(), true)
}

fn toolbar_refresh(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.refresh()
}

fn toolbar_new_folder(mut c vtk.Ctl, mut app vtk.App) {
	mut p := pane_from(c) or { return }
	p.new_folder(mut app)
}

fn toolbar_hidden(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.show_hidden = !p.show_hidden
	c.value = int(p.show_hidden)
	p.refresh()
}

fn toolbar_new_window(mut c vtk.Ctl, mut app vtk.App) {
	mut p := pane_from(c) or { return }
	new_files_window(mut app, p.shared, p.path)
}

fn set_view(mut p Pane, view View) {
	p.view = view
	p.top = 0
	if view == .columns { p.build_columns() }
	p.update_status()
	p.canvas.invalidate()
}

fn toolbar_list(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	set_view(mut p, .list)
}

fn toolbar_icons(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	set_view(mut p, .icons)
}

fn toolbar_columns(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	set_view(mut p, .columns)
}

fn toolbar_sort(mut c vtk.Ctl, mut app vtk.App) {
	menu := c.context_menu() or { return }
	area := c.rect()
	app.open_menu(menu, area.x, area.y + 1)
}

fn choose_sort(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	by := SortBy.from(c.data) or { return }
	if p.sort == by {
		p.descending = !p.descending
	} else {
		p.sort = by
		p.descending = false
	}
	p.sort_listing()
	if p.view == .columns { p.sort_columns() }
	p.ensure_visible()
	p.update_status()
	p.canvas.invalidate_paint()
}

fn path_submitted(mut c vtk.Ctl, mut app vtk.App) {
	mut p := pane_from(c) or { return }
	text := c.text.trim_space()
	if text == '' { return }
	target := os.expand_tilde_to_home(text)
	if os.is_file(target) && os.is_abs_path(target) {
		p.navigate(os.dir(target), true)
		p.cursor_path = os.real_path(target)
		p.cursor = p.index_of(p.cursor_path)
		p.select_only(p.cursor)
		p.ensure_visible()
	} else {
		p.navigate(target, true)
	}
	app.set_focus(p.canvas)
}

fn copy_focused_selection(mut app vtk.App) {
	if f := app.focused_ctl() {
		if p := pane_from(f) {
			mut paths := []string{}
			for path in p.chosen_paths() { paths << path }
			app.clipboard_set(paths.join('\n'))
			if paths.len > 0 { app.notify('Copied ${paths.len} path(s)', 1500) }
			return
		}
	}
}

fn window_destroyed(mut c vtk.Ctl, mut _ vtk.App) {
	p := pane_from(c) or { return }
	mut sh := p.shared
	if sh.drag.active && sh.drag.origin == p.id {
		sh.drag = Drag{}
	}
	for i, other in sh.panes {
		if other.id == p.id {
			sh.panes.delete(i)
			break
		}
	}
}

fn next_id(sh &Shared) int {
	mut highest := -1
	for p in sh.panes { highest = math.max(highest, p.id) }
	return highest + 1
}

fn new_files_window(mut app vtk.App, shared &Shared, path string) &Pane {
	// The drag ghost spans every window, so Files owns the app overlay.
	app.overlay = draw_overlay
	resolved := os.real_path(path)
	start := if os.is_dir(resolved) { resolved } else { os.home_dir() }
	mut win := app.window('Files', 84, 24)
	win.destroy = window_destroyed
	win.set_size_limits(40, 8, 0, 0)

	mut tools := vtk.toolbar()
	mut back := vtk.toolbutton('←')
	mut fwd := vtk.toolbutton('→')
	mut up := vtk.toolbutton('↑')
	mut home := vtk.toolbutton('~')
	mut refresh := vtk.toolbutton('R')
	mut folder := vtk.toolbutton('+')
	mut hidden := vtk.toolbutton('H')
	mut newwin := vtk.toolbutton('New window')
	mut list := vtk.toolbutton('List')
	mut icons := vtk.toolbutton('Icons')
	mut columns := vtk.toolbutton('Cols')
	mut sort_btn := vtk.toolbutton('Sort')
	mut field := vtk.entry(start, 0)
	mut status := vtk.statusbar('')
	mut canvas := vtk.canvas(20, 10, paint_pane)
	mut p := &Pane{
		id:         next_id(shared)
		shared:     shared
		win:        win
		canvas:     canvas
		status:     status
		path_field: field
		hidden_btn: hidden
		path:       start
		selected:   map[string]bool{}
		sort:       .name
		view:       .list
	}
	win.set_context(p)
	field.expand = true
	field.submit = path_submitted

	mut buttons := [back, fwd, up, home, refresh, folder, hidden, newwin, list, icons, columns,
		sort_btn]
	for mut button in buttons {
		button.set_context(p)
	}
	back.changed = toolbar_back
	fwd.changed = toolbar_forward
	up.changed = toolbar_up
	home.changed = toolbar_home
	refresh.changed = toolbar_refresh
	folder.changed = toolbar_new_folder
	hidden.changed = toolbar_hidden
	newwin.changed = toolbar_new_window
	list.changed = toolbar_list
	icons.changed = toolbar_icons
	columns.changed = toolbar_columns
	sort_btn.changed = toolbar_sort

	mut sort_menu := vtk.context_menu()
	for entry in sort_entries {
		mut item := sort_menu.menu_item(entry.label, choose_sort)
		item.data = i64(int(entry.by))
		item.set_context(p)
	}
	sort_btn.set_menu(mut sort_menu)

	canvas.expand = true
	canvas.focusable = true
	canvas.mouse_capture = true
	canvas.set_context(p)
	canvas.mousefn = pane_mouse
	canvas.keyfn = pane_key

	tools.add(mut back)
	tools.add(mut fwd)
	tools.add(mut up)
	tools.add(mut home)
	tools.add(mut refresh)
	tools.add(mut folder)
	tools.add(mut hidden)
	tools.add(mut newwin)
	tools.add(mut list)
	tools.add(mut icons)
	tools.add(mut columns)
	tools.add(mut sort_btn)
	tools.add(mut field)

	mut body := vtk.box(true)
	body.add(mut tools)
	body.add(mut canvas)
	body.add(mut status)
	win.add(mut body)
	p.shared.panes << p
	p.refresh()
	app.set_focus(canvas)
	return p
}

// shared_for reuses the drag state of an open Files window, so dropping works
// between windows opened from the desktop menu as well.
fn shared_for(mut app vtk.App) &Shared {
	for w in app.window_list() {
		if w.is_closed() || !files_window(w) { continue }
		if p := pane_from(w) { return p.shared }
	}
	return &Shared{ app: app }
}

pub fn launch(mut app vtk.App) {
	new_files_window(mut app, shared_for(mut app), os.home_dir())
}

pub fn run() {
	mut app := vtk.new_app()
	app.start_programs = true
	app.ctrl_c = .callback
	app.ctrl_c_handler = copy_focused_selection
	app.native_clipboard = true
	args := os.args[1..].filter(!it.starts_with('--'))
	start := if args.len > 0 { args[0] } else { os.home_dir() }
	snapshot := '--snapshot' in os.args
	launch_cli := fn [start, snapshot] (mut app vtk.App) {
		mut pane := new_files_window(mut app, shared_for(mut app), start)
		if '--icons' in os.args { set_view(mut pane, .icons) }
		if '--columns' in os.args { set_view(mut pane, .columns) }
		if !snapshot {
			app.notify('Ctrl-N opens another Files window. Drag with the mouse; Ctrl copies, Shift moves. Pasting file paths imports them.', 7000)
		}
	}
	if snapshot {
		common.snapshot(mut app, 100, 30, launch_cli)
		return
	}
	common.run(mut app, launch_cli)
}
