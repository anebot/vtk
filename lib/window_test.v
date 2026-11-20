module vtk

fn test_window_titles_stop_before_controls_and_preserve_the_frame() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('X'.repeat(80), 40, 8)
	app.redraw()
	row := w.y * app.width + w.x
	assert app.screen.cells[row + 29].glyph == 'X'
	assert app.screen.cells[row + 30..row + 39].map(it.glyph).join('') == '[_][□][■]'
	w.controls = window_close
	app.redraw()
	assert app.screen.cells[row + 35].glyph == 'X'
	assert app.screen.cells[row + 36..row + 39].map(it.glyph).join('') == '[■]'
	w.controls = 0
	app.redraw()
	assert app.screen.cells[row + 38].glyph == 'X'
	assert app.screen.cells[row + 39].glyph == '╗'
	w.controls = window_default_controls
	w.set_text('界'.repeat(80))
	app.redraw()
	assert app.screen.cells[row + 28].glyph == '界' && app.screen.cells[row + 29].continuation
	assert app.screen.cells[row + 30].glyph == '['
	w.set_text('e\u0301'.repeat(80))
	app.redraw()
	assert app.screen.cells[row + 29].glyph == 'e\u0301'
	assert app.screen.cells[row + 30].glyph == '['
}
