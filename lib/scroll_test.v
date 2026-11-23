module vtk

fn wheel_reports(mut app App, mut input Input, code int, c &Ctl) {
	packet := '\x1b[<${code};${c.x + 3};${c.y + 4}M'
	// PTY reads can split a single report at any byte boundary.
	for byte in packet.bytes() {
		for event in input.feed(byte.ascii_str()) { app.dispatch(event) }
	}
	app.redraw()
}

fn test_mixed_axis_wheel_reports_only_scroll_vertical_text_in_the_vertical_direction() {
	for kind in [Kind.markdown, .multiline] {
		mut app := new_app()
		app.desktop = false
		mut window := app.window('Wrapped text', 42, 12)
		text := 'Long text with é😀 and `code` that wraps over several screen rows. '.repeat(50)
		mut c := if kind == .markdown { markdown(text) } else { multiline(text) }
		c.wrap = true
		c.readonly = true
		c.scrollbar = true
		window.add(mut c)
		app.redraw()
		assert c.editor_rows().len > 50 && c.text.split('\n').len == 1
		mut input := Input{}
		mut expected := 0
		for code in [65, 66, 65, 67, 65, 66, 65, 67] {
			if code == 65 { expected++ }
			wheel_reports(mut app, mut input, code, c)
			assert c.top == expected, '${kind}: report ${code} moved to ${c.top}, expected ${expected}'
			assert c.cursor == 0 && c.anchor == -1
			// Repainting an unchanged wrapped document must preserve the viewport.
			for _ in 0 .. 3 {
				app.redraw()
				assert c.top == expected
			}
		}
		for code in [64, 66, 64, 67] {
			if code == 64 { expected-- }
			wheel_reports(mut app, mut input, code, c)
			assert c.top == expected
		}
	}
}

fn test_wheel_during_text_drag_scrolls_without_turning_into_a_selection_click() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Selecting text', 42, 12)
	mut c := markdown('A long wrapped paragraph with Unicode é😀. '.repeat(60))
	c.scrollbar = true
	window.add(mut c)
	app.redraw()
	app.scroll_ctl(mut c, 10)
	app.redraw()
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: c.x + 2, y: c.y + 3 })
	app.redraw()
	assert app.drag == c
	cursor, anchor, top := c.cursor, c.anchor, c.top
	app.dispatch(Event{ kind: .mouse, button: .wheel_down, pressed: true, x: c.x + 2, y: c.y + 3 })
	app.redraw()
	assert c.top == top + 1
	assert c.cursor == cursor && c.anchor == anchor && app.drag == c
	app.dispatch(Event{ kind: .mouse, button: .wheel_down, x: c.x + 2, y: c.y + 3 })
	assert app.drag == c // Wheel release cannot end a left-button capture.
	app.dispatch(Event{ kind: .mouse, button: .left, x: c.x + 2, y: c.y + 3 })
	assert isnil(app.drag)
}

fn test_sgr_wheel_axes_and_modifiers_remain_distinct() {
	for flags in [0, 4, 8, 16, 28] {
		for direction, button in [MouseButton.wheel_up, .wheel_down, .wheel_left, .wheel_right] {
			mut input := Input{}
			events := input.feed('\x1b[<${64 + flags + direction};12;7M')
			assert events.len == 1 && events[0].button == button && events[0].pressed
			assert events[0].shift == (flags & 4 != 0)
			assert events[0].alt == (flags & 8 != 0)
			assert events[0].ctrl == (flags & 16 != 0)
		}
	}
}

fn test_wheel_does_not_reposition_or_release_a_dragged_scrollbar() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Scrollbar', 42, 12)
	mut c := markdown('wrapped text '.repeat(400))
	c.scrollbar = true
	window.add(mut c)
	app.redraw()
	x, y := c.x + c.w - 1, c.y + c.h / 2
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: x, y: y })
	app.redraw()
	assert app.scroll_drag == c
	top := c.top
	for button in [MouseButton.wheel_up, .wheel_down, .wheel_left, .wheel_right] {
		for pressed in [true, false] {
			app.dispatch(Event{ kind: .mouse, button: button, pressed: pressed, x: x, y: y + 2 })
			app.redraw()
			assert c.top == top && app.scroll_drag == c
		}
	}
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, motion: true, x: x, y: y + 1 })
	app.redraw()
	assert c.top > top
	app.dispatch(Event{ kind: .mouse, button: .left, x: x, y: y + 1 })
	assert isnil(app.scroll_drag)
}
