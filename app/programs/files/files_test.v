module files

import io.util
import os
import vtk

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
	mut option := vtk.new_ctl(.menuitem)
	option.set_context(pane)
	option.data = i64(SortBy.name)
	choose_sort(mut option, mut app)
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
