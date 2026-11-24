module word

import vtk

fn test_canceling_save_as_keeps_the_edit_group_open() {
	mut app := vtk.new_app()
	defer { app.fini() }
	mut doc := &Document{
		window:  app.window('Document', 60, 20)
		view:    vtk.markdown('a')
		outline: vtk.tree()
		status:  vtk.statusbar('')
		toolbar: vtk.toolbar()
	}
	doc.view.begin_edit_group()
	assert doc.view.replace_range(1, 1, 'b')
	app.after(0, fn (mut app vtk.App) {
		mut dialog := app.top_window() or { panic('missing Save As dialog') }
		app.close(mut dialog)
	})
	assert !save(mut doc, true, mut app)
	assert doc.view.replace_range(2, 2, 'c')
	assert doc.view.undo()
	assert doc.view.text == 'a'
}
