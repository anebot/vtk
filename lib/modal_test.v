module vtk

fn close_nested_modal(mut app App) {
	mut child := app.top_window()
	assert child.modal && !isnil(child.modal_parent)
	assert app.blocker(child.modal_parent) == child
	assert app.blocker(app.windows[0]) == child
	app.close(mut child)
}

fn check_settings_modality(mut app App) {
	mut settings := app.top_window()
	assert settings.text == 'Settings' && settings.modal && isnil(settings.modal_owner)
	assert isnil(app.drag) && isnil(app.scroll_drag) && isnil(app.placement)
	assert app.popups.len == 0
	app.redraw()
	for w in app.windows {
		if w == settings { continue }
		assert app.blocker(w) == settings
		app.set_focus(w.kids[0])
		assert app.focus.owner_window() == settings
		// Even stale focus from application callbacks cannot route input behind it.
		app.focus = w.kids[0]
		app.dispatch(Event{ key: int(`x`) })
		app.focus = w.kids[0]
		app.dispatch(Event{ kind: .paste, text: 'paste' })
		assert w.kids[0].text == 'unchanged'
		app.drag = w.kids[0]
		app.dispatch(Event{ kind: .mouse, x: w.x, y: w.y, button: .left, pressed: true, motion: true })
		assert isnil(app.drag) && app.focus.owner_window() == settings
	}
	mut created := app.window('New window', 24, 6)
	mut field := entry('unchanged', 0)
	created.add(mut field)
	assert app.blocker(created) == settings && app.top_window() == settings
	app.always_on_top(mut created, true)
	app.set_focus(field)
	assert app.top_window() == settings && app.focus.owner_window() == settings
	app.dispatch(Event{ key: int(Key.tab), ctrl: true })
	app.dispatch(Event{ key: int(`a`), alt: true })
	app.dispatch(Event{ key: int(`o`), ctrl: true })
	app.app_menu(0, app.height - 1)
	app.window_menu(mut created, 0, 0)
	assert app.popups.len == 0 && app.top_window() == settings
	app.minimize(mut settings)
	assert !settings.minimized && app.blocker(created) == settings
	mut nested := app.window('Nested application modal', 24, 6)
	app.after(0, close_nested_modal)
	app.modal_for(mut nested, unsafe { nil })
	assert app.blocker(created) == settings && app.top_window() == settings
	app.close(mut created)
	app.close(mut settings)
}

fn test_settings_blocks_existing_new_windows_and_stale_input() {
	mut app := new_app()
	mut one := app.window('One', 30, 8)
	mut first := entry('unchanged', 0)
	one.add(mut first)
	mut two := app.window('Two', 30, 8)
	mut second := entry('unchanged', 0)
	two.add(mut second)
	app.set_focus(second)
	app.drag = first
	app.scroll_drag = first
	app.begin_placement(mut one, false)
	mut menu := two.add_menu('Menu')
	menu.menu_item('Action', dialog_accept)
	app.open_menu(menu, 0, 0)
	assert app.popups.len == 1
	app.after(0, check_settings_modality)
	app.settings_dialog()
	assert isnil(app.blocker(one)) && isnil(app.blocker(two))
	assert app.focus == second
	app.set_focus(first)
	app.dispatch(Event{ key: int(`x`) })
	assert first.text == 'unchangedx'
}
