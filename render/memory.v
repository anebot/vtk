module render

import strings

// snapshot presents the frame in memory, without any terminal state or I/O.
pub fn snapshot(cells []Cell, width int) string {
	if width <= 0 { return '' }
	mut out := strings.new_builder(cells.len)
	for i, cell in cells {
		if i > 0 && i % width == 0 { out.write_u8(`\n`) }
		out.write_string(cell.glyph)
	}
	return out.str()
}
