module vtk

fn test_markdown_alignment_hides_fences_and_shifts_rows() {
	mut md := markdown('::: {.htk-align-center style="text-align:center"}\nhello\n:::\nafter')
	md.set_wrap_mode(.word)
	md.w = 21
	rows := md.editor_rows()
	assert rows.len == 2
	assert rows[0].align == .center
	assert rows[0].pad == 2 + (21 - 2 - 5) / 2
	assert rows[0].glyphs.len == 5
	assert rows[1].align == .none && rows[1].pad == 0
	// The class alone is enough, as in htk's HTML-aware readers.
	mut plain := markdown('::: {.htk-align-right}\nhi\n:::')
	plain.set_wrap_mode(.word)
	plain.w = 20
	right := plain.editor_rows()
	assert right[0].align == .right
	assert right[0].pad == 2 + (20 - 2 - 2)
}

fn test_markdown_alignment_justifies_every_row_but_the_last() {
	mut md := markdown('::: {.htk-align-justify style="text-align:justify"}\nalpha beta gamma delta\n:::')
	md.set_wrap_mode(.word)
	md.w = 15
	rows := md.editor_rows()
	assert rows.len == 2
	assert rows[0].align == .justify
	assert rows[0].pad == markdown_align_indent
	assert rows[0].gapw[5] == 2
	assert rows[1].glyphs.len > 0 && rows[1].gapw.len == 0
}

fn test_markdown_alignment_stretches_wide_paragraphs_until_the_last_line() {
	mut md := markdown('::: {.htk-align-justify style="text-align:justify"}\nalpha beta gamma delta epsilon zeta eta theta\n:::')
	md.set_wrap_mode(.word)
	md.w = 30
	rows := md.editor_rows()
	mut total := 0
	for row in rows { total += row.gapw.len }
	assert total > 0
	assert rows.last().gapw.len == 0
}

fn test_markdown_alignment_draws_shifted_text() {
	mut app := new_app()
	app.screen.resize(30, 6)
	mut md := markdown('::: {.htk-align-right style="text-align:right"}\nhi\n:::')
	md.md.hide_status = true
	md.set_wrap_mode(.word)
	md.measure()
	md.layout(Rect{0, 0, 20, 6})
	app.screen.fill(md.rect(), ` `, app.theme.fg, app.theme.bg)
	app.draw_ctl(mut md)
	assert app.screen.cells[18].glyph == 'h'
	assert app.screen.cells[19].glyph == 'i'
}

fn test_markdown_alignment_justify_draws_extra_word_gaps() {
	mut app := new_app()
	app.screen.resize(30, 6)
	mut md := markdown('::: {.htk-align-justify style="text-align:justify"}\nalpha beta gamma delta\n:::')
	md.md.hide_status = true
	md.set_wrap_mode(.word)
	md.md.column_width = 15
	md.measure()
	md.layout(Rect{0, 0, 30, 6})
	app.screen.fill(md.rect(), ` `, app.theme.fg, app.theme.bg)
	app.draw_ctl(mut md)
	rows := app.screen.snapshot().split('\n')
	assert rows[0].trim_right(' ') == '  alpha   beta'
	assert rows[1].trim_right(' ') == '  gamma delta'
}

fn test_markdown_alignment_keeps_the_caret_in_the_first_paragraph() {
	mut md := markdown('::: {.htk-align-left style="text-align:left"}\nhello\n:::')
	md.w = 20
	rows := md.editor_rows()
	assert rows.len == 1
	assert md.caret_row(rows) == 0
	assert md.editor_rows()[md.caret_row(md.editor_rows())].glyphs.len == 5
}

fn test_markdown_alignment_leaves_unclosed_divs_visible() {
	mut md := markdown('::: {.htk-align-center style="text-align:center"}\nhello')
	md.set_wrap_mode(.word)
	md.w = 60
	rows := md.editor_rows()
	assert rows.len == 2
	assert rows[0].align == .none && rows[0].glyphs.len > 0
	assert rows[1].align == .none
}

fn test_markdown_align_wraps_and_replaces_paragraph_fences() {
	fence_center := '::: {.htk-align-center style="text-align:center"}'
	fence_right := '::: {.htk-align-right style="text-align:right"}'
	mut md := markdown('alpha beta\n\ngamma')
	assert md.markdown_align(.center)
	assert md.text == '${fence_center}\nalpha beta\n:::\n\ngamma'
	assert md.markdown_align_at(md.cursor) == .center
	md.anchor = 0
	md.cursor = md.text.len
	assert md.markdown_align(.right)
	assert md.text == '${fence_right}\nalpha beta\n:::\n\n${fence_right}\ngamma\n:::\n'
	assert md.markdown_align_at(0) == .right
	assert md.markdown_align_at(md.text.len - 1) == .right
}

fn test_markdown_align_skips_code_blocks_and_tables() {
	source := '```\nalpha\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |'
	mut md := markdown(source)
	md.anchor = 0
	md.cursor = md.text.len
	assert !md.markdown_align(.left)
	assert md.text == source
}
