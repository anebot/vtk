module files

import io.util
import os
import vtk

fn test_location_submits_with_enter_and_go_at_minimum_window_width() ! {
	root := util.temp_dir(pattern: 'vtk-files-location-')!
	defer { os.rmdir_all(root) or {} }
	child := os.join_path(root, 'folder with spaces')
	os.mkdir(child)!
	os.write_file(os.join_path(root, 'notes.txt'), '')!
	mut app := vtk.new_app()
	defer { app.fini() }
	app.dispatch(vtk.Event{kind: .resize, width: 40, height: 20})
	pane := new_files_window(mut app, shared_for(mut app), root)
	app.redraw()
	mut field := pane.path_field
	app.dispatch(vtk.Event{key: int(`l`), ctrl: true})
	assert app.focused_ctl() == ?&vtk.Ctl(field)
	field.set_text('folder with spaces')
	app.dispatch(vtk.Event{key: int(vtk.Key.enter)})
	assert pane.path == os.real_path(child)
	assert app.focused_ctl() == ?&vtk.Ctl(pane.canvas)

	row := field.parent_ctl() or { return error('missing location row') }
	go_button := row.children().filter(it.text == 'Go')[0]
	app.redraw()
	area := go_button.rect()
	assert area.y == field.rect().y && area.x >= field.rect().x + field.rect().w
	assert area.x + area.w <= pane.win.rect().x + pane.win.rect().w - 1
	click := vtk.Event{kind: .mouse, button: .left, pressed: true, x: area.x, y: area.y}
	field.set_text('missing')
	app.dispatch(click)
	assert pane.path == os.real_path(child)
	assert field.text == 'missing' && app.focused_ctl() == ?&vtk.Ctl(field)
	assert pane.status.text.contains('missing')
	app.dispatch(vtk.Event{...click, pressed: false})

	field.set_text(os.join_path('..', 'notes.txt'))
	app.dispatch(click)
	assert pane.path == os.real_path(root)
	assert pane.selected[os.join_path(os.real_path(root), 'notes.txt')]
	assert app.focused_ctl() == ?&vtk.Ctl(pane.canvas)
}

fn test_files_menubar_dispatches_window_edit_and_view_actions() ! {
	root := util.temp_dir(pattern: 'vtk-files-menus-')!
	defer { os.rmdir_all(root) or {} }
	os.write_file(os.join_path(root, 'notes.txt'), '')!
	mut app := vtk.new_app()
	defer { app.fini() }
	app.dispatch(vtk.Event{kind: .resize, width: 100, height: 30})
	first := new_files_window(mut app, shared_for(mut app), root)
	app.redraw()
	assert first.win.children().filter(it.kind == .menu).map(it.text) == ['File', 'Edit', 'View', 'Help']
	app.dispatch(vtk.Event{key: int(vtk.Key.f10)})
	app.dispatch(vtk.Event{key: int(vtk.Key.enter)})
	assert app.window_list().len == 2
	second := pane_from(app.window_list().last()) or { return error('missing second Files pane') }
	assert second.path == first.path
	app.redraw()

	menus := second.win.children().filter(it.kind == .menu)
	edit := menus[1].rect()
	app.dispatch(vtk.Event{kind: .mouse, button: .left, pressed: true, x: edit.x, y: edit.y})
	app.dispatch(vtk.Event{key: int(vtk.Key.enter)})
	assert second.selected.len == 1 && first.selected.len == 0
	view := menus[2].rect()
	app.dispatch(vtk.Event{kind: .mouse, button: .left, pressed: true, x: view.x, y: view.y})
	app.dispatch(vtk.Event{key: int(vtk.Key.down)})
	app.dispatch(vtk.Event{key: int(vtk.Key.enter)})
	assert second.view == .icons && first.view == .list
}

fn test_double_click_prompts_for_an_opener_and_loads_the_file_in_word() ! {
	directory := util.temp_dir(pattern: 'vtk-files-open-')!
	defer { os.rmdir_all(directory) or {} }
	os.write_file(os.join_path(directory, 'draft notes.md'), 'Content from the selected file')!
	mut app := vtk.new_app()
	defer { app.fini() }
	app.dispatch(vtk.Event{kind: .resize, width: 100, height: 30})
	pane := new_files_window(mut app, shared_for(mut app), directory)
	app.redraw()
	area := pane.canvas.rect()
	press := vtk.Event{kind: .mouse, button: .left, pressed: true, x: area.x + 2, y: area.y + header_rows}
	app.dispatch(press)
	app.dispatch(vtk.Event{...press, pressed: false})
	app.after(0, fn (mut app vtk.App) {
		app.redraw()
		dialog := app.top_window() or { panic('missing Open With dialog') }
		assert dialog.text == 'Open draft notes.md with'
		buttons := dialog.children()[0].children()
		assert buttons.map(it.text) == ['Word', 'Slides', 'Sheets', 'Paint',
			'Open folder in Terminal', 'System launcher']
		button := buttons[0].rect()
		app.dispatch(vtk.Event{kind: .mouse, button: .left, pressed: true, x: button.x, y: button.y})
	})
	app.dispatch(press)
	assert app.window_list().len == 2
	app.redraw()
	assert app.snapshot().contains('Content from the selected file')
}

fn test_decode_uri_preserves_utf8_and_literal_path_characters() {
	assert decode_uri('caf%C3%A9%20%E6%97%A5+%f0%9f%8c%9f.txt') == 'café 日+🌟.txt'
	assert decode_uri('café%20photo.jpg') == 'café photo.jpg'
	assert decode_uri('%25%00%+1%GG%2%') == '%%00%+1%GG%2%'
}

fn test_sort_keeps_folders_first_and_preserves_ties() {
	mut entries := [Entry{name: 'same'}, Entry{name: 'before'}, Entry{name: 'Zoo', dir: true},
		Entry{name: 'SAME'}, Entry{name: 'aardvark', dir: true}]
	sort_entries(mut entries, .name, false)
	assert entries.map(it.name) == ['aardvark', 'Zoo', 'before', 'same', 'SAME']
	sort_entries(mut entries, .name, true)
	assert entries.map(it.name) == ['Zoo', 'aardvark', 'same', 'SAME', 'before']
}

fn test_sort_reorders_cached_columns_and_preserves_selection() ! {
	root := util.temp_dir(pattern: 'vtk-files-sort-')!
	defer { os.rmdir_all(root) or {} }
	dir := os.join_path(root, 'target')
	os.mkdir(dir)!
	os.mkdir(os.join_path(root, 'other'))!
	for name in ['a.txt', 'b.txt'] {
		os.write_file(os.join_path(dir, name), '')!
	}
	mut app := vtk.new_app()
	defer { app.fini() }
	app.dispatch(vtk.Event{kind: .resize, width: 100, height: 30})
	mut pane := new_files_window(mut app, shared_for(mut app), dir)
	pane.set_cursor(0, false)
	picked := pane.cursor_path
	set_view(mut pane, .columns)
	// The original path is unreadable and the parent listing has changed on disk.
	os.mv(dir, os.join_path(root, 'renamed'))!
	view_menu := pane.win.children().filter(it.kind == .menu && it.text == 'View')[0]
	sort_menu := view_menu.children().filter(it.kind == .menu && it.text == 'Sort by')[0]
	mut sort_by_name := sort_menu.children().filter(it.text == 'Name')[0]
	sort_by_name.fire()
	last := pane.cols.len - 1
	parent := pane.cols[last - 1]
	assert parent.entries.map(it.name) == ['target', 'other']
	assert parent.cursor == 0
	assert pane.entries.map(it.name) == ['b.txt', 'a.txt']
	entry := entry_at(pane, last, 1) or { return error('missing selected entry in column view') }
	assert entry.path == picked
	assert pane.cursor == 1 && pane.anchor == 1 && pane.selected[picked]
}

fn test_status_reports_capped_directory_scans() ! {
	root := util.temp_dir(pattern: 'vtk-files-limit-')!
	defer { os.rmdir_all(root) or {} }
	child := os.join_path(root, 'child')
	os.mkdir(child)!
	for i in 1 .. scan_limit {
		os.write_file(os.join_path(root, '${i}'), '')!
	}
	mut app := vtk.new_app()
	defer { app.fini() }
	app.dispatch(vtk.Event{kind: .resize, width: 100, height: 30})
	mut pane := new_files_window(mut app, shared_for(mut app), root)
	assert pane.entries.len == scan_limit
	assert !pane.status.text.contains('capped')
	os.write_file(os.join_path(root, 'extra'), '')!
	pane.refresh()
	assert pane.entries.len == scan_limit
	app.redraw()
	assert app.snapshot().contains('Scan capped at ${scan_limit} names')
	pane.navigate(child, false)
	assert !pane.status.text.contains('capped')
	set_view(mut pane, .columns)
	assert pane.status.text.contains('Column scan capped at ${scan_limit} names')
}

fn test_launch_opens_windows_that_share_drag_state() {
	mut app := vtk.new_app()
	app.dispatch(vtk.Event{ kind: .resize, width: 100, height: 30 })
	launch(mut app)
	assert app.window_list().len == 1
	mut first := app.window_list().last()
	assert first.text.starts_with('Files - ')
	first.set_text('Renamed Files window')
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
