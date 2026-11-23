module main

import vtk

fn test_preferences_show_current_settings_and_apply_each_theme() {
	mut app := vtk.new_app()
	defer { app.fini() }
	app.theme = vtk.theme_preset(.dark)
	app.set_desktop_count(3)
	app.set_mouse_cursor(vtk.MouseCursor{ enabled: true })
	app.title_gradient = true
	window := build_ui(mut app)
	body := window.children()[0].children()
	grid := body[0].children()[0].children()
	mut theme := grid[1]
	mut desktops := grid[3]
	mut cursor := body[1].children()[0]
	mut gradient := body[2]
	status := body[3]
	mut defaults := body[4].children()[0]
	mut apply := body[4].children()[1]
	assert theme.children().len == theme_presets.len
	assert theme.value == 2 && desktops.value == 3
	assert cursor.value == 1 && gradient.value == 1
	desktops.set_value(4)
	cursor.set_value(0)
	gradient.set_value(0)
	for i, preset in theme_presets {
		theme.set_value(i)
		apply.fire()
		assert app.theme == vtk.theme_preset(preset)
	}
	assert app.get_desktop_count() == 4
	assert !app.mouse_cursor.enabled && !app.title_gradient
	assert status.text == 'Preferences applied to this session.'
	defaults.fire()
	assert theme.value == 0 && desktops.value == 1
	assert cursor.value == 0 && gradient.value == 0
	assert app.theme == vtk.theme_preset(.wineight) && app.get_desktop_count() == 4
	assert status.text == 'Defaults selected; press Apply.'
	apply.fire()
	assert app.theme == vtk.theme_default() && app.get_desktop_count() == 1
}
