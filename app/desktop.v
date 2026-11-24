// VTK Desktop: a small Start menu shell for the bundled applications.
module main

import vtk
import vtk.app.programs.common
import vtk.app.programs.desktop

fn main() {
	mut app := vtk.new_app()
	app.start_programs = true
	app.ctrl_c = .copy
	app.native_clipboard = true
	common.run(mut app, fn (mut app vtk.App) {
		desktop.register(mut app)
		app.notify('Click Start or press Alt-S. Programs lists Word, Slides, Spread, Paint, Calc, Clock, Files and Terminal.', 6000)
	})
}
