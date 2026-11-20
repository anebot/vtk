module vtk

fn app_button_click(mut app App) {
	app.dispatch(Event{ kind: .mouse, x: 2, y: app.height - 1, button: .left, pressed: true })
	app.dispatch(Event{ kind: .mouse, x: 2, y: app.height - 1, button: .left })
}

fn test_app_menu_opens_above_button_and_click_toggles_it() {
	mut app := new_app()
	app.redraw()
	app_button_click(mut app)
	assert app.popups.len == 1
	p := app.popups[0]
	assert p == app.app_popup
	assert p.y + p.h == app.height - 1
	assert !p.rect().contains(2, app.height - 1)
	app.redraw()
	assert app.screen.cells[(app.height - 1) * app.width..(app.height - 1) * app.width + 5].map(it.glyph).join('') == '[App]'
	app_button_click(mut app)
	assert app.popups.len == 0 && isnil(app.app_popup)
	app_button_click(mut app)
	assert app.popups.len == 1
	app.app_menu(0, app.height - 1)
	assert app.popups.len == 0
	app.app_menu(10, 8)
	assert app.popups.len == 1 && isnil(app.app_popup)
	assert app.popups[0].x == 10 && app.popups[0].y == 8
	app.close_popups()
	app.dispatch(Event{ kind: .resize, width: 20, height: 3 })
	app.app_menu(0, 2)
	assert app.popups.len == 0
}

fn menu_test_launcher(mut app App, _ voidptr) { app.clipboard = 'launched' }

fn test_app_menu_reanchors_on_resize_and_clears_the_old_frame() {
	mut app := new_app()
	app.bar_clock = false
	app.app_menu(0, app.height - 1)
	app.redraw()
	old_y := app.app_popup.y
	app.dispatch(Event{ kind: .resize, width: 40, height: 30 })
	assert app.app_popup.y + app.app_popup.h == 29
	app.redraw()
	assert app.screen.cells[old_y * app.width].glyph == '▒'
	assert app.screen.cells[app.app_popup.y * app.width].glyph == '┌'
	app_button_click(mut app)
	assert app.popups.len == 0
	for i in 0 .. 20 { app.register('Tool ${i}', menu_test_launcher, unsafe { nil }) }
	app.app_menu(0, app.height - 1)
	for _ in 0 .. 30 { app.dispatch(Event{ key: int(Key.down) }) }
	selected := app.app_popup.value
	app.dispatch(Event{ kind: .resize, width: 12, height: 10 })
	p := app.app_popup
	assert p.w == 12 && p.h == 9 && p.y == 0
	assert p.value == selected && p.value >= p.top && p.value < p.top + p.h - 2
	app.dispatch(Event{ kind: .resize, width: 80, height: 50 })
	assert p.y + p.h == 49 && p.top == 0 && p.value == selected
	app_button_click(mut app)
	assert app.popups.len == 0
	app.app_menu(0, 49)
	app.dispatch(Event{ kind: .resize, width: 80, height: 3 })
	assert app.popups.len == 0 && isnil(app.app_popup)
	app.dispatch(Event{ kind: .resize, width: 80, height: 24 })
	app.app_menu(0, 23)
	app.dispatch(Event{ kind: .resize, width: 4, height: 24 })
	assert app.popups.len == 0
}

fn test_resize_keeps_context_menus_and_submenus_in_bounds() {
	mut app := new_app()
	app.app_menu(0, app.height - 1)
	mut more := app.app_popup.link.add_menu('More')
	more.menu_item('Action', dialog_accept)
	app.app_popup.value = app.app_popup.link.kids.len - 1
	app.choose_popup()
	assert app.popups.len == 2
	app.dispatch(Event{ kind: .resize, width: 20, height: 12 })
	for p in app.popups {
		assert p.x >= 0 && p.x + p.w <= 20
		assert p.y >= 0 && p.y + p.h <= 11
	}
	app_button_click(mut app)
	assert app.popups.len == 0
	app.app_menu(18, 10)
	app.dispatch(Event{ kind: .resize, width: 10, height: 6 })
	assert app.popups[0].x + app.popups[0].w <= 10
	assert app.popups[0].y + app.popups[0].h <= 6
}
