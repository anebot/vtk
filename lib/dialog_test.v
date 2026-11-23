module vtk

import os

fn file_pick_click(mut app App, list &Ctl, row int) {
	app.dispatch(Event{ kind: .mouse, x: list.x, y: list.y + row, button: .left, pressed: true })
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
	pick.field.user = pick
	pick.field.submit = file_accept
	pick.list.user = pick
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
	assert pick.list.selected_node.text == 'sub'
	assert pick.directory == os.abs_path(directory)
	file_pick_click(mut app, pick.list, 2)
	assert pick.directory == os.join_path(os.abs_path(directory), 'sub')
	// Back to the parent, then accept a file.
	file_pick_click(mut app, pick.list, 0)
	assert pick.directory == os.abs_path(directory)
	file_pick_click(mut app, pick.list, 1)
	assert pick.list.selected_node.text == 'file.txt'
	assert pick.result == '' && !pick.window.closed
	file_pick_click(mut app, pick.list, 1)
	assert pick.result == os.join_path(os.abs_path(directory), 'file.txt')
	assert pick.window.closed
}
