module vtk

fn test_blocky_progress_has_square_blocks_and_empty_separators() {
	mut app := new_app()
	app.screen.resize(20, 3)
	mut progress := progress()
	progress.blocky = true
	progress.high = 4
	progress.layout(Rect{0, 0, 12, 1})
	for count in 0 .. 5 {
		progress.set_value(count)
		app.draw_ctl(mut progress)
		for block in 0 .. 4 {
			for column in 0 .. 2 {
				assert app.screen.cells[block * 3 + column].glyph == if block < count {
					'█'
				} else {
					' '
				}
			}
			assert app.screen.cells[block * 3 + 2].glyph == ' '
		}
	}
	for width in 1 .. 4 {
		progress.layout(Rect{0, 1, width, 1})
		app.draw_ctl(mut progress)
		assert app.screen.cells[20].glyph == '█'
	}
}

fn test_continuous_progress_respects_custom_ranges() {
	mut app := new_app()
	app.screen.resize(12, 1)
	mut progress := progress()
	progress.low = 10
	progress.high = 14
	progress.set_value(12)
	progress.layout(Rect{0, 0, 12, 1})
	app.draw_ctl(mut progress)
	assert app.screen.cells[..6].all(it.glyph == '█')
	assert app.screen.cells[6..].all(it.glyph == '░')
}
