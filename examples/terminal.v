module main

import os
import vtk

fn main() {
	mut app := vtk.new_app()
	app.init() or {
		eprintln(err)
		return
	}
	defer { app.fini() }
	app.terminal_window(
		directory: if os.args.len > 1 { os.args[1] } else { '' }
		title: if os.args.len > 2 { os.args[2] } else { 'Terminal' }
	) or {
		eprintln(err)
		return
	}
	app.run() or { eprintln(err) }
}
