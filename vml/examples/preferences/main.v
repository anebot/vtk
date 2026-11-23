module main

import vtk

fn main() {
	mut app := vtk.new_app()
	build_ui(mut app)
	app.run() or { eprintln(err) }
}
