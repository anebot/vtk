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

// snapshot launches the app at a fixed size and prints one frame.
pub fn snapshot(mut app vtk.App, width int, height int, launch fn (mut vtk.App)) {
	app.dispatch(vtk.Event{ kind: .resize, width: width, height: height })
	defer { app.fini() }
	launch(mut app)
	app.redraw()
	println(app.snapshot())
}
