module vtk

import os

fn desktop_click(mut app App, desktop_id int) {
	app.dispatch(Event{
		kind:    .mouse
		button:  .left
		pressed: true
		x:       8 + (desktop_id - 1) * 3 + 1
		y:       app.bar_y()
	})
	app.dispatch(Event{
		kind:   .mouse
		button: .left
		x:      8 + (desktop_id - 1) * 3 + 1
		y:      app.bar_y()
	})
}

fn test_desktop_buttons_switch_visible_windows_and_restore_focus() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		app.set_desktop_count(4)
		mut first := app.window('First desktop', 36, 9)
		mut field1 := entry('first', 0)
		first.add(mut field1)
		app.set_focus(field1)
		app.redraw()
		row := app.bar_y() * app.width
		assert app.screen.cells[row..row + 21].map(it.glyph).join('') == '[Start] [1][_][_][_] '
		desktop_click(mut app, 2)
		assert app.active_desktop == 2 && isnil(app.top_window()) && isnil(app.focus)
		assert !field1.visible() && app.bar_windows().len == 0
		mut second := app.window('Second desktop', 36, 9)
		mut field2 := entry('second', 0)
		second.add(mut field2)
		app.set_focus(field2)
		app.redraw()
		assert second.desktop_id == 2 && app.top_window() == second
		assert !app.screen.snapshot().contains('First desktop')
		assert app.screen.cells[row..row + 21].map(it.glyph).join('') == '[Start] [_][2][_][_] '
		desktop_click(mut app, 1)
		assert app.focus == field1 && app.top_window() == first
		app.set_focus(field2)
		assert app.focus == field1
		app.dispatch(Event{ key: int(Key.tab), ctrl: true })
		assert app.active_desktop == 1 && app.top_window() == first
		// Stale focus cannot route paste to an inactive desktop.
		app.focus = field2
		app.dispatch(Event{ kind: .paste, text: '!' })
		assert field1.text == 'first!' && field2.text == 'second'
		desktop_click(mut app, 2)
		assert app.focus == field2 && app.bar_windows() == [second]
		app.raise(mut first)
		assert app.active_desktop == 1 && app.top_window() == first
	}
}

fn test_move_window_menu_moves_to_another_desktop_without_switching() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		app.set_desktop_count(4)
		mut first := app.window('Stay here', 30, 8)
		mut fallback := entry('stay', 0)
		first.add(mut fallback)
		mut moved := app.window('Move me', 30, 8)
		mut field := entry('moved', 0)
		moved.add(mut field)
		app.set_focus(field)
		app.redraw()
		// Open the [=] title control's menu, then its desktop submenu.
		title := app.window_title_layout(moved)
		app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: title.menu + 1, y: moved.y })
		assert app.popups.len == 1
		mut p := app.popups[0]
		p.value = p.link.kids.len - 1
		assert p.link.kids[p.value].text == 'Move to desktop'
		app.dispatch(Event{ key: int(Key.right) })
		assert app.popups.len == 2
		mut submenu := app.popups[1]
		assert submenu.link.kids.map(it.text) == ['Desktop 1', 'Desktop 2', 'Desktop 3', 'Desktop 4']
		assert submenu.link.kids[0].disabled
		submenu.value = 2
		app.dispatch(Event{ key: int(Key.enter) })
		assert moved.desktop_id == 3 && app.active_desktop == 1
		assert app.top_window() == first && app.focus == fallback && !field.visible()
		assert app.bar_windows() == [first] && app.popups.len == 0
		desktop_click(mut app, 3)
		assert app.top_window() == moved && field.visible()
		app.redraw()
		// The appbar [=] exposes the same move menu.
		app.dispatch(Event{
			kind:    .mouse
			button:  .left
			pressed: true
			x:       app.bar_buttons_rect().x + 1
			y:       app.bar_y()
		})
		assert app.popups[0].link.kids.last().text == 'Move to desktop'
	}
}

fn test_switching_clears_mouse_capture_popups_and_keyboard_placement() {
	mut app := new_app()
	app.set_desktop_count(2)
	mut w := app.window('Window', 32, 9)
	mut field := entry('text', 0)
	w.add(mut field)
	app.redraw()
	app.dispatch(Event{ kind: .mouse, motion: true, x: field.x + 1, y: field.y })
	assert app.hovered_ctl() == field
	app.drag = field
	app.scroll_drag = field
	original := w.rect()
	app.begin_placement(mut w, false)
	app.placement_key(Event{ key: int(Key.right) })
	mut menu := context_menu()
	menu.menu_item('Action', dialog_accept)
	app.open_menu(menu, 10, 10)
	assert app.switch_desktop(2)
	assert isnil(app.drag) && isnil(app.scroll_drag) && isnil(app.placement)
	assert app.popups.len == 0 && isnil(app.hovered_ctl()) && !field.hovered
	assert w.rect() == original
}

fn test_desktop_reduction_keeps_windows_and_modal_families_together() {
	mut app := new_app()
	app.set_desktop_count(4)
	mut owner := app.window('Owner', 30, 8)
	mut owned := app.window('Owned modal', 30, 8)
	owned.modal = true
	owned.modal_owner = owner
	assert app.move_window_to_desktop(mut owner, 4)
	assert owner.desktop_id == 4 && owned.desktop_id == 4 && isnil(app.top_window())
	assert app.switch_desktop(4) && app.top_window() == owned
	assert !app.move_window_to_desktop(mut owned, 2)
	app.set_desktop_count(2)
	assert app.desktop_count == 2 && app.active_desktop == 2
	assert owner.desktop_id == 2 && owned.desktop_id == 2 && app.top_window() == owned
	mut global := app.window('Application modal', 30, 8)
	global.modal = true
	assert !app.switch_desktop(1)
	assert !app.move_window_to_desktop(mut owner, 1)
	app.set_desktop_count(1)
	assert app.active_desktop == 1 && app.top_window() == global
	assert app.windows.len == 3 && app.windows.all(it.desktop_id == 1)
	app.set_desktop_count(20)
	assert app.desktop_count == 4
	assert !app.switch_desktop(0) && !app.switch_desktop(5)
}

fn test_tiling_and_resizing_do_not_join_windows_across_desktops() {
	mut app := new_app()
	app.set_desktop_count(2)
	mut first := app.window('Left on one', 40, 23)
	first.x = 0
	first.y = 0
	app.switch_desktop(2)
	mut second := app.window('Right on two', 40, 23)
	second.x = 40
	second.y = 0
	app.dispatch(Event{ kind: .resize, width: 128, height: 24 })
	assert first.w == 40 && second.w == 40 && second.x == 88
	before := first.rect()
	app.tile()
	assert first.rect() == before
	app.cascade()
	assert first.rect() == before
}

fn test_narrow_bar_does_not_activate_clipped_desktop_slots() {
	mut app := new_app()
	app.width = 20
	app.set_desktop_count(4)
	app.redraw()
	// The clock and its separating blank cover the remaining desktop slots.
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: 14, y: app.bar_y() })
	assert app.active_desktop == 1
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: 15, y: app.bar_y() })
	assert app.active_desktop == 1
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: 12, y: app.bar_y() })
	assert app.active_desktop == 2
}

fn check_desktop_count_settings(mut app App) {
	mut w := app.top_window()
	mut rows := w.kids[0].kids.filter(it.kind == .box && it.kids.len > 0 && it.kids[0].text == 'Virtual desktops:')
	assert rows.len == 1
	mut row := rows[0]
	mut minus, mut progress, mut plus, mut count := row.kids[1], row.kids[2], row.kids[3], row.kids[4]
	assert progress.kind == .progress && progress.blocky
	assert progress.value == 1 && minus.disabled && !plus.disabled && count.text == '1'
	for _ in 0 .. 5 { plus.fire() }
	assert progress.value == 4 && plus.disabled && !minus.disabled && count.text == '4'
	assert app.desktop_count == 1
	app.redraw()
	for i in 0 .. 4 {
		at := progress.y * app.width + progress.x + i * 3
		assert app.screen.cells[at].glyph == '█' && app.screen.cells[at + 1].glyph == '█'
		assert app.screen.cells[at + 2].glyph == ' '
	}
	buttons := w.kids[0].kids.last().kids
	buttons[0].fire() // Apply
	assert app.desktop_count == 4
	buttons[1].fire() // Save
	mut loaded := new_app()
	loaded.settings_file(app.settings_filename())
	loaded.settings_load() or { panic(err) }
	assert loaded.desktop_count == 4 && loaded.active_desktop == 1
	for _ in 0 .. 5 { minus.fire() }
	assert progress.value == 1 && minus.disabled && !plus.disabled
	buttons[2].fire() // Reset
	assert app.desktop_count == 1 && progress.value == 1 && count.text == '1'
	app.close(mut w)
}

fn test_settings_selects_applies_saves_and_resets_one_to_four_desktops() {
	path := os.join_path(os.temp_dir(), 'vtk-desktops-${os.getpid()}.ini')
	defer { os.rm(path) or {} }
	mut app := new_app()
	app.settings_file(path)
	app.after(0, check_desktop_count_settings)
	app.settings_dialog()
	os.write_file(path, '[vtk]\ndesktop_count = 99\n') or { panic(err) }
	app.settings_load() or { panic(err) }
	assert app.desktop_count == 4
	os.write_file(path, '[vtk]\ndesktop_count = -2\n') or { panic(err) }
	app.settings_load() or { panic(err) }
	assert app.desktop_count == 1
}

fn test_owned_dialog_opened_from_another_desktop_follows_its_owner() {
	mut app := new_app()
	app.set_desktop_count(2)
	owner := app.window('Owner on one', 30, 8)
	app.switch_desktop(2)
	app.after(0, fn (mut app App) {
		assert app.active_desktop == 1 && app.top_window().desktop_id == 1
		assert app.top_window().modal_owner.desktop_id == 1
		app.dispatch(Event{ key: int(Key.escape) })
	})
	if _ := app.prompt_for(owner, 'Owned dialog', 'Text:', '') {
		assert false
	}
	assert app.active_desktop == 1 && app.top_window() == owner
}
