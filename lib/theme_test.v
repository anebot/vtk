module vtk

import os
import math

fn test_titlebar_colors_roundtrip_through_settings_and_older_settings_still_load() {
	path := os.join_path(os.temp_dir(), 'vtk-theme-${os.getpid()}.ini')
	defer { os.rm(path) or {} }
	mut app := new_app()
	app.settings_file(path)
	app.theme.title = color_rgb(240, 245, 250)
	app.theme.title_bg = color_rgb(40, 60, 80)
	app.theme.inactive_title = color_rgb(180, 190, 200)
	app.theme.inactive_title_bg = color_rgb(30, 35, 40)
	app.theme.focus_fg = color_rgb(240, 245, 250)
	app.theme.focus_bg = color_rgb(35, 55, 75)
	app.settings_save() or { panic(err) }
	mut loaded := new_app()
	loaded.settings_file(path)
	loaded.settings_load() or { panic(err) }
	assert loaded.theme == app.theme
	os.write_file(path, '[vtk]\ntitle = 15\nbg = 0\nfocus_bg = 4\nfield_bg = 4\nfield_fg = 15\n') or { panic(err) }
	loaded.theme = theme_default()
	loaded.settings_load() or { panic(err) }
	assert loaded.theme.title == bright_white && loaded.theme.bg == black
	assert loaded.theme.title_bg == blue && loaded.theme.focus_fg == bright_white
	assert loaded.theme.inactive_title_bg == theme_default().inactive_title_bg
}

// Reference xterm colors for the ANSI presets; Dark and Modern specify RGB.
fn theme_test_luminance(color int) f64 {
	ansi := [0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, 0xe5e5e5,
		0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff]
	rgb := if color & 0x1000000 != 0 { color & 0xffffff } else { ansi[color] }
	mut channels := []f64{}
	for shift in [16, 8, 0] {
		value := f64((rgb >> shift) & 255) / 255.0
		channels << if value <= 0.04045 { value / 12.92 } else { math.pow((value + 0.055) / 1.055, 2.4) }
	}
	return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
}

fn test_presets_keep_text_readable_on_each_assigned_background() {
	for preset in [Preset.borland, .light_borland, .dark, .light, .teal, .modern, .serial] {
		t := theme_preset(preset)
		for pair in [[t.fg, t.bg], [t.btn_fg, t.btn_bg], [t.focus_fg, t.focus_bg],
			[t.field_fg, t.field_bg], [t.sel_fg, t.sel_bg], [t.bar_fg, t.bar_bg],
			[t.menu_fg, t.menu_bg], [t.tool_fg, t.tool_bg], [t.title, t.title_bg],
			[t.inactive_title, t.inactive_title_bg], [t.accent, t.bg], [t.dim, t.bg]] {
			fg, bg := theme_test_luminance(pair[0]), theme_test_luminance(pair[1])
			ratio := if fg > bg { (fg + 0.05) / (bg + 0.05) } else { (bg + 0.05) / (fg + 0.05) }
			assert ratio >= 4.5, '${preset}: ${pair} has contrast ${ratio}'
		}
	}
}

fn theme_test_cell(_ &Ctl, _ int, _ int) string { return 'Project' }

fn test_controls_use_matching_foreground_and_background_roles() {
	for preset in [Preset.borland, .light_borland, .dark, .light, .teal, .modern, .serial] {
		mut app := new_app()
		app.theme = theme_preset(preset)
		app.screen.resize(80, 24)
		t := app.theme
		for kind in [Kind.button, .checkbox, .switch, .spin, .combo, .radio] {
			mut c := new_ctl(kind)
			c.text = 'Add'
			c.add_item('Choice')
			c.layout(Rect{0, 0, 16, 1})
			app.focus = c
			app.draw_ctl(mut c)
			assert app.screen.cells[0].fg == t.focus_fg && app.screen.cells[0].bg == t.focus_bg
		}
		for kind in [Kind.button, .toolbutton] {
			mut c := new_ctl(kind)
			c.text = 'Remove'
			c.disabled = true
			c.layout(Rect{0, 0, 16, 1})
			app.focus = c
			app.draw_ctl(mut c)
			assert app.screen.cells[0].fg == t.dim && app.screen.cells[0].bg == t.bg
		}
		mut status := statusbar('Ready')
		status.layout(Rect{0, 0, 16, 1})
		app.draw_ctl(mut status)
		assert app.screen.cells[0].fg == t.bar_fg && app.screen.cells[0].bg == t.bar_bg
		mut table := table(theme_test_cell)
		table.table_column('Name')
		table.high = 2
		table.value = 0
		mut tree := tree()
		tree.tree_add(unsafe { nil }, 'Project')
		mut selections := [table, tree]
		for mut c in selections {
			c.layout(Rect{0, 0, 20, 3})
			at := if c.kind == .table { 80 } else { 0 }
			app.focus = c
			app.draw_ctl(mut c)
			assert app.screen.cells[at].fg == t.focus_fg && app.screen.cells[at].bg == t.focus_bg,
				'${preset} ${c.kind}: ${app.screen.cells[at]}'
			app.focus = unsafe { nil }
			app.draw_ctl(mut c)
			assert app.screen.cells[at].fg == t.sel_fg && app.screen.cells[at].bg == t.sel_bg
		}
		mut menu := context_menu()
		mut item := menu.menu_item('Disabled', dialog_accept)
		item.disabled = true
		app.open_menu(menu, 0, 5)
		app.redraw()
		p := app.popups[0]
		cell := app.screen.cells[(p.y + 1) * app.width + p.x + 2]
		assert cell.fg == t.dim && cell.bg == t.bg
	}
}
