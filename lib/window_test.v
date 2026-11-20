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

fn test_window_minimum_size_limits_and_resizing() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Tiny', 1, 1)
	assert w.w == 16 && w.h == 3 && w.min_w == 16 && w.min_h == 3
	w.set_size_limits(1, 1, 8, 2)
	assert w.w == 16 && w.h == 3 && w.max_w == 16 && w.max_h == 3
	w.set_size_limits(16, 3, 0, 0)
	w.w = 30
	w.h = 10
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: w.x + w.w - 1, y: w.y + w.h - 1, button: .left, pressed: true })
	app.dispatch(Event{ kind: .mouse, x: 0, y: 0, button: .left, pressed: true, motion: true })
	app.dispatch(Event{ kind: .mouse, x: 0, y: 0, button: .left })
	assert w.w == 16 && w.h == 3
	app.begin_placement(mut w, true)
	for _ in 0 .. 30 {
		app.dispatch(Event{ key: int(Key.left) })
		app.dispatch(Event{ key: int(Key.up) })
	}
	app.dispatch(Event{ key: int(Key.enter) })
	assert w.w == 16 && w.h == 3
	app.width = 12
	app.height = 2
	app.tile()
	assert w.w == 16 && w.h == 3
	app.cascade()
	assert w.w == 16 && w.h == 3
	w.set_size_limits(20, 6, 0, 0)
	app.cascade()
	assert w.w == 20 && w.h == 6
}
