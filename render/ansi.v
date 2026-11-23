module render

import strings

pub struct Ansi {
pub:
	conservative bool
	basic_colors bool
pub mut:
	front []Cell
mut:
	width        int
	height       int
	out          strings.Builder
	pen          Cell = Cell{ fg: -1, bg: -1, attr: -1 }
	cursor       Cursor
	cursor_known bool
}

pub fn (mut p Ansi) reset() {
	p.front = []
	p.pen = Cell{ fg: -1, bg: -1, attr: -1 }
	p.cursor_known = false
}

pub fn (mut p Ansi) present(frame Frame) string {
	if frame.cells.len == 0 { return '' }
	full := p.width != frame.width || p.height != frame.height || p.front.len != frame.cells.len
	p.width, p.height = frame.width, frame.height
	if full { p.front = []Cell{len: frame.cells.len} }
	mut exposed := -1
	if !full && !p.conservative {
		exposed = p.scroll(frame)
	}
	first, end := if full { 0 } else { frame.first }, if full { frame.height } else { frame.end }
	for y in first .. end {
		span := if full || y == exposed { Span{0, frame.width} } else { frame.damage[y] }
		mut next_x := -1
		for x in span.start .. span.end {
			i := y * frame.width + x
			cell := frame.cells[i]
			if !full && y != exposed && cell == p.front[i] { continue }
			p.front[i] = cell
			if cell.continuation { continue }
			if next_x != x && !p.bridge(frame, y, next_x, x, cell) {
				p.move_to(x, y)
			}
			p.select_style(cell)
			p.out.write_string(cell.glyph)
			next_x = x + 1 + int(x + 1 < frame.width && frame.cells[i + 1].continuation)
		}
	}
	p.present_cursor(frame.cursor)
	return if p.out.len == 0 { '' } else { p.out.str() }
}

fn (mut p Ansi) move_to(x int, y int) {
	p.out.write_string('\x1b[${y + 1};${x + 1}H')
}

fn (mut p Ansi) bridge(frame Frame, row int, from int, to int, cell Cell) bool {
	if p.conservative || from < 0 || to <= from || to - from > 4
		|| !same_style(p.output_cell(cell), p.pen) {
		return false
	}
	base := row * frame.width
	for x in from .. to {
		other := frame.cells[base + x]
		if other.continuation || other.glyph.len != 1 || !same_style(p.output_cell(other), p.pen) {
			return false
		}
	}
	for x in from .. to { p.out.write_string(frame.cells[base + x].glyph) }
	return true
}

fn same_style(a Cell, b Cell) bool {
	return a.fg == b.fg && a.bg == b.bg && a.attr == b.attr
}

fn (mut p Ansi) present_cursor(cursor Cursor) {
	shown := cursor.x >= 0 && cursor.y >= 0 && cursor.x < p.width && cursor.y < p.height
	was_shown := p.cursor.x >= 0 && p.cursor.y >= 0
	if shown {
		if !p.cursor_known || p.out.len > 0 || cursor.x != p.cursor.x || cursor.y != p.cursor.y {
			p.move_to(cursor.x, cursor.y)
		}
		if !p.conservative && (!p.cursor_known || !was_shown || cursor.block != p.cursor.block) {
			p.out.write_string(if cursor.block { '\x1b[2 q' } else { '\x1b[6 q' })
		}
		if !p.cursor_known || !was_shown { p.out.write_string('\x1b[?25h') }
		p.cursor = cursor
	} else {
		if !p.cursor_known || was_shown { p.out.write_string('\x1b[?25l') }
		p.cursor = Cursor{}
	}
	p.cursor_known = true
}

// Control sequences are generated here. Frame graphemes have already been
// filtered by Screen, including any cells coming from an embedded terminal.
fn (p &Ansi) output_cell(source Cell) Cell {
	if !p.conservative && !p.basic_colors { return source }
	return Cell{ ...source, fg: basic_color(source.fg), bg: basic_color(source.bg) }
}

fn (mut p Ansi) select_style(source Cell) {
	cell := p.output_cell(source)
	if same_style(cell, p.pen) { return }
	if p.conservative || p.pen.attr < 0 || p.pen.attr & ~cell.attr != 0 {
		p.out.write_string('\x1b[0;${ansi_color(cell.fg, false)};${ansi_color(cell.bg, true)}')
		write_attributes(mut p.out, cell.attr)
	} else {
		p.out.write_string('\x1b[')
		mut separator := ''
		if cell.fg != p.pen.fg {
			p.out.write_string(ansi_color(cell.fg, false))
			separator = ';'
		}
		if cell.bg != p.pen.bg {
			p.out.write_string(separator + ansi_color(cell.bg, true))
			separator = ';'
		}
		attr := cell.attr & ~p.pen.attr
		if attr != 0 {
			if separator == '' { p.out.write_string(ansi_color(cell.fg, false)) }
			write_attributes(mut p.out, attr)
		}
	}
	p.out.write_u8(`m`)
	p.pen = cell
}

fn write_attributes(mut out strings.Builder, attr int) {
	if attr & 1 != 0 { out.write_string(';1') }
	if attr & 2 != 0 { out.write_string(';4') }
	if attr & 4 != 0 { out.write_string(';3') }
	if attr & 8 != 0 { out.write_string(';7') }
}

fn ansi_color(color int, bg bool) string {
	base := if bg { 48 } else { 38 }
	if color & 0x1000000 != 0 {
		return '${base};2;${(color >> 16) & 255};${(color >> 8) & 255};${color & 255}'
	}
	if color & 0x2000000 != 0 { return '${base};5;${color & 255}' }
	return '${(if bg { 40 } else { 30 }) + (color & 7) + (if color & 8 != 0 { 60 } else { 0 })}'
}
