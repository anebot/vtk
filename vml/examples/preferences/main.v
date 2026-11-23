module main

import vtk

const theme_presets = [vtk.Preset.borland, .light_borland, .dark, .light, .teal, .modern,
	.serial, .wineight]

fn theme_index(current vtk.Theme) int {
	for i, preset in theme_presets {
		if current == vtk.theme_preset(preset) { return i }
	}
	return 0
}

fn main() {
	mut app := vtk.new_app()
	app.init() or { eprintln(err); return }
	build_ui(mut app)
	app.run() or { eprintln(err) }
}
