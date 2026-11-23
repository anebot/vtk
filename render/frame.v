module render

// Cell contains a complete terminal grapheme or the second cell of a wide glyph.
pub struct Cell {
pub mut:
	glyph        string = ' '
	fg           int    = 7
	bg           int
	attr         int
	continuation bool
}

// Span is a half-open interval of columns within a damaged row.
pub struct Span {
pub:
	start int
	end   int
}

pub struct Cursor {
pub:
	x     int = -1
	y     int = -1
	block bool
}

pub struct Frame {
pub:
	cells  []Cell
	width  int
	height int
	damage []Span
	first  int
	end    int
	cursor Cursor
}
