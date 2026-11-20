module vtk

import encoding.base64
import time

fn (app &App) now() i64 { return time.ticks() }

// V strings retain explicit byte lengths, including embedded NUL bytes.
pub fn (mut app App) clipboard_set(text string) {
	app.clipboard = text
	if app.native_clipboard && app.started {
		print('\x1b]52;c;${base64.encode_str(text)}\x07')
		flush_stdout()
	}
}

pub fn (app &App) clipboard_text() string { return app.clipboard }

pub fn (mut app App) copy_focus() bool {
	if isnil(app.focus) { return false }
	c := app.focus
	if c.kind in [.entry, .multiline, .markdown] && !c.secret {
		a, b := c.selection()
		if b > a {
			app.clipboard_set(c.text[a..b])
			return true
		}
	}
	if c.kind == .table && c.value >= 0 && c.value < c.high {
		mut cells := []string{}
		for col in 0 .. c.kids.len { cells << c.table_cell(c.value, col) }
		app.clipboard_set(cells.join('\t'))
		return true
	}
	return false
}
