module vtk

pub enum TileSide {
	left
	right
	top
	bottom
}

pub fn (mut app App) window(title string, width int, height int) &Ctl {
	offset := (app.windows.len * 2) % 10
	mut w := &Ctl{ kind: .window, text: title, x: 2 + offset, y: 1 + offset / 2, w: max(12, width), h: max(4, height), min_w: 12, min_h: 4 }
	app.windows << w
	app.raise(mut w)
	return w
}

pub fn (app &App) top_window() &Ctl {
	for i := app.windows.len - 1; i >= 0; i-- {
		w := app.windows[i]
		if !w.closed && !w.minimized && !w.hidden { return w }
	}
	return unsafe { nil }
}

fn (app &App) blocker(w &Ctl) &Ctl {
	for i := app.windows.len - 1; i >= 0; i-- {
		d := app.windows[i]
		if d == w {
			if d.modal { return unsafe { nil } }
			continue
		}
		if d.closed || d.minimized || !d.modal { continue }
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
	mut blocked := app.blocker(&w)
	if !isnil(blocked) {
		mut dialog := blocked
		app.raise(mut dialog)
		return
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
	app.focus = unsafe { nil }
	app.focus_first(app.top_window())
	app.dirty = true
}

pub fn (mut app App) maximize(mut w Ctl) {
	if !w.maximized { w.saved = w.rect() }
	w.maximized = true
	w.minimized = false
	w.x = 0
	w.y = 0
	w.w = app.width
	w.h = app.height - app.bar_height()
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
	app.raise(mut w)
}

pub fn (mut app App) always_on_top(mut w Ctl, enabled bool) {
	w.always_on_top = enabled
	app.raise(mut w)
}

pub fn (mut c Ctl) set_size_limits(min_w int, min_h int, max_w int, max_h int) {
	c.min_w = max(12, min_w)
	c.min_h = max(4, min_h)
	c.max_w = if max_w > 0 { max(c.min_w, max_w) } else { 0 }
	c.max_h = if max_h > 0 { max(c.min_h, max_h) } else { 0 }
	c.bound_size()
}

fn (mut c Ctl) bound_size() {
	c.w = max(max(12, c.min_w), c.w)
	c.h = max(max(4, c.min_h), c.h)
	if c.max_w > 0 { c.w = min(c.w, c.max_w) }
	if c.max_h > 0 { c.h = min(c.h, c.max_h) }
}

pub fn (mut app App) tile_side(mut w Ctl, side TileSide) {
	w.maximized = false
	h := app.height - app.bar_height()
	match side {
		.left {
			w.x = 0
			w.y = 0
			w.w = app.width / 2
			w.h = h
		}
		.right {
			w.x = app.width / 2
			w.y = 0
			w.w = app.width - w.x
			w.h = h
		}
		.top {
			w.x = 0
			w.y = 0
			w.w = app.width
			w.h = h / 2
		}
		.bottom {
			w.x = 0
			w.y = h / 2
			w.w = app.width
			w.h = h - w.y
		}
	}
	w.bound_size()
	app.raise(mut w)
}

pub fn (mut app App) tile() {
	mut windows := app.windows.filter(!it.closed && !it.minimized)
	if windows.len == 0 { return }
	mut cols := 1
	for cols * cols < windows.len { cols++ }
	rows := (windows.len + cols - 1) / cols
	for i, mut w in windows {
		w.maximized = false
		w.x = (i % cols) * app.width / cols
		w.y = (i / cols) * (app.height - app.bar_height()) / rows
		w.w = app.width / cols
		w.h = (app.height - app.bar_height()) / rows
		w.bound_size()
	}
	app.dirty = true
}

pub fn (mut app App) cascade() {
	for i, mut w in app.windows.filter(!it.closed && !it.minimized) {
		w.maximized = false
		w.x = (i * 3) % max(1, app.width / 3)
		w.y = i % max(1, app.height / 3)
		w.w = max(12, app.width * 2 / 3)
		w.h = max(4, (app.height - app.bar_height()) * 2 / 3)
	}
	app.dirty = true
}

fn (mut app App) draw_window(mut w Ctl) {
	t := app.theme
	active := app.top_window() == &w
	frame := if active || !app.dim_inactive { t.frame } else { t.dim }
	app.screen.fill(w.rect(), ` `, t.fg, t.bg)
	app.screen.frame(w.rect(), true, frame, t.bg)
	if w.controls & window_menu != 0 { app.screen.text(w.x + 1, w.y, '[=]', frame, t.bg, 0) }
	app.screen.text(w.x + 5, w.y, ' ${w.text} ', t.title, t.bg, bold)
	mut x := w.x + w.w - 4
	if w.controls & window_close != 0 {
		app.screen.text(x, w.y, '[■]', frame, t.bg, 0)
		x -= 3
	}
	if w.controls & window_maximize != 0 {
		app.screen.text(x, w.y, if w.maximized { '[▣]' } else { '[□]' }, frame, t.bg, 0)
		x -= 3
	}
	if w.controls & window_minimize != 0 { app.screen.text(x, w.y, '[_]', frame, t.bg, 0) }
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
	if w.maximized || w.minimized { return }
	app.placement = &w
	app.placement_resize = resize
	app.placement_start = w.rect()
	app.dirty = true
}
