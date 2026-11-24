module vtk

import os

fn file_pick_click(mut app App, list &Ctl, row int) {
	app.dispatch(Event{ kind: .mouse, x: list.x, y: list.y + row, button: .left, pressed: true })
}

fn test_about_box_reports_name_version_and_author() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('About test', 40, 10)
	app.after(0, fn (mut app App) {
		app.redraw()
		text := app.snapshot()
		assert text.contains('About VtkDemo')
		assert text.contains('VtkDemo version 1.2.3')
		assert text.contains('Author: pancake')
		mut dialog := app.top_window() or { panic('expected a window') }
		app.close(mut dialog)
	})
	app.about_for(window, 'VtkDemo', '1.2.3')
	assert app.windows.len == 1
	app.destroy_ctl(mut window)
}

fn test_file_picker_opens_row_that_is_already_selected() {
	directory := os.join_path(os.temp_dir(), 'vtk-file-picker-${os.getpid()}')
	os.mkdir_all(os.join_path(directory, 'sub')) or { panic(err) }
	os.write_file(os.join_path(directory, 'file.txt'), '') or { panic(err) }
	defer {
		os.rmdir_all(directory) or {}
	}
	mut app := new_app()
	app.desktop = false
	mut body := box(true)
	mut pick := &FilePicker{
		window: app.window('Open', 60, 18)
		field:  entry(directory, 0)
		list:   tree()
	}
	pick.field.set_context(pick)
	pick.field.submit = file_accept
	pick.list.set_context(pick)
	pick.list.changed = file_select
	pick.list.submit = file_accept
	pick.list.mousefn = file_list_click
	body.add(mut pick.field)
	body.add(mut pick.list)
	pick.window.add(mut body)
	pick.fill(directory) or { panic(err) }
	app.redraw()
	rows := pick.list.tree_rows()
	assert rows.len == 3 && rows[1].node.text == 'file.txt' && rows[2].node.text == 'sub'
	// The first click selects, the second one enters the folder.
	file_pick_click(mut app, pick.list, 2)
	assert (pick.list.selected_node or { panic('expected selected node') }).text == 'sub'
	assert pick.directory == os.abs_path(directory)
	file_pick_click(mut app, pick.list, 2)
	assert pick.directory == os.join_path(os.abs_path(directory), 'sub')
	// Back to the parent, then accept a file.
	file_pick_click(mut app, pick.list, 0)
	assert pick.directory == os.abs_path(directory)
	file_pick_click(mut app, pick.list, 1)
	assert (pick.list.selected_node or { panic('expected selected node') }).text == 'file.txt'
	assert pick.result == '' && !pick.window.closed
	file_pick_click(mut app, pick.list, 1)
	assert pick.result == os.join_path(os.abs_path(directory), 'file.txt')
	assert pick.window.closed
}
