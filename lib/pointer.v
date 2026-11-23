module vtk

import time

enum PointerSupport {
	unknown
	pending
	supported
	unsupported
}

// OSC 22 extensions may advertise the CSS "none" shape. Query first: ordinary
// OSC 22 support alone does not imply a terminal can hide its native pointer.
struct MousePointer {
mut:
	support PointerSupport
	due     i64
	hidden  bool
}

fn (mut p MousePointer) update(enabled bool, visible bool, now i64) string {
	if p.support == .pending && now >= p.due { p.support = .unsupported }
	if !enabled || !visible {
		if p.hidden { return p.restore() }
	}
	if !enabled { return '' }
	if p.support == .unknown {
		p.support = .pending
		p.due = now + 1500
		return '\x1b]22;?none\x1b\\'
	}
	if visible && p.support == .supported && !p.hidden {
		p.hidden = true
		// Push/pop preserves the pointer shape that was active before VTK.
		return '\x1b]22;>none\x1b\\'
	}
	return ''
}

fn (mut p MousePointer) reply(text string, now i64) {
	if p.support == .pending && now >= p.due { p.support = .unsupported }
	if p.support != .pending || text !in ['0', '1'] { return }
	p.support = if text == '1' { .supported } else { .unsupported }
}

fn (mut p MousePointer) restore() string {
	if !p.hidden { return '' }
	p.hidden = false
	return '\x1b]22;<\x1b\\'
}

// mouse_pointer_supported is true only after a terminal confirms that it can
// hide the native pointer. A missing reply leaves normal pointer behavior.
pub fn (app &App) mouse_pointer_supported() bool {
	return app.driver.pointer.support == .supported
}

fn (mut app App) sync_mouse_pointer() {
	if !app.driver.active { return }
	enabled := app.mouse_cursor.enabled && app.mouse_cursor.hide_pointer && app.terminal_focused
	visible := enabled && Rect{0, 0, app.width, app.height}.contains(app.mouse_x, app.mouse_y)
	sequence := app.driver.pointer.update(enabled, visible, time.ticks())
	app.driver.output(sequence)
}
