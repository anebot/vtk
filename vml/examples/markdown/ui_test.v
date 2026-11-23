module main

import vtk

fn test_markdown_actions_keep_preview_and_counts_in_sync() {
	mut app := vtk.new_app()
	defer { app.fini() }
	window := build_ui(mut app)
	body := window.children()[0].children()
	toolbar := body[0].children()
	mut undo := toolbar[0]
	mut redo := toolbar[1]
	mut reset := toolbar[2]
	line_numbers := toolbar[3]
	mut split_share := toolbar[5]
	panes := body[1].children()
	mut source := panes[0].children()[1]
	mut preview := panes[1].children()[1]
	status := body[2]
	assert source.text == sample_markdown && preview.text == sample_markdown
	assert preview.readonly && !preview.md.task_interactive
	assert !preview.replace_selection('read-only')
	edited := '# Revised\n\nHello VML!'
	assert source.replace_range(0, source.text.len, edited)
	assert preview.text == edited && status.text == document_status(edited)
	undo.fire()
	assert source.text == sample_markdown && preview.text == sample_markdown
	redo.fire()
	assert source.text == edited && preview.text == edited
	reset.fire()
	assert source.text == sample_markdown && preview.text == sample_markdown
	undo.fire()
	assert source.text == edited && status.text == document_status(edited)
	app.set_focus(line_numbers)
	app.dispatch(vtk.Event{ key: int(vtk.Key.space) })
	assert !source.line_numbers
	split_share.set_value(700)
	app.redraw()
	assert source.rect().w > preview.rect().w
	assert app.snapshot().contains('3 lines')
}
