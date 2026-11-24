// VTK Desktop: a small Start menu shell for the bundled applications.
module main

import os
import vtk
import vtk.app.programs.desktop

fn main() {
	mut app := vtk.new_app()
	app.start_programs = true
	app.ctrl_c = .copy
	app.native_clipboard = true
	snapshot := '--snapshot' in os.args
	if snapshot {
		app.dispatch(vtk.Event{ kind: .resize, width: 100, height: 30 })
	} else {
		app.init() or {
			eprintln(err)
			return
		}
	}
	defer { app.fini() }
	desktop.register(mut app)
	if snapshot {
		_, height := app.size()
		app.app_menu(0, height - 1)
		app.dispatch(vtk.Event{ key: int(vtk.Key.right) })
		app.redraw()
		println(app.snapshot())
		return
	}
	app.notify('Click Start or press Alt-S. Programs lists Word, Slides, Spread, Paint, Calc, Clock, Files and Terminal.', 6000)
	app.run() or { eprintln(err) }
}
