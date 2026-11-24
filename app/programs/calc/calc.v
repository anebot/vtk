// VTK Calc: a four-function calculator with a clickable keypad.
module calc

import math
import vtk
import vtk.app.programs.common

const app_name = 'VtkCalc'
const app_version = '0.1.0'
// Narrower windows would hide the rightmost keypad column.
const key_width = 7
const window_width = key_width * 4 + 5 // four keys, three dividers, two borders
const window_height = 10 // display lines, keypad rows, frame and menu bar
const keypad = [
	['C', 'Del', '%', '/'],
	['7', '8', '9', '*'],
	['4', '5', '6', '-'],
	['1', '2', '3', '+'],
	['+/-', '0', '.', '='],
]
const help_text = 'Click a key or type it.\n+ - * / fold into the running total.\nEnter or = shows the result.\nDel removes the last digit; C or Esc clears.\n+/- changes the sign; % divides by 100.\nCtrl-Q quits.'

enum CalcAction {
	clear
	help
	about
	quit
}

@[heap]
struct Calculator {
mut:
	entry   string = '0'
	total   f64
	pending string
	fresh   bool = true
	error   bool
	message string
	theme   vtk.Theme
	window  &vtk.Ctl @[required]
	display &vtk.Ctl @[required]
}

fn format_number(value f64) string {
	if !math.is_finite(value) { return 'Error' }
	return '${value:.12g}'
}

fn operate(left f64, op string, right f64) !f64 {
	value := match op {
		'+' { left + right }
		'-' { left - right }
		'*' { left * right }
		'/' {
			if right == 0 { return error('Cannot divide by zero') }
			left / right
		}
		else { return error('Unknown operator') }
	}
	if !math.is_finite(value) { return error('Result is too large') }
	return value
}

fn (mut c Calculator) reset() {
	c.entry = '0'
	c.total = 0
	c.pending = ''
	c.fresh = true
	c.error = false
	c.message = ''
}

fn (mut c Calculator) fail(message string) {
	c.reset()
	c.error = true
	c.entry = 'Error'
	c.message = message
}

fn (mut c Calculator) value() f64 { return c.entry.f64() }

fn (mut c Calculator) digit(d string) {
	if c.error { c.reset() }
	if c.fresh {
		c.entry = d
		c.fresh = false
		return
	}
	if c.entry.len < 15 {
		c.entry = if c.entry == '0' { d } else { c.entry + d }
	}
}

fn (mut c Calculator) point() {
	if c.error { c.reset() }
	if c.fresh {
		c.entry = '0.'
		c.fresh = false
	} else if !c.entry.contains('.') {
		c.entry += '.'
	}
}

fn (mut c Calculator) backspace() {
	if c.error {
		c.reset()
		return
	}
	if c.fresh { return }
	c.entry = c.entry[..c.entry.len - 1]
	if c.entry == '' || c.entry == '-' {
		c.entry = '0'
		c.fresh = true
	}
}

fn (mut c Calculator) negate() {
	if c.error || c.entry.f64() == 0 { return }
	c.entry = format_number(-c.value())
}

fn (mut c Calculator) percent() {
	if c.error { return }
	c.entry = format_number(c.value() / 100)
	c.fresh = true
}

fn (mut c Calculator) operator(op string) {
	if c.error { return }
	if c.pending != '' && !c.fresh {
		c.total = operate(c.total, c.pending, c.value()) or {
			c.fail(err.msg())
			return
		}
	} else if c.pending == '' {
		c.total = c.value()
	}
	c.pending = op
	c.entry = format_number(c.total)
	c.fresh = true
}

fn (mut c Calculator) equals() {
	if c.error || c.pending == '' { return }
	c.total = operate(c.total, c.pending, c.value()) or {
		c.fail(err.msg())
		return
	}
	c.entry = format_number(c.total)
	c.pending = ''
	c.fresh = true
}

// input applies one keypad label, so buttons and the keyboard share one path.
fn (mut c Calculator) input(key string) {
	label := match key {
		'x', 'X' { '*' }
		'c', 'C' { 'C' }
		else { key }
	}
	if label.len == 1 && label[0] >= `0` && label[0] <= `9` {
		c.digit(label)
		return
	}
	match label {
		'C' { c.reset() }
		'Del' { c.backspace() }
		'+/-' { c.negate() }
		'%' { c.percent() }
		'=' { c.equals() }
		'.' { c.point() }
		'+', '-', '*', '/' { c.operator(label) }
		else {}
	}
}

fn paint_display(mut c vtk.Ctl, mut screen vtk.Screen) {
	calc := c.context[Calculator]() or { return }
	bounds := c.rect()
	theme := calc.theme
	screen.fill(bounds, ` `, theme.field_fg, theme.field_bg)
	if calc.message != '' {
		screen.text(bounds.x, bounds.y, calc.message, vtk.red, theme.field_bg, 0)
	} else if calc.pending != '' {
		screen.text(bounds.x, bounds.y, '${format_number(calc.total)} ${calc.pending}', theme.dim,
			theme.field_bg, 0)
	}
	y := bounds.y + bounds.h - 1
	x := bounds.x + math.max(0, bounds.w - vtk.text_width(calc.entry))
	fg := if calc.error { vtk.red } else { theme.field_fg }
	screen.text(x, y, calc.entry, fg, theme.field_bg, vtk.bold)
}

fn button_press(mut c vtk.Ctl, mut app vtk.App) {
	mut calc := c.context[Calculator]() or { return }
	calc.input(c.text)
	app.invalidate()
}

fn key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut calc := c.context[Calculator]() or { return false }
	if e.ctrl {
		if e.key == int(`q`) {
			app.close(mut calc.window)
			return true
		}
		return false
	}
	if e.key == int(vtk.Key.f1) {
		app.msgbox_for(calc.window, 'Calculator keys', help_text)
		return true
	}
	label := match e.key {
		int(vtk.Key.enter) { '=' }
		int(vtk.Key.backspace) { 'Del' }
		int(vtk.Key.escape) { 'C' }
		else {
			if e.key > 32 && e.key < 127 { u8(e.key).ascii_str() } else { return false }
		}
	}
	calc.input(label)
	app.invalidate()
	return true
}

fn menu_action(mut c vtk.Ctl, mut app vtk.App) {
	mut calc := c.context[Calculator]() or { return }
	cmd := CalcAction.from(c.data) or { return }
	match cmd {
		.clear {
			calc.reset()
			app.invalidate()
		}
		.help { app.msgbox_for(calc.window, 'Calculator keys', help_text) }
		.about { app.about_for(calc.window, app_name, app_version) }
		.quit { app.close(mut calc.window) }
	}
}

fn menu_item(mut menu vtk.Ctl, calc &Calculator, title string, id CalcAction) {
	mut item := menu.menu_item(title, menu_action)
	item.set_context(calc)
	item.data = i64(id)
}

fn new_calculator(mut app vtk.App) &Calculator {
	mut calc := &Calculator{
		theme: app.theme
		window: app.window('VTK Calc', window_width, window_height)
		display: vtk.canvas(window_width - 2, 2, paint_display)
	}
	calc.window.set_size_limits(window_width, window_height, 0, 0)
	calc.window.set_context(calc)
	calc.window.keyfn = key
	mut calc_menu := calc.window.add_menu('Calc')
	menu_item(mut calc_menu, calc, 'Clear   C', .clear)
	calc_menu.menu_separator()
	menu_item(mut calc_menu, calc, 'Quit   Ctrl-Q', .quit)
	mut help := calc.window.add_menu('Help')
	menu_item(mut help, calc, 'Keys   F1', .help)
	help.menu_separator()
	menu_item(mut help, calc, 'About', .about)
	mut body := vtk.box(true)
	calc.display.expand = true
	calc.display.focusable = true
	calc.display.set_context(calc)
	calc.display.keyfn = key
	body.add(mut calc.display)
	mut keys := vtk.grid()
	for row, labels in keypad {
		for col, label in labels {
			mut button := vtk.button(label)
			button.col = col
			button.row = row
			button.min_w = key_width
			button.expand = true
			button.set_context(calc)
			button.changed = button_press
			button.keyfn = key
			keys.add(mut button)
		}
	}
	body.add(mut keys)
	calc.window.add(mut body)
	width, height := app.size()
	window := calc.window.rect()
	app.move(mut calc.window, math.max(0, (width - window.w) / 2), math.max(0,
		(height - window.h) / 2))
	app.set_focus(calc.display)
	return calc
}

pub fn launch(mut app vtk.App) {
	_ := new_calculator(mut app)
}

pub fn run() {
	mut app := vtk.new_app()
	common.run(mut app, launch)
}
