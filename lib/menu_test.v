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
	assert same_ctl(app.app_popup, p)
	assert p.y + p.h == app.height - 1
	assert !p.rect().contains(2, app.height - 1)
	app.redraw()
	assert app.screen.cells[(app.height - 1) * app.width..(app.height - 1) * app.width + 7].map(it.glyph).join('') == '[Start]'
	app_button_click(mut app)
	assert app.popups.len == 0 && app.app_popup == none
	app_button_click(mut app)
	assert app.popups.len == 1
	app.app_menu(0, app.height - 1)
	assert app.popups.len == 0
	app.app_menu(10, 8)
	assert app.popups.len == 1 && app.app_popup == none
	assert app.popups[0].x == 10 && app.popups[0].y == 8
	app.close_popups()
	app.dispatch(Event{ kind: .resize, width: 20, height: 3 })
	app.app_menu(0, 2)
	assert app.popups.len == 0
}

fn start_popup(app &App) &Ctl {
	return app.app_popup or { panic('expected a Start menu') }
}

fn popup_source(popup &Ctl) &Ctl {
	return popup.popup_owner or { panic('expected a popup owner') }
}

fn menu_test_launcher(mut app App) { app.clipboard = 'launched' }

fn test_app_menu_reanchors_on_resize_and_clears_the_old_frame() {
	mut app := new_app()
	app.bar_clock = false
	app.app_menu(0, app.height - 1)
	app.redraw()
	old_y := start_popup(app).y
	app.dispatch(Event{ kind: .resize, width: 40, height: 30 })
	assert start_popup(app).y + start_popup(app).h == 29
	app.redraw()
	assert app.screen.cells[old_y * app.width].glyph == '▒'
	assert app.screen.cells[start_popup(app).y * app.width].glyph == '┌'
	app_button_click(mut app)
	assert app.popups.len == 0
	for i in 0 .. 20 { app.register('Tool ${i}', menu_test_launcher) }
	app.app_menu(0, app.height - 1)
	for _ in 0 .. 30 { app.dispatch(Event{ key: int(Key.down) }) }
	selected := start_popup(app).value
	app.dispatch(Event{ kind: .resize, width: 12, height: 10 })
	p := app.app_popup or { panic('expected a Start menu') }
	assert p.w == 12 && p.h == 9 && p.y == 0
	assert p.value == selected && p.value >= p.top && p.value < p.top + p.h - 2
	app.dispatch(Event{ kind: .resize, width: 80, height: 50 })
	assert p.y + p.h == 49 && p.top == 0 && p.value == selected
	app_button_click(mut app)
	assert app.popups.len == 0
	app.app_menu(0, 49)
	app.dispatch(Event{ kind: .resize, width: 80, height: 3 })
	assert app.popups.len == 0 && app.app_popup == none
	app.dispatch(Event{ kind: .resize, width: 80, height: 24 })
	app.app_menu(0, 23)
	app.dispatch(Event{ kind: .resize, width: 4, height: 24 })
	assert app.popups.len == 0
}

fn test_resize_keeps_context_menus_and_submenus_in_bounds() {
	mut app := new_app()
	app.app_menu(0, app.height - 1)
	mut popup := start_popup(app)
	mut menu := popup_source(popup)
	mut more := menu.add_menu('More')
	more.menu_item('Action', dialog_accept)
	popup.value = menu.kids.len - 1
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
	assert app.screen.cells[..7].map(it.glyph).join('') == '[Start]'
	assert app.screen.cells[(app.height - 1) * app.width].glyph == '▒'
	for shortcut in [Event{ key: int(`a`), alt: true }, Event{ key: int(Key.f10), alt: true },
		Event{ key: int(`o`), ctrl: true }] {
		app.dispatch(shortcut)
		assert start_popup(app).y == 1
		app_button_click(mut app)
		assert app.popups.len == 0
	}
	for i in 0 .. 20 { app.register('Tool ${i}', menu_test_launcher) }
	app_button_click(mut app)
	mut menu := popup_source(start_popup(app))
	mut more := menu.add_menu('More')
	more.menu_item('Action', menu_test_launcher_action)
	for _ in 0 .. 30 { app.dispatch(Event{ key: int(Key.down) }) }
	selected := start_popup(app).value
	app.dispatch(Event{ kind: .resize, width: 20, height: 10 })
	assert start_popup(app).y == 1 && start_popup(app).h == 9
	assert start_popup(app).value == selected && start_popup(app).top > 0
	app.dispatch(Event{ key: int(Key.right) })
	assert app.popups.len == 2
	for p in app.popups {
		assert p.y >= 1 && p.y + p.h <= 10
		assert p.x >= 0 && p.x + p.w <= 20
	}
	app.dispatch(Event{ kind: .resize, width: 80, height: 50 })
	assert start_popup(app).y == 1 && start_popup(app).top == 0
	app.bar_top = false
	app.redraw()
	assert start_popup(app).y + start_popup(app).h == 49
	app.bar_top = true
	app.redraw()
	assert start_popup(app).y == 1
	app.dispatch(Event{ key: int(Key.enter) })
	assert app.clipboard == 'launched' && app.popups.len == 0
}

fn menu_test_launcher_action(mut _ Ctl, mut app App) { menu_test_launcher(mut app) }

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
	app.dispatch(Event{ kind: .mouse, x: 13, y: 0, button: .left, pressed: true })
	assert app.popups.len == 1 && app.popups[0].x == 13 && app.popups[0].y == 1
	assert (app.hovered_ctl() == none)
	app.dispatch(Event{ key: int(Key.enter) })
	assert w.minimized
	app.dispatch(Event{ kind: .mouse, x: 13, y: 0, button: .left, pressed: true })
	assert app.popups.len == 1 && w.minimized
	app.dispatch(Event{ key: int(Key.escape) })
	app.dispatch(Event{ kind: .mouse, x: 15, y: 0, button: .left, pressed: true })
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
		assert app.screen.cells[at..at + 28].map(it.glyph).join('') == '[Start] [1] [= 界e\u0301] [= Two] '
		app.window_menu(mut first, first.x, first.y + 1)
		actions := popup_source(app.popups[0]).kids.map(it.text)
		app.close_popups()
		app.dispatch(Event{ kind: .mouse, x: 13, y: app.bar_y(), button: .left, pressed: true })
		assert same_ctl(app.top_window(), second) && app.popups.len == 1
		p := app.popups[0]
		assert popup_source(p).kids[0].link == ?&Ctl(first) && popup_source(p).kids.map(it.text) == actions
		if bar_top {
			assert p.y == 1
		} else {
			assert p.y + p.h == app.height - 1
		}
		app.dispatch(Event{ key: int(Key.escape) })
		app.dispatch(Event{ kind: .mouse, x: 21, y: app.bar_y(), button: .left, pressed: true })
		assert popup_source(app.popups[0]).kids[0].link == ?&Ctl(second)
		app.dispatch(Event{ key: int(Key.escape) })
		app.dispatch(Event{ kind: .mouse, x: 15, y: app.bar_y(), button: .left, pressed: true })
		assert same_ctl(app.top_window(), first) && app.popups.len == 0
		app.dispatch(Event{ kind: .mouse, x: 21, y: app.bar_y(), button: .left, pressed: true })
		for _ in 0 .. 5 { app.dispatch(Event{ key: int(Key.down) }) }
		app.dispatch(Event{ key: int(Key.enter) })
		assert second.closed && !first.closed && same_ctl(app.top_window(), first)
	}
}

fn test_window_bar_keeps_creation_order_when_windows_are_raised_minimized_or_pinned() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		mut first := app.window('One', 30, 8)
		mut second := app.window('Two', 30, 8)
		mut third := app.window('Tri', 30, 8)
		mut raised := [first, second, third, first]
		for mut window in raised {
			app.raise(mut window)
			app.redraw()
			row := app.bar_y() * app.width
			assert app.screen.cells[row + 12..row + 36].map(it.glyph).join('') == '[= One] [= Two] [= Tri] '
		}
		app.minimize(mut first)
		app.dispatch(Event{ kind: .mouse, x: 15, y: app.bar_y(), button: .left, pressed: true })
		assert same_ctl(app.top_window(), first) && !first.minimized
		app.always_on_top(mut first, true)
		app.raise(mut third)
		app.redraw()
		row := app.bar_y() * app.width
		assert app.screen.cells[row + 12..row + 36].map(it.glyph).join('') == '[= One] [= Two] [= Tri] '
		app.dispatch(Event{ kind: .mouse, x: 21, y: app.bar_y(), button: .left, pressed: true })
		assert popup_source(app.popups[0]).kids[0].link == ?&Ctl(second)
		app.close_popups()
		app.close(mut first)
		app.redraw()
		assert app.screen.cells[row + 12..row + 28].map(it.glyph).join('') == '[= Two] [= Tri] '
		app.destroy_ctl(mut second)
		app.window('New', 30, 8)
		app.redraw()
		assert app.screen.cells[row + 12..row + 28].map(it.glyph).join('') == '[= Tri] [= New] '
	}
}

fn test_bar_menu_targets_follow_scrolling_and_ignore_clipped_buttons() {
	mut app := new_app()
	app.width = 32
	app.window('First界!', 20, 8)
	second := app.window('Two', 20, 8)
	app.redraw()
	for x in [11, 26, 29] {
		app.dispatch(Event{ kind: .mouse, x: x, y: app.bar_y(), button: .left, pressed: true })
		assert app.popups.len == 0 && same_ctl(app.top_window(), second)
	}
	app.dispatch(Event{ kind: .mouse, x: 16, y: app.bar_y(), button: .wheel_down, pressed: true })
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: 23, y: app.bar_y(), button: .left, pressed: true })
	assert app.popups.len == 1 && popup_source(app.popups[0]).kids[0].link == ?&Ctl(second)
	app.dispatch(Event{ key: int(Key.escape) })
	app.bar_offset = 2
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: 11, y: app.bar_y(), button: .left, pressed: true })
	assert app.popups.len == 0
}

fn test_clicking_a_parent_item_switches_submenus_instead_of_closing() {
	mut app := new_app()
	app.desktop = false
	mut menu := context_menu()
	mut wrap := menu.add_menu('Wrap')
	wrap.menu_item('Word', menu_test_launcher_action)
	mut page := menu.add_menu('Page')
	page.menu_item('Ruler', menu_test_launcher_action)
	app.open_menu(menu, 10, 5)
	assert app.popups.len == 1
	parent := app.popups[0]
	wrap_y := parent.y + 1
	page_y := parent.y + 2
	app.dispatch(Event{ kind: .mouse, x: parent.x + 2, y: wrap_y, button: .left, pressed: true })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, wrap)
	// The release that follows the opening press must not close the submenu.
	app.dispatch(Event{ kind: .mouse, x: parent.x + 2, y: wrap_y, button: .left })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, wrap)
	// Moving across the parent towards the submenu keeps it open.
	app.dispatch(Event{ kind: .mouse, x: parent.x + 2, y: page_y, motion: true })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, wrap)
	app.dispatch(Event{ kind: .mouse, x: 0, y: 0, motion: true })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, wrap)
	// The sibling item stays reachable while the Wrap submenu is open.
	app.dispatch(Event{ kind: .mouse, x: parent.x + 2, y: page_y, button: .left, pressed: true })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, page)
	app.dispatch(Event{ kind: .mouse, x: parent.x + 2, y: page_y, button: .left })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, page)
	app.dispatch(Event{ kind: .mouse, x: 0, y: 0, button: .left, pressed: true })
	assert app.popups.len == 0
}

fn test_clicking_another_menu_title_switches_menus_instead_of_closing() {
	mut app := new_app()
	app.desktop = false
	app.width = 40
	app.height = 14
	mut w := app.window('Doc', 30, 10)
	mut text := label('Body')
	w.add(mut text)
	mut file := w.add_menu('File')
	file.menu_item('Save', menu_test_launcher_action)
	mut edit := w.add_menu('Edit')
	edit.menu_item('Undo', menu_test_launcher_action)
	app.redraw()
	press := fn (mut app App, x int, y int) {
		app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
	}
	press(mut app, file.x + 1, file.y)
	assert app.popups.len == 1 && same_ctl(app.popups[0].popup_owner, file)
	press(mut app, edit.x + 1, edit.y)
	assert app.popups.len == 1 && same_ctl(app.popups[0].popup_owner, edit)
	// The title of the open menu still toggles it closed.
	press(mut app, edit.x + 1, edit.y)
	assert app.popups.len == 0
	// A press away from every menu dismisses them.
	press(mut app, file.x + 1, file.y)
	assert app.popups.len == 1
	press(mut app, w.x + 1, w.y + 4)
	assert app.popups.len == 0
}

fn test_bar_menu_switches_windows_while_open() {
	mut app := new_app()
	app.bar_clock = false
	mut first := app.window('One', 30, 8)
	mut second := app.window('Two', 30, 8)
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: 13, y: app.bar_y(), button: .left, pressed: true })
	assert app.popups.len == 1 && popup_source(app.popups[0]).kids[0].link == ?&Ctl(first)
	app.dispatch(Event{ kind: .mouse, x: 21, y: app.bar_y(), button: .left, pressed: true })
	assert app.popups.len == 1 && popup_source(app.popups[0]).kids[0].link == ?&Ctl(second)
	app.dispatch(Event{ kind: .mouse, x: 70, y: app.bar_y(), button: .left, pressed: true })
	assert app.popups.len == 0
}

fn test_mouse_press_and_release_open_window_submenus_without_closing_them() {
	mut app := new_app()
	app.desktop = false
	app.width = 60
	app.height = 20
	mut w := app.window('Doc', 40, 12)
	mut text := label('Body')
	w.add(mut text)
	mut menu := w.add_menu('View')
	mut wrap := menu.add_menu('Wrap')
	wrap.menu_item('Word', menu_test_launcher_action)
	mut page := menu.add_menu('Page')
	page.menu_item('Ruler', menu_test_launcher_action)
	app.redraw()
	assert menu.y == w.y + 1
	app.dispatch(Event{ kind: .mouse, x: menu.x + 1, y: menu.y, button: .left, pressed: true })
	assert app.popups.len == 1 && same_ctl(app.popups[0].popup_owner, menu)
	// The release that ends the opening click must not close the menu.
	app.dispatch(Event{ kind: .mouse, x: menu.x + 1, y: menu.y, button: .left })
	assert app.popups.len == 1
	p := app.popups[0]
	app.dispatch(Event{ kind: .mouse, x: p.x + 2, y: p.y + 1, button: .left, pressed: true })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, wrap)
	app.dispatch(Event{ kind: .mouse, x: p.x + 2, y: p.y + 1, button: .left })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, wrap)
	app.dispatch(Event{ kind: .mouse, x: p.x + 2, y: p.y + 2, motion: true })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, wrap)
	app.dispatch(Event{ kind: .mouse, x: p.x + 2, y: p.y + 2, button: .left, pressed: true })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, page)
	app.dispatch(Event{ kind: .mouse, x: p.x + 2, y: p.y + 2, button: .left })
	assert app.popups.len == 2 && same_ctl(app.popups[1].popup_owner, page)
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
		assert app.screen.cells[row..row + 7].map(it.glyph).join('') == '[Start]'
		app.dispatch(Event{ kind: .resize, width: 20, height: 6 })
		for p in app.popups {
			assert p.y >= int(bar_top) && p.y + p.h <= 5 + int(bar_top)
		}
	}
}
