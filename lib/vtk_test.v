module vtk

import os

fn test_utf8_entry_limits_selection_and_history() {
	mut app := new_app()
	mut c := entry('é', 6)
	assert c.replace_selection('😀', mut app)
	assert c.text == 'é😀'
	assert !c.replace_selection('x', mut app)
	c.cursor = 2
	c.anchor = 0
	assert c.replace_selection('a', mut app)
	assert c.text == 'a😀'
	assert c.undo(mut app)
	assert c.text == 'é😀'
	assert c.redo(mut app)
	assert c.text == 'a😀'
	c.readonly = true
	assert !c.replace_selection('oops', mut app)
	assert !c.undo(mut app)
	assert !c.replace_range(2, 3, '', mut app)
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
	assert w.hit(first.x, first.y) == first
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
}

fn test_markdown_tasks_source_mapping_and_readonly() {
	mut app := new_app()
	mut c := markdown('- [ ] task é😀\n```text\n- [ ] code\n```\n')
	c.markdown_mode(.read)
	c.cursor = 9
	assert c.toggle_task(c.cursor, mut app)
	assert c.text.starts_with('- [x]') && c.readonly && c.cursor == 9
	assert c.edit.undo.len == 1
	assert !c.toggle_task(30, mut app)
	c.markdown_mode(.edit)
	assert c.undo(mut app)
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
	c.undo(mut app)
	c.cursor = 0
	c.vim_key(Event{ key: int(`i`) }, mut app)
	c.editor_key(Event{ key: int(`a`) }, mut app)
	c.editor_key(Event{ key: int(`b`) }, mut app)
	c.vim_key(Event{ key: int(Key.escape) }, mut app)
	assert c.text.starts_with('abé')
	c.undo(mut app)
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
	c.undo(mut app)
	assert c.text == 'one two' && c.cursor == 0
}

fn modal_close_hook(mut app App) {
	mut dialog := app.top_window()
	assert dialog.modal
	if !isnil(dialog.modal_owner) {
		assert app.blocker(dialog.modal_owner) == dialog
		mut other := app.window('Independent window', 24, 6)
		assert isnil(app.blocker(other))
		app.close(mut other)
	} else {
		mut other := app.window('Blocked new window', 24, 6)
		assert app.blocker(other) == dialog
		assert app.top_window() == dialog
		app.close(mut other)
	}
	dialog.value = 42
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
	assert app.modal_for(mut application_dialog, unsafe { nil }) == 42
	assert app.running
}

fn test_settings_roundtrip_and_manual_scroll_ownership() {
	path := os.join_path(os.temp_dir(), 'vtk-settings-${os.getpid()}.ini')
	defer { os.rm(path) or {} }
	mut app := new_app()
	app.settings_file(path)
	app.theme = theme_preset(.modern)
	app.bar_always = false
	app.set_mouse_cursor(MouseCursor{ enabled: true })
	app.vim_set(true)
	app.settings_save() or { panic(err) }
	mut loaded := new_app()
	loaded.settings_file(path)
	loaded.settings_load() or { panic(err) }
	assert loaded.theme == app.theme
	assert !loaded.bar_always && loaded.vim_mode
	assert loaded.mouse_cursor.enabled
	assert loaded.move_key == app.move_key
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
	assert w.w == 12 && w.x + w.w == right
	assert w.y == top && w.h == height
	app.mouse(Event{ kind: .mouse, button: .left })
	app.mouse(Event{ kind: .mouse, x: w.x + w.w - 1, y: w.y, button: .left, pressed: true })
	assert !w.closed && app.drag == w
}
