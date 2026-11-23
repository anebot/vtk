module vtk

fn assert_presented(screen &Screen, terminal &Terminal) {
	assert terminal.cells == screen.cells
}

fn test_ansi_updates_preserve_cells_styles_wide_glyphs_and_cursor() {
	mut screen := Screen{}
	screen.resize(30, 8)
	mut terminal := new_terminal(30, 8)
	screen.text(0, 0, 'abcdef 👩‍💻 ok', white, blue, 0)
	screen.set_cursor(4, 0, .bar)
	terminal.feed(screen.diff())
	assert_presented(screen, terminal)
	assert terminal.cx == 4 && terminal.cy == 0 && !terminal.cursor_hidden
	assert screen.diff() == ''

	screen.put(0, 0, `A`, white, blue, 0)
	screen.put(3, 0, `D`, white, blue, 0)
	screen.put(4, 0, `E`, white, blue, bold | reverse)
	screen.put(5, 0, `F`, cyan, blue, bold)
	screen.put(9, 0, `x`, white, blue, 0)
	screen.put(8, 0, `界`, white, blue, 0)
	terminal.feed(screen.diff())
	assert_presented(screen, terminal)
	assert terminal.cx == 4 && terminal.cy == 0 && !terminal.cursor_hidden
	assert screen.diff() == ''
}

fn test_ansi_scroll_replays_in_both_directions_and_preserves_fixed_rows() {
	mut screen := Screen{}
	screen.resize(40, 10)
	mut terminal := new_terminal(40, 10)
	for y in 0 .. 10 {
		screen.fill(Rect{0, y, 40, 1}, rune(`a` + y), white, blue)
	}
	terminal.feed(screen.diff())
	for shift in [1, 0] {
		for y in 1 .. 9 {
			screen.fill(Rect{0, y, 40, 1}, rune(`a` + y + shift), white, blue)
		}
		update := screen.diff()
		assert update.len < 90
		terminal.feed(update)
		assert_presented(screen, terminal)
		assert screen.diff() == ''
	}
}

fn test_conservative_presenter_maps_colors_and_memory_works_without_tty() {
	mut screen := Screen{}
	screen.resize(20, 6)
	screen.text(0, 0, 'ready', color_rgb(240, 30, 25), color_256(21), underline)
	screen.set_cursor(1, 0, .bar)
	options := RenderOptions{ backend: .conservative }
	out := screen.present(options)
	assert !out.contains('38;2;') && !out.contains('48;5;') && !out.contains(' q')
	mut terminal := new_terminal(20, 6)
	terminal.feed(out)
	assert terminal.cells[0] == Cell{'r', 9, 12, underline, false}
	assert screen.present(options) == ''

	mut app := new_app()
	app.rendering = RenderOptions{ backend: .memory }
	app.bar_clock = false
	mut w := app.window('Snapshot', 30, 7)
	mut field := label('headless text')
	w.add(mut field)
	app.init() or { panic(err) }
	defer { app.fini() }
	app.step(0)
	assert !app.driver.active && app.screen.ansi.front.len == 0
	assert app.snapshot().contains('headless text')
}

fn test_partial_repaint_matches_full_layout_after_window_move() {
	mut app := new_app()
	app.bar_clock = false
	mut back := app.window('Background', 50, 18)
	mut body := markdown('A界B👩‍💻C '.repeat(6))
	back.add(mut body)
	mut front := app.window('Overlay', 24, 6)
	mut field := entry('wide 界', 0)
	front.add(mut field)
	app.set_focus(field)
	app.redraw()
	app.move(mut front, front.x + 7, front.y + 5)
	app.step(0)
	cells := app.screen.cell_snapshot()
	x, y := app.screen.cursor_x, app.screen.cursor_y
	app.redraw()
	assert app.screen.cells == cells
	assert app.screen.cursor_x == x && app.screen.cursor_y == y
}

fn test_incremental_markdown_matches_fresh_layout_at_append_boundaries() {
	mut editor := markdown('')
	editor.w = 26
	editor.set_wrap_mode(.word)
	mut source := 'Intro\n\n'
	for chunk in ['| Key | Value |', '\n| --- | --- |\n| α | content |', '\n| β | more |\n\n',
		'```c\n/* comment\n', 'still in comment\ncontinued ', 'here */\nint n = 42;\n', '```\n\n',
		'👩', '\u200d💻 reports', '\n'] {
		source += chunk
		editor.set_text(source)
		incremental := editor.editor_rows()
		mut fresh := markdown(source)
		fresh.w = editor.w
		fresh.set_wrap_mode(.word)
		expected := fresh.editor_rows()
		assert incremental.len == expected.len, chunk
		for i, row in expected {
			matches := row == incremental[i]
			assert matches, 'chunk=${chunk} row=${i} expected=${row.start},${row.end},${row.line} actual=${incremental[i].start},${incremental[i].end},${incremental[i].line}'
		}
	}
}

fn test_passive_motion_does_not_repaint_an_unrelated_canvas() {
	mut app := new_app()
	app.bar_clock = false
	mut w := app.window('Motion', 35, 10)
	mut c := canvas(8, 3, fn (mut control Ctl, mut _ Screen) { control.data++ })
	w.add(mut c)
	app.redraw()
	e := Event{ kind: .mouse, x: w.x + 3, y: w.y, motion: true }
	app.dispatch(e)
	app.step(0)
	paints := c.data
	app.dispatch(e)
	app.step(0)
	assert c.data == paints && !app.needs_frame()
}

fn test_append_preserves_diff_hunk_state() {
	mut editor := multiline('@@ -1,2 +1,2 @@\n-old\n+new')
	editor.syntax = .diff
	editor.editor_rows()
	editor.set_text(editor.text + '\n context\n--- a/file\n+++ b/file')
	rows := editor.editor_rows()
	assert rows[1].color == ?int(red)
	assert rows[2].color == ?int(green)
	assert rows[3].color == none
	assert rows[4].attr == bold && rows[5].attr == bold
}
