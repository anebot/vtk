module vtk

import os

fn test_utf8_entry_limits_selection_and_history() {
	mut c := entry('é', 6)
	c.min_w = 30
	c.measure()
	assert c.pw == 30
	assert c.replace_selection('😀')
	assert c.text == 'é😀'
	assert !c.replace_selection('x')
	c.cursor = 2
	c.anchor = 0
	assert c.replace_selection('a')
	assert c.text == 'a😀'
	assert c.undo()
	assert c.text == 'é😀'
	assert c.redo()
	assert c.text == 'a😀'
	c.readonly = true
	assert !c.replace_selection('oops')
	assert !c.undo()
	assert !c.replace_range(2, 3, '')
}

fn test_layout_focus_tabs_and_window_lifecycle() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Test', 40, 12)
	mut tabs := tabs()
	mut first := entry('', 0)
	mut second := button('Second')
	tabs.add_tab('One', mut first)
	tabs.add_tab('Two', mut second)
	w.add(mut tabs)
	app.redraw()
	app.set_focus(first)
	assert app.focus == first
	assert w.hit_ptr(first.x, first.y) == first
	assert !second.visible()
	app.set_focus(tabs)
	app.dispatch(Event{ key: int(Key.right) })
	app.redraw()
	assert second.visible()
	assert !first.visible()
	app.dispatch(Event{ key: int(Key.tab) })
	assert app.focus == second
	app.maximize(mut w)
	assert w.w == app.width
	app.restore(mut w)
	assert w.w == 40
	app.minimize(mut w)
	assert w.minimized
	app.raise(mut w)
	assert !w.minimized
	assert app.close(mut w)
	assert w.closed
}

fn test_grid_split_and_reparent_cycles() {
	mut root := split(false, 500)
	mut one := label('one')
	mut two := label('two')
	root.add(mut one)
	root.add(mut two)
	root.measure()
	root.layout(Rect{0, 0, 41, 8})
	assert one.w == 20 && two.w == 20 && two.x == 21
	one.add(mut root)
	assert isnil(root.parent)
	mut parent := box(true)
	parent.add(mut one)
	assert root.kids.len == 1 && one.parent == parent
}

fn test_input_split_utf8_mouse_paste_and_modifiers() {
	mut input := Input{}
	enter := input.feed('\r')[0]
	assert enter.key == int(Key.enter) && !enter.ctrl
	backspace := input.feed('\x08')[0]
	assert backspace.key == int(Key.backspace) && !backspace.ctrl
	assert input.feed('\xf0\x9f').len == 0
	events := input.feed('\x98\x80\x1b[1;6A\x1b[<0;4;3M')
	assert events.len == 3
	assert events[0].key == 0x1f600
	assert events[1].key == int(Key.up) && events[1].ctrl && events[1].shift
	assert events[2].kind == .mouse && events[2].x == 3 && events[2].y == 2
	assert input.feed('\x1b[200~hello\x1b[').len == 0
	paste := input.feed('201~')
	assert paste.len == 1 && paste[0].kind == .paste && paste[0].text == 'hello'
	move := parse_binding('Alt+F7') or { panic(err) }
	resize := parse_binding('Ctrl+Shift+r') or { panic(err) }
	assert move.str() == 'Alt+F7'
	mut app := new_app()
	assert app.set_keys(move, resize)
	assert !app.set_keys(move, move)
	assert app.resize_key == resize
}

fn test_screen_unicode_clipping_and_diff() {
	mut screen := Screen{}
	screen.resize(8, 3)
	screen.text(0, 0, 'é界e\u0301', white, blue, 0)
	assert screen.cells[1].glyph == '界'
	assert screen.cells[2].continuation
	assert screen.cells[3].glyph == 'e\u0301'
	old := screen.set_clip(Rect{0, 1, 2, 1})
	screen.text(1, 1, '界', white, blue, 0)
	assert screen.cells[9].glyph == ' '
	screen.restore_clip(old)
	assert screen.diff().contains('界')
	assert !screen.diff().contains('界')
	screen.text(2, 0, 'x', white, blue, 0)
	assert screen.cells[1].glyph == ' '
	assert !screen.cells[2].continuation
	screen.text(0, 2, 'x\x1b[2J', white, black, 0)
	assert !screen.cells[16].glyph.contains('\x1b')
	clip := screen.set_clip(Rect{1, 2, 1, 1})
	screen.put(1, 2, `\u0301`, white, black, 0)
	assert screen.cells[16].glyph == 'x'
	screen.text(1, 2, 'e\u0301', white, black, 0)
	assert screen.cells[17].glyph == 'e\u0301'
	screen.restore_clip(clip)
}

fn test_combo_text_alignment_clipping_and_popup_choices() {
	mut app := new_app()
	app.screen.resize(20, 8)
	mut c := combo()
	c.add_item('Two')
	c.add_item('Longer')
	c.value = 0
	c.layout(Rect{1, 1, 10, 1})
	for i, align in [TextAlign.left, .center, .right] {
		c.text_align = align
		app.screen.fill(Rect{0, 0, 20, 8}, `.`, white, black)
		app.draw_ctl(mut c)
		row := app.screen.cells[21..31].map(it.glyph).join('')
		assert row == ['Two      ▼', '   Two   ▼', '      Two▼'][i]
		assert app.screen.cells[20].glyph == '.' && app.screen.cells[31].glyph == '.'
	}
	c.kids[0].set_text('界界e\u0301')
	app.screen.fill(Rect{0, 0, 20, 8}, `.`, white, black)
	app.draw_ctl(mut c)
	assert app.screen.cells[25].glyph == '界' && app.screen.cells[26].continuation
	assert app.screen.cells[27].glyph == '界' && app.screen.cells[28].continuation
	assert app.screen.cells[29].glyph == 'e\u0301' && app.screen.cells[30].glyph == '▼'
	app.screen.ascii = true
	app.draw_ctl(mut c)
	assert app.screen.cells[21..31].map(it.glyph).join('') == '     ??e?v'
	app.screen.ascii = false
	c.kids[0].set_text('123456789abcdef')
	app.draw_ctl(mut c)
	assert app.screen.cells[21..31].map(it.glyph).join('') == '123456789▼'
	assert app.screen.cells[31].glyph == '.'
	c.text_align = .center
	c.kids[0].set_text('A\nlong second line')
	app.draw_ctl(mut c)
	assert app.screen.cells[21..31].map(it.glyph).join('') == '    A    ▼'
	c.w = 1
	app.draw_ctl(mut c)
	assert app.screen.cells[21].glyph == '▼'
	c.kids[0].set_text('Two')
	for i, align in [TextAlign.left, .center, .right] {
		c.text_align = align
		app.open_menu(c, 1, 3)
		app.draw_popups()
		p := app.popups.last()
		at := (p.y + 1) * app.screen.width + p.x
		assert app.screen.cells[at + 1..at + p.w - 1].map(it.glyph).join('') == [' Two    ', '  Two   ', '    Two '][i]
	}
}

fn test_markdown_tasks_source_mapping_and_readonly() {
	mut c := markdown('- [ ] task é😀\n```text\n- [ ] code\n```\n')
	c.markdown_mode(.read)
	c.cursor = 9
	assert c.toggle_task(c.cursor)
	assert c.text.starts_with('- [x]') && c.readonly && c.cursor == 9
	assert c.edit.undo.len == 1
	assert !c.toggle_task(30)
	c.markdown_mode(.edit)
	assert c.undo()
	assert c.text.starts_with('- [ ]')
	c.w = 30
	c.h = 8
	rows := c.editor_rows()
	assert rows.len == 5
	assert rows[2].code
	assert rows[2].glyphs[0].at == 26
}

fn test_terminal_parser_split_sequences_colors_and_scrolling() {
	mut t := new_terminal(8, 3)
	t.feed('hello\r\n\x1b[38;2;10;20;30m界')
	assert t.cells[8].glyph == '界' && t.cells[9].continuation
	assert t.cells[8].fg == color_rgb(10, 20, 30)
	t.feed('\x1b[2;')
	t.feed('4H!')
	assert t.cells[11].glyph == '!'
	t.feed('\x1b[2J\x1b[H1\r\n2\r\n3\r\n4')
	assert t.cells[0].glyph == '2' && t.cells[16].glyph == '4'
	t.feed('\x1b[?25l')
	assert t.cursor_hidden
}

fn test_vim_utf8_edits_visual_and_undo_group() {
	mut app := new_app()
	mut c := multiline('é😀 word\nsecond')
	c.vim_mode(true)
	c.vim_key(Event{ key: int(`l`) }, mut app)
	assert c.cursor == 2
	c.vim_key(Event{ key: int(`x`) }, mut app)
	assert c.text == 'é word\nsecond'
	c.undo()
	c.cursor = 0
	c.vim_key(Event{ key: int(`i`) }, mut app)
	c.editor_key(Event{ key: int(`a`) }, mut app)
	c.editor_key(Event{ key: int(`b`) }, mut app)
	c.vim_key(Event{ key: int(Key.escape) }, mut app)
	assert c.text.starts_with('abé')
	c.undo()
	assert c.text.starts_with('é😀')
	c.vim_key(Event{ key: int(`v`) }, mut app)
	c.vim_key(Event{ key: int(`l`) }, mut app)
	c.vim_key(Event{ key: int(`y`) }, mut app)
	assert app.clipboard_text() == 'é😀'
	c.set_text('one two')
	c.cursor = 0
	c.vim_mode(true)
	c.vim_key(Event{ key: int(`c`) }, mut app)
	c.vim_key(Event{ key: int(`w`) }, mut app)
	c.editor_key(Event{ key: int(`X`) }, mut app)
	c.vim_key(Event{ key: int(Key.escape) }, mut app)
	assert c.text == 'X two'
	c.undo()
	assert c.text == 'one two' && c.cursor == 0
}

fn modal_close_hook(mut app App) {
	mut dialog := app.top_window_ptr()
	assert dialog.modal
	if !isnil(dialog.modal_owner) {
		assert app.blocker(dialog.modal_owner) == dialog
		mut other := app.window('Independent window', 24, 6)
		assert isnil(app.blocker(other))
		app.close(mut other)
	} else {
		mut other := app.window('Blocked new window', 24, 6)
		assert app.blocker(other) == dialog
		assert app.top_window_ptr() == dialog
		app.close(mut other)
	}
	dialog.dialog_result = 42
	app.close(mut dialog)
}

fn test_modal_owners_application_modality_and_timer_reentrancy() {
	mut app := new_app()
	mut owner := app.window('Owner', 30, 8)
	mut dialog := app.window('Dialog', 24, 6)
	app.after(0, modal_close_hook)
	assert app.modal_for(mut dialog, owner) == 42
	assert !dialog.modal
	mut application_dialog := app.window('Application modal', 24, 6)
	app.after(0, modal_close_hook)
	assert app.modal_for(mut application_dialog, none) == 42
	assert app.running
}

fn test_settings_roundtrip_and_manual_scroll_ownership() {
	path := os.join_path(os.temp_dir(), 'vtk-settings-${os.getpid()}.ini')
	defer { os.rm(path) or {} }
	mut app := new_app()
	app.settings_file(path)
	app.theme = theme_preset(.modern)
	app.bar_always = false
	app.bar_top = true
	app.set_mouse_cursor(MouseCursor{ enabled: true })
	app.vim_set(true)
	app.settings_save() or { panic(err) }
	mut loaded := new_app()
	loaded.settings_file(path)
	loaded.settings_load() or { panic(err) }
	assert loaded.theme == app.theme
	assert !loaded.bar_always && loaded.vim_mode
	assert loaded.bar_top
	assert loaded.mouse_cursor.enabled
	assert loaded.move_key == app.move_key
	loaded.settings_reset() or { panic(err) }
	assert !loaded.bar_top
	mut parent := scroll()
	mut child := multiline('row\n'.repeat(20))
	parent.add(mut child)
	parent.measure()
	parent.layout(Rect{0, 0, 20, 3})
	assert app.scroll_ctl(mut child, 1)
	assert child.top == 1 && child.cursor == 0 && child.scroll_hold
	assert parent.top == 0
	app.scroll_ctl(mut child, 100)
	assert child.top == 21 - child.h
}

fn test_markdown_section_and_inline_links() {
	mut c := markdown('# One\nfirst\n# Two\n[link](target.md) <u>under</u>\n')
	c.md.layout = .section
	c.md.section_at = 15
	rows := c.markdown_rows()
	assert rows[0].start == 12
	assert rows.len == 3
	assert rows[1].glyphs[0].link == 'target.md'
	assert rows[1].glyphs.last().attr & underline != 0
}

fn test_frame_resize_preserves_opposite_edge_and_side_height() {
	mut app := new_app()
	mut w := app.window('Resize', 40, 12)
	right, top, height := w.x + w.w, w.y, w.h
	app.mouse(Event{ kind: .mouse, x: w.x, y: w.y + 3, button: .left, pressed: true })
	app.mouse(Event{ kind: .mouse, x: right + 10, y: top + 6, button: .left, pressed: true, motion: true })
	assert w.w == 16 && w.x + w.w == right
	assert w.y == top && w.h == height
	app.mouse(Event{ kind: .mouse, button: .left })
	app.mouse(Event{ kind: .mouse, x: w.x + w.w - 1, y: w.y, button: .left, pressed: true })
	assert !w.closed && app.drag == w
}

fn test_vim_selection_navigation_uses_arrows_and_respects_modifiers() {
	mut app := new_app()
	for kind in [Kind.table, .radio, .tabs] {
		mut c := new_ctl(kind)
		c.row_count = 3
		c.value = 0
		for title in ['One', 'Two', 'Three'] { c.add_item(title) }
		assert !app.widget_key(mut c, Event{ key: int(`j`) })
		app.vim_set(true)
		assert !app.widget_key(mut c, Event{ key: int(`j`), ctrl: true })
		assert !app.widget_key(mut c, Event{ key: int(`k`), alt: true })
		assert c.value == 0
		c.scroll_hold = true
		assert app.widget_key(mut c, Event{ key: int(`j`) })
		assert c.value == 1 && !c.scroll_hold
		assert app.widget_key(mut c, Event{ key: int(`k`) })
		assert c.value == 0
		assert app.widget_key(mut c, Event{ key: int(`k`) })
		assert c.value == 0
		app.vim_set(false)
		assert !app.widget_key(mut c, Event{ key: int(`j`) })
		c.vim_mode(true)
		assert app.widget_key(mut c, Event{ key: int(`j`) })
		assert c.value == 1
	}
	app.vim_set(true)
	mut tree := tree()
	first := tree.tree_add(none, 'First')
	second := tree.tree_add(none, 'Second')
	tree.selected_node = first
	assert app.widget_key(mut tree, Event{ key: int(`j`) })
	assert tree.selected_node == second
	assert app.widget_key(mut tree, Event{ key: int(`k`) })
	assert tree.selected_node == first
	mut field := entry('', 0)
	assert app.widget_key(mut field, Event{ key: int(`j`) })
	assert app.widget_key(mut field, Event{ key: int(`k`) })
	assert field.text == 'jk'
}
