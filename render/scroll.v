module render

// A full-width vertical scroll can be reproduced with VT margins. Require
// several changed rows and exact copies of every moved cell. The exposed row
// is transmitted in full, independent of the terminal's erase color.
fn (mut p Ansi) scroll(frame Frame) int {
	width := frame.width
	if frame.end - frame.first < 4 || width < 16 { return -1 }
	mut best, mut top, mut bottom, mut direction := 0, 0, 0, 0
	for shift in [-1, 1] {
		mut start, mut changed := frame.first, 0
		for y in frame.first .. frame.end {
			source := y + shift
			if source < frame.first || source >= frame.end || frame.damage[y].end == 0
				|| !row_matches(frame.cells, p.front, width, y, source) {
				start, changed = y + 1, 0
				continue
			}
			if !row_matches(frame.cells, p.front, width, y, y) { changed++ }
			if changed >= 3 && changed > best {
				a, b := start - int(shift < 0), y + int(shift > 0)
				if frame.damage[a].end == 0 || frame.damage[b].end == 0 { continue }
				best, top, bottom, direction = changed, a, b, shift
			}
		}
	}
	if best == 0 { return -1 }
	p.out.write_string('\x1b[${top + 1};${bottom + 1}r')
	p.out.write_string(if direction > 0 { '\x1b[S' } else { '\x1b[T' })
	p.out.write_string('\x1b[r')
	for y in top .. bottom + 1 {
		source := y + direction
		if source < top || source > bottom { continue }
		offset := y * width
		// The moved rows already match the frame, so there is no overlap.
		copy(mut p.front[offset..offset + width], frame.cells[offset..offset + width])
	}
	return if direction > 0 { bottom } else { top }
}

fn row_matches(cells []Cell, front []Cell, width int, y int, source int) bool {
	a, b := y * width, source * width
	for x in 0 .. width {
		if cells[a + x] != front[b + x] { return false }
	}
	return true
}
