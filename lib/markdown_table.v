module vtk

// Table cells retain their original byte spans. Borders and padding are display
// glyphs only, so selecting or copying a table still returns its Markdown source.
struct MarkdownCell {
	text string
	at   int
	end  int
}

struct MarkdownTableRow {
	cells []MarkdownCell
	at    int
	end   int
	line  int
}

struct MarkdownTable {
	rows       []MarkdownTableRow
	alignments []TextAlign
	separator  MarkdownTableRow
	lines      int
}

struct MarkdownColumnWidth {
	index int
	width int
}

// Backticks and escaped pipes inside cells must not become column separators.
fn markdown_cells(line string, offset int) []MarkdownCell {
	mut spans := []int{cap: 8}
	mut i := 0
	for i < line.len {
		if line[i] == `\\` && i + 1 < line.len {
			i += 2
			continue
		}
		if line[i] == 96 {
			_, end := markdown_code_span(line, i)
			if end > i {
				i = end
				continue
			}
		}
		if line[i] == `|` { spans << i }
		i++
	}
	if spans.len == 0 { return []MarkdownCell{} }
	mut cells := []MarkdownCell{}
	mut start := 0
	for end in spans {
		cells << markdown_cell(line, start, end, offset)
		start = end + 1
	}
	cells << markdown_cell(line, start, line.len, offset)
	if line[..spans[0]].trim_space() == '' { cells.delete(0) }
	if line[spans.last() + 1..].trim_space() == '' && cells.len > 0 { cells.delete_last() }
	return cells
}

fn markdown_cell(line string, from int, to int, offset int) MarkdownCell {
	mut a, mut b := from, to
	for a < b && line[a] in [u8(` `), u8(`\t`)] { a++ }
	for b > a && line[b - 1] in [u8(` `), u8(`\t`), u8(`\r`)] { b-- }
	return MarkdownCell{ text: line[a..b], at: offset + a, end: offset + b }
}

fn markdown_table_alignments(line string) ?[]TextAlign {
	cells := markdown_cells(line, 0)
	if cells.len == 0 { return none }
	mut alignments := []TextAlign{}
	for cell in cells {
		core := cell.text.trim(':')
		if core.len < 3 || !core.bytes().all(it == `-`) { return none }
		alignments << if cell.text.starts_with(':') && cell.text.ends_with(':') {
			TextAlign.center
		} else if cell.text.ends_with(':') {
			TextAlign.right
		} else {
			TextAlign.left
		}
	}
	return alignments
}

fn parse_markdown_table(lines []string, first int, offset int) ?MarkdownTable {
	if first + 1 >= lines.len { return none }
	alignments := markdown_table_alignments(lines[first + 1]) or { return none }
	header := markdown_cells(lines[first], offset)
	if header.len != alignments.len || header.len == 0 { return none }
	mut rows := [MarkdownTableRow{ cells: header, at: offset, end: offset + lines[first].len, line: first }]
	divider := MarkdownTableRow{
		at:   offset + lines[first].len + 1
		end:  offset + lines[first].len + 1 + lines[first + 1].len
		line: first + 1
	}
	mut at := divider.end + 1
	mut cursor := first + 2
	for cursor < lines.len {
		line := lines[cursor]
		if line.starts_with('    ') || line.starts_with('\t') || line.trim_space().starts_with('```')
			|| line.trim_space().starts_with('~~~') {
			break
		}
		if _ := markdown_table_alignments(line) { break }
		mut cells := markdown_cells(line, at)
		if cells.len == 0 { break }
		if cells.len > header.len { cells = cells[..header.len] }
		for cells.len < header.len {
			cells << MarkdownCell{ at: at + line.len, end: at + line.len }
		}
		rows << MarkdownTableRow{ cells: cells, at: at, end: at + line.len, line: cursor }
		at += line.len + 1
		cursor++
	}
	return MarkdownTable{ rows: rows, alignments: alignments, separator: divider, lines: cursor - first }
}

fn markdown_glyph_width(glyphs []Glyph) int {
	mut width := 0
	for g in glyphs { width += if g.r == `\t` { 4 } else { glyph_width(g) } }
	return width
}

fn markdown_wrap_cell(glyphs []Glyph, width int) [][]Glyph {
	mut lines := [][]Glyph{}
	mut line := []Glyph{}
	mut column := 0
	for g in glyphs {
		gw := if g.r == `\t` { 4 } else { glyph_width(g) }
		if column > 0 && column + gw > width {
			lines << line
			line = []
			column = 0
		}
		if g.r == `\t` {
			for _ in 0 .. min(4, width) { line << Glyph{ ...g, r: ` ` } }
			column += min(4, width)
		} else {
			line << g
			column += gw
		}
	}
	lines << line
	return lines
}

fn markdown_table_border(widths []int, left rune, middle rune, right rune, source MarkdownTableRow) TextRow {
	mut glyphs := [Glyph{ r: left, at: source.at, end: source.at, element: .table_border }]
	for i, width in widths {
		for _ in 0 .. width + 2 { glyphs << Glyph{ r: `─`, at: source.at, end: source.at, element: .table_border } }
		glyphs << Glyph{ r: if i + 1 == widths.len { right } else { middle }, at: source.at, end: source.at, element: .table_border }
	}
	return TextRow{ start: source.at, end: source.end, line: source.line, glyphs: glyphs, no_wrap: true }
}

fn (c &Ctl) render_markdown_table(table MarkdownTable) []TextRow {
	count := table.alignments.len
	mut natural := []int{len: count, init: 2}
	mut content := [][][]Glyph{}
	for row in table.rows {
		mut cells := [][]Glyph{}
		for i, cell in row.cells {
			glyphs := inline_markdown(cell.text, cell.at, 0)
			natural[i] = max(natural[i], markdown_glyph_width(glyphs))
			cells << glyphs
		}
		content << cells
	}
	mut viewport := max(1, c.w - c.editor_gutter() - int(c.scrollbar))
	if c.md.column_width > 0 { viewport = min(viewport, c.md.column_width) }
	mut widths := natural.clone()
	if !c.md.no_wrap {
		// Preserve naturally short columns and share space among wrapping ones.
		mut order := []MarkdownColumnWidth{}
		for i, width in natural { order << MarkdownColumnWidth{ index: i, width: width } }
		order.sort(a.width < b.width)
		mut remaining := max(count * 2, viewport - count * 3 - 1)
		for i, column in order {
			widths[column.index] = min(column.width, max(2, remaining / (count - i)))
			remaining -= widths[column.index]
		}
	}
	mut result := [markdown_table_border(widths, `┌`, `┬`, `┐`, table.rows[0])]
	for row_index, row in table.rows {
		mut wrapped := [][][]Glyph{}
		mut height := 1
		for i, glyphs in content[row_index] {
			parts := markdown_wrap_cell(glyphs, widths[i])
			height = max(height, parts.len)
			wrapped << parts
		}
		for visual_line in 0 .. height {
			mut glyphs := [Glyph{ r: `│`, at: row.at, end: row.at, element: .table_border }]
			for i, parts in wrapped {
				cell := row.cells[i]
				part := if visual_line < parts.len { parts[visual_line] } else { []Glyph{} }
				space := max(0, widths[i] - markdown_glyph_width(part))
				before := match table.alignments[i] {
					.right { space }
					.center { space / 2 }
					else { 0 }
				}
				for _ in 0 .. before + 1 { glyphs << Glyph{ r: ` `, at: cell.at, end: cell.at } }
				glyphs << part
				for _ in 0 .. space - before + 1 {
					glyphs << Glyph{ r: ` `, at: cell.end, end: cell.end }
				}
				glyphs << Glyph{ r: `│`, at: cell.end, end: cell.end, element: .table_border }
			}
			result << TextRow{ start: row.at, end: row.end, line: row.line, glyphs: glyphs, no_wrap: true, element: if row_index == 0 { .table_header } else { .text } }
		}
		if row_index == 0 {
			result << markdown_table_border(widths, `├`, `┼`, `┤`, table.separator)
		}
	}
	result << markdown_table_border(widths, `└`, `┴`, `┘`, table.rows.last())
	return result
}

// Return the closing delimiter's byte range, matching the opening run exactly.
// Unclosed backticks remain visible while an agent is streaming a response.
fn markdown_code_span(text string, at int) (int, int) {
	mut opening := at
	for opening < text.len && text[opening] == 96 { opening++ }
	mut cursor := opening
	for cursor < text.len {
		if text[cursor] != 96 {
			cursor++
			continue
		}
		start := cursor
		for cursor < text.len && text[cursor] == 96 { cursor++ }
		if cursor - start == opening - at { return start, cursor }
	}
	return -1, -1
}
