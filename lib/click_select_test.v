module vtk

fn text_box_click(mut app App, x int, y int) {
	app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
	app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left })
}

fn test_double_and_triple_clicks_select_words_and_lines() {
	mut app := new_app()
	app.desktop = false
	app.width = 40
	app.height = 14
	mut w := app.window('Edit', 30, 10)
	mut body := box(true)
	mut field := multiline('alpha beta gamma\nsecond line')
	field.min_w = 24
	body.add(mut field)
	w.add(mut body)
	app.redraw()
	x := field.x + 2
	text_box_click(mut app, x, field.y)
	mut a, mut b := field.selection()
	assert a == b && field.cursor == 2
	text_box_click(mut app, x, field.y)
	a, b = field.selection()
	assert field.text[a..b] == 'alpha'
	text_box_click(mut app, x, field.y)
	a, b = field.selection()
	assert field.text[a..b] == 'alpha beta gamma\n'
	// A fourth press starts over with a collapsed caret.
	text_box_click(mut app, x, field.y)
	a, b = field.selection()
	assert a == b && field.cursor == 2
	// The second source line selects its own word and line.
	y := field.y + 1
	second := field.x + 8
	text_box_click(mut app, second, y)
	text_box_click(mut app, second, y)
	a, b = field.selection()
	assert field.text[a..b] == 'line'
	text_box_click(mut app, second, y)
	a, b = field.selection()
	assert field.text[a..b] == 'second line'
}

fn test_entry_double_click_selects_its_only_line() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Entry', 30, 6)
	mut field := entry('hello world', 0)
	w.add(mut field)
	app.redraw()
	x := field.x + 1
	text_box_click(mut app, x, field.y)
	text_box_click(mut app, x, field.y)
	mut a, mut b := field.selection()
	assert field.text[a..b] == 'hello'
	text_box_click(mut app, x, field.y)
	a, b = field.selection()
	assert field.text[a..b] == 'hello world'
}
