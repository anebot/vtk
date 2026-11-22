module vtk

import os

fn test_titlebar_colors_roundtrip_through_settings_and_older_settings_still_load() {
	path := os.join_path(os.temp_dir(), 'vtk-theme-${os.getpid()}.ini')
	defer { os.rm(path) or {} }
	mut app := new_app()
	app.settings_file(path)
	app.theme.title = color_rgb(240, 245, 250)
	app.theme.title_bg = color_rgb(40, 60, 80)
	app.theme.inactive_title = color_rgb(180, 190, 200)
	app.theme.inactive_title_bg = color_rgb(30, 35, 40)
	app.settings_save() or { panic(err) }
	mut loaded := new_app()
	loaded.settings_file(path)
	loaded.settings_load() or { panic(err) }
	assert loaded.theme == app.theme
	os.write_file(path, '[vtk]\ntitle = 15\nbg = 0\n') or { panic(err) }
	loaded.theme = theme_default()
	loaded.settings_load() or { panic(err) }
	assert loaded.theme.title == bright_white && loaded.theme.bg == black
	assert loaded.theme.title_bg == theme_default().title_bg
	assert loaded.theme.inactive_title_bg == theme_default().inactive_title_bg
}
