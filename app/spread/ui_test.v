module spread

import vtk

fn test_spreadsheet_uses_table_api_for_ranges_paste_sort_edit_and_undo() ! {
	mut app := vtk.new_app()
	app.desktop = false
	app.ctrl_c = .copy
	mut view := create_view(mut app, demo_book())
	mut current := view.current() or { panic('missing sheet') }
	mut grid := current.grid
	app.redraw()
	assert grid.table.selection == .cells && grid.table.editable && view.tabs.reorderable
	assert grid.table_select(1, 1, 2, 2)
	app.dispatch(vtk.Event{key: `c`, ctrl: true})
	assert app.clipboard_text() == '4\t3.5\n12\t0.75'
	grid.table_select(1, 1, 1, 1)
	app.dispatch(vtk.Event{kind: .paste, text: '10\t2'})
	assert current.sheet.display(1, 3) == '20'
	view.action(.undo, mut app)
	assert current.sheet.display(1, 3) == '14'
	view.action(.redo, mut app)
	assert current.sheet.display(1, 3) == '20'
	grid.table_sort(1, .descending)
	assert grid.value == 1 && grid.table_cell(grid.value, 0) == 'Notebook'
	app.after(0, fn (mut app vtk.App) {
		mut input := app.focused_ctl() or { panic('missing editor') }
		assert input.kind == .entry
		input.set_text('=2+3')
		app.dispatch(vtk.Event{key: int(vtk.Key.enter)})
	})
	grid.table_begin_edit()
	assert current.sheet.raw(1, 1) == '=2+3' && current.sheet.display(1, 1) == '5'
	app.redraw()
	assert app.snapshot().contains('Notebook')
}

fn test_sheet_tabs_reorder_models_and_selection_modes_are_configurable() {
	mut app := vtk.new_app()
	app.desktop = false
	mut view := create_view(mut app, demo_book())
	app.redraw()
	x, y := view.tabs.rect().x + 4, view.tabs.rect().y
	target := view.tabs.rect().x + 2 + vtk.text_width('Budget') + 5 + 5
	app.dispatch(vtk.Event{kind: .mouse, button: .left, pressed: true, x: x, y: y})
	app.dispatch(vtk.Event{kind: .mouse, button: .left, pressed: true, motion: true, x: target, y: y})
	app.dispatch(vtk.Event{kind: .mouse, button: .left, x: target, y: y})
	assert view.book.sheets[1].data.name == 'Budget'
	assert view.tabs.value == 1
	mut current := view.current() or { panic('missing sheet') }
	assert current.sheet.data.name == 'Budget'
	for mode in 0 .. 4 {
		view.mode.value = mode
		configure_selection(mut view.mode, mut app)
		assert int(current.grid.table.selection) == [1, 2, 3, 0][mode]
	}
}
