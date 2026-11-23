module vtk

import encoding.utf8
import vtk.render

pub type Cell = render.Cell

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
	ansi render.Ansi
	damage []render.Span
	damage_first int
	damage_end int
	clip  Rect
	paint_y int
	paint_end int
}

pub fn (mut s Screen) resize(width int, height int) {
	w, h := max(1, width), max(1, height)
	if s.width == w && s.height == h && s.cells.len > 0 { return }
	s.width = w
	s.height = h
	s.cells = []Cell{len: w * h}
	s.ansi.reset()
	s.damage = []render.Span{len: h}
	s.damage_first, s.damage_end = h, 0
	s.clip = Rect{0, 0, w, h}
	s.paint_y, s.paint_end = 0, h
	s.set_cursor(s.cursor_x, s.cursor_y, s.cursor_shape)
}

pub fn (mut s Screen) invalidate() { s.ansi.reset() }

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

// ASCII is common in borders, tables, diffs and shell output.
const printable_ascii = [' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~']!

fn display_rune(r rune) string {
	if r >= 32 && r < 127 { return printable_ascii[int(r) - 32] }
	return r.str()
}

pub fn text_width(text string) int {
	mut width := 0
	for i in 0 .. text.len {
		ch := text[i]
		if ch >= 128 {
			width = 0
			for cluster in text.graphemes() { width += grapheme_width(cluster) }
			return width
		}
		if ch >= 32 && ch < 127 { width++ }
	}
	return width
}

fn is_ascii(text string) bool {
	for i in 0 .. text.len {
		if text[i] >= 128 { return false }
	}
	return true
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
	s.put_grapheme(x, y, display_rune(r), rune_width(r), fg, bg, attr)
}

fn (mut s Screen) put_grapheme(x int, y int, text string, columns int, fg int, bg int, attr int) {
	if y < s.paint_y || y >= s.paint_end || x < 0 || x > s.width { return }
	mut r := rune(0)
	if text.len == 1 {
		r = rune(text[0])
	} else if text.len > 1 {
		r, _ = utf8.decode_rune_at(text, 0)
	}
	if r < 32 || (r >= 0x7f && r < 0xa0) { return }
	actual := if s.ascii && r > 126 { display_rune(ascii_glyph(r)) } else { text }
	width := if s.ascii { 1 } else { columns }
	if width == 0 {
		if x > 0 && s.clip.contains(x - 1, y) {
			mut at := y * s.width + x - 1
			if s.cells[at].continuation && x > 1 { at-- }
			if s.clip.contains(at % s.width, y) {
				s.cells[at].glyph += actual
				s.mark(at % s.width, x, y)
			}
		}
		return
	}
	if x >= s.width || !s.clip.contains(x, y) { return }
	if width == 2 && (!s.clip.contains(x + 1, y) || x + 1 >= s.width) { return }
	at := y * s.width + x
	// Overwriting either half of a wide character clears its partner.
	mut first, mut end := x, x + width
	if s.cells[at].continuation && x > 0 {
		s.cells[at - 1] = Cell{fg: fg, bg: bg}
		first = x - 1
	}
	if x + width < s.width && s.cells[at + width].continuation {
		s.cells[at + width] = Cell{fg: fg, bg: bg}
		end++
	}
	s.cells[at] = Cell{actual, fg, bg, attr, false}
	if width == 2 { s.cells[at + 1] = Cell{'', fg, bg, attr, true} }
	s.mark(first, end, y)
}

pub fn (mut s Screen) text(x int, y int, text string, fg int, bg int, attr int) {
	if y < s.paint_y || y >= s.paint_end || !s.clip.contains(s.clip.x, y)
		|| x > s.clip.x + s.clip.w { return }
	right := s.clip.x + s.clip.w
	mut at := x
	if is_ascii(text) {
		for i in 0 .. text.len {
			ch := text[i]
			if ch == `\n` || ch == `\r` || at >= right { break }
			if ch >= 32 && ch < 127 {
				s.put_grapheme(at, y, printable_ascii[int(ch) - 32], 1, fg, bg, attr)
				at++
			} else if s.ascii {
				at++
			}
		}
		return
	}
	if s.ascii {
		mut i := 0
		for i < text.len && at < right {
			r, n := utf8.decode_rune_at(text, i)
			if r == `\n` || r == `\r` { break }
			s.put(at, y, r, fg, bg, attr)
			at++
			i += max(1, n)
		}
		return
	}
	for cluster in text.graphemes() {
		if cluster[0] == `\n` || cluster[0] == `\r` || at > right { break }
		width := grapheme_width(cluster)
		s.put_grapheme(at, y, cluster, width, fg, bg, attr)
		at += width
	}
}

// Align inside a clipped content row, using the same cell widths as text().
fn (mut s Screen) aligned_text(x int, y int, width int, text string, align TextAlign, fg int, bg int, attr int) {
	if width <= 0 { return }
	line := text.all_before('\n').all_before('\r')
	columns := if align == .left { 0 } else if s.ascii { line.runes().len } else { text_width(line) }
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
	area := r.intersection(s.clip).intersection(Rect{0, 0, s.width, s.height})
	if area.w == 0 || !s.paints(area) || glyph < 32 || (glyph >= 127 && glyph < 160) { return }
	text := display_rune(if s.ascii { ascii_glyph(glyph) } else { glyph })
	width := if s.ascii { 1 } else { rune_width(glyph) }
	start, end := area.x, area.x + area.w
	for y in max(s.paint_y, area.y) .. min(s.paint_end, area.y + area.h) {
		if width != 1 {
			for x in start .. end { s.put_grapheme(x, y, text, width, fg, bg, 0) }
			continue
		}
		base := y * s.width
		mut first, mut last := start, end
		if start > 0 && s.cells[base + start].continuation {
			first--
			s.cells[base + first] = Cell{fg: fg, bg: bg}
		}
		if end < s.width && s.cells[base + end].continuation {
			s.cells[base + end] = Cell{fg: fg, bg: bg}
			last++
		}
		cell := Cell{glyph: text, fg: fg, bg: bg}
		for x in start .. end { s.cells[base + x] = cell }
		s.mark(first, last, y)
	}
}

pub fn (mut s Screen) frame(r Rect, double bool, fg int, bg int) {
	if r.w < 2 || r.h < 2 { return }
	g := if double { [`╔`, `╗`, `╚`, `╝`, `═`, `║`]! } else { [`┌`, `┐`, `└`, `┘`, `─`, `│`]! }
	s.fill(Rect{r.x + 1, r.y, r.w - 2, 1}, g[4], fg, bg)
	s.fill(Rect{r.x + 1, r.y + r.h - 1, r.w - 2, 1}, g[4], fg, bg)
	s.fill(Rect{r.x, r.y + 1, 1, r.h - 2}, g[5], fg, bg)
	s.fill(Rect{r.x + r.w - 1, r.y + 1, 1, r.h - 2}, g[5], fg, bg)
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

// diff returns the incremental ANSI update since the previous presentation.
pub fn (mut s Screen) diff() string { return s.present(RenderOptions{}) }

fn (mut s Screen) present(options RenderOptions) string {
	if options.backend == .memory { return '' }
	conservative := options.backend == .conservative
	if s.ansi.conservative != conservative || s.ansi.basic_colors != options.slow_terminal {
		s.ansi = render.Ansi{conservative: conservative, basic_colors: options.slow_terminal}
	}
	sequence := s.ansi.present(render.Frame{
		cells: s.cells
		width: s.width
		height: s.height
		damage: s.damage
		first: s.damage_first
		end: s.damage_end
		cursor: render.Cursor{s.cursor_x, s.cursor_y, s.cursor_shape == .block}
	})
	for y in s.damage_first .. s.damage_end { s.damage[y] = render.Span{} }
	s.damage_first, s.damage_end = s.height, 0
	return sequence
}

fn (mut s Screen) mark(x int, end int, y int) {
	old := s.damage[y]
	s.damage[y] = render.Span{if old.end > 0 { min(x, old.start) } else { x }, max(end, old.end)}
	s.damage_first, s.damage_end = min(y, s.damage_first), max(y + 1, s.damage_end)
}

pub fn (s &Screen) snapshot() string { return render.snapshot(s.cells, s.width) }

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
