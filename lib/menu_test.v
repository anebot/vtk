module vtk

fn app_button_click(mut app App) {
	app.dispatch(Event{ kind: .mouse, x: 2, y: app.bar_y(), button: .left, pressed: true })
	app.dispatch(Event{ kind: .mouse, x: 2, y: app.bar_y(), button: .left })
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

fn test_top_app_menu_opens_downward_and_survives_resizing() {
	mut app := new_app()
	app.bar_top = true
	app.redraw()
	assert app.screen.cells[..5].map(it.glyph).join('') == '[App]'
	assert app.screen.cells[(app.height - 1) * app.width].glyph == '▒'
	for shortcut in [Event{ key: int(`a`), alt: true }, Event{ key: int(Key.f10), alt: true },
		Event{ key: int(`o`), ctrl: true }] {
		app.dispatch(shortcut)
		assert app.app_popup.y == 1
		app_button_click(mut app)
		assert app.popups.len == 0
	}
	for i in 0 .. 20 { app.register('Tool ${i}', menu_test_launcher, unsafe { nil }) }
	app_button_click(mut app)
	mut more := app.app_popup.link.add_menu('More')
	more.menu_item('Action', menu_test_launcher_action)
	for _ in 0 .. 30 { app.dispatch(Event{ key: int(Key.down) }) }
	selected := app.app_popup.value
	app.dispatch(Event{ kind: .resize, width: 20, height: 10 })
	assert app.app_popup.y == 1 && app.app_popup.h == 9
	assert app.app_popup.value == selected && app.app_popup.top > 0
	app.dispatch(Event{ key: int(Key.right) })
	assert app.popups.len == 2
	for p in app.popups {
		assert p.y >= 1 && p.y + p.h <= 10
		assert p.x >= 0 && p.x + p.w <= 20
	}
	app.dispatch(Event{ kind: .resize, width: 80, height: 50 })
	assert app.app_popup.y == 1 && app.app_popup.top == 0
	app.bar_top = false
	app.redraw()
	assert app.app_popup.y + app.app_popup.h == 49
	app.bar_top = true
	app.redraw()
	assert app.app_popup.y == 1
	app.dispatch(Event{ key: int(Key.enter) })
	assert app.clipboard == 'launched' && app.popups.len == 0
}

fn menu_test_launcher_action(mut _ Ctl, mut app App) { menu_test_launcher(mut app, unsafe { nil }) }

fn test_top_bar_window_menu_and_window_dropdowns_open_below_their_controls() {
	mut app := new_app()
	app.bar_top = true
	mut w := app.window('One', 40, 12)
	mut menu := w.add_menu('File')
	menu.menu_item('Action', menu_test_launcher_action)
	mut dropdown := combo()
	dropdown.add_item('Choice')
	w.add(mut dropdown)
	app.maximize(mut w)
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: 7, y: 0, button: .left, pressed: true })
	assert app.popups.len == 1 && app.popups[0].x == 7 && app.popups[0].y == 1
	assert isnil(app.hovered_ctl())
	app.dispatch(Event{ key: int(Key.enter) })
	assert w.minimized
	app.dispatch(Event{ kind: .mouse, x: 7, y: 0, button: .left, pressed: true })
	assert app.popups.len == 1 && w.minimized
	app.dispatch(Event{ key: int(Key.escape) })
	app.dispatch(Event{ kind: .mouse, x: 9, y: 0, button: .left, pressed: true })
	assert !w.minimized
	app.redraw()
	app.dispatch(Event{ key: int(Key.f10) })
	assert app.popups[0].y == menu.y + 1
	app.close_popups()
	app.set_focus(dropdown)
	app.dispatch(Event{ key: int(Key.down) })
	assert app.popups[0].y == dropdown.y + 1
}

fn test_bar_window_menu_targets_the_clicked_window_without_raising_it() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		app.bar_clock = false
		mut first := app.window('界e\u0301', 30, 8)
		mut second := app.window('Two', 30, 8)
		app.redraw()
		at := app.bar_y() * app.width
		assert app.screen.cells[at..at + 22].map(it.glyph).join('') == '[App] [= 界e\u0301] [= Two] '
		app.window_menu(mut first, first.x, first.y + 1)
		actions := app.popups[0].link.kids.map(it.text)
		app.close_popups()
		app.dispatch(Event{ kind: .mouse, x: 7, y: app.bar_y(), button: .left, pressed: true })
		assert app.top_window() == second && app.popups.len == 1
		p := app.popups[0]
		assert p.link.kids[0].link == first && p.link.kids.map(it.text) == actions
		if bar_top {
			assert p.y == 1
		} else {
			assert p.y + p.h == app.height - 1
		}
		app.dispatch(Event{ key: int(Key.escape) })
		app.dispatch(Event{ kind: .mouse, x: 15, y: app.bar_y(), button: .left, pressed: true })
		assert app.popups[0].link.kids[0].link == second
		app.dispatch(Event{ key: int(Key.escape) })
		app.dispatch(Event{ kind: .mouse, x: 9, y: app.bar_y(), button: .left, pressed: true })
		assert app.top_window() == first && app.popups.len == 0
		app.dispatch(Event{ kind: .mouse, x: 7, y: app.bar_y(), button: .left, pressed: true })
		for _ in 0 .. 5 { app.dispatch(Event{ key: int(Key.down) }) }
		app.dispatch(Event{ key: int(Key.enter) })
		assert second.closed && !first.closed && app.top_window() == first
	}
}

fn test_bar_menu_targets_follow_scrolling_and_ignore_clipped_buttons() {
	mut app := new_app()
	app.width = 26
	app.window('First界!', 20, 8)
	second := app.window('Two', 20, 8)
	app.redraw()
	for x in [5, 20, 23] {
		app.dispatch(Event{ kind: .mouse, x: x, y: app.bar_y(), button: .left, pressed: true })
		assert app.popups.len == 0 && app.top_window() == second
	}
	app.dispatch(Event{ kind: .mouse, x: 10, y: app.bar_y(), button: .wheel_down, pressed: true })
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: 17, y: app.bar_y(), button: .left, pressed: true })
	assert app.popups.len == 1 && app.popups[0].link.kids[0].link == second
	app.dispatch(Event{ key: int(Key.escape) })
	app.bar_offset = 2
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: 5, y: app.bar_y(), button: .left, pressed: true })
	assert app.popups.len == 0
}

fn test_context_menus_and_submenus_leave_the_bar_row_available_at_both_edges() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		mut menu := context_menu()
		mut more := menu.add_menu('More')
		for i in 0 .. 30 { more.menu_item('Action ${i}', menu_test_launcher_action) }
		app.open_menu(menu, 10, app.height - 1)
		app.choose_popup()
		assert app.popups.len == 2
		for p in app.popups {
			assert p.y >= int(bar_top) && p.y + p.h <= 23 + int(bar_top)
			assert !p.rect().contains(p.x, app.bar_y())
		}
		app.redraw()
		row := app.bar_y() * app.width
		assert app.screen.cells[row..row + 5].map(it.glyph).join('') == '[App]'
		app.dispatch(Event{ kind: .resize, width: 20, height: 6 })
		for p in app.popups {
			assert p.y >= int(bar_top) && p.y + p.h <= 5 + int(bar_top)
		}
	}
}
