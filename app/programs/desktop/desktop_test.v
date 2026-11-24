module desktop

import vtk

fn contains_terminal(control &vtk.Ctl) bool {
	if control.kind == .terminal { return true }
	return control.children().any(contains_terminal(it))
}

fn test_apps_launched_from_desktop_dispatch_toolbar_and_menu_actions() {
	mut app := vtk.new_app()
	defer { app.fini() }
	app.start_programs = true
	app.dispatch(vtk.Event{kind: .resize, width: 120, height: 40})
	register(mut app)
	app.app_menu(0, 39)
	app.dispatch(vtk.Event{key: int(vtk.Key.right)})
	for _ in 0 .. 2 { app.dispatch(vtk.Event{key: int(vtk.Key.down)}) }
	app.dispatch(vtk.Event{key: int(vtk.Key.enter)})
	sheets := app.top_window() or { panic('missing Sheets window') }
	mut grid := app.focused_ctl() or { panic('missing sheet grid') }
	assert grid.kind == .table && grid.table_select(1, 1, 1, 1)
	app.redraw()
	sheet_body := sheets.children().filter(it.kind == .box)[0]
	sort := sheet_body.children()[0].children().filter(it.text == 'Sort ↑')[0].rect()
	app.dispatch(vtk.Event{kind: .mouse, button: .left, pressed: true, x: sort.x, y: sort.y})
	assert grid.table_row_at(0) != 0
	app.app_menu(0, 39)
	app.dispatch(vtk.Event{key: int(vtk.Key.right)})
	app.dispatch(vtk.Event{key: int(vtk.Key.down)})
	app.dispatch(vtk.Event{key: int(vtk.Key.enter)})
	slides := app.top_window() or { panic('missing Slides window') }
	editor := app.focused_ctl() or { panic('missing slide editor') }
	mode := editor.md.mode
	app.redraw()
	slides_body := slides.children().filter(it.kind == .box)[0]
	source := slides_body.children()[0].children().filter(it.text == 'Source')[0].rect()
	app.dispatch(vtk.Event{kind: .mouse, button: .left, pressed: true, x: source.x, y: source.y})
	assert editor.md.mode != mode
	notes := slides_body.children()[1].children()[1].children().filter(it.kind == .multiline)[0]
	notes_hidden := notes.hidden
	notes_button := slides_body.children()[0].children().filter(it.text == 'Notes')[0].rect()
	app.dispatch(vtk.Event{kind: .mouse, button: .left, pressed: true, x: notes_button.x, y: notes_button.y})
	assert notes.hidden != notes_hidden
	file_menu := slides.children().filter(it.kind == .menu && it.text == 'File')[0]
	mut present := file_menu.children().filter(it.text == 'Present   F5')[0]
	present.fire()
	assert app.window_list().len == 3
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
