module vtk

import time

fn date_changed(mut c Ctl, mut app App) {
	c.data++
	app.clipboard_set(c.text)
}

fn test_date_picker_normalizes_dates_without_an_app() {
	mut picker := date_picker(time.Time{ year: 2024, month: 2, day: 31, hour: 15, is_local: true })
	picker.changed = date_changed
	assert picker.text == '2024-02-29'
	assert picker.date().hour == 0 && !picker.date().is_local
	picker.set_date(time.Time{ year: 1900, month: 2, day: 29 })
	assert picker.text == '1900-02-28'
	picker.set_date(time.Time{ year: 2000, month: 2, day: 29 })
	assert picker.text == '2000-02-29'
	picker.set_date(time.Time{ year: 2024, month: 15, day: 40 })
	assert picker.text == '2024-12-31'
	picker.set_date(time.Time{})
	assert picker.text == '0001-01-01'
	picker.set_date(time.Time{ year: 10000 })
	assert picker.text == '9999-12-31' && picker.data == 0
}

fn test_date_picker_keyboard_crosses_month_year_and_leap_day_boundaries() {
	mut app := new_app()
	mut w := app.window('Dates', 28, 13)
	mut picker := date_picker(time.Time{ year: 2024, month: 1, day: 31 })
	picker.changed = date_changed
	w.add(mut picker)
	app.set_focus(picker)
	app.redraw()
	app.dirty = false
	app.dispatch(Event{ key: int(Key.page_down) })
	assert picker.text == '2024-02-29' && picker.data == 1 && app.dirty
	assert app.clipboard_text() == picker.text
	app.dispatch(Event{ key: int(Key.page_down), shift: true })
	assert picker.text == '2025-02-28'
	app.dispatch(Event{ key: int(Key.right) })
	assert picker.text == '2025-03-01'
	app.dispatch(Event{ key: int(Key.left) })
	assert picker.text == '2025-02-28'
	app.dispatch(Event{ key: int(Key.up) })
	assert picker.text == '2025-02-21'
	app.dispatch(Event{ key: int(Key.down) })
	assert picker.text == '2025-02-28'
	app.dispatch(Event{ key: int(Key.page_up), ctrl: true })
	assert picker.text == '2024-02-28'
	app.dispatch(Event{ key: int(Key.end) })
	assert picker.text == '2024-02-29'
	app.dispatch(Event{ key: int(Key.home) })
	assert picker.text == '2024-02-01'
	picker.set_date(time.Time{ year: 2024, month: 12, day: 31 })
	app.dispatch(Event{ key: int(Key.right) })
	assert picker.text == '2025-01-01'
	app.dispatch(Event{ key: int(Key.left) })
	assert picker.text == '2024-12-31'
	picker.set_date(time.Time{ year: 1, month: 1, day: 1 })
	app.dispatch(Event{ key: int(Key.left) })
	assert picker.text == '0001-01-01'
	picker.set_date(time.Time{ year: 9999, month: 12, day: 31 })
	app.dispatch(Event{ key: int(Key.right) })
	assert picker.text == '9999-12-31'
	picker.readonly = true
	app.dispatch(Event{ key: int(Key.home) })
	assert picker.text == '9999-12-31'
	picker.readonly = false
	picker.disabled = true
	app.dispatch(Event{ key: int(Key.left) })
	assert picker.text == '9999-12-31'
	picker.disabled = false
	app.dispatch(Event{ key: int(`t`) })
	assert picker.text == picker_date_text(time.now())
}

fn date_click(mut app App, x int, y int, shift bool) {
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: x, y: y, shift: shift })
	app.dispatch(Event{ kind: .mouse, button: .left, x: x, y: y })
}

fn test_date_picker_mouse_grid_matches_rendered_days_including_sixth_week() {
	for date in [time.Time{ year: 2024, month: 2, day: 1 }, time.Time{ year: 2020, month: 8, day: 1 }] {
		mut app := new_app()
		mut w := app.window('Dates', 30, 13)
		mut picker := date_picker(date)
		w.add(mut picker)
		app.redraw()
		first := time.Time{ year: date.year, month: date.month, day: 1 }
		offset := first.day_of_week() - 1
		x := picker.date_picker_grid_x()
		// Empty cells before the first day are inert.
		date_click(mut app, x, picker.y + 2, false)
		assert picker.date().day == 1
		days := time.days_in_month(date.month, date.year) or { 31 }
		for day in 1 .. days + 1 {
			cell := offset + day - 1
			cx, cy := x + cell % 7 * 3, picker.y + 2 + cell / 7
			date_click(mut app, cx + 2, cy, false)
			assert picker.date().day == day && app.focus == picker
			app.redraw()
			assert app.screen.cells[cy * app.width + cx + 2].glyph == (day % 10).str()
			assert app.screen.cells[cy * app.width + cx].bg == app.theme.focus_bg
		}
		date_click(mut app, picker.x + picker.w - 2, picker.y, false)
		assert picker.date().month == date.month + 1
		date_click(mut app, picker.x + 1, picker.y, true)
		assert picker.date().year == date.year - 1
		date_click(mut app, picker.x + 2, picker.y + 8, false)
		assert picker.text == picker_date_text(time.now())
		picker.readonly = true
		date_click(mut app, picker.x + 1, picker.y, false)
		assert picker.text == picker_date_text(time.now())
		app.dispatch(Event{ kind: .resize, width: 10, height: 6 })
		app.redraw()
	}
}

fn test_date_dialog_accept_cancel_and_focus_restoration() {
	mut app := new_app()
	mut owner := app.window('Owner', 40, 15)
	mut field := entry('', 0)
	owner.add(mut field)
	app.set_focus(field)
	app.after(0, fn (mut app App) {
		assert app.focus.kind == .date_picker
		app.dispatch(Event{ key: int(Key.right) })
		app.dispatch(Event{ key: int(Key.enter) })
	})
	date := app.date_pick(owner, 'Pick a date', time.Time{ year: 2024, month: 2, day: 28 }) or { panic('Date was cancelled') }
	assert picker_date_text(date) == '2024-02-29'
	assert app.focus == field && app.windows.len == 1
	for cancel_with_escape in [true, false] {
		app.after(0, fn [cancel_with_escape] (mut app App) {
			if cancel_with_escape {
				app.dispatch(Event{ key: int(Key.escape) })
			} else {
				app.dispatch(Event{ key: int(Key.tab) })
				app.dispatch(Event{ key: int(Key.tab) })
				assert app.focus.text == 'Cancel'
				app.dispatch(Event{ key: int(Key.enter) })
			}
		})
		if _ := app.date_pick(owner, 'Cancel date', date) {
			assert false
		}
		assert app.focus == field && app.windows.len == 1
	}
}
