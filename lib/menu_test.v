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
