module main

import vtk
import time

fn test_generated_ui_builds_a_live_control_tree_without_a_terminal() {
	mut app := vtk.new_app()
	window := build_ui(mut app)
	assert app.window_list() == [window]
	assert window.text == 'VML hello' && window.dismissable
	body := window.children()[0]
	tabs := body.children()[0]
	assert tabs.children().len == 2
	assert tabs.children()[0].text == 'Greeting'
	page := tabs.children()[0].children()[0]
	button := page.children()[1]
	entry := page.children()[2]
	assert entry.text == 'World' && entry.byte_limit == 40
	assert button.link == ?&vtk.Ctl(entry)
	assert window.get_default_button() == ?&vtk.Ctl(button)
	assert app.focused_ctl() == ?&vtk.Ctl(entry)
	assert entry.owner_window() == ?&vtk.Ctl(window)
	progress_row := body.children()[1].children()
	assert progress_row[0].link == ?&vtk.Ctl(progress_row[1])
	assert progress_row[1].value == 0 && progress_row[1].blocky
	check := page.children()[3]
	app.set_focus(check)
	app.dispatch(vtk.Event{ key: int(vtk.Key.space) })
	assert !progress_row[1].blocky
	app.dispatch(vtk.Event{ key: int(vtk.Key.space) })
	assert progress_row[1].blocky
	app.set_focus(entry)
	app.dispatch(vtk.Event{ key: int(vtk.Key.enter) })
	app.redraw()
	assert app.snapshot().contains('Hello, World!')
}

fn test_progress_animates_to_completion_and_can_restart() {
	mut app := vtk.new_app()
	mut window := build_ui(mut app)
	row := window.children()[0].children()[1].children()
	mut button := row[0]
	progress := row[1]
	button.fire()
	assert button.disabled && button.text == 'Working...'
	assert progress.value == 0
	deadline := time.ticks() + 5000
	for button.disabled && time.ticks() < deadline {
		time.sleep(10 * time.millisecond)
		app.step(0)
	}
	assert progress.value == 100
	assert !button.disabled && button.text == 'Run again'
	button.fire()
	assert progress.value == 0 && button.disabled
	assert app.close(mut window)
	time.sleep(100 * time.millisecond)
	app.step(0)
	assert progress.value == 0
	app.fini()
}
