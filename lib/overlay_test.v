module vtk

fn paint_nothing(_ &Ctl, mut _ Screen) {}

fn test_overlay_paints_above_windows_and_popups() {
	mut app := new_app()
	app.bar_clock = false
	mut w := app.window('Overlay', 24, 6)
	mut body := label('base')
	w.add(mut body)
	app.overlay = fn (mut app App, mut screen Screen) {
		screen.fill(Rect{0, 0, 4, 1}, `#`, white, blue)
	}
	app.redraw()
	assert app.snapshot().contains('####')
	// The overlay shares the painter's band clipping, so partial repaints keep
	// every other row untouched.
	app.invalidate_area(Rect{0, 4, 10, 1})
	app.step(0)
	assert app.snapshot().contains('####')
	app.overlay = none
	app.redraw()
	assert !app.snapshot().contains('####')
}

fn test_paste_reaches_the_focused_keyfn() {
	mut app := new_app()
	app.bar_clock = false
	mut w := app.window('Paste', 30, 8)
	mut drop := canvas(10, 2, paint_nothing)
	drop.focusable = true
	drop.keyfn = fn (mut c Ctl, e Event, mut app App) bool {
		if e.kind == .paste {
			c.text = e.text
			return true
		}
		return false
	}
	w.add(mut drop)
	app.set_focus(drop)
	app.dispatch(Event{ kind: .paste, text: '/tmp/a file.txt' })
	assert drop.text == '/tmp/a file.txt'
}

fn test_mouse_capture_delivers_motion_and_release_outside() {
	mut app := new_app()
	app.bar_clock = false
	mut w := app.window('Capture', 40, 12)
	mut log := canvas(6, 2, paint_nothing)
	log.focusable = true
	log.mouse_capture = true
	log.mousefn = fn (mut c Ctl, e Event, mut app App) bool {
		if e.kind != .mouse || e.button != .left { return false }
		if e.pressed && !e.motion { c.data = 1 }
		if e.motion { c.data += 10 }
		if !e.pressed && !e.motion { c.data += 100 }
		return true
	}
	w.add(mut log)
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: log.x + 1, y: log.y, button: .left, pressed: true })
	assert log.data == 1
	assert same_ctl(app.drag, log)
	// Motion and the release continue to reach the captured canvas far outside it.
	app.dispatch(Event{ kind: .mouse, x: 0, y: 0, button: .left, pressed: true, motion: true })
	assert log.data == 11
	app.dispatch(Event{ kind: .mouse, x: 0, y: 0, button: .left })
	assert log.data == 111
	assert app.drag == none
}
