module main

import vtk

fn say_hello(mut button vtk.Ctl, mut app vtk.App) {
	name := button.link or { return }
	app.notify('Hello, ${name.text}!', 2000)
}

fn main() {
	mut app := vtk.new_app()
	build_ui(mut app)
	app.run() or { eprintln(err) }
}
