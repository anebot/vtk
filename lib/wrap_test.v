module vtk

fn wrap_row_text(row TextRow) string { return row.glyphs.map(glyph_text(it)).join('') }

fn test_wrap_modes_preserve_defaults_and_legacy_flags() {
	mut text := multiline('alpha beta')
	assert text.wrap_mode() == .none
	text.wrap = true
	assert text.wrap_mode() == .character
	assert text.set_wrap_mode(.word) && text.wrap_mode() == .word && text.wrap
	text.wrap = false
	assert text.wrap_mode() == .none
	assert text.set_wrap_mode(.character) && text.wrap_mode() == .character
	mut md := markdown('alpha beta')
	assert md.wrap_mode() == .character
	md.md.no_wrap = true
	assert md.wrap_mode() == .none
	assert md.set_wrap_mode(.word) && md.wrap && !md.md.no_wrap
	assert md.set_wrap_mode(.none) && !md.wrap && md.md.no_wrap
	mut input := entry('one line', 0)
	assert input.wrap_mode() == .none && !input.set_wrap_mode(.word)
	mut label := label('Label')
	assert !label.set_wrap_mode(.character)
}

fn test_character_and_word_wrap_keep_source_spans_and_overlong_words() {
	source := 'alpha beta gamma delta'
	mut text := multiline(source)
	text.w = 8
	text.set_wrap_mode(.none)
	assert text.editor_rows().map(wrap_row_text(it)) == [source]
	text.set_wrap_mode(.character)
	assert text.editor_rows().map(wrap_row_text(it)) == ['alpha be', 'ta gamma', ' delta']
	text.set_wrap_mode(.word)
	rows := text.editor_rows()
	assert rows.map(wrap_row_text(it)) == ['alpha ', 'beta ', 'gamma ', 'delta']
	assert rows.map(wrap_row_text(it)).join('') == source
	for i, row in rows {
		assert row.line == 0 && row.start < row.end
		assert source[row.start..row.end] == wrap_row_text(row)
		if i + 1 < rows.len { assert row.end == rows[i + 1].start }
	}
	text.set_text('abcde fghijklmnop')
	text.w = 5
	assert text.editor_rows().map(wrap_row_text(it)) == ['abcde ', 'fghij', 'klmno', 'p']
	assert text.text == 'abcde fghijklmnop'
}

fn test_word_wrap_hangs_whitespace_and_preserves_tabs_blank_lines_and_graphemes() {
	mut text := multiline('ab\tcd\n\nlast\n')
	text.w = 3
	text.md.tab_width = 4
	text.set_wrap_mode(.character)
	assert text.editor_rows().map(wrap_row_text(it)) == ['ab', '\t', 'cd', '', 'las', 't', '']
	text.set_wrap_mode(.word)
	rows := text.editor_rows()
	assert rows.map(wrap_row_text(it)) == ['ab\t', 'cd', '', 'las', 't', '']
	assert rows.map(it.line) == [0, 0, 1, 2, 2, 3]
	text.set_text('café 👩‍💻 🇪🇸 omega')
	text.w = 6
	assert text.editor_rows().map(wrap_row_text(it)) == ['café ', '👩‍💻 🇪🇸 ', 'omega']
	text.set_text('x aa\u00a0bb')
	text.w = 6
	assert text.editor_rows().map(wrap_row_text(it)) == ['x ', 'aa\u00a0bb']
	text.set_text('ab   cd')
	text.w = 3
	assert text.editor_rows().map(wrap_row_text(it)) == ['ab   ', 'cd']
	text.set_text('👩‍💻🇪🇸e\u0301')
	text.w = 1
	assert text.editor_rows().map(wrap_row_text(it)) == ['👩‍💻', '🇪🇸', 'e\u0301']
}

fn test_wrapped_caret_belongs_to_the_next_soft_row_and_navigation_uses_visual_columns() {
	for mode in [TextWrapMode.character, .word] {
		mut text := multiline('alpha beta gamma delta')
		text.w, text.h = 8, 6
		text.set_wrap_mode(mode)
		rows := text.editor_rows()
		for i, row in rows {
			text.cursor = row.start
			assert text.caret_row(rows) == i
			assert row_hit(row, 0, 4, false) == row.glyphs[0].at
		}
	}
	mut text := multiline('alpha beta gamma')
	text.w, text.h = 8, 6
	text.set_wrap_mode(.word)
	text.cursor = 2
	text.vertical_move(1, true)
	assert text.anchor == 2 && text.cursor == 8
	assert text.caret_row(text.editor_rows()) == 1
	text.vertical_move(-1, false)
	assert text.cursor == 2 && text.anchor == -1
	text.set_text('abc\ndef')
	text.w = 3
	text.cursor = 3
	assert text.caret_row(text.editor_rows()) == 0
	text.cursor = 4
	assert text.caret_row(text.editor_rows()) == 1
}

fn test_word_wrapped_mouse_selection_caret_and_clipboard_use_original_bytes() {
	mut app := new_app()
	app.desktop = false
	app.screen.resize(40, 16)
	mut window := app.window('Words', 30, 12)
	mut text := multiline('alpha beta gamma')
	text.set_wrap_mode(.word)
	window.add(mut text)
	app.set_focus(text)
	text.layout(Rect{window.x + 1, window.y + 1, 8, 6})
	rows := text.editor_rows()
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: text.x, y: text.y + 1})
	assert text.cursor == rows[1].start && text.caret_row(rows) == 1
	app.draw_editor(mut text)
	assert app.screen.cursor_x == text.x && app.screen.cursor_y == text.y + 1
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, motion: true, x: text.x + 2, y: text.y + 2})
	app.dispatch(Event{kind: .mouse, button: .left, x: text.x + 2, y: text.y + 2})
	assert app.copy_focus() && app.clipboard_text() == 'beta ga'
	text.set_text('abcde     word')
	text.w = 5
	text.cursor = 8
	app.draw_editor(mut text)
	assert app.screen.cursor_x >= text.x && app.screen.cursor_x < text.x + text.w
	assert text.text == 'abcde     word'
}

fn test_mode_changes_preserve_edit_history_selection_readonly_and_resize_correctly() {
	mut text := multiline('alpha beta')
	text.cursor = text.text.len
	assert text.replace_selection(' gamma')
	text.anchor = 3
	text.readonly = true
	before, cursor, anchor, revision := text.text, text.cursor, text.anchor, text.edit.revision
	history := text.edit.undo_changes()
	text.w, text.h = 8, 8
	for mode in [TextWrapMode.none, .character, .word, .none] {
		assert text.set_wrap_mode(mode)
		assert text.text == before && text.cursor == cursor && text.anchor == anchor && text.readonly
		assert text.edit.revision == revision && text.edit.undo_changes() == history
	}
	text.set_wrap_mode(.word)
	assert text.editor_rows().len == 3
	text.w = 30
	assert text.editor_rows().len == 1
	text.line_numbers = true
	text.scrollbar = true
	text.w = 14 // eight cells after gutter and scrollbar
	assert text.editor_rows().len == 3
	text.readonly = false
	assert text.undo() && text.text == 'alpha beta'
}

fn test_no_wrap_scrolls_horizontally_and_switching_to_wrap_resets_the_offset() {
	for kind in [Kind.multiline, .markdown] {
		mut app := new_app()
		app.desktop = false
		app.screen.resize(40, 16)
		mut window := app.window('Wrapping', 30, 12)
		mut text := if kind == .multiline { multiline('0123456789 hello world') } else { markdown('0123456789 hello world') }
		text.md.hide_status = true
		window.add(mut text)
		app.set_focus(text)
		text.layout(Rect{window.x + 1, window.y + 1, 8, 6})
		text.cursor = text.text.len
		text.set_wrap_mode(.none)
		app.draw_editor(mut text)
		assert text.editor_rows().len == 1 && text.left > 0
		assert app.screen.cursor_x >= text.x && app.screen.cursor_x < text.x + text.w
		for mode in [TextWrapMode.character, .word] {
			text.set_wrap_mode(mode)
			app.draw_editor(mut text)
			assert text.left == 0 && text.editor_rows().len > 1
			assert app.screen.cursor_x >= text.x && app.screen.cursor_x < text.x + text.w
		}
	}
}

fn test_word_wrapping_keeps_markdown_diff_styles_and_table_layout() {
	mut md := markdown('**alpha beta** gamma delta')
	md.w = 8
	md.set_wrap_mode(.word)
	rows := md.editor_rows()
	assert rows.map(wrap_row_text(it)) == ['alpha ', 'beta ', 'gamma ', 'delta']
	assert rows[0].glyphs[0].attr & bold != 0 && rows[1].glyphs[0].attr & bold != 0
	mut diff := multiline('-alpha beta gamma delta')
	diff.syntax = .diff
	diff.w = 8
	diff.set_wrap_mode(.word)
	for row in diff.editor_rows() { assert row.line == 0 && (row.color or { -1 }) == red }
	md.set_text('| Column | Other |\n| --- | --- |\n| alpha beta gamma | delta |')
	md.w = 28
	md.set_wrap_mode(.word)
	for row in md.editor_rows() { assert row.no_wrap }
	md.set_wrap_mode(.none)
	assert md.md.no_wrap && md.editor_rows()[0].no_wrap
}
