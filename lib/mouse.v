module vtk

// MouseCursor is a software pointer, independent of the editor's caret.
// glyph must occupy one terminal cell. ASCII themes use the usual fallback.
pub struct MouseCursor {
pub mut:
	enabled      bool
	hide_pointer bool = true
	glyph        rune = `█`
	fg           int  = bright_white
	bg           int  = black
	attr         int
}

// set_mouse_cursor rejects zero-width, wide and control glyphs.
pub fn (mut app App) set_mouse_cursor(cursor MouseCursor) bool {
	if rune_width(cursor.glyph) != 1 { return false }
	app.mouse_cursor = cursor
	app.sync_mouse_motion()
	app.dirty = true
	return true
}

// set_mouse_motion enables movement reports without a button held. A visible
// software cursor also requests these reports, even when mouse_motion is false.
pub fn (mut app App) set_mouse_motion(enabled bool) {
	app.mouse_motion = enabled
	app.sync_mouse_motion()
}

// mouse_position returns zero-based cells, or (-1, -1) before the first report
// and after terminal focus is lost. Terminals do not report pointer exit.
pub fn (app &App) mouse_position() (int, int) { return app.mouse_x, app.mouse_y }

// hovered_ctl is the deepest eligible control under the pointer; events do not
// bubble to its parents. Keyboard focus and mouse capture are independent.
pub fn (app &App) hovered_ctl() &Ctl { return app.hover }

fn (mut app App) sync_mouse_motion() {
	app.driver.set_mouse_motion(app.mouse_motion || app.mouse_cursor.enabled)
	app.sync_mouse_pointer()
}

fn (mut d Driver) set_mouse_motion(enabled bool) {
	if !d.active || d.mouse_motion == enabled { return }
	d.mouse_motion = enabled
	print(if enabled { '\x1b[?1002l\x1b[?1003h' } else { '\x1b[?1003l\x1b[?1002h' })
	flush_stdout()
}

fn (app &App) hover_target() &Ctl {
	x, y := app.mouse_x, app.mouse_y
	if !Rect{0, 0, app.width, app.height}.contains(x, y) { return unsafe { nil } }
	if app.popups.len > 0 {
		p := app.popups.last()
		if !p.rect().contains(x, y) { return unsafe { nil } }
		row := p.top + y - p.y - 1
		if x > p.x && x < p.x + p.w - 1 && y > p.y && y < p.y + p.h - 1
			&& row >= 0 && row < p.link.kids.len {
			item := p.link.kids[row]
			if item.disabled || item.hidden || item.kind == .separator { return unsafe { nil } }
			return item
		}
		return p
	}
	for n in app.notices {
		if !n.closed && n.rect.contains(x, y) { return unsafe { nil } }
	}
	if y == app.height - 1 && (app.bar_height() > 0 || !isnil(app.placement)) {
		return unsafe { nil }
	}
	for i := app.windows.len - 1; i >= 0; i-- {
		w := app.windows[i]
		if w.hidden || w.closed || w.minimized || !w.rect().contains(x, y) { continue }
		if !w.visible() || !isnil(app.blocker(w)) { return unsafe { nil } }
		// The frame and menubar cover any children extending beyond the body.
		if x == w.x || x == w.x + w.w - 1 || y == w.y || y == w.y + w.h - 1 {
			return w
		}
		for menu in w.kids {
			if menu.kind == .menu && !menu.hidden && menu.rect().contains(x, y) {
				return if menu.visible() { menu } else { unsafe { nil } }
			}
		}
		c := w.hit(x, y)
		return if !isnil(c) && c.visible() { c } else { unsafe { nil } }
	}
	return unsafe { nil }
}

fn (mut app App) clear_hover() {
	mut old := app.hover
	app.hover = unsafe { nil }
	if isnil(old) { return }
	old.hovered = false
	app.dirty = true
	if f := old.mouse_leave { f(mut old, mut app) }
}

fn (mut app App) clear_hover_within(c &Ctl) {
	mut p := app.hover
	for !isnil(p) {
		if p == c {
			app.clear_hover()
			return
		}
		p = p.parent
	}
}

fn (mut app App) update_hover() {
	if app.updating_hover { return }
	app.updating_hover = true
	defer { app.updating_hover = false }
	if app.hover_target() == app.hover { return }
	app.clear_hover()
	// A leave callback may close, hide, reparent or replace the next target.
	mut target := app.hover_target()
	if isnil(target) { return }
	app.hover = target
	target.hovered = true
	if f := target.mouse_enter { f(mut target, mut app) }
	// Reconcile callback changes even if it performed a nested redraw.
	app.dirty = true
}

fn (mut app App) clear_mouse() {
	app.mouse_x = -1
	app.mouse_y = -1
	app.clear_hover()
	app.dirty = true
}

fn (mut app App) draw_mouse_cursor() {
	if !app.mouse_cursor.enabled { return }
	c := app.mouse_cursor
	glyph := if rune_width(c.glyph) == 1 { c.glyph } else { `█` }
	app.screen.put(app.mouse_x, app.mouse_y, glyph, c.fg, c.bg, c.attr)
}
