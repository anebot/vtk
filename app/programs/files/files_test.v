module files

import vtk

fn test_launch_opens_windows_that_share_drag_state() {
	mut app := vtk.new_app()
	app.dispatch(vtk.Event{ kind: .resize, width: 100, height: 30 })
	launch(mut app)
	assert app.window_list().len == 1
	mut first := app.window_list().last()
	assert first.text.starts_with('Files - ')
	launch(mut app)
	assert app.window_list().len == 2
	mut second := app.window_list().last()
	first_pane := pane_from(first) or { panic('the Files window is not a pane') }
	second_pane := pane_from(second) or { panic('the second window is not a pane') }
	assert first_pane.shared == second_pane.shared
	// A similar title and state of a different type do not identify a Files window.
	mut other := app.window('Files - Other window', 20, 8)
	other.set_context(other)
	assert pane_from(other) == none
	if _ := pane_under(mut app, other.rect().x + 1, other.rect().y + 1) {
		assert false
	}
	app.close(mut second)
	app.close(mut first)
	app.fini()
}
