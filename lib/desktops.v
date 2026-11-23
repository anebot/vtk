module vtk

fn (app &App) on_desktop(w &Ctl) bool { return w.desktop_id == app.active_desktop }

fn (mut app App) clear_desktop_input() {
	if !isnil(app.placement) { app.placement_key(Event{ key: int(Key.escape) }) }
	app.drag = unsafe { nil }
	app.scroll_drag = unsafe { nil }
	app.title_click = unsafe { nil }
	app.close_popups()
	app.clear_hover()
}

// set_desktop_count clamps the count to 1..4 and keeps windows from removed
// desktops on the last remaining desktop. The active desktop is clamped too.
pub fn (mut app App) set_desktop_count(count int) {
	value := clamp(count, 1, 4)
	if app.desktop_count == value { return }
	app.clear_desktop_input()
	app.desktop_count = value
	for mut w in app.windows { w.desktop_id = clamp(w.desktop_id, 1, value) }
	app.active_desktop = clamp(app.active_desktop, 1, value)
	for i in value .. 4 { app.desktop_focus[i] = none }
	app.bar_offset = 0
	app.enforce_modal_input()
	app.dirty = true
}

// switch_desktop uses one-based desktop numbers. Application-modal dialogs
// block switching; owner-modal dialogs stay on their owner's desktop.
pub fn (mut app App) switch_desktop(desktop_id int) bool {
	if desktop_id < 1 || desktop_id > app.desktop_count { return false }
	if desktop_id == app.active_desktop { return true }
	if !isnil(app.blocker(unsafe { nil })) { return false }
	app.desktop_focus[app.active_desktop - 1] = ctl_option(app.focus)
	app.clear_desktop_input()
	app.active_desktop = desktop_id
	app.bar_offset = 0
	app.focus = unsafe { nil }
	if previous := app.desktop_focus[desktop_id - 1] { app.set_focus(previous) }
	app.enforce_modal_input()
	app.dirty = true
	return true
}

// move_window_to_desktop keeps owned dialogs with their window. Moving a window
// does not switch desktops; raising it later switches to its destination.
pub fn (mut app App) move_window_to_desktop(mut w Ctl, desktop_id int) bool {
	if w.kind != .window || w.app != &app || w.closed || w.modal
		|| desktop_id < 1 || desktop_id > app.desktop_count
		|| !isnil(app.blocker(unsafe { nil })) {
		return false
	}
	if w.desktop_id == desktop_id { return true }
	app.clear_desktop_input()
	mut family := [&w]
	mut i := 0
	for i < family.len {
		owner := family[i]
		for window in app.windows {
			if window !in family && (window.modal_owner == owner || window.modal_parent == owner) {
				family << window
			}
		}
		i++
	}
	for mut window in family { window.desktop_id = desktop_id }
	app.enforce_modal_input()
	app.dirty = true
	return true
}
