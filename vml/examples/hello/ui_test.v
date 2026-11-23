module main

import vtk

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
	mut button := page.children()[1]
	entry := page.children()[2]
	assert entry.text == 'World' && entry.byte_limit == 40
	assert button.link == ?&vtk.Ctl(entry)
	assert app.focused_ctl() == ?&vtk.Ctl(entry)
	assert entry.owner_window() == ?&vtk.Ctl(window)
	assert body.children()[1].value == 25 && body.children()[1].blocky
	button.fire()
	app.redraw()
	assert app.snapshot().contains('Hello, World!')
}
