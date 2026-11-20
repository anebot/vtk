module main

import vtk

fn main() {
	mut app := vtk.new_app()
	app.init() or {
		eprintln(err)
		return
	}
	defer { app.fini() }
	app.terminal_window() or {
		eprintln(err)
		return
	}
	app.run() or { eprintln(err) }
}
