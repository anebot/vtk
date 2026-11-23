module vtk

const minimum_window_width = 16
const minimum_window_height = 3

pub enum TileSide {
	left
	right
	top
	bottom
}

pub fn (mut app App) window(title string, width int, height int) &Ctl {
	offset := (app.windows.filter(it.desktop_id == app.active_desktop && !it.closed).len * 2) % 10
	app.next_window_order++
	mut w := &Ctl{ kind: .window, app: app, desktop_id: app.active_desktop, text: title, x: 2 + offset, y: 1 + offset / 2, w: max(minimum_window_width, width), h: max(minimum_window_height, height), min_w: minimum_window_width, min_h: minimum_window_height, window_order: app.next_window_order }
	app.windows << w
	app.raise(mut w)
	return w
}

pub fn (app &App) top_window() &Ctl {
	for i := app.windows.len - 1; i >= 0; i-- {
		w := app.windows[i]
		if app.on_desktop(w) && !w.closed && !w.minimized && !w.hidden { return w }
	}
	return unsafe { nil }
}

fn (app &App) blocker(w &Ctl) &Ctl {
	desktop_id := if isnil(w) { app.active_desktop } else { w.desktop_id }
	for i := app.windows.len - 1; i >= 0; i-- {
		d := app.windows[i]
		if d == w {
			if d.modal { return unsafe { nil } }
			continue
		}
		if d.closed || d.minimized || !d.modal || d.desktop_id != desktop_id { continue }
		// A nested dialog is allowed above the modal which owns it.
		mut ancestor := unsafe { w }
		mut descendant := false
		for !isnil(ancestor) {
			if ancestor == d {
				descendant = true
				break
			}
			ancestor = if !isnil(ancestor.modal_parent) { ancestor.modal_parent } else { ancestor.modal_owner }
		}
		if descendant { continue }
		if isnil(d.modal_owner) || d.modal_owner == w { return d }
	}
	return unsafe { nil }
}

pub fn (mut app App) raise(mut w Ctl) {
	if !isnil(w.app) && w.app != &app { return }
	if isnil(w.app) { w.app = app; w.desktop_id = app.active_desktop }
	if !app.on_desktop(&w) && !app.switch_desktop(w.desktop_id) { return }
	mut blocked := app.blocker(&w)
	if !isnil(blocked) {
		mut dialog := blocked
		app.raise(mut dialog)
		return
	}
	if w.window_order == 0 {
		app.next_window_order++
		w.window_order = app.next_window_order
	}
	for i, window in app.windows {
		if window == &w {
			app.windows.delete(i)
			break
		}
	}
	w.minimized = false
	mut at := app.windows.len
	if !w.always_on_top {
		for i, window in app.windows {
			if window.always_on_top {
				at = i
				break
			}
		}
	}
	app.windows.insert(at, &w)
	w.fit_window(app.work_area())
	if isnil(app.focus) || app.focus.owner_window() != &w || !app.focus.visible() {
		app.focus_first(&w)
	}
	app.dirty = true
}

pub fn (mut app App) close(mut w Ctl) bool {
	if w.closed { return true }
	if f := w.closing {
		if !f(mut w, mut app) { return false }
	}
	// Owned modal dialogs close with their owner.
	for mut dialog in app.windows.clone() {
		if (dialog.modal_owner == &w || dialog.modal_parent == &w) && !dialog.closed {
			if !app.close(mut dialog) { return false }
		}
	}
	w.closed = true
	app.clear_hover_within(&w)
	app.close_terminals(mut w)
	app.close_popups()
	if !isnil(app.focus) && app.focus.owner_window() == &w {
		app.focus = unsafe { nil }
		app.focus_first(app.top_window())
	}
	app.dirty = true
	return true
}

pub fn (mut app App) destroy_ctl(mut c Ctl) {
	if c.kind == .window && !app.close(mut c) { return }
	c.closed = true
	app.clear_hover_within(&c)
	for mut child in c.kids.clone() { app.destroy_ctl(mut child) }
	if !isnil(c.menu) {
		mut menu := c.menu
		app.destroy_ctl(mut menu)
	}
	if !isnil(c.term) { c.term.close() }
	if f := c.destroy { f(mut c, mut app) }
	c.detach()
	c.kids.clear()
	for i, w in app.windows {
		if w == &c {
			app.windows.delete(i)
			break
		}
	}
	if app.focus == &c { app.focus = unsafe { nil } }
	app.dirty = true
}

pub fn (mut app App) quit() {
	for mut w in app.windows.clone() {
		if !w.closed {
			if f := w.closing {
				if !f(mut w, mut app) { return }
			}
		}
	}
	app.running = false
}

pub fn (mut app App) minimize(mut w Ctl) {
	if w.modal || !isnil(app.blocker(&w)) { return }
	w.minimized = true
	app.clear_hover_within(&w)
	if !isnil(app.focus) && app.focus.owner_window() == &w { app.focus = unsafe { nil } }
	if isnil(app.focus) { app.focus_first(app.top_window()) }
	app.dirty = true
}

pub fn (mut app App) maximize(mut w Ctl) {
	if !w.maximized { w.saved = w.rect() }
	w.maximized = true
	w.minimized = false
	area := app.work_area()
	w.x = area.x
	w.y = area.y
	w.w = area.w
	w.h = area.h
	app.raise(mut w)
}

pub fn (mut app App) restore(mut w Ctl) {
	if w.maximized {
		w.x = w.saved.x
		w.y = w.saved.y
		w.w = w.saved.w
		w.h = w.saved.h
	}
	w.maximized = false
	w.minimized = false
	w.fit_window(app.work_area())
	app.raise(mut w)
}

pub fn (mut app App) always_on_top(mut w Ctl, enabled bool) {
	w.always_on_top = enabled
	app.raise(mut w)
}

pub fn (mut c Ctl) set_size_limits(min_w int, min_h int, max_w int, max_h int) {
	c.min_w = max(minimum_window_width, min_w)
	c.min_h = max(minimum_window_height, min_h)
	c.max_w = if max_w > 0 { max(c.min_w, max_w) } else { 0 }
	c.max_h = if max_h > 0 { max(c.min_h, max_h) } else { 0 }
	c.bound_size()
	c.invalidate()
}

fn (mut c Ctl) bound_size() {
	c.w = max(max(minimum_window_width, c.min_w), c.w)
	c.h = max(max(minimum_window_height, c.min_h), c.h)
	if c.max_w > 0 { c.w = min(c.w, c.max_w) }
	if c.max_h > 0 { c.h = min(c.h, c.max_h) }
}

fn (mut w Ctl) fit_window(area Rect) {
	if w.maximized {
		w.x = area.x
		w.y = area.y
		w.w = area.w
		w.h = area.h
		return
	}
	w.w = min(w.w, area.w)
	w.h = min(w.h, area.h)
	w.bound_size()
	w.x = clamp(w.x, area.x, area.x + area.w - w.w)
	w.y = clamp(w.y, area.y, area.y + area.h - w.h)
}

// Limit the moving edges before restoring the fixed edges. Size limits still
// take precedence when the workspace is smaller than a window's minimum size.
fn (mut w Ctl) resize_window(width int, height int, area Rect, from_left bool, from_top bool) {
	right, bottom := w.x + w.w, w.y + w.h
	w.w = min(width, if from_left { right - area.x } else { area.x + area.w - w.x })
	w.h = min(height, if from_top { bottom - area.y } else { area.y + area.h - w.y })
	w.bound_size()
	if from_left { w.x = right - w.w }
	if from_top { w.y = bottom - w.h }
	w.fit_window(area)
}

fn (mut app App) fit_windows() {
	area := app.work_area()
	for mut w in app.windows {
		if !w.closed { w.fit_window(area) }
	}
}

pub fn (mut app App) tile_side(mut w Ctl, side TileSide) {
	w.maximized = false
	area := app.work_area()
	h := area.h
	match side {
		.left {
			w.x = 0
			w.y = area.y
			w.w = app.width / 2
			w.h = h
		}
		.right {
			w.x = app.width / 2
			w.y = area.y
			w.w = app.width - w.x
			w.h = h
		}
		.top {
			w.x = 0
			w.y = area.y
			w.w = app.width
			w.h = h / 2
		}
		.bottom {
			w.x = 0
			w.y = area.y + h / 2
			w.w = app.width
			w.h = h - h / 2
		}
	}
	w.fit_window(area)
	app.raise(mut w)
}

pub fn (mut app App) tile() {
	mut windows := app.windows.filter(it.desktop_id == app.active_desktop && !it.closed && !it.minimized)
	if windows.len == 0 { return }
	mut cols := 1
	for cols * cols < windows.len { cols++ }
	rows := (windows.len + cols - 1) / cols
	area := app.work_area()
	for i, mut w in windows {
		w.maximized = false
		w.x = (i % cols) * app.width / cols
		w.y = area.y + (i / cols) * area.h / rows
		w.w = ((i % cols) + 1) * app.width / cols - w.x
		w.h = area.y + ((i / cols) + 1) * area.h / rows - w.y
		w.fit_window(area)
	}
	app.dirty = true
}

pub fn (mut app App) cascade() {
	area := app.work_area()
	for i, mut w in app.windows.filter(it.desktop_id == app.active_desktop && !it.closed && !it.minimized) {
		w.maximized = false
		w.x = (i * 3) % max(1, app.width / 3)
		w.y = area.y + i % max(1, area.h / 3)
		w.w = app.width * 2 / 3
		w.h = area.h * 2 / 3
		w.fit_window(area)
	}
	app.dirty = true
}

struct WindowTitleLayout {
mut:
	menu     int = -1
	close    int = -1
	minimize int = -1
	maximize int = -1
	start    int
	end      int
}

fn (app &App) window_title_layout(w &Ctl) WindowTitleLayout {
	mut title := WindowTitleLayout{ start: w.x + 5, end: w.x + w.w - 1 }
	if !app.macos_buttons && w.controls & window_menu != 0 {
		title.menu = w.x + 1
	}
	mut x := if app.macos_buttons { w.x + 1 } else { w.x + w.w - 4 }
	buttons := if app.macos_buttons {
		[window_close, window_menu, window_minimize]
	} else {
		[window_close, window_maximize, window_minimize]
	}
	for control in buttons {
		if w.controls & control == 0 { continue }
		match control {
			window_close { title.close = x }
			window_menu { title.menu = x }
			window_minimize { title.minimize = x }
			window_maximize { title.maximize = x }
			else {}
		}
		if !app.macos_buttons { title.end = x }
		x += if app.macos_buttons { 3 } else { -3 }
	}
	if app.macos_buttons {
		title.start = max(title.start, x + 1)
	}
	return title
}

fn (mut app App) draw_window(mut w Ctl) {
	t := app.theme
	active := app.top_window() == &w
	frame := if active || !app.dim_inactive { t.frame } else { t.dim }
	title_fg := if active || !app.dim_inactive { t.title } else { t.inactive_title }
	title_bg := if active || !app.dim_inactive { t.title_bg } else { t.inactive_title_bg }
	app.screen.fill(w.rect(), ` `, t.fg, t.bg)
	app.screen.frame(w.rect(), true, frame, t.bg)
	app.screen.fill(Rect{w.x, w.y, w.w, 1}, ` `, title_fg, title_bg)
	title := app.window_title_layout(w)
	if title.menu >= 0 { app.screen.text(title.menu, w.y, '[=]', title_fg, title_bg, 0) }
	if title.close >= 0 { app.screen.text(title.close, w.y, '[■]', title_fg, title_bg, 0) }
	if title.maximize >= 0 {
		app.screen.text(title.maximize, w.y, if w.maximized { '[▣]' } else { '[□]' }, title_fg, title_bg, 0)
	}
	if title.minimize >= 0 { app.screen.text(title.minimize, w.y, '[_]', title_fg, title_bg, 0) }
	app.screen.aligned_text(title.start, w.y, max(0, title.end - title.start), ' ${w.text} ', .left, title_fg, title_bg, bold)
	if app.title_gradient && w.y >= 0 && w.y < app.screen.height {
		rgb := color_as_rgb(title_bg)
		end := color_as_rgb(if active || !app.dim_inactive { t.title_bg_end } else { t.inactive_title_bg_end })
		for column in max(0, w.x) .. min(app.screen.width, w.x + w.w) {
			if !app.screen.clip.contains(column, w.y) { continue }
			app.screen.cells[w.y * app.screen.width + column].bg = color_blend(rgb, end,
				column - w.x, max(1, w.w - 1))
		}
	}
	inside := app.screen.set_clip(Rect{w.x + 1, w.y + 1, w.w - 2, w.h - 2})
	for mut menu in w.kids {
		if menu.kind == .menu && !menu.hidden {
			app.screen.fill(Rect{w.x + 1, menu.y, w.w - 2, 1}, ` `, t.menu_fg, t.menu_bg)
			break
		}
	}
	for mut child in w.kids {
		if child.kind == .menu {
			app.screen.text(child.x, child.y, child.text, t.menu_fg, t.menu_bg, 0)
		} else {
			app.draw_ctl(mut child)
		}
	}
	app.screen.restore_clip(inside)
}

pub fn (mut app App) set_focus(c &Ctl) {
	if isnil(c) || !c.focusable || !c.visible() || !isnil(app.blocker(c.owner_window())) { return }
	app.focus = c
	app.dirty = true
}

fn focusable(c &Ctl, mut found []&Ctl) {
	if !c.visible() { return }
	if c.focusable { found << c }
	for child in c.kids { if child.kind != .menu { focusable(child, mut found) } }
}

fn (mut app App) focus_first(w &Ctl) {
	if isnil(w) || !w.visible() || !isnil(app.blocker(w)) { return }
	mut found := []&Ctl{}
	focusable(w, mut found)
	if found.len > 0 { app.focus = found[0] }
}

fn (mut app App) enforce_modal_input() {
	if !isnil(app.drag) && (!app.drag.visible() || !isnil(app.blocker(app.drag.owner_window()))) {
		app.drag = unsafe { nil }
	}
	if !isnil(app.scroll_drag) && (!app.scroll_drag.visible() || !isnil(app.blocker(app.scroll_drag.owner_window()))) {
		app.scroll_drag = unsafe { nil }
	}
	if !isnil(app.placement) && !isnil(app.blocker(app.placement)) {
		app.placement_key(Event{ key: int(Key.escape) })
	}
	if !isnil(app.focus) && !app.focus.visible() { app.focus = unsafe { nil } }
	mut blocked := app.blocker(if isnil(app.focus) { app.top_window() } else { app.focus.owner_window() })
	if !isnil(blocked) { app.raise(mut blocked) }
	if isnil(app.focus) { app.focus_first(app.top_window()) }
}

fn (mut app App) focus_next(back bool) {
	mut found := []&Ctl{}
	w := if !isnil(app.focus) { app.focus.owner_window() } else { app.top_window() }
	if isnil(w) { return }
	focusable(w, mut found)
	if found.len == 0 { return }
	mut at := if back { 0 } else { -1 }
	for i, c in found {
		if app.focus == c {
			at = i
			break
		}
	}
	app.focus = found[(at + (if back { found.len - 1 } else { 1 })) % found.len]
	app.dirty = true
}

pub fn (mut app App) begin_placement(mut w Ctl, resize bool) {
	if !app.on_desktop(&w) || w.maximized || w.minimized { return }
	w.fit_window(app.work_area())
	app.placement = &w
	app.placement_resize = resize
	app.placement_start = w.rect()
	app.dirty = true
}
