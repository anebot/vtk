module vtk

fn test_terminal_recovers_from_cancelled_frame_and_clipboard_output() {
	for incomplete in ['\x1b[38;2;255;', '\x1b]52;c;abc'] {
		mut t := new_terminal(20, 10)
		t.feed(tty_setup + tty_mouse_drag_off + tty_mouse_all + '\x1b[2;8r')
		assert t.mouse_mode == 1003 && t.mouse_sgr && t.cursor_hidden && t.top == 1
		t.feed(incomplete)
		t.feed('\x18\x1b[r' + tty_restore(false, ''))
		assert t.mouse_mode == 0 && !t.mouse_sgr && !t.cursor_hidden && t.top == 0
		t.mouse(Event{kind: .mouse, motion: true}, 1, 1)
		assert t.pending == ''
	}
}

fn test_terminal_mouse_modes_and_encodings() {
	mut t := new_terminal(300, 30)
	press := Event{kind: .mouse, button: .left, pressed: true, shift: true, alt: true, ctrl: true}
	t.mouse(press, 2, 3)
	assert t.pending == ''
	t.feed('\x1b[?1000;1006h')
	t.mouse(press, 2, 3)
	t.mouse(Event{...press, pressed: false}, 2, 3)
	t.mouse(Event{kind: .mouse, button: .wheel_down, pressed: true}, 299, 29)
	t.mouse(Event{kind: .mouse, button: .wheel_down}, 299, 29)
	assert t.pending == '\x1b[<28;3;4M\x1b[<28;3;4m\x1b[<65;300;30M'
	t.pending = ''
	t.feed('\x1b[?1006l')
	t.mouse(Event{kind: .mouse, button: .right, pressed: true}, 0, 0)
	t.mouse(Event{kind: .mouse, button: .right}, 0, 0)
	t.mouse(press, 223, 0)
	assert t.pending == '\x1b[M"!!\x1b[M#!!'
	t.pending = ''
	t.feed('\x1b[?1000l\x1b[?9h')
	t.mouse(press, 0, 0)
	t.mouse(Event{...press, pressed: false}, 0, 0)
	t.mouse(Event{kind: .mouse, button: .wheel_up, pressed: true}, 0, 0)
	assert t.pending == '\x1b[M !!'
	t.feed('\x1bc')
	assert t.mouse_mode == 0 && !t.mouse_sgr
}

fn test_terminal_mouse_dispatch_capture_and_motion() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Terminal', 24, 10)
	mut c := &Ctl{kind: .terminal, term: new_terminal(10, 3), pw: 10, ph: 3,
		intrinsic_w: 10, intrinsic_h: 3, focusable: true, expand: true,
		padding: Insets{left: 1, top: 1}}
	window.add(mut c)
	app.redraw()
	c.term.feed('\x1b[?1002;1006h')
	x, y := c.x, c.y
	app.dispatch(Event{kind: .mouse, x: x, y: y, button: .left, pressed: true})
	assert app.focus == c && app.drag == c
	app.dispatch(Event{kind: .mouse, x: x + 1, y: y + 1, button: .left, pressed: true, motion: true})
	app.dispatch(Event{kind: .mouse, x: x + 1, y: y + 1, button: .wheel_up, pressed: true})
	app.dispatch(Event{kind: .mouse, x: 0, y: 0, button: .left})
	assert isnil(app.drag)
	assert c.term.pending == '\x1b[<0;1;1M\x1b[<32;2;2M\x1b[<64;2;2M\x1b[<0;1;1m'
	c.term.pending = ''
	app.dispatch(Event{kind: .mouse, x: x, y: y, motion: true})
	assert c.term.pending == ''
	c.term.feed('\x1b[?1003h')
	app.dispatch(Event{kind: .mouse, x: x, y: y, motion: true})
	assert c.term.pending == '\x1b[<35;1;1M'
	c.term.feed('\x1b[?1003l')
	c.term.pending = ''
	app.dispatch(Event{kind: .mouse, x: x, y: y, button: .left, pressed: true})
	assert c.term.pending == '' && isnil(app.drag)
}
