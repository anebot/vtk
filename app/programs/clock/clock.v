// VTK Clock: an analog clock with today's date. The dial follows the window size.
module clock

import math
import os
import time
import vtk

const app_name = 'VtkClock'
const app_version = '0.1.0'
const window_width = 44
const window_height = 22
// The dial and the date line must both stay readable, so narrower or shorter
// windows are rejected instead of hiding the date.
const minimum_width = 32
const minimum_height = 12
// Terminal cells are about twice as tall as wide, so one visual radius uses
// twice as many columns as rows.
const row_aspect = 2
// Hand lengths and the number ring as fractions of the dial radius.
const hour_hand = 0.46
const minute_hand = 0.74
const second_hand = 0.9
const number_ring = 0.78
const help_text = 'Drag the window frame or press Alt-F8 to resize the dial.\nThe short hand shows hours, the long hand minutes and the dotted hand seconds.\nThe bottom line shows the weekday, month, day and year.\nF1: this help; Ctrl-Q: quit.'

enum Action {
	help
	about
	quit
}

@[heap]
struct Clock {
mut:
	theme  vtk.Theme
	window &vtk.Ctl @[required]
	dial   &vtk.Ctl @[required]
	status &vtk.Ctl @[required]
}

// Dial is the largest circle that fits the cell area: cx/cy are its cell
// centre, rx the horizontal radius in columns and ry the vertical one in rows.
struct Dial {
mut:
	cx int
	cy int
	rx int
	ry int
}

// dial_fit returns the largest dial that fits area, as a circle rather than an
// ellipse in cell space.
fn dial_fit(area vtk.Rect) Dial {
	ry := math.max(0, math.min((area.h - 1) / 2, (area.w - 1) / (2 * row_aspect)))
	return Dial{area.x + area.w / 2, area.y + area.h / 2, row_aspect * ry, ry}
}

fn scaled(radius int, factor f64) int {
	return int(math.round(f64(radius) * factor))
}

// dial_point maps a clockwise angle from twelve o'clock onto a cell.
fn dial_point(cx int, cy int, rx int, ry int, angle f64) (int, int) {
	return cx + int(math.round(f64(rx) * math.sin(angle))), cy - int(math.round(f64(ry) * math.cos(angle)))
}

// hand_angle converts hours, minutes or seconds to a clockwise angle from
// twelve o'clock.
fn hand_angle(units f64, span f64) f64 {
	return math.tau * units / span
}

// hand_glyph follows a slope from the centre in cell space. Rows are twice as
// tall as columns, so doubled row offsets decide between the four glyphs.
fn hand_glyph(dx int, dy int) rune {
	ax, ay := if dx < 0 { -dx } else { dx }, if dy < 0 { -dy } else { dy }
	if 4 * ay < ax { return `─` }
	if ay > ax { return `│` }
	return if (dx > 0) != (dy > 0) { `/` } else { `\\` }
}

fn draw_rim(mut screen vtk.Screen, dial Dial, fg int, bg int) {
	glyph := if screen.ascii { `o` } else { `·` }
	steps := math.max(48, 8 * (dial.rx + dial.ry))
	for step in 0 .. steps {
		x, y := dial_point(dial.cx, dial.cy, dial.rx, dial.ry, hand_angle(f64(step), f64(steps)))
		screen.put(x, y, glyph, fg, bg, 0)
	}
}

fn draw_ticks(mut screen vtk.Screen, dial Dial, fg int, bg int) {
	glyph := if screen.ascii { `+` } else { `▪` }
	for hour in 0 .. 12 {
		x, y := dial_point(dial.cx, dial.cy, math.max(1, dial.rx - 1), math.max(1, dial.ry - 1),
			hand_angle(f64(hour), 12))
		screen.put(x, y, glyph, fg, bg, 0)
	}
}

// draw_numbers labels all twelve hours when the dial is wide enough, and the
// four quarters otherwise.
fn draw_numbers(mut screen vtk.Screen, dial Dial, fg int, bg int) {
	every_hour := dial.rx >= 11 && dial.ry >= 6
	rx, ry := scaled(dial.rx, number_ring), scaled(dial.ry, number_ring)
	for hour in 1 .. 13 {
		if !every_hour && hour !in [3, 6, 9, 12] { continue }
		label := hour.str()
		x, y := dial_point(dial.cx, dial.cy, rx, ry, hand_angle(f64(hour), 12))
		screen.text(x - vtk.text_width(label) / 2, y, label, fg, bg, vtk.bold)
	}
}

fn draw_hand(mut screen vtk.Screen, dial Dial, length f64, units f64, span f64, fg int, bg int) {
	x, y := dial_point(dial.cx, dial.cy, scaled(dial.rx, length), scaled(dial.ry, length),
		hand_angle(units, span))
	screen.line(dial.cx, dial.cy, x, y, hand_glyph(x - dial.cx, y - dial.cy), fg, bg)
}

fn draw_second_hand(mut screen vtk.Screen, dial Dial, units f64, fg int, bg int) {
	x, y := dial_point(dial.cx, dial.cy, scaled(dial.rx, second_hand), scaled(dial.ry,
		second_hand), hand_angle(units, 60))
	glyph := if screen.ascii { `.` } else { `·` }
	screen.line(dial.cx, dial.cy, x, y, glyph, fg, bg)
}

// clock_date names the weekday, month, day and year, shortening the text only
// when the row is too narrow for the long form.
fn clock_date(now time.Time, width int) string {
	day := time.long_days[now.day_of_week() - 1]
	month := time.long_months[vtk.clamp(now.month - 1, 0, 11)]
	long := '${day}, ${month} ${now.day}, ${now.year}'
	if vtk.text_width(long) <= width { return long }
	short := '${day[..3]} ${now.day} ${month[..3]} ${now.year}'
	if vtk.text_width(short) <= width { return short }
	return ''
}

// clock_text formats the wall-clock time shown in the status bar and, on a
// dial too small to read, in the dial area itself.
fn clock_text(now time.Time) string {
	return '${now.hour:02}:${now.minute:02}:${now.second:02}'
}

fn paint_clock(mut screen vtk.Screen, area vtk.Rect, now time.Time, theme vtk.Theme) {
	date_rows := if area.h >= 3 { 1 } else { 0 }
	screen.fill(area, ` `, theme.field_fg, theme.field_bg)
	face := vtk.Rect{area.x, area.y, area.w, area.h - date_rows}
	mut dial := dial_fit(face)
	mut date_y := area.y + area.h - 1
	if dial.rx < 4 || dial.ry < 2 {
		// A dial this small cannot be read, so show the time as digits.
		digits := clock_text(now)
		screen.text(face.x + math.max(0, (face.w - vtk.text_width(digits)) / 2), face.y + face.h / 2,
			digits, theme.field_fg, theme.field_bg, vtk.bold)
	} else {
		// Centre the dial and its date line as one block, so a tall window keeps
		// them together instead of leaving a gap between them.
		dial.cy = area.y + math.max(0, (area.h - 2 * dial.ry - 1 - date_rows) / 2) + dial.ry
		date_y = dial.cy + dial.ry + 1
		draw_rim(mut screen, dial, theme.dim, theme.field_bg)
		draw_ticks(mut screen, dial, theme.dim, theme.field_bg)
		draw_hand(mut screen, dial, hour_hand, f64(now.hour % 12) + f64(now.minute) / 60, 12,
			theme.accent, theme.field_bg)
		draw_hand(mut screen, dial, minute_hand, f64(now.minute) + f64(now.second) / 60, 60,
			theme.field_fg, theme.field_bg)
		draw_second_hand(mut screen, dial, f64(now.second), vtk.color_rgb(255, 96, 96),
			theme.field_bg)
		// Numbers are drawn over the hands, as on a real dial.
		draw_numbers(mut screen, dial, theme.field_fg, theme.field_bg)
		screen.put(dial.cx, dial.cy, if screen.ascii { `*` } else { `•` }, theme.field_fg,
			theme.field_bg, 0)
	}
	if date_rows == 1 {
		date := clock_date(now, area.w)
		x := area.x + math.max(0, (area.w - vtk.text_width(date)) / 2)
		screen.text(x, date_y, date, theme.dim, theme.field_bg, vtk.bold)
	}
}

fn paint_dial(mut c vtk.Ctl, mut screen vtk.Screen) {
	clock := c.context[Clock]() or { return }
	paint_clock(mut screen, c.rect(), time.now(), clock.theme)
}

// refresh keeps the digital time and the dial in step with the wall clock.
fn (mut clock Clock) refresh() {
	clock.status.set_text(clock_text(time.now()) + '   F1 help')
	clock.dial.invalidate_paint()
}

fn key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut clock := c.context[Clock]() or { return false }
	if e.ctrl && e.key == int(`q`) {
		app.close(mut clock.window)
		return true
	}
	if e.key == int(vtk.Key.f1) {
		app.msgbox_for(clock.window, 'Clock keys', help_text)
		return true
	}
	return false
}

fn menu_action(mut c vtk.Ctl, mut app vtk.App) {
	mut clock := c.context[Clock]() or { return }
	cmd := Action.from(c.data) or { return }
	match cmd {
		.help { app.msgbox_for(clock.window, 'Clock keys', help_text) }
		.about { app.about_for(clock.window, app_name, app_version) }
		.quit { app.close(mut clock.window) }
	}
}

fn menu_item(mut menu vtk.Ctl, clock &Clock, title string, id Action) {
	mut item := menu.menu_item(title, menu_action)
	item.set_context(clock)
	item.data = i64(id)
}

fn new_clock(mut app vtk.App) &Clock {
	mut clock := &Clock{
		theme: app.theme
		window: app.window('VTK Clock', window_width, window_height)
		// The preferred canvas fits inside the smallest window.
		dial: vtk.canvas(minimum_width - 2, minimum_height - 4, paint_dial)
		status: vtk.statusbar('')
	}
	clock.window.set_size_limits(minimum_width, minimum_height, 0, 0)
	clock.window.set_context(clock)
	clock.window.keyfn = key
	mut clock_menu := clock.window.add_menu('Clock')
	menu_item(mut clock_menu, clock, 'Quit   Ctrl-Q', .quit)
	mut help := clock.window.add_menu('Help')
	menu_item(mut help, clock, 'Keys   F1', .help)
	help.menu_separator()
	menu_item(mut help, clock, 'About', .about)
	mut body := vtk.box(true)
	clock.dial.expand = true
	clock.dial.focusable = true
	clock.dial.set_context(clock)
	clock.dial.keyfn = key
	body.add(mut clock.dial)
	body.add(mut clock.status)
	clock.window.add(mut body)
	app.set_focus(clock.dial)
	return clock
}

fn (mut clock Clock) schedule(mut app vtk.App) {
	app.after(500, fn [mut clock] (mut app vtk.App) {
		if clock.window.is_closed() { return }
		clock.refresh()
		clock.schedule(mut app)
	})
}

pub fn launch(mut app vtk.App) {
	mut clock := new_clock(mut app)
	clock.refresh()
	clock.schedule(mut app)
}

pub fn run() {
	mut app := vtk.new_app()
	app.ctrl_c = .quit
	snapshot := '--snapshot' in os.args
	if snapshot {
		app.desktop = false
		app.dispatch(vtk.Event{ kind: .resize, width: 64, height: 24 })
	} else {
		app.init() or {
			eprintln(err)
			return
		}
	}
	defer { app.fini() }
	launch(mut app)
	if snapshot {
		app.redraw()
		println(app.snapshot())
		return
	}
	app.run() or { eprintln(err) }
}
