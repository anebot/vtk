module vtk

@[heap]
struct HoverLog {
mut:
	events []string
}

fn record_enter(mut c Ctl, mut app App) {
	assert c.hovered && app.hovered_ctl() == &c
	mut log := unsafe { &HoverLog(c.user) }
	log.events << 'enter:${c.text}'
}

fn record_leave(mut c Ctl, mut app App) {
	assert !c.hovered && app.hovered_ctl() != &c
	mut log := unsafe { &HoverLog(c.user) }
	log.events << 'leave:${c.text}'
}

fn watch_hover(mut c Ctl, log &HoverLog) {
	c.user = log
	c.mouse_enter = record_enter
	c.mouse_leave = record_leave
}

fn pointer_move(mut app App, x int, y int) {
	app.dispatch(Event{ kind: .mouse, x: x, y: y, motion: true })
}

fn count_click(mut c Ctl, mut app App) {
	c.value++
	app.dirty = true
}

fn test_mouse_input_idle_drag_release_focus_and_chunking() {
	sequence := '\x1b[<35;301;42M'
	for split_at in 1 .. sequence.len {
		mut input := Input{}
		assert input.feed(sequence[..split_at]).len == 0
		events := input.feed(sequence[split_at..])
		assert events.len == 1
		e := events[0]
		assert e.kind == .mouse && e.motion && e.button == .none && !e.pressed
		assert e.x == 300 && e.y == 41
	}
	mut input := Input{}
	events := input.feed('\x1b[<0;4;3M\x1b[<32;5;3M\x1b[<0;5;3m\x1b[I\x1b[Oa')
	assert events.len == 6
	assert events[0].button == .left && events[0].pressed && !events[0].motion
	assert events[1].button == .left && events[1].pressed && events[1].motion
	assert events[2].button == .left && !events[2].pressed
	assert events[3].kind == .focus_in && events[4].kind == .focus_out
	assert events[5].kind == .key && events[5].key == `a`
}

fn test_hover_transitions_do_not_activate_or_focus_controls() {
	mut app := new_app()
	app.desktop = false
	mut log := &HoverLog{}
	mut w := app.window('Hover', 30, 8)
	mut body := box(true)
	mut one := button('One')
	mut two := button('Two')
	watch_hover(mut one, log)
	watch_hover(mut two, log)
	one.changed = count_click
	two.changed = count_click
	body.add(mut one)
	body.add(mut two)
	w.add(mut body)
	app.redraw()
	app.set_focus(two)
	pointer_move(mut app, one.x, one.y)
	pointer_move(mut app, one.x + 1, one.y)
	app.redraw()
	assert log.events == ['enter:One']
	assert one.value == 0 && two.value == 0 && app.focus == two
	pointer_move(mut app, two.x, two.y)
	assert log.events == ['enter:One', 'leave:One', 'enter:Two']
	assert !one.hovered && two.hovered
	app.dispatch(Event{ kind: .mouse, x: one.x, y: one.y, button: .left, pressed: true })
	assert app.focus == one && one.value == 1
	app.dispatch(Event{ kind: .mouse, x: two.x, y: two.y, button: .left, pressed: true, motion: true })
	app.dispatch(Event{ kind: .mouse, x: two.x, y: two.y, button: .left })
	assert one.value == 1 && two.value == 0 && app.focus == one
	pointer_move(mut app, 0, 0)
	assert isnil(app.hovered_ctl()) && !two.hovered
	assert log.events.last() == 'leave:Two'
}

fn test_hover_rechecks_tabs_visibility_detach_and_lifecycle() {
	mut app := new_app()
	app.desktop = false
	mut log := &HoverLog{}
	mut w := app.window('Tabs', 30, 10)
	mut pages := tabs()
	mut one := button('One')
	mut two := button('Two')
	watch_hover(mut one, log)
	watch_hover(mut two, log)
	pages.add_tab('First', mut one)
	pages.add_tab('Second', mut two)
	w.add(mut pages)
	app.redraw()
	pointer_move(mut app, one.x, one.y)
	pages.value = 1
	app.redraw()
	assert log.events == ['enter:One', 'leave:One', 'enter:Two']
	two.disabled = true
	app.redraw()
	assert !two.hovered && isnil(app.hovered_ctl())
	two.disabled = false
	app.redraw()
	assert two.hovered
	two.detach()
	app.redraw()
	assert !two.hovered && app.hovered_ctl() != two
	mut page := pages.kids[1]
	page.add(mut two)
	app.redraw()
	assert two.hovered
	app.minimize(mut w)
	assert !two.hovered && isnil(app.hovered_ctl())
	app.raise(mut w)
	app.redraw()
	assert two.hovered
	assert app.close(mut w)
	assert !two.hovered && isnil(app.hovered_ctl())
}

fn test_hover_respects_occlusion_modals_popups_notices_and_clipping() {
	mut app := new_app()
	app.desktop = false
	app.width = 44
	app.height = 13
	mut back := app.window('Back', 40, 12)
	mut one := button('One')
	back.add(mut one)
	mut front := app.window('Front', 40, 12)
	front.x = back.x
	front.y = back.y
	mut two := button('Two')
	front.add(mut two)
	app.redraw()
	pointer_move(mut app, two.x, two.y)
	assert two.hovered && !one.hovered
	front.hidden = true
	app.redraw()
	assert one.hovered && !two.hovered
	front.hidden = false
	front.x = 24
	front.w = 20
	front.h = 6
	front.modal = true
	app.redraw()
	assert isnil(app.hovered_ctl())
	order := app.windows.clone()
	focus := app.focus
	pointer_move(mut app, one.x, one.y)
	assert app.windows == order && app.focus == focus
	front.modal = false
	mut menu := context_menu()
	mut item := menu.menu_item('Action', count_click)
	app.open_menu(menu, one.x - 1, one.y - 1)
	app.redraw()
	assert item.hovered && !one.hovered
	item.disabled = true
	app.redraw()
	assert isnil(app.hovered_ctl())
	app.close_popups()
	app.redraw()
	assert one.hovered
	// A notice's rectangle is laid out before hover is recalculated.
	pointer_move(mut app, app.width - 10, app.height - 2)
	assert one.hovered
	app.notify('Overlay', 0)
	app.redraw()
	mut n := app.notices[0]
	assert isnil(app.hovered_ctl())
	n.closed = true
	app.redraw()
	assert app.hovered_ctl() == one
	mut viewport := scroll()
	mut wide := label('a long clipped row\nsecond\nthird')
	viewport.add(mut wide)
	one.detach()
	back.add(mut viewport)
	back.w = 15
	back.h = 4
	app.redraw()
	pointer_move(mut app, viewport.x, viewport.y)
	assert wide.hovered
	pointer_move(mut app, viewport.x + viewport.w - 1, viewport.y)
	assert !wide.hovered && viewport.hovered
	pointer_move(mut app, back.x, viewport.y)
	assert !wide.hovered && back.hovered
}

fn leave_hides_next(mut c Ctl, mut app App) {
	record_leave(mut c, mut app)
	c.link.hidden = true
	app.redraw()
}

fn destroy_on_enter(mut c Ctl, mut app App) {
	record_enter(mut c, mut app)
	app.destroy_ctl(mut c)
}

fn record_destroy(mut c Ctl, mut app App) {
	assert !c.hovered && app.hovered_ctl() != &c
	mut log := unsafe { &HoverLog(c.user) }
	log.events << 'destroy:${c.text}'
}

fn test_hover_callbacks_can_mutate_and_destroy_controls() {
	mut app := new_app()
	app.desktop = false
	mut log := &HoverLog{}
	mut w := app.window('Callbacks', 30, 8)
	mut body := box(true)
	mut one := button('One')
	mut two := button('Two')
	watch_hover(mut one, log)
	watch_hover(mut two, log)
	one.link = two
	one.mouse_leave = leave_hides_next
	body.add(mut one)
	body.add(mut two)
	w.add(mut body)
	app.redraw()
	pointer_move(mut app, one.x, one.y)
	pointer_move(mut app, two.x, two.y)
	assert log.events == ['enter:One', 'leave:One']
	assert !one.hovered && !two.hovered
	assert app.hovered_ctl() == body
	one.mouse_leave = record_leave
	one.mouse_enter = destroy_on_enter
	one.destroy = record_destroy
	pointer_move(mut app, one.x, one.y)
	assert log.events == ['enter:One', 'leave:One', 'enter:One', 'leave:One', 'destroy:One']
	assert !one.hovered && app.hovered_ctl() != one && body.kids.len == 1
}

fn pointer_canvas(mut c Ctl, mut screen Screen) {
	screen.text(c.x, c.y, 'A界BC', white, blue, 0)
}

fn assert_terminal_cells(t &Terminal, s &Screen) {
	for i, cell in s.cells {
		assert t.cells[i].glyph == cell.glyph
		assert t.cells[i].continuation == cell.continuation
	}
}

fn test_mouse_cursor_restores_unicode_cells_and_preserves_caret() {
	mut app := new_app()
	app.desktop = false
	app.width = 30
	app.height = 10
	mut w := app.window('Pointer', 24, 7)
	mut body := box(true)
	mut picture := canvas(8, 1, pointer_canvas)
	mut field := entry('typing', 0)
	body.add(mut picture)
	body.add(mut field)
	w.add(mut body)
	app.set_focus(field)
	app.redraw()
	base := app.screen.cells.clone()
	cx, cy := app.screen.cursor_x, app.screen.cursor_y
	mut terminal := new_terminal(app.width, app.height)
	terminal.feed(app.screen.diff())
	assert app.set_mouse_cursor(MouseCursor{ enabled: true, fg: color_rgb(20, 40, 60), bg: yellow, attr: bold })
	for x in [picture.x + 1, picture.x + 2, picture.x + 4] {
		pointer_move(mut app, x, picture.y)
		app.redraw()
		at := picture.y * app.width + x
		assert app.screen.cells[at].glyph == '█'
		assert app.screen.cells[at].fg == color_rgb(20, 40, 60)
		assert app.screen.cells[at].bg == yellow && app.screen.cells[at].attr == bold
		assert app.screen.cursor_x == cx && app.screen.cursor_y == cy
		terminal.feed(app.screen.diff())
		assert_terminal_cells(terminal, &app.screen)
	}
	previous := app.mouse_cursor
	for invalid in [`界`, `\u0301`, `\n`] {
		assert !app.set_mouse_cursor(MouseCursor{ enabled: true, glyph: invalid })
		assert app.mouse_cursor == previous
	}
	app.theme.ascii = true
	app.redraw()
	assert app.screen.cells[picture.y * app.width + picture.x + 4].glyph == '#'
	app.theme.ascii = false
	app.dispatch(Event{ kind: .focus_out })
	app.redraw()
	assert app.screen.cells == base
	mx, my := app.mouse_position()
	assert mx == -1 && my == -1
	assert isnil(app.hovered_ctl())
	app.dispatch(Event{ kind: .focus_in })
	app.redraw()
	assert app.screen.cells == base
	pointer_move(mut app, picture.x, picture.y)
	app.redraw()
	assert app.screen.cells[picture.y * app.width + picture.x].glyph == '█'
	assert app.set_mouse_cursor(MouseCursor{})
	app.redraw()
	assert app.screen.cells == base
	terminal.feed(app.screen.diff())
	assert_terminal_cells(terminal, &app.screen)
}
