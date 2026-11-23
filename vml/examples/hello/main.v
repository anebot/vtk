module main

import vtk

fn say_hello(mut button vtk.Ctl, mut app vtk.App) {
	name := button.link or { return }
	app.notify('Hello, ${name.text}!', 2000)
}

fn run_progress(mut button vtk.Ctl, mut app vtk.App) {
	if button.disabled { return }
	mut progress := button.link or { return }
	button.disabled = true
	button.set_text('Working...')
	progress.set_value(0)
	advance_progress(mut button, mut app)
}

fn advance_progress(mut button vtk.Ctl, mut app vtk.App) {
	app.after(80, fn [mut button] (mut app vtk.App) {
		window := button.owner_window() or { return }
		if window.is_closed() { return }
		mut progress := button.link or { return }
		progress.set_value(progress.value + 5)
		if progress.value < progress.high {
			advance_progress(mut button, mut app)
		} else {
			button.disabled = false
			button.set_text('Run again')
		}
	})
}

fn main() {
	mut app := vtk.new_app()
	build_ui(mut app)
	app.run() or { eprintln(err) }
}
