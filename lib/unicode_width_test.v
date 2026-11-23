module vtk

fn test_emoji_presentation_sequences_have_their_terminal_cell_width() {
	assert rune_width(`✅`) == 2
	assert rune_width(`🟡`) == 2
	for emoji in ['✅', '⚠️', '🟡', '✖️', '❤️', '👍🏽', '👩‍💻',
		'👨‍👩‍👧‍👦', '🇪🇸', '1️⃣', '🗑️'] {
		assert text_width(emoji) == 2, emoji
		assert text_width('a${emoji}b') == 4, emoji
	}
	assert text_width('⚠') == 1
	assert text_width('⚠︎') == 1
	assert text_width('🗑') == 1
	assert text_width('e\u0301') == 1
	assert text_width('界') == 2
}

fn test_emoji_table_columns_stay_aligned_in_the_screen_and_ansi_output() {
	mut app := new_app()
	app.desktop = false
	app.width = 60
	app.height = 20
	source := '| # | Verdict | Note |\n| --- | :---: | --- |\n| 1 | ✅ | passed |\n| 2 | 🟡 | follow up |\n| 3 | ⚠️ | warning |\n| 4 | X | declined |\n| 5 | 👩‍💻 | developer |\n| 6 | 🇪🇸 | country |'
	mut c := markdown(source)
	c.markdown_mode(.read)
	c.md.hide_status = true
	mut window := app.window('Verdicts', 58, 18)
	window.add(mut c)
	app.redraw()
	mut expected := []int{}
	for row_index in 3 .. 9 {
		mut borders := []int{}
		for x in 0 .. c.w {
			if app.screen.cells[(c.y + row_index) * app.width + c.x + x].glyph == '│' {
				borders << x
			}
		}
		if expected.len == 0 { expected = borders.clone() }
		assert borders == expected && borders.len == 4
	}
	mut terminal := new_terminal(app.width, app.height)
	terminal.feed(app.screen.diff())
	for i, cell in app.screen.cells {
		assert terminal.cells[i].glyph == cell.glyph, 'cell ${i}: ${terminal.cells[i].glyph} != ${cell.glyph}'
		assert terminal.cells[i].continuation == cell.continuation, 'cell ${i}'
	}
}

fn test_screen_draws_and_clips_whole_emoji_clusters() {
	mut screen := Screen{}
	screen.resize(12, 2)
	screen.text(0, 0, 'a⚠️b✅c', white, black, 0)
	assert screen.cells[1].glyph == '⚠️' && screen.cells[2].continuation
	assert screen.cells[3].glyph == 'b'
	assert screen.cells[4].glyph == '✅' && screen.cells[5].continuation
	assert screen.cells[6].glyph == 'c'
	screen.text(11, 1, '⚠️', white, black, 0)
	assert screen.cells[23].glyph == ' ' && screen.cells[22].glyph == ' '
	screen.text(10, 1, '👩‍💻', white, black, 0)
	assert screen.cells[22].glyph == '👩‍💻' && screen.cells[23].continuation
	screen.put(11, 1, `x`, white, black, 0)
	assert screen.cells[22].glyph == ' ' && screen.cells[23].glyph == 'x'
}

fn test_wrapping_and_hit_testing_do_not_split_variation_or_joined_emoji() {
	mut c := markdown('A⚠️B👩‍💻C🇪🇸D')
	c.w = 3
	rows := c.editor_rows()
	assert rows.len == 4
	assert rows[0].glyphs.map(glyph_text(it)).join('') == 'A⚠️'
	assert rows[1].glyphs.map(glyph_text(it)).join('') == 'B👩‍💻'
	assert rows[2].glyphs.map(glyph_text(it)).join('') == 'C🇪🇸'
	assert row_hit(rows[0], 1, 4, false) == 1
	assert row_hit(rows[0], 2, 4, false) == 1
	assert row_hit(rows[0], 3, 4, false) == 'A⚠️'.len
}

fn test_terminal_keeps_emoji_width_when_sequences_arrive_byte_by_byte() {
	mut terminal := new_terminal(40, 2)
	text := '✅🟡⚠️👩‍💻🇪🇸1️⃣👍🏽'
	for byte in text.bytes() { terminal.feed(byte.ascii_str()) }
	assert terminal.cx == 14
	assert terminal.cells[4].glyph == '⚠️' && terminal.cells[5].continuation
	assert terminal.cells[6].glyph == '👩‍💻' && terminal.cells[7].continuation
	assert terminal.cells[8].glyph == '🇪🇸' && terminal.cells[9].continuation
	mut narrow := new_terminal(2, 2)
	narrow.feed('a⚠')
	narrow.feed('️')
	assert narrow.cy == 1 && narrow.cx == 2
	assert narrow.cells[0].glyph == 'a' && narrow.cells[1].glyph == ' '
	assert narrow.cells[2].glyph == '⚠️' && narrow.cells[3].continuation
}
