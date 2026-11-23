module vtk

fn markdown_row_text(row TextRow) string { return row.glyphs.map(it.r).string() }

fn test_markdown_tables_render_alignment_inline_styles_and_source_spans() {
	source := '| Name | Center | Value |\n| :--- | :---: | ---: |\n| **é😀** | [docs](https://example.com) | `42` |\n| a\\|b | ``a|b`` | 7 |'
	mut c := markdown(source)
	c.markdown_mode(.read)
	c.w = 60
	rows := c.editor_rows()
	assert rows.len == 6
	assert markdown_row_text(rows[0]).starts_with('┌')
	assert markdown_row_text(rows[2]).contains('┼')
	assert markdown_row_text(rows[5]).starts_with('└')
	assert markdown_row_text(rows[3]).contains('é😀')
	assert !markdown_row_text(rows[3]).contains('**')
	assert markdown_row_text(rows[4]).contains('a|b')
	assert !markdown_row_text(rows[4]).contains('``')
	for row in rows {
		assert markdown_glyph_width(row.glyphs) == markdown_glyph_width(rows[0].glyphs)
	}
	for glyph in rows[3].glyphs {
		if glyph.r == `é` {
			assert glyph.attr & bold != 0 && source[glyph.at..glyph.end] == 'é'
		}
		if glyph.r == `d` {
			assert glyph.link == 'https://example.com'
		}
		if glyph.r == `4` {
			assert glyph.attr & reverse != 0
		}
	}
	assert markdown_row_text(rows[3]).ends_with(' 42 │')
	assert c.text == source
	c.markdown_mode(.source_read)
	assert !c.markdown_rows().any(markdown_row_text(it).contains('┌'))
}

fn test_tables_wrap_cells_on_resize_and_keep_mouse_selection_on_source() {
	mut app := new_app()
	app.desktop = false
	mut c := markdown('| ID | Description |\n| --- | --- |\n| 7 | A long response with é😀 text and more words |')
	c.markdown_mode(.read)
	c.md.hide_status = true
	mut window := app.window('Markdown', 38, 18)
	window.add(mut c)
	app.redraw()
	wide := c.editor_rows().len
	c.w = 23
	rows := c.editor_rows()
	assert rows.len > wide
	for row in rows {
		assert markdown_glyph_width(row.glyphs) <= 23
	}
	mut target_row, mut target_col := -1, 0
	for i, row in rows {
		mut column := 0
		for glyph in row.glyphs {
			if glyph.r == `é` {
				target_row = i
				target_col = column
			}
			column += rune_width(glyph.r)
		}
	}
	assert target_row >= 0
	c.editor_mouse(Event{ kind: .mouse, button: .left, pressed: true, x: c.x + target_col, y: c.y + target_row }, mut app)
	assert c.text[c.cursor..].starts_with('é')
	assert c.caret_row(rows) == target_row
	c.anchor = 0
	c.cursor = c.text.len
	app.set_focus(c)
	assert app.copy_focus()
	assert app.clipboard_text() == c.text
}

fn test_fences_indentation_streaming_and_invalid_tables_stay_literal() {
	for source in ['```md\n| A | B |\n| --- | --- |\n| 1 | 2 |\n```', '    | A | B |\n    | --- | --- |',
		'| A | B |\n| --- |', '| A | B |\n| -- | --- |', '| A | B |', '| A | B |\n| --- | --'] {
		mut c := markdown(source)
		c.w = 60
		assert !c.markdown_rows().any(markdown_row_text(it).contains('┌'))
	}
	mut c := markdown('A | B\n--- | ---\n1 | 2\n\nAfter')
	c.w = 60
	assert c.markdown_rows().any(markdown_row_text(it).contains('┌'))
	assert markdown_row_text(c.markdown_rows().last()) == 'After'
	c.set_text('| A | B |\n| --- | --- |\n| 1 |')
	assert c.markdown_rows().any(markdown_row_text(it).contains('1'))
	assert c.text.ends_with('| 1 |')
}

fn test_inline_code_handles_multiple_backticks_and_unfinished_streams() {
	assert inline_markdown('``a`b|c``', 0, 0).map(it.r).string() == 'a`b|c'
	assert inline_markdown('`unfinished', 0, 0).map(it.r).string() == '`unfinished'
	assert inline_markdown('`**literal**`', 0, 0).map(it.r).string() == '**literal**'
}
