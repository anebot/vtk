module vtk

import encoding.base64
import time

fn (app &App) now() i64 { return time.ticks() }

// V strings retain explicit byte lengths, including embedded NUL bytes.
pub fn (mut app App) clipboard_set(text string) {
	app.clipboard = text
	if app.native_clipboard && app.driver.active {
		app.driver.output('\x1b]52;c;${base64.encode_str(text)}\x07', discard_on_stop: true)
	}
}

pub fn (app &App) clipboard_text() string { return app.clipboard }

pub fn (mut app App) copy_focus() bool {
	c := app.focus or { return false }
	if !app.can_access(c) || !c.visible() { return false }
	if c.kind in [.entry, .multiline, .markdown] && !c.secret {
		a, b := c.selection()
		if b > a {
			app.clipboard_set(c.text[a..b])
			return true
		}
	}
	if c.kind == .table && c.table.copyable && c.table_selection().x >= 0 {
		app.clipboard_set(c.table_selection_text())
		return true
	}
	return false
}
