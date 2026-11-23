module vtk

import encoding.utf8

// Terminal is an incremental xterm subset, independent of the PTY transport.
// feed can be used on arbitrary chunks, including split UTF-8/CSI sequences.
@[heap]
pub struct Terminal {
pub mut:
	cols          int
	rows          int
	cells         []Cell
	cx            int
	cy            int
	cursor_hidden bool
	exited        bool
mut:
	pty         Pty
	saved_x     int
	saved_y     int
	top         int
	bottom      int
	fg          int = white
	bg          int
	attr        int
	state       int
	sequence    string
	utf8_buffer string
	osc_escape  bool
	repaint     bool = true
	pending     string
}

pub fn new_terminal(cols int, rows int) &Terminal {
	mut t := &Terminal{}
	t.resize(cols, rows)
	return t
}

pub fn terminal(cols int, rows int) !&Ctl {
	mut t := new_terminal(cols, rows)
	t.pty = spawn_pty(t.cols, t.rows)!
	return &Ctl{ kind: .terminal, term: t, pw: cols, ph: rows, expand: true, focusable: true }
}

pub fn (mut app App) terminal_window() !&Ctl {
	mut control := terminal(72, 18)!
	mut w := app.window('Terminal', 74, 20)
	w.add(mut control)
	app.set_focus(control)
	return w
}

pub fn (mut t Terminal) resize(cols int, rows int) {
	w, h := max(2, cols), max(1, rows)
	if w == t.cols && h == t.rows { return }
	mut cells := []Cell{len: w * h}
	for y in 0 .. min(h, t.rows) {
		for x in 0 .. min(w, t.cols) { cells[y * w + x] = t.cells[y * t.cols + x] }
	}
	t.cols = w
	t.rows = h
	t.cells = cells
	t.top = 0
	t.bottom = h - 1
	t.cx = clamp(t.cx, 0, w - 1)
	t.cy = clamp(t.cy, 0, h - 1)
	t.pty.resize(w, h)
	t.repaint = true
}

fn (t &Terminal) blank() Cell { return Cell{ fg: t.fg, bg: t.bg } }

fn (mut t Terminal) clear_range(row int, from int, to int) {
	if row < 0 || row >= t.rows { return }
	a, b := clamp(from, 0, t.cols), clamp(to, 0, t.cols)
	if a >= b { return }
	if a > 0 && a < t.cols && t.cells[row * t.cols + a].continuation {
		t.cells[row * t.cols + a - 1] = t.blank()
	}
	if b < t.cols && t.cells[row * t.cols + b].continuation {
		t.cells[row * t.cols + b] = t.blank()
	}
	for x in clamp(from, 0, t.cols) .. clamp(to, 0, t.cols) {
		t.cells[row * t.cols + x] = t.blank()
	}
}

fn (mut t Terminal) scroll_region(lines int) {
	n := min(abs(lines), t.bottom - t.top + 1)
	if lines > 0 {
		for y in t.top .. t.bottom + 1 - n {
			for x in 0 .. t.cols { t.cells[y * t.cols + x] = t.cells[(y + n) * t.cols + x] }
		}
		for y in t.bottom + 1 - n .. t.bottom + 1 { t.clear_range(y, 0, t.cols) }
	} else if lines < 0 {
		for y := t.bottom; y >= t.top + n; y-- {
			for x in 0 .. t.cols { t.cells[y * t.cols + x] = t.cells[(y - n) * t.cols + x] }
		}
		for y in t.top .. t.top + n { t.clear_range(y, 0, t.cols) }
	}
}

fn (mut t Terminal) newline() {
	if t.cy == t.bottom { t.scroll_region(1) } else { t.cy = min(t.rows - 1, t.cy + 1) }
}

fn (mut t Terminal) put(r rune) {
	// ACP/PTY output can split a selector, modifier or ZWJ sequence between
	// reads. Upgrade the previous cell in place instead of advancing again.
	if r >= 0x80 && t.cx > 0 {
		mut at := t.cy * t.cols + min(t.cols - 1, t.cx - 1)
		if t.cells[at].continuation && at % t.cols > 0 { at-- }
		previous := t.cells[at]
		joined := previous.glyph + r.str()
		if joined.graphemes().len == 1 {
			width := grapheme_width(joined)
			old_width := if at % t.cols + 1 < t.cols && t.cells[at + 1].continuation { 2 } else { 1 }
			column := at % t.cols
			t.clear_range(t.cy, column, column + max(width, old_width))
			if column + width > t.cols {
				t.cx = 0
				t.newline()
				at = t.cy * t.cols
			} else { t.cx = column }
			t.cells[at] = Cell{ ...previous, glyph: joined }
			if width == 2 { t.cells[at + 1] = Cell{ ...previous, glyph: '', continuation: true } }
			t.cx += width
			return
		}
	}
	w := rune_width(r)
	if w == 0 {
		if t.cx > 0 {
			mut at := t.cy * t.cols + min(t.cols - 1, t.cx - 1)
			if t.cells[at].continuation && at > 0 { at-- }
			t.cells[at].glyph += r.str()
		}
		return
	}
	if t.cx + w > t.cols {
		t.cx = 0
		t.newline()
	}
	at := t.cy * t.cols + t.cx
	if t.cells[at].continuation && t.cx > 0 { t.cells[at - 1] = t.blank() }
	if t.cx + 1 < t.cols && t.cells[at + 1].continuation { t.cells[at + 1] = t.blank() }
	t.cells[at] = Cell{r.str(), t.fg, t.bg, t.attr, false}
	if w == 2 { t.cells[at + 1] = Cell{'', t.fg, t.bg, t.attr, true} }
	t.cx += w
}

pub fn (mut t Terminal) feed(bytes string) {
	for byte in bytes.bytes() {
		match t.state {
			0 {
				if byte == 27 {
					t.state = 1
					t.utf8_buffer = ''
					continue
				}
				if byte < 32 || byte == 127 {
					match byte {
						10, 11, 12 { t.newline() }
						13 { t.cx = 0 }
						8 { t.cx = max(0, t.cx - 1) }
						9 { t.cx = min(t.cols - 1, (t.cx / 8 + 1) * 8) }
						else {}
					}
					continue
				}
				t.utf8_buffer += byte.ascii_str()
				if t.utf8_buffer.len >= utf8_char_len(t.utf8_buffer[0]) {
					r, _ := utf8.decode_rune_at(t.utf8_buffer, 0)
					t.put(r)
					t.utf8_buffer = ''
				}
			}
			1 {
				t.state = 0
				match byte {
					`[` {
						t.state = 2
						t.sequence = ''
					}
					`]` {
						t.state = 3
						t.osc_escape = false
					}
					`7` {
						t.saved_x = t.cx
						t.saved_y = t.cy
					}
					`8` {
						t.cx = clamp(t.saved_x, 0, t.cols - 1)
						t.cy = clamp(t.saved_y, 0, t.rows - 1)
					}
					`D` { t.newline() }
					`E` {
						t.cx = 0
						t.newline()
					}
					`M` {
						if t.cy == t.top { t.scroll_region(-1) } else { t.cy = max(0, t.cy - 1) }
					}
					`c` {
						t.fg = white
						t.bg = black
						t.attr = 0
						t.cx = 0
						t.cy = 0
						t.top = 0
						t.bottom = t.rows - 1
						for y in 0 .. t.rows { t.clear_range(y, 0, t.cols) }
					}
					`(`, `)` { t.state = 4 }
					else {}
				}
			}
			2 {
				if byte >= 0x40 && byte <= 0x7e {
					t.csi(byte)
					t.state = 0
				} else if t.sequence.len < 256 {
					t.sequence += byte.ascii_str()
				} else {
					t.state = 0
				}
			}
			3 {
				if byte == 7 || (t.osc_escape && byte == `\\`) { t.state = 0 }
				t.osc_escape = byte == 27
			}
			else { t.state = 0 }
		}
	}
	t.repaint = true
}

fn param(params []int, i int, fallback int) int {
	return if i >= params.len || params[i] == 0 { fallback } else { params[i] }
}

fn (mut t Terminal) csi(final u8) {
	private := t.sequence.starts_with('?')
	seq := t.sequence.trim_left('?')
	mut p := []int{}
	for part in seq.split(';') { p << part.int() }
	n := param(p, 0, 1)
	match final {
		`A` { t.cy = max(0, t.cy - n) }
		`B` { t.cy = min(t.rows - 1, t.cy + n) }
		`C` { t.cx = min(t.cols - 1, t.cx + n) }
		`D` { t.cx = max(0, t.cx - n) }
		`E` {
			t.cy = min(t.rows - 1, t.cy + n)
			t.cx = 0
		}
		`F` {
			t.cy = max(0, t.cy - n)
			t.cx = 0
		}
		`G`, 96 { t.cx = clamp(n - 1, 0, t.cols - 1) }
		`d` { t.cy = clamp(n - 1, 0, t.rows - 1) }
		`H`, `f` {
			t.cy = clamp(n - 1, 0, t.rows - 1)
			t.cx = clamp(param(p, 1, 1) - 1, 0, t.cols - 1)
		}
		`J` {
			if p[0] in [2, 3] {
				for y in 0 .. t.rows { t.clear_range(y, 0, t.cols) }
			} else if p[0] == 1 {
				for y in 0 .. t.cy { t.clear_range(y, 0, t.cols) }
				t.clear_range(t.cy, 0, t.cx + 1)
			} else {
				t.clear_range(t.cy, t.cx, t.cols)
				for y in t.cy + 1 .. t.rows { t.clear_range(y, 0, t.cols) }
			}
		}
		`K` {
			if p[0] == 2 {
				t.clear_range(t.cy, 0, t.cols)
			} else if p[0] == 1 {
				t.clear_range(t.cy, 0, t.cx + 1)
			} else {
				t.clear_range(t.cy, t.cx, t.cols)
			}
		}
		`X` { t.clear_range(t.cy, t.cx, min(t.cols, t.cx + n)) }
		`m` { t.sgr(p) }
		`r` {
			top, bottom := clamp(n - 1, 0, t.rows - 1), clamp(param(p, 1, t.rows) - 1, 0, t.rows - 1)
			if top < bottom {
				t.top = top
				t.bottom = bottom
				t.cx = 0
				t.cy = 0
			}
		}
		`s` {
			t.saved_x = t.cx
			t.saved_y = t.cy
		}
		`u` {
			t.cx = clamp(t.saved_x, 0, t.cols - 1)
			t.cy = clamp(t.saved_y, 0, t.rows - 1)
		}
		`S` { t.scroll_region(n) }
		`T` { t.scroll_region(-n) }
		`L`, `M` {
			if t.cy >= t.top && t.cy <= t.bottom {
				old := t.top
				t.top = t.cy
				t.scroll_region(if final == `L` { -n } else { n })
				t.top = old
			}
		}
		`P`, `@` {
			count := min(n, max(0, t.cols - t.cx))
			if final == `P` {
				for x in t.cx .. t.cols - count {
					t.cells[t.cy * t.cols + x] = t.cells[t.cy * t.cols + x + count]
				}
				t.clear_range(t.cy, t.cols - count, t.cols)
			} else {
				for x := t.cols - 1; x >= t.cx + count; x-- {
					t.cells[t.cy * t.cols + x] = t.cells[t.cy * t.cols + x - count]
				}
				t.clear_range(t.cy, t.cx, t.cx + count)
			}
		}
		`h`, `l` {
			if private {
				for mode in p {
					if mode == 25 { t.cursor_hidden = final == `l` }
					if mode in [47, 1047, 1049] && final == `h` {
						for y in 0 .. t.rows { t.clear_range(y, 0, t.cols) }
						t.cx = 0
						t.cy = 0
					}
				}
			}
		}
		`n` {
			if p[0] == 6 { t.write('\x1b[${t.cy + 1};${t.cx + 1}R') }
		}
		`c` { t.write('\x1b[?1;2c') }
		else {}
	}
}

fn (mut t Terminal) sgr(p []int) {
	mut i := 0
	for i < p.len {
		n := p[i]
		match n {
			0 {
				t.fg = white
				t.bg = black
				t.attr = 0
			}
			1 { t.attr |= bold }
			3 { t.attr |= italic }
			4 { t.attr |= underline }
			7 { t.attr |= reverse }
			22 { t.attr &= ~bold }
			23 { t.attr &= ~italic }
			24 { t.attr &= ~underline }
			27 { t.attr &= ~reverse }
			39 { t.fg = white }
			49 { t.bg = black }
			38, 48 {
				mut color := -1
				if i + 2 < p.len && p[i + 1] == 5 {
					color = color_256(p[i + 2])
					i += 2
				} else if i + 4 < p.len && p[i + 1] == 2 {
					color = color_rgb(p[i + 2], p[i + 3], p[i + 4])
					i += 4
				}
				if color >= 0 {
					if n == 38 { t.fg = color } else { t.bg = color }
				}
			}
			else {
				if n >= 30 && n <= 37 { t.fg = n - 30 }
				if n >= 40 && n <= 47 { t.bg = n - 40 }
				if n >= 90 && n <= 97 { t.fg = n - 90 + 8 }
				if n >= 100 && n <= 107 { t.bg = n - 100 + 8 }
			}
		}
		i++
	}
}

pub fn (mut t Terminal) write(text string) {
	t.pending += text
	t.flush_input()
}

fn (mut t Terminal) flush_input() {
	if t.pending == '' { return }
	n := t.pty.write(t.pending)
	if n > 0 { t.pending = t.pending[n..] }
}

pub fn (mut t Terminal) key(e Event) {
	mut text := match e.key {
		int(Key.enter) { '\r' }
		int(Key.tab) { '\t' }
		int(Key.backspace) { '\x7f' }
		int(Key.escape) { '\x1b' }
		int(Key.up) { '\x1b[A' }
		int(Key.down) { '\x1b[B' }
		int(Key.right) { '\x1b[C' }
		int(Key.left) { '\x1b[D' }
		int(Key.home) { '\x1b[H' }
		int(Key.end) { '\x1b[F' }
		int(Key.page_up) { '\x1b[5~' }
		int(Key.page_down) { '\x1b[6~' }
		int(Key.delete) { '\x1b[3~' }
		int(Key.insert) { '\x1b[2~' }
		int(Key.f1) { '\x1bOP' }
		int(Key.f2) { '\x1bOQ' }
		int(Key.f3) { '\x1bOR' }
		int(Key.f4) { '\x1bOS' }
		int(Key.f5) { '\x1b[15~' }
		int(Key.f6) { '\x1b[17~' }
		int(Key.f7) { '\x1b[18~' }
		int(Key.f8) { '\x1b[19~' }
		int(Key.f9) { '\x1b[20~' }
		int(Key.f10) { '\x1b[21~' }
		int(Key.f11) { '\x1b[23~' }
		int(Key.f12) { '\x1b[24~' }
		else {
			if e.key >= 32 && e.key < 0x110000 {
				rune(if e.ctrl { lower_key(e.key) & 31 } else { e.key }).str()
			} else {
				''
			}
		}
	}
	if e.alt { text = '\x1b' + text }
	t.write(text)
}

pub fn (mut t Terminal) close() {
	t.pty.close()
	t.exited = true
}

fn (mut app App) pump_terminals(mut c Ctl) {
	if c.closed { return }
	if !isnil(c.term) {
		c.term.flush_input()
		mut budget := 65536
		for budget > 0 {
			bytes := c.term.pty.read(min(16384, budget))
			if bytes == '' { break }
			c.term.feed(bytes)
			budget -= bytes.len
			app.dirty = true
		}
		c.term.exited = !c.term.pty.alive()
	}
	for mut child in c.kids { app.pump_terminals(mut child) }
}

fn (mut app App) close_terminals(mut c Ctl) {
	if !isnil(c.term) { c.term.close() }
	for mut child in c.kids { app.close_terminals(mut child) }
}

fn (mut app App) draw_terminal(mut c Ctl) {
	if isnil(c.term) { return }
	c.term.resize(c.w, c.h)
	for y in 0 .. min(c.h, c.term.rows) {
		for x in 0 .. min(c.w, c.term.cols) {
			cell := c.term.cells[y * c.term.cols + x]
			if !cell.continuation {
				app.screen.text(c.x + x, c.y + y, cell.glyph, cell.fg, cell.bg, cell.attr)
			}
		}
	}
	if app.focus == &c && !c.term.cursor_hidden {
		app.screen.cursor_x = c.x + min(c.w - 1, c.term.cx)
		app.screen.cursor_y = c.y + c.term.cy
		app.screen.cursor_shape = .block
	}
	c.term.repaint = false
}
