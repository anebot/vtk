module vtk

import time

fn clock_record(e Event, mut app App) {
	app.clipboard_set('${e.button}:${e.x}:${e.y}')
	app.notify('Clock clicked', 0)
}

fn test_clock_clicks_report_button_coordinates_and_ignore_other_mouse_events() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		app.clock_clicked = clock_record
		app.redraw()
		x, y := app.width - 3, app.bar_y()
		for button in [MouseButton.left, .right, .middle] {
			count := app.notices.len
			app.dispatch(Event{ kind: .mouse, x: x, y: y, button: button, pressed: true })
			assert app.notices.len == count + 1
			assert app.clipboard_text() == '${button}:${x}:${y}'
			app.dispatch(Event{ kind: .mouse, x: x, y: y, button: button })
			app.dispatch(Event{ kind: .mouse, x: x, y: y, button: button, pressed: true, motion: true })
			assert app.notices.len == count + 1
		}
		for button in [MouseButton.wheel_up, .wheel_down, .wheel_left, .wheel_right, .none] {
			app.dispatch(Event{ kind: .mouse, x: x, y: y, button: button, pressed: true })
			assert app.notices.len == 3
		}
		for cx in [app.width - 6, app.width] {
			app.dispatch(Event{ kind: .mouse, x: cx, y: y, button: .left, pressed: true })
			assert app.notices.len == 3
		}
		app.bar_clock = false
		app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
		assert app.notices.len == 3
		app.bar_clock = true
		app.desktop = false
		app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
		assert app.notices.len == 3
		app.desktop = true
		app.bar_always = false
		app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
		assert app.notices.len == 3
	}
}

fn test_clock_clicks_match_visible_clock_on_narrow_screens_and_respect_modals() {
	for width in [1, 3, 5, 8, 10] {
		mut app := new_app()
		app.width = width
		app.clock_clicked = clock_record
		app.redraw()
		app.dispatch(Event{ kind: .mouse, x: width - 1, y: app.bar_y(), button: .left, pressed: true })
		assert app.notices.len == 1 && app.popups.len == 0
	}
	mut app := new_app()
	app.clock_clicked = clock_record
	mut modal := app.window('Modal', 30, 8)
	modal.modal = true
	app.dispatch(Event{ kind: .mouse, x: app.width - 1, y: app.bar_y(), button: .left, pressed: true })
	assert app.notices.len == 0
}

fn test_clock_callback_can_open_a_menu_and_date_picker() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		mut menu := context_menu()
		menu.menu_item('Calendar', fn (mut _ Ctl, mut app App) { app.clipboard_set('Calendar') })
		app.clock_clicked = fn [menu] (e Event, mut app App) { app.open_menu(menu, e.x, e.y) }
		app.dispatch(Event{ kind: .mouse, x: app.width - 2, y: app.bar_y(), button: .right, pressed: true })
		assert app.popups.len == 1
		p := app.popups[0]
		assert p.x >= 0 && p.x + p.w <= app.width
		assert !p.rect().contains(p.x, app.bar_y())
		app.dispatch(Event{ key: int(Key.enter) })
		assert app.clipboard_text() == 'Calendar'
	}
	mut app := new_app()
	app.window('Desktop', 30, 12)
	app.clock_clicked = fn (_ Event, mut app App) {
		if date := app.date_pick(app.top_window_ptr(), 'Calendar', time.Time{ year: 2024, month: 2, day: 28 }) {
			app.clipboard_set(picker_date_text(date))
		}
	}
	app.after(0, fn (mut app App) {
		app.dispatch(Event{ key: int(Key.right) })
		app.dispatch(Event{ key: int(Key.enter) })
	})
	app.dispatch(Event{ kind: .mouse, x: app.width - 2, y: app.bar_y(), button: .left, pressed: true })
	assert app.clipboard_text() == '2024-02-29' && app.windows.len == 1
}
