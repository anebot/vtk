module vtk

fn code_color(row TextRow, text string, token string) ?int {
	at := row.start + (text.index(token) or { panic('missing ${token}') })
	for glyph in row.glyphs {
		if glyph.at == at { return glyph.color }
	}
	panic('missing glyph at ${at}')
}

fn test_markdown_code_colors_tokens_and_preserves_unicode_source_spans() {
	line := 'const café = "é😀 // literal"; return 42 // comment'
	for language in ['v', 'c', 'python', 'javascript', 'unknown', ''] {
		source := '~~~${language}\n${line}\n~~~\nreturn 42'
		mut c := markdown(source)
		for mode in [MarkdownMode.read, .source_read] {
			c.markdown_mode(mode)
			rows := c.markdown_rows()
			row := rows[1]
			assert code_color(row, line, 'const') == ?int(magenta)
			assert code_color(row, line, 'café') == none
			assert code_color(row, line, '"é😀') == ?int(green)
			assert code_color(row, line, '// literal') == ?int(green)
			assert code_color(row, line, 'return') == ?int(magenta)
			assert code_color(row, line, '42') == ?int(cyan)
			assert code_color(row, line, '// comment') == ?int(gray)
			for glyph in row.glyphs {
				assert source[glyph.at..glyph.end] == glyph_text(glyph)
			}
			assert rows[3].glyphs.all(it.color == none)
		}
	}
}

fn test_markdown_code_state_stays_inside_each_block_and_plain_text_is_literal() {
	mut c := markdown('```c\n/* comment\nreturn 42 */ const x = true\n```\n```js\n`template\n/* literal */` // comment\n```\n```text\nconst x = "plain" // text\n```\n    return 42')
	c.markdown_mode(.read)
	rows := c.markdown_rows()
	assert rows[1].glyphs.all(it.color == ?int(gray))
	assert code_color(rows[2], 'return 42 */ const x = true', 'return') == ?int(gray)
	assert code_color(rows[2], 'return 42 */ const x = true', 'const') == ?int(magenta)
	assert code_color(rows[2], 'return 42 */ const x = true', 'true') == ?int(cyan)
	assert code_color(rows[6], '/* literal */` // comment', '/* literal') == ?int(green)
	assert code_color(rows[6], '/* literal */` // comment', '// comment') == ?int(gray)
	assert rows[9].glyphs.all(it.color == none)
	assert code_color(rows[11], '    return 42', 'return') == ?int(magenta)
	// An unfinished comment must not leak into the next fence.
	c.set_text('```c\n/* unfinished\n```\n```v\nreturn 42\n```')
	assert code_color(c.markdown_rows()[4], 'return 42', 'return') == ?int(magenta)
}

fn test_markdown_diff_reuses_hunk_counts_and_resets_at_fences() {
	patch := '--- a/a\n+++ b/a\n@@ -1,2 +1,2 @@\n--- removed heading\n+++ added heading\n-old\n+new'
	for language in ['diff', 'patch', ''] {
		mut c := markdown('```${language}\n${patch}\n```\n```v\nreturn 42\n```')
		c.markdown_mode(.read)
		rows := c.markdown_rows()
		assert rows[1].attr == bold && rows[2].attr == bold
		assert rows[3].color == ?int(cyan)
		assert rows[4].color == ?int(red) && rows[5].color == ?int(green)
		assert rows[6].color == ?int(red) && rows[7].color == ?int(green)
		assert rows[10].color == none
		assert code_color(rows[10], 'return 42', 'return') == ?int(magenta)
		c.w = 8
		for row in c.editor_rows() {
			if row.line == 4 { assert row.color == ?int(red) }
			if row.line == 5 { assert row.color == ?int(green) }
		}
	}
	mut fragment := markdown('```diff\n-old\n+new\n```')
	fragment.markdown_mode(.read)
	assert fragment.markdown_rows()[1].color == ?int(red)
	assert fragment.markdown_rows()[2].color == ?int(green)
}

fn test_markdown_syntax_colors_keep_uniform_shading_selection_and_style_overrides() {
	source := '```v\nreturn "é😀" + 42\n```\n```diff\n@@ -1 +1 @@\n-old\n+new\n```'
	for preset in [Preset.modern, .light] {
		mut app := new_app()
		app.theme = theme_preset(preset)
		app.screen.resize(40, 12)
		mut c := markdown(source)
		c.markdown_mode(.read)
		c.md.hide_status = true
		c.layout(Rect{0, 0, 40, 12})
		app.draw_editor(mut c)
		assert app.screen.cells[40].fg == magenta
		assert app.screen.cells[47].fg == green
		assert app.screen.cells[55].fg == cyan
		assert app.screen.cells[5 * 40].fg == red
		assert app.screen.cells[6 * 40].fg == green
		background := app.screen.cells[40 + 30].bg
		for x in 0 .. 16 { assert app.screen.cells[40 + x].bg == background }
		assert app.screen.cells[5 * 40].bg == background
		c.anchor = 5
		c.cursor = 11
		app.draw_editor(mut c)
		assert app.screen.cells[40].fg == app.theme.sel_fg
		assert app.screen.cells[40].bg == app.theme.sel_bg
		c.anchor = -1
		c.cursor = 0
		c.disabled = true
		app.draw_editor(mut c)
		assert app.screen.cells[40].fg == app.theme.dim
		c.disabled = false
		c.md.styles.code_block.fg = yellow
		app.draw_editor(mut c)
		assert app.screen.cells[40].fg == yellow
		assert app.screen.cells[5 * 40].fg == yellow
	}
}
