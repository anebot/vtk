module vtk

fn test_markdown_left_ruler_labels_every_five_lines() {
	mut app := new_app()
	app.screen.resize(40, 14)
	mut md := markdown('one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten')
	md.md.ruler_left = true
	md.md.hide_status = true
	md.line_numbers = false
	md.measure()
	md.layout(Rect{0, 0, 40, 12})
	app.screen.fill(md.rect(), ` `, app.theme.fg, app.theme.bg)
	app.draw_ctl(mut md)
	rows := app.screen.snapshot().split('\n')
	assert md.editor_gutter() == 8
	assert rows[0].starts_with('   1  | one')
	assert rows[1].starts_with('      | two')
	assert rows[3].starts_with('      | four')
	assert rows[4].starts_with('   5  | five')
	assert rows[9].starts_with('  10  | ten')
}

fn test_markdown_left_ruler_counts_visual_rows_when_wrapped() {
	mut app := new_app()
	app.screen.resize(30, 16)
	mut md := markdown('alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron')
	md.md.ruler_left = true
	md.md.hide_status = true
	md.line_numbers = false
	md.set_wrap_mode(.word)
	md.md.column_width = 6
	md.measure()
	md.layout(Rect{0, 0, 30, 14})
	app.screen.fill(md.rect(), ` `, app.theme.fg, app.theme.bg)
	app.draw_ctl(mut md)
	rows := app.screen.snapshot().split('\n')
	assert md.editor_gutter() == 8
	assert rows[0].starts_with('   1  | alpha')
	assert rows[1].starts_with('      | beta')
	assert rows[4].starts_with('   5  |')
	assert rows[9].starts_with('  10  |')
}

fn test_markdown_plain_line_numbers_still_work() {
	mut app := new_app()
	app.screen.resize(40, 6)
	mut md := markdown('alpha\nbeta')
	md.md.hide_status = true
	md.line_numbers = true
	md.measure()
	md.layout(Rect{0, 0, 40, 6})
	app.screen.fill(md.rect(), ` `, app.theme.fg, app.theme.bg)
	app.draw_ctl(mut md)
	rows := app.screen.snapshot().split('\n')
	assert md.editor_gutter() == 5
	assert rows[0].starts_with('   1 alpha')
}

fn test_markdown_top_ruler_stops_at_page_width() {
	mut app := new_app()
	app.screen.resize(60, 6)
	mut md := markdown('alpha beta gamma delta epsilon zeta eta theta')
	md.md.ruler_top = true
	md.md.hide_status = true
	md.md.column_width = 12
	md.measure()
	md.layout(Rect{0, 0, 60, 6})
	app.screen.fill(md.rect(), ` `, app.theme.fg, app.theme.bg)
	app.draw_ctl(mut md)
	rows := app.screen.snapshot().split('\n')
	assert rows[0].starts_with('1---5----10-')
	assert rows[0][12] == ` `
}

fn test_markdown_top_ruler_fills_the_view_without_a_page_width() {
	mut app := new_app()
	app.screen.resize(40, 6)
	mut md := markdown('alpha')
	md.md.ruler_top = true
	md.md.hide_status = true
	md.md.column_width = 0
	md.measure()
	md.layout(Rect{0, 0, 40, 6})
	app.screen.fill(md.rect(), ` `, app.theme.fg, app.theme.bg)
	app.draw_ctl(mut md)
	rows := app.screen.snapshot().split('\n')
	assert rows[0].starts_with(markdown_ruler(40))
}

fn test_markdown_table_respects_page_width() {
	mut md := markdown('| Alpha alpha | Beta beta | Gamma gamma |\n|---|---|---|\n| one one one | two two two | three three three |')
	md.set_wrap_mode(.word)
	md.md.column_width = 20
	md.w = 80
	rows := md.editor_rows()
	for row in rows {
		assert row.no_wrap
		assert markdown_glyph_width(row.glyphs) <= 20
	}
}

fn test_markdown_table_shrinks_many_columns_to_page_width() {
	mut md := markdown('| A | B | C | D | E | F | G | H | I | J | K | L |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n| one | two | three | four | five | six | seven | eight | nine | ten | eleven | twelve |')
	md.set_wrap_mode(.word)
	md.md.column_width = 50
	md.w = 100
	rows := md.editor_rows()
	for row in rows {
		assert row.no_wrap
		assert markdown_glyph_width(row.glyphs) <= 50
	}
}

fn test_markdown_table_drops_padding_before_overflowing() {
	mut header := '|'
	mut separator := '|'
	mut body := '|'
	for i in 0 .. 15 {
		header += ' H${i} |'
		separator += '---|'
		body += ' value${i} |'
	}
	mut md := markdown('${header}\n${separator}\n${body}')
	md.set_wrap_mode(.word)
	md.md.column_width = 59
	md.w = 100
	rows := md.editor_rows()
	for row in rows {
		assert row.no_wrap
		assert markdown_glyph_width(row.glyphs) <= 59
	}
}

fn test_markdown_table_fits_page_width_without_wrapping() {
	mut md := markdown('| A | B | C | D | E | F | G | H | I | J | K | L |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n| one | two | three | four | five | six | seven | eight | nine | ten | eleven | twelve |')
	md.set_wrap_mode(.none)
	md.md.column_width = 50
	md.w = 100
	rows := md.editor_rows()
	for row in rows {
		assert row.no_wrap
		assert markdown_glyph_width(row.glyphs) <= 50
	}
}

fn test_markdown_table_draw_stops_at_page_width() {
	mut app := new_app()
	app.screen.resize(80, 8)
	mut md := markdown('| A | B | C | D |\n|---|---|---|---|\n| 1 | 2 | 3 | 4 |\n')
	md.md.hide_status = true
	md.md.column_width = 12
	md.set_wrap_mode(.word)
	md.measure()
	md.layout(Rect{0, 0, 80, 8})
	app.screen.fill(md.rect(), ` `, app.theme.fg, app.theme.bg)
	app.draw_ctl(mut md)
	assert app.screen.cells[12].glyph == ' '
}

fn test_markdown_page_width_limits_wrapped_rows() {
	mut md := markdown('alpha beta gamma delta')
	md.set_wrap_mode(.word)
	md.md.column_width = 6
	md.w = 40
	rows := md.editor_rows()
	assert rows.len > 1
	for row in rows { assert markdown_glyph_width(row.glyphs) <= 6 }
}
