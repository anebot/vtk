module common

import vtk

// run initializes the terminal before launching the app.
pub fn run(mut app vtk.App, launch fn (mut vtk.App)) {
	app.init() or {
		eprintln(err)
		return
	}
	launch(mut app)
	app.run() or { eprintln(err) }
}
