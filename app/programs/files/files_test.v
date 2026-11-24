module files

import vtk

fn test_launch_opens_windows_that_share_drag_state() {
	mut app := vtk.new_app()
	app.dispatch(vtk.Event{ kind: .resize, width: 100, height: 30 })
	launch(mut app, unsafe { nil })
	assert app.window_list().len == 1
	mut first := app.window_list().last()
	assert first.text.starts_with('Files - ')
	launch(mut app, unsafe { nil })
	assert app.window_list().len == 2
	mut second := app.window_list().last()
	first_pane := pane_from(first) or { panic('the Files window is not a pane') }
	second_pane := pane_from(second) or { panic('the second window is not a pane') }
	assert first_pane.shared == second_pane.shared
	// Another program keeps its own state in Ctl.user, so a window of it is
	// never a drop target.
	mut other := app.window('Other window', 20, 8)
	other.user = unsafe { voidptr(42) }
	if _ := pane_under(mut app, other.rect().x + 1, other.rect().y + 1) {
		assert false
	}
	app.close(mut second)
	app.close(mut first)
	app.fini()
}
