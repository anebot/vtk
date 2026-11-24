module vtk

import time

fn padding_row_text(row TextRow) string { return row.glyphs.map(glyph_text(it)).join('') }

fn test_padding_measures_and_lays_out_without_accumulating() {
	mut c := label('abc\nx')
	c.padding = Insets{left: 1, right: 2, top: 3, bottom: 4}
	c.measure()
	assert c.pw == 6 && c.ph == 9
	outer := Rect{5, 6, 20, 10}
	c.layout(outer)
	assert c.rect() == outer && c.content_rect() == Rect{6, 9, 17, 3}
	for _ in 0 .. 5 {
		c.measure()
		c.layout(c.rect())
		assert c.pw == 6 && c.ph == 9
		assert c.rect() == outer && c.content_rect() == Rect{6, 9, 17, 3}
	}
	assert c.set_padding(Insets{left: 2, right: 1, top: 1})
	c.layout(c.rect())
	assert c.rect() == outer && c.content_rect() == Rect{7, 7, 17, 9}
	mut canvas := canvas(8, 3, fn (_ &Ctl, mut _ Screen) {})
	canvas.padding = Insets{left: 2, right: 2, top: 1, bottom: 1}
	for _ in 0 .. 5 { canvas.measure(); assert canvas.pw == 12 && canvas.ph == 5 }
	canvas.min_w = 20
	canvas.measure()
	canvas.padding.left = 3
	canvas.measure()
	assert canvas.pw == 20
	canvas.min_w = 0
	canvas.measure()
	assert canvas.pw == 13
}

fn test_padding_clamps_negative_oversized_and_empty_content_bounds() {
	assert Rect{1, 2, 6, 4}.inset(Insets{left: -2, right: 2, top: 1}) == Rect{1, 3, 4, 3}
	mut c := multiline('Hidden content')
	c.padding = Insets{left: 100, right: 100, top: 100, bottom: 100}
	c.layout(Rect{3, 4, 6, 4})
	assert c.rect() == Rect{3, 4, 6, 4} && c.content_rect() == Rect{9, 8, 0, 0}
	mut app := new_app()
	app.screen.resize(30, 20)
	app.focus = c
	app.screen.cursor_x = 8
	app.draw_ctl(mut c)
	assert app.screen.cursor_x == -1
	c.padding = Insets{left: 0x7fffffff, right: 0x7fffffff}
	c.measure()
	assert c.pw == 0x7fffffff
	c.layout(c.rect())
	assert c.rect() == Rect{3, 4, 6, 4} && c.content_rect().w == 0
}

fn test_padded_textareas_wrap_draw_and_hit_test_in_the_same_content_box() {
	for kind in [Kind.multiline, .markdown] {
		mut app := new_app()
		app.desktop = false
		mut window := app.window('Padding', 26, 12)
		source := '01234567890123456789012\nsecond line'
		mut text := if kind == .multiline { multiline(source) } else { markdown(source) }
		text.md.hide_status = true
		text.scrollbar = true
		text.padding = Insets{left: 1, right: 1, top: 1, bottom: 1}
		text.set_wrap_mode(.character)
		window.add(mut text)
		app.set_focus(text)
		app.redraw()
		outer, inner := text.rect(), text.content_rect()
		assert outer == window.content_rect()
		assert inner == outer.inset(text.padding)
		assert text.editor_rows().map(padding_row_text(it)) == ['012345678901234567890', '12', 'second line']
		assert app.screen.cells[outer.y * app.width + outer.x].glyph == ' '
		assert app.screen.cells[inner.y * app.width + inner.x].glyph == '0'
		assert app.screen.cells[inner.y * app.width + outer.x + outer.w - 1].glyph == ' '
		assert app.screen.cells[inner.y * app.width + inner.x + inner.w - 1].glyph == '█'
		assert app.screen.cursor_x == inner.x && app.screen.cursor_y == inner.y
		text.cursor = 5
		text.anchor = -1
		// Padding focuses the textarea but does not move its caret or start a drag.
		app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: outer.x, y: inner.y})
		assert same_ctl(app.focus, text) && text.cursor == 5 && text.anchor == -1 && app.drag == none
		app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: inner.x + 2, y: inner.y})
		app.dispatch(Event{kind: .mouse, button: .left, x: inner.x + 2, y: inner.y})
		assert text.cursor == 2
		text.anchor, text.cursor = 0, source.len
		assert app.copy_focus() && app.clipboard_text() == source
		app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: outer.x + outer.w - 1, y: inner.y + 2})
		assert app.scroll_drag == none
		app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: inner.x + inner.w - 1, y: inner.y + 2})
		assert same_ctl(app.scroll_drag, text)
		app.dispatch(Event{kind: .mouse, button: .left, x: inner.x + inner.w - 1, y: inner.y + 2})
		assert app.scroll_drag == none && text.text == source
	}
}

fn test_nested_padding_and_window_client_padding_preserve_chrome_and_allocations() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Nested', 40, 18)
	window.padding = Insets{left: 2, right: 2, top: 1, bottom: 1}
	mut menu := window.add_menu('File')
	menu.menu_item('Nothing', fn (mut _ Ctl, mut _ App) {})
	mut body := box(true)
	body.padding = Insets{left: 1, right: 1, top: 1, bottom: 1}
	mut title := label('Title')
	title.padding = Insets{left: 1, right: 1}
	mut text := multiline('Padded text')
	text.padding = Insets{left: 1, right: 1}
	body.add(mut title); body.add(mut text)
	window.add(mut body)
	app.redraw()
	outer := window.rect()
	assert body.rect() == window.content_rect()
	assert body.rect().y == outer.y + 3
	assert title.rect().x == body.content_rect().x
	assert title.content_rect().x == title.rect().x + 1
	assert text.rect().y == title.rect().y + title.rect().h
	assert menu.y == window.y + 1 && menu.x == window.x + 2
	for _ in 0 .. 5 {
		app.redraw()
		assert window.rect() == outer && body.rect() == window.content_rect()
		assert text.content_rect() == text.rect().inset(text.padding)
	}
}

fn test_padding_applies_to_common_controls_and_clips_all_drawing() {
	mut app := new_app()
	app.desktop = false
	app.screen.resize(40, 24)
	mut rows := table(fn (_ &Ctl, _ int, _ int) string { return 'long cell text '.repeat(4) }, 2)
	rows.table_column('Column')
	mut radio := radio()
	radio.add_item('a long choice '.repeat(4))
	mut tree := tree()
	tree.tree_add(none, 'a long node '.repeat(4))
	mut canvas := canvas(8, 3, fn (c &Ctl, mut screen Screen) { screen.fill(c.rect(), `#`, white, black) })
	mut controls := [label('long text '.repeat(4)), entry('long text '.repeat(4), 0),
		button('long button '.repeat(4)), toolbutton('long tool '.repeat(4)),
		checkbox('long check '.repeat(4), true), switch_ctl('long switch '.repeat(4), true),
		spin(0, 100), slider(0, 100), progress(), spinner('long activity '.repeat(4)),
		separator(), date_picker(time.now()), rows, radio, tree, canvas]
	for mut control in controls {
		app.screen.fill(Rect{0, 0, 40, 24}, `!`, white, black)
		control.padding = Insets{left: 2, right: 2, top: 2, bottom: 2}
		control.measure()
		control.layout(Rect{3, 2, 26, 14})
		app.draw_ctl(mut control)
		outer, inner := control.rect(), control.content_rect()
		assert inner == outer.inset(control.padding)
		for y in outer.y .. outer.y + outer.h {
			for x in outer.x .. outer.x + outer.w {
				if !inner.contains(x, y) { assert app.screen.cells[y * 40 + x].glyph == ' ', '${control.kind} at ${x}, ${y}' }
			}
		}
	}
}

fn test_padding_does_not_move_button_click_targets_and_entries_fill_their_padding() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Button', 30, 10)
	mut button := button('Click')
	button.padding = Insets{left: 1, right: 1, top: 1, bottom: 1}
	button.changed = fn (mut c Ctl, mut _ App) { c.data++ }
	window.add(mut button)
	app.redraw()
	outer := button.rect()
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: outer.x, y: outer.y})
	assert button.data == 1 && same_ctl(app.focus, button)
	mut input := entry('Entry', 0)
	input.padding = Insets{left: 1, right: 1}
	window.clear()
	window.add(mut input)
	app.redraw()
	assert app.screen.cells[input.rect().y * app.width + input.rect().x].bg == app.theme.field_bg
}

fn test_padded_split_panes_drag_at_outer_edges_and_keep_a_content_cell() {
	for vertical in [false, true] {
		mut app := new_app()
		app.desktop = false
		mut window := app.window('Split', 50, 20)
		mut panes := split(vertical, 500)
		panes.padding = Insets{left: 1, right: 1, top: 1, bottom: 1}
		panes.resizable = true
		mut first := label('First')
		mut second := label('Second')
		first.padding, second.padding = Insets{left: 2, right: 2, top: 1, bottom: 1}, Insets{left: 2, right: 2, top: 1, bottom: 1}
		panes.add(mut first); panes.add(mut second)
		window.add(mut panes)
		app.redraw()
		divider := panes.split_divider()
		assert (if vertical { divider.y } else { divider.x }) == if vertical { first.rect().y + first.rect().h } else { first.rect().x + first.rect().w }
		app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: divider.x, y: divider.y})
		assert same_ctl(app.drag, panes)
		app.dispatch(Event{kind: .mouse, button: .left, pressed: true, motion: true, x: -100, y: -100})
		assert (if vertical { first.content_rect().h } else { first.content_rect().w }) >= 1
		app.dispatch(Event{kind: .mouse, button: .left, x: 1000, y: 1000})
		assert app.drag == none
		assert (if vertical { second.content_rect().h } else { second.content_rect().w }) >= 1
		app.redraw()
		assert panes.rect() == window.content_rect()
	}
}

fn test_padding_clips_descendant_carets_and_scroll_content() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Clipping', 30, 7)
	mut body := box(true)
	body.padding = Insets{top: 1, bottom: 1, left: 1, right: 1}
	mut text := multiline('0\n1\n2\n3\n4\n5\n6\n7')
	text.cursor = text.text.len
	body.add(mut text)
	window.add(mut body)
	app.set_focus(text)
	app.redraw()
	assert text.rect().h > body.content_rect().h
	assert app.screen.cursor_x == -1
	mut scroll := scroll()
	scroll.padding = Insets{left: 1, right: 1, top: 1, bottom: 1}
	mut label := label('long text '.repeat(30))
	scroll.add(mut label)
	window.clear()
	window.add(mut scroll)
	app.redraw()
	assert same_ctl(scroll.hit(scroll.rect().x, scroll.rect().y), scroll)
	assert app.screen.cells[(scroll.rect().y + scroll.rect().h - 1) * app.width + scroll.rect().x + 1].glyph == ' '
}

fn test_padded_flows_grids_tabs_and_terminals_use_content_bounds() {
	mut flow := flow()
	flow.padding = Insets{left: 1, right: 1, top: 1, bottom: 1}
	mut first := button('A')
	mut second := button('B')
	flow.add(mut first); flow.add(mut second)
	flow.measure()
	flow.layout(Rect{0, 0, 12, 8})
	assert first.rect().y == 1 && second.rect().y == 2 && flow.ph == 4
	mut grid := grid()
	grid.padding = Insets{left: 2, top: 1}
	mut cell := label('Cell')
	grid.add(mut cell)
	grid.measure(); grid.layout(Rect{0, 0, 20, 8})
	assert cell.rect().x == 2 && cell.rect().y == 1
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Tabs', 40, 15)
	mut tabs := tabs()
	tabs.padding = Insets{left: 1, right: 1, top: 1, bottom: 1}
	mut content := label('Page')
	mut page := tabs.add_tab('One', mut content)
	page.padding = Insets{left: 2, right: 1}
	window.add(mut tabs)
	app.redraw()
	assert page.tab_x == tabs.content_rect().x + 2
	assert content.rect() == page.content_rect()
	assert content.rect().x == tabs.content_rect().x + 3
	mut terminal := &Ctl{kind: .terminal, term: new_terminal(10, 3), pw: 10, ph: 3,
		intrinsic_w: 10, intrinsic_h: 3, focusable: true, padding: Insets{left: 1, right: 1, top: 1, bottom: 1}}
	mut term := terminal.term or { panic('expected a terminal') }
	term.feed('X')
	window.clear()
	window.add(mut terminal)
	app.set_focus(terminal)
	app.redraw()
	inner := terminal.content_rect()
	assert term.cols == inner.w && term.rows == inner.h
	assert app.screen.cells[inner.y * app.width + inner.x].glyph == 'X'
	assert app.screen.cursor_x == inner.x + 1 && app.screen.cursor_y == inner.y
}
