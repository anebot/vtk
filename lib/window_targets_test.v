module vtk

fn test_window_actions_reject_widget_targets_before_mutation() {
	actions := [
		fn (mut app App, mut c Ctl) { app.raise(mut c) },
		fn (mut app App, mut c Ctl) { app.move(mut c, 9, 4) },
		fn (mut app App, mut c Ctl) { app.minimize(mut c) },
		fn (mut app App, mut c Ctl) { app.maximize(mut c) },
		fn (mut app App, mut c Ctl) { app.restore(mut c) },
		fn (mut app App, mut c Ctl) { app.always_on_top(mut c, true) },
		fn (mut app App, mut c Ctl) { app.tile_side(mut c, .left) },
		fn (mut app App, mut c Ctl) { app.begin_placement(mut c, false) },
		fn (mut app App, mut c Ctl) { app.window_menu(mut c, 0, 0) },
		fn (mut app App, mut c Ctl) { assert !app.close(mut c) },
		fn (mut app App, mut c Ctl) { assert !app.set_default_button(mut c, none) },
		fn (mut app App, mut c Ctl) { assert !app.move_window_to_desktop(mut c, 2) },
		fn (mut app App, mut c Ctl) { assert app.modal_for(mut c, none) == -1 },
	]
	for attached in [false, true] {
		for action in actions {
			mut app := new_app()
			defer { app.fini() }
			app.set_desktop_count(2)
			mut w := app.window('Window', 30, 8)
			mut c := button('Button')
			if attached { w.add(mut c); app.set_focus(c) }
			mut menu := context_menu()
			menu.menu_item('Keep', fn (mut _ Ctl, mut _ App) {})
			app.open_menu(menu, 0, 0)
			app.after(0, fn (mut app App) { app.quit() })
			before := c.rect()
			app.dirty = false
			action(mut app, mut c)
			assert c.rect() == before && !c.is_closed() && !c.is_minimized() && !c.is_maximized()
			assert !c.is_modal() && !c.is_always_on_top() && c.get_desktop_id() == 1
			assert app.window_list() == [w] && app.popups.len == 1 && isnil(app.placement)
			assert !app.dirty && app.is_running()
			assert (c.parent_ctl() != none) == attached
		}
	}
}

fn test_modal_requests_reject_nonwindow_owners_and_dependency_cycles() {
	mut app := new_app()
	defer { app.fini() }
	mut owner := app.window('Owner', 30, 8)
	mut child := app.window('Child', 30, 8)
	mut field := button('Button')
	owner.add(mut field)
	app.after(0, fn (mut app App) { app.quit() })
	assert app.modal_for(mut child, field) == -1
	assert app.modal_for(mut owner, owner) == -1
	child.modal_owner = owner
	child.modal = true
	assert app.modal_for(mut owner, child) == -1
	assert app.modal_for(mut child, none) == -1
	assert !owner.is_modal() && app.is_running()
}
