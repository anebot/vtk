module vtk

import os

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
	assert app.bar_windows().last() == created
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

fn check_settings_bar_position(mut app App) {
	mut settings := app.top_window()
	body := settings.kids[0]
	options := body.kids.filter(it.kind == .checkbox && it.text == 'Window bar at top')
	assert options.len == 1
	option := options[0]
	buttons := body.kids.last().kids
	app.set_focus(option)
	app.dispatch(Event{ key: int(Key.space) })
	assert !app.bar_top
	app.set_focus(buttons[0]) // Apply
	app.dispatch(Event{ key: int(Key.enter) })
	app.redraw()
	assert app.bar_top && settings.y >= 1
	assert app.screen.cells[..5].map(it.glyph).join('') == '[App]'
	app.set_focus(buttons[1]) // Save
	app.dispatch(Event{ key: int(Key.enter) })
	mut loaded := new_app()
	loaded.settings_file(app.settings_filename())
	loaded.settings_load() or { panic(err) }
	assert loaded.bar_top
	app.set_focus(buttons[2]) // Reset
	app.dispatch(Event{ key: int(Key.enter) })
	assert !app.bar_top && option.value == 0 && !app.settings_saved()
	app.close(mut settings)
}

fn test_settings_applies_saves_and_resets_bar_position() {
	path := os.join_path(os.temp_dir(), 'vtk-bar-settings-${os.getpid()}.ini')
	defer { os.rm(path) or {} }
	mut app := new_app()
	app.settings_file(path)
	app.after(0, check_settings_bar_position)
	app.settings_dialog()
}

fn choose_settings_desktop_color(mut app App) {
	mut picker := app.top_window()
	assert picker.text == 'Desktop background' && picker.modal_owner.text == 'Settings'
	mut sliders := picker.kids[0].kids.filter(it.kind == .slider)
	assert sliders.map(it.value) == [12, 34, 56]
	preview := picker.kids[0].kids[6].kids[1]
	app.redraw()
	assert app.screen.cells[preview.y * app.width + preview.x].bg == color_rgb(12, 34, 56)
	for i, mut slider in sliders { slider.set_value([65, 43, 21][i]) }
	app.redraw()
	assert app.screen.cells[preview.y * app.width + preview.x].bg == color_rgb(65, 43, 21)
	app.set_focus(picker.link)
	app.dispatch(Event{ key: int(Key.enter) })
}

fn change_settings_appearance(mut app App) {
	mut settings := app.top_window()
	body := settings.kids[0]
	theme := body.kids[1].kids[1]
	desktop := body.kids[2].kids[1]
	gradient := body.kids.filter(it.text == 'Gradient window titles')[0]
	buttons := body.kids.last().kids
	app.redraw()
	assert body.kids[0].text == '' && theme.y == body.y + 1
	assert theme.value == int(Preset.dark)
	app.set_focus(gradient)
	app.dispatch(Event{ key: int(Key.space) })
	app.after(0, choose_settings_desktop_color)
	app.set_focus(desktop)
	app.dispatch(Event{ key: int(Key.enter) })
	assert !app.title_gradient && app.theme.desk_bg == color_rgb(12, 34, 56)
	app.set_focus(buttons[0])
	app.dispatch(Event{ key: int(Key.enter) })
	assert app.title_gradient && app.theme.desk_bg == color_rgb(65, 43, 21)
	assert app.theme.bg == theme_preset(.dark).bg
	app.redraw()
	assert app.screen.cells[0].bg == app.theme.desk_bg
	swatch := body.kids[2].kids[2]
	assert app.screen.cells[swatch.y * app.width + swatch.x].bg == app.theme.desk_bg
	app.set_focus(buttons[1])
	app.dispatch(Event{ key: int(Key.enter) })
	app.close(mut settings)
}

fn check_saved_settings_appearance_and_reset(mut app App) {
	mut settings := app.top_window()
	body := settings.kids[0]
	theme := body.kids[1].kids[1]
	gradient := body.kids.filter(it.text == 'Gradient window titles')[0]
	buttons := body.kids.last().kids
	assert theme.value == int(Preset.dark) && gradient.value == 1
	app.set_focus(buttons[0])
	app.dispatch(Event{ key: int(Key.enter) })
	assert app.title_gradient && app.theme.desk_bg == color_rgb(65, 43, 21)
	app.set_focus(theme)
	app.dispatch(Event{ key: int(Key.down) })
	app.dispatch(Event{ key: int(Key.down) })
	app.dispatch(Event{ key: int(Key.enter) })
	app.set_focus(buttons[0])
	app.dispatch(Event{ key: int(Key.enter) })
	assert app.theme == theme_preset(.light)
	app.set_focus(theme)
	app.dispatch(Event{ key: int(Key.down) })
	for _ in 0 .. theme.kids.len { app.dispatch(Event{ key: int(Key.down) }) }
	app.dispatch(Event{ key: int(Key.enter) })
	assert theme.kids[theme.value].text == 'wineight' && gradient.value == 1
	app.set_focus(buttons[0])
	app.dispatch(Event{ key: int(Key.enter) })
	assert app.theme == theme_preset(.wineight) && app.title_gradient
	app.set_focus(buttons[2])
	app.dispatch(Event{ key: int(Key.enter) })
	assert app.theme == theme_default() && !app.title_gradient && gradient.value == 0
	assert !app.settings_saved()
	app.close(mut settings)
}

fn test_settings_appearance_color_picker_save_reopen_and_reset() {
	path := os.join_path(os.temp_dir(), 'vtk-appearance-settings-${os.getpid()}.ini')
	defer { os.rm(path) or {} }
	mut app := new_app()
	app.settings_file(path)
	app.theme = theme_preset(.dark)
	app.theme.desk_bg = color_rgb(12, 34, 56)
	app.after(0, change_settings_appearance)
	app.settings_dialog()
	mut loaded := new_app()
	loaded.settings_file(path)
	loaded.settings_load() or { panic(err) }
	assert loaded.theme == app.theme && loaded.title_gradient
	loaded.after(0, check_saved_settings_appearance_and_reset)
	loaded.settings_dialog()
}
