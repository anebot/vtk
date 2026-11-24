module desktop

import vtk

fn contains_terminal(control &vtk.Ctl) bool {
	if control.kind == .terminal { return true }
	return control.children().any(contains_terminal(it))
}

fn test_program_windows_open_and_quit_on_shared_desktop() {
	mut app := vtk.new_app()
	app.dispatch(vtk.Event{kind: .resize, width: 120, height: 40})
	app.start_programs = true
	register(mut app)
	mut keeper := app.window('Other window', 20, 8)
	titles := ['VTK Word', 'VTK Slides', 'VTK Sheets', 'VTK Draw', 'VTK Calc', 'VTK Clock', 'Files']
	for index in 0 .. titles.len {
		app.app_menu(0, 39)
		app.dispatch(vtk.Event{key: int(vtk.Key.right)})
		for _ in 0 .. index { app.dispatch(vtk.Event{key: int(vtk.Key.down)}) }
		app.dispatch(vtk.Event{key: int(vtk.Key.enter)})
		mut window := app.window_list().last()
		assert window != keeper
		assert window.text.contains(titles[index])
		assert !contains_terminal(window)
		app.redraw()
		app.dispatch(vtk.Event{key: int(`q`), ctrl: true})
		assert window.is_closed()
		assert !keeper.is_closed()
	}
	app.fini()
}

fn test_clock_reuses_existing_window_even_when_renamed() {
	mut app := vtk.new_app()
	app.dispatch(vtk.Event{kind: .resize, width: 100, height: 30})
	other := app.window('VTK Clock', 20, 8)
	click := vtk.Event{kind: .mouse, button: .left}
	clock_clicked(click, mut app)
	mut clock_window := app.window_list().last()
	assert clock_window != other
	clock_window.set_text('Renamed clock')
	mut cover := app.window('Cover', 20, 8)
	clock_clicked(click, mut app)
	assert app.window_list().len == 3
	assert app.window_list().last() == clock_window
	assert app.close(mut clock_window)
	clock_clicked(click, mut app)
	assert app.window_list().len == 4
	new_clock := app.window_list().last()
	assert new_clock != other && new_clock != cover && new_clock != clock_window
	assert !new_clock.is_closed()
	app.fini()
}
