module vtk

import time

// date_picker selects a Gregorian date. Time of day and timezone are ignored;
// components are clamped to valid dates in years 1..9999.
pub fn date_picker(initial time.Time) &Ctl {
	date := picker_date(initial)
	return &Ctl{ kind: .date_picker, date_value: date, text: picker_date_text(date), focusable: true }
}

// date returns the selected date at midnight, without a timezone.
pub fn (c &Ctl) date() time.Time { return picker_date(c.date_value) }

pub fn (mut c Ctl) set_date(value time.Time) {
	if c.kind != .date_picker { return }
	date := picker_date(value)
	if c.date_value.year == date.year && c.date_value.month == date.month && c.date_value.day == date.day {
		return
	}
	c.date_value = date
	c.text = picker_date_text(date)
	c.fire()
}

fn picker_date(value time.Time) time.Time {
	if value.year < 1 { return time.new(time.Time{ year: 1, month: 1, day: 1 }) }
	if value.year > 9999 { return time.new(time.Time{ year: 9999, month: 12, day: 31 }) }
	month := clamp(value.month, 1, 12)
	days := time.days_in_month(month, value.year) or { 31 }
	return time.new(time.Time{ year: value.year, month: month, day: clamp(value.day, 1, days) })
}

fn picker_date_text(date time.Time) string {
	return '${date.year:04}-${date.month:02}-${date.day:02}'
}

fn (mut c Ctl) date_picker_months(months int) {
	date := c.date()
	index := clamp((date.year - 1) * 12 + date.month - 1 + months, 0, 9999 * 12 - 1)
	c.set_date(time.Time{ year: index / 12 + 1, month: index % 12 + 1, day: date.day })
}

fn (mut c Ctl) date_picker_key(e Event, mut app App) bool {
	if c.readonly || e.alt { return false }
	if e.ctrl && e.key !in [int(Key.page_up), int(Key.page_down)] { return false }
	date := c.date()
	match e.key {
		int(Key.left) { c.set_date(date.add_days(-1)) }
		int(Key.right) { c.set_date(date.add_days(1)) }
		int(Key.up) { c.set_date(date.add_days(-7)) }
		int(Key.down) { c.set_date(date.add_days(7)) }
		int(Key.page_up) { c.date_picker_months(if e.shift || e.ctrl { -12 } else { -1 }) }
		int(Key.page_down) { c.date_picker_months(if e.shift || e.ctrl { 12 } else { 1 }) }
		int(Key.home) { c.set_date(time.Time{ year: date.year, month: date.month, day: 1 }) }
		int(Key.end) { c.set_date(time.Time{ year: date.year, month: date.month, day: 31 }) }
		int(`t`), int(`T`) { c.set_date(time.now()) }
		int(Key.enter), int(Key.space) {
			if f := c.submit { f(mut c, mut app) } else { return false }
		}
		else { return false }
	}
	return true
}

fn (c &Ctl) date_picker_grid_x() int { return c.x + max(0, (c.w - 21) / 2) }

fn (mut c Ctl) date_picker_mouse(e Event) {
	if c.readonly { return }
	if e.y == c.y {
		if e.x < c.x + 3 {
			c.date_picker_months(if e.shift { -12 } else { -1 })
		} else if e.x >= c.x + c.w - 3 {
			c.date_picker_months(if e.shift { 12 } else { 1 })
		}
		return
	}
	if e.y == c.y + 8 && e.x < c.x + 7 {
		c.set_date(time.now())
		return
	}
	x, row := e.x - c.date_picker_grid_x(), e.y - c.y - 2
	if x < 0 || x >= 21 || row < 0 || row >= 6 { return }
	date := c.date()
	first := time.Time{ year: date.year, month: date.month, day: 1 }
	day := row * 7 + x / 3 - (first.day_of_week() - 1) + 1
	days := time.days_in_month(date.month, date.year) or { 31 }
	if day >= 1 && day <= days {
		c.set_date(time.Time{ year: date.year, month: date.month, day: day })
	}
}

fn (mut app App) draw_date_picker(c &Ctl) {
	padding_clip := app.screen.set_clip(c.rect())
	defer { app.screen.restore_clip(padding_clip) }
	t := app.theme
	date := c.date()
	fg := if c.disabled { t.dim } else { t.field_fg }
	app.fill_ctl(c, fg, t.field_bg)
	header := '${time.long_months[date.month - 1]} ${date.year:04}'
	app.screen.aligned_text(c.x + 3, c.y, max(0, c.w - 6), header, .center, fg, t.field_bg, bold)
	app.screen.text(c.x, c.y, ' < ', fg, t.field_bg, 0)
	app.screen.text(c.x + c.w - 3, c.y, ' > ', fg, t.field_bg, 0)
	x := c.date_picker_grid_x()
	app.screen.text(x, c.y + 1, ' Mo Tu We Th Fr Sa Su', t.dim, t.field_bg, 0)
	first := time.Time{ year: date.year, month: date.month, day: 1 }
	offset := first.day_of_week() - 1
	days := time.days_in_month(date.month, date.year) or { 31 }
	today := time.now()
	for day in 1 .. days + 1 {
		cell := offset + day - 1
		selected := day == date.day
		is_today := day == today.day && date.month == today.month && date.year == today.year
		bg := if selected && !c.disabled {
			if same_ctl(app.focus, c) { t.focus_bg } else { t.sel_bg }
		} else {
			t.field_bg
		}
		color := if c.disabled {
			t.dim
		} else if selected {
			if same_ctl(app.focus, c) { t.focus_fg } else { t.sel_fg }
		} else if is_today {
			t.accent
		} else {
			fg
		}
		app.screen.text(x + cell % 7 * 3, c.y + 2 + cell / 7, '${day:3}', color, bg, if selected || is_today {
			bold
		} else {
			0
		})
	}
	app.screen.text(c.x, c.y + 8, '[Today]', fg, t.field_bg, 0)
	app.screen.text(c.x + max(8, c.w - 10), c.y + 8, picker_date_text(date), fg, t.field_bg, 0)
}

fn date_picker_accept(mut c Ctl, mut app App) {
	mut w := c.owner_window() or { return }
	w.dialog_result = 1
	app.close(mut w)
}

// date_pick returns the chosen date, or none when cancelled.
pub fn (mut app App) date_pick(owner ?&Ctl, title string, initial time.Time) ?time.Time {
	if !app.can_own_dialog(owner) { return none }
	mut body := box(true)
	mut picker := date_picker(initial)
	picker.submit = date_picker_accept
	mut row := button_bar()
	mut ok := dialog_button('OK', true)
	mut cancel := dialog_button('Cancel', false)
	row.add(mut ok)
	row.add(mut cancel)
	body.add(mut picker)
	body.add(mut row)
	mut w := app.dialog(title, mut body)
	w.default_button = ok
	app.set_focus(picker)
	accepted := app.modal_for(mut w, owner) == 1
	result := picker.date()
	app.destroy_ctl(mut w)
	if !accepted { return none }
	return result
}
