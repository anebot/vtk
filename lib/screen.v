module vtk

import encoding.utf8
import strings

pub struct Cell {
pub mut:
	glyph        string = ' '
	fg           int    = white
	bg           int
	attr         int
	continuation bool
}

pub struct Screen {
pub mut:
	ascii        bool
mut:
	width        int
	height       int
	cells        []Cell
	cursor_x     int = -1
	cursor_y     int = -1
	cursor_shape CursorShape
	front []Cell
	clip  Rect
}

pub fn (mut s Screen) resize(width int, height int) {
	w, h := max(1, width), max(1, height)
	if s.width == w && s.height == h && s.cells.len > 0 { return }
	s.width = w
	s.height = h
	s.cells = []Cell{len: w * h}
	s.front = []Cell{}
	s.clip = Rect{0, 0, w, h}
	s.set_cursor(s.cursor_x, s.cursor_y, s.cursor_shape)
}

pub fn (mut s Screen) invalidate() { s.front = []Cell{} }

pub fn (mut s Screen) set_cursor(x int, y int, shape CursorShape) bool {
	s.cursor_x, s.cursor_y = -1, -1
	if !s.clip.contains(x, y) || x < 0 || y < 0 || x >= s.width || y >= s.height { return false }
	s.cursor_x, s.cursor_y = x, y
	s.cursor_shape = shape
	return true
}

pub fn (mut s Screen) set_clip(r Rect) Rect {
	old := s.clip
	x, y := max(old.x, r.x), max(old.y, r.y)
	s.clip = Rect{x, y, max(0, min(old.x + old.w, r.x + r.w) - x), max(0, min(old.y + old.h, r.y + r.h) - y)}
	return old
}

pub fn (mut s Screen) restore_clip(r Rect) { s.clip = r }

pub fn rune_width(r rune) int {
	if r == 0 || r < 32 || (r >= 0x7f && r < 0xa0) { return 0 }
	if (r >= 0x300 && r <= 0x36f) || (r >= 0x1ab0 && r <= 0x1aff) || (r >= 0x1dc0 && r <= 0x1dff) || (r >= 0x20d0 && r <= 0x20ff) || (r >= 0xfe00 && r <= 0xfe0f) || r == 0x200d || (r >= 0xfe20 && r <= 0xfe2f) || (r >= 0xe0100 && r <= 0xe01ef) {
		return 0
	}
	if r < 0x1100 { return 1 }
	if in_rune_ranges(r, emoji_presentation) || (r >= 0x1100 && (r <= 0x115f || r == 0x2329 || r == 0x232a || (r >= 0x2e80 && r <= 0xa4cf && r != 0x303f) || (r >= 0xac00 && r <= 0xd7a3) || (r >= 0xf900 && r <= 0xfaff) || (r >= 0xfe10 && r <= 0xfe19) || (r >= 0xfe30 && r <= 0xfe6f) || (r >= 0xff00 && r <= 0xff60) || (r >= 0xffe0 && r <= 0xffe6) || (r >= 0x1f200 && r <= 0x1f251) || (r >= 0x20000 && r <= 0x3fffd))) {
		return 2
	}
	return 1
}

pub fn text_width(text string) int {
	mut width := 0
	for cluster in text.graphemes() { width += grapheme_width(cluster) }
	return width
}

fn ascii_glyph(r rune) rune {
	return match r {
		`─`, `═` { `-` }
		`│`, `║` { `|` }
		`┌`, `┐`, `└`, `┘`, `╔`, `╗`, `╚`, `╝`, `╭`, `╮`, `╯`, `╰`, `┴` { `+` }
		`▒`, `░` { `.` }
		`█`, `■` { `#` }
		`▼`, `▾` { `v` }
		`▸`, `►` { `>` }
		`◄` { `<` }
		`□`, `▣` { `O` }
		`•` { `*` }
		else {
			if r > 126 { `?` } else { r }
		}
	}
}

pub fn (mut s Screen) put(x int, y int, r rune, fg int, bg int, attr int) {
	s.put_grapheme(x, y, r.str(), rune_width(r), fg, bg, attr)
}

fn (mut s Screen) put_grapheme(x int, y int, text string, columns int, fg int, bg int, attr int) {
	if y < 0 || y >= s.height || x < 0 || x > s.width { return }
	r := text.runes()[0]
	if r < 32 || (r >= 0x7f && r < 0xa0) { return }
	actual := if s.ascii { ascii_glyph(r).str() } else { text }
	width := if s.ascii { 1 } else { columns }
	if width == 0 {
		if x > 0 && s.clip.contains(x - 1, y) {
			mut at := y * s.width + x - 1
			if s.cells[at].continuation && x > 1 { at-- }
			if s.clip.contains(at % s.width, y) { s.cells[at].glyph += actual }
		}
		return
	}
	if x >= s.width || !s.clip.contains(x, y) { return }
	if width == 2 && (!s.clip.contains(x + 1, y) || x + 1 >= s.width) { return }
	at := y * s.width + x
	// Overwriting either half of a wide character clears its partner.
	if s.cells[at].continuation && x > 0 { s.cells[at - 1] = Cell{ fg: fg, bg: bg } }
	if x + 1 < s.width && s.cells[at + 1].continuation { s.cells[at + 1] = Cell{ fg: fg, bg: bg } }
	s.cells[at] = Cell{actual, fg, bg, attr, false}
	if width == 2 { s.cells[at + 1] = Cell{'', fg, bg, attr, true} }
}

pub fn (mut s Screen) text(x int, y int, text string, fg int, bg int, attr int) {
	mut at := x
	if s.ascii {
		for r in text.runes() {
			if r == `\n` || r == `\r` { break }
			s.put(at, y, r, fg, bg, attr)
			at++
		}
		return
	}
	for cluster in text.graphemes() {
		if cluster.starts_with('\n') || cluster.starts_with('\r') { break }
		width := grapheme_width(cluster)
		s.put_grapheme(at, y, cluster, width, fg, bg, attr)
		at += width
	}
}

// Align inside a clipped content row, using the same cell widths as text().
fn (mut s Screen) aligned_text(x int, y int, width int, text string, align TextAlign, fg int, bg int, attr int) {
	if width <= 0 { return }
	mut columns := 0
	line := text.all_before('\n').all_before('\r')
	columns = if s.ascii { line.runes().len } else { text_width(line) }
	spare := max(0, width - columns)
	offset := match align {
		.left { 0 }
		.center { spare / 2 }
		.right { spare }
	}
	clip := s.set_clip(Rect{x, y, width, 1})
	s.text(x + offset, y, text, fg, bg, attr)
	s.restore_clip(clip)
}

pub fn (mut s Screen) fill(r Rect, glyph rune, fg int, bg int) {
	for y in max(0, max(s.clip.y, r.y)) .. min(s.height, min(s.clip.y + s.clip.h, r.y + max(0, r.h))) {
		for x in max(0, max(s.clip.x, r.x)) .. min(s.width, min(s.clip.x + s.clip.w, r.x + max(0, r.w))) {
			s.put(x, y, glyph, fg, bg, 0)
		}
	}
}

pub fn (mut s Screen) frame(r Rect, double bool, fg int, bg int) {
	if r.w < 2 || r.h < 2 { return }
	g := if double { '╔╗╚╝═║'.runes() } else { '┌┐└┘─│'.runes() }
	for x in r.x + 1 .. r.x + r.w - 1 {
		s.put(x, r.y, g[4], fg, bg, 0)
		s.put(x, r.y + r.h - 1, g[4], fg, bg, 0)
	}
	for y in r.y + 1 .. r.y + r.h - 1 {
		s.put(r.x, y, g[5], fg, bg, 0)
		s.put(r.x + r.w - 1, y, g[5], fg, bg, 0)
	}
	s.put(r.x, r.y, g[0], fg, bg, 0)
	s.put(r.x + r.w - 1, r.y, g[1], fg, bg, 0)
	s.put(r.x, r.y + r.h - 1, g[2], fg, bg, 0)
	s.put(r.x + r.w - 1, r.y + r.h - 1, g[3], fg, bg, 0)
}

pub fn (mut s Screen) line(x1 int, y1 int, x2 int, y2 int, glyph rune, fg int, bg int) {
	mut x, mut y := x1, y1
	dx, dy := abs(x2 - x1), -abs(y2 - y1)
	sx, sy := if x1 < x2 { 1 } else { -1 }, if y1 < y2 { 1 } else { -1 }
	mut err := dx + dy
	for {
		s.put(x, y, glyph, fg, bg, 0)
		if x == x2 && y == y2 { break }
		e := 2 * err
		if e >= dy {
			err += dy
			x += sx
		}
		if e <= dx {
			err += dx
			y += sy
		}
	}
}

fn ansi_color(color int, bg bool) string {
	base := if bg { 48 } else { 38 }
	if color & 0x1000000 != 0 {
		return '${base};2;${(color >> 16) & 255};${(color >> 8) & 255};${color & 255}'
	}
	if color & 0x2000000 != 0 { return '${base};5;${color & 255}' }
	return '${(if bg { 40 } else { 30 }) + (color & 7) + (if color & 8 != 0 { 60 } else { 0 })}'
}

// diff returns a single ANSI write and retains the front buffer. Text control
// bytes never reach the host terminal; only renderer-generated escapes do.
pub fn (mut s Screen) diff() string {
	mut out := strings.new_builder(s.cells.len)
	mut pen := Cell{ fg: -1, bg: -1, attr: -1 }
	for y in 0 .. s.height {
		mut positioned := false
		for x in 0 .. s.width {
			i := y * s.width + x
			cell := s.cells[i]
			if s.front.len == s.cells.len && cell == s.front[i] {
				positioned = false
				continue
			}
			if cell.continuation { continue }
			if !positioned {
				out.write_string('\x1b[${y + 1};${x + 1}H')
				positioned = true
			}
			if cell.fg != pen.fg || cell.bg != pen.bg || cell.attr != pen.attr {
				out.write_string('\x1b[0;${ansi_color(cell.fg, false)};${ansi_color(cell.bg, true)}m')
				if cell.attr & bold != 0 { out.write_string('\x1b[1m') }
				if cell.attr & underline != 0 { out.write_string('\x1b[4m') }
				if cell.attr & italic != 0 { out.write_string('\x1b[3m') }
				if cell.attr & reverse != 0 { out.write_string('\x1b[7m') }
				pen = cell
			}
			out.write_string(cell.glyph)
		}
	}
	s.front = s.cells.clone()
	if s.cursor_x >= 0 && s.cursor_x < s.width && s.cursor_y >= 0 && s.cursor_y < s.height {
		shape := if s.cursor_shape == .block { 2 } else { 6 }
		out.write_string('\x1b[${s.cursor_y + 1};${s.cursor_x + 1}H\x1b[${shape} q\x1b[?25h')
	} else {
		out.write_string('\x1b[?25l')
	}
	return out.str()
}

pub fn (s &Screen) snapshot() string {
	mut rows := []string{}
	for y in 0 .. s.height {
		mut row := ''
		for x in 0 .. s.width { row += s.cells[y * s.width + x].glyph }
		rows << row
	}
	return rows.join('\n')
}

fn boundary(text string, offset int) int {
	mut at := clamp(offset, 0, text.len)
	for at > 0 && at < text.len && text[at] & 0xc0 == 0x80 { at-- }
	return at
}

fn prev_char(text string, offset int) int { return boundary(text, max(0, offset - 1)) }

fn next_char(text string, offset int) int {
	if offset >= text.len { return text.len }
	_, n := utf8.decode_rune_at(text, max(0, offset))
	return min(text.len, offset + max(1, n))
}
