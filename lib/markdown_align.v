module vtk

import math { max }

// Paragraph alignment mirrors htk's Pandoc fenced divs, so the same sources
// render here and in HTML-aware Markdown readers.
pub enum MarkdownAlign {
	none
	left
	center
	right
	justify
}

const markdown_align_indent = 2

fn markdown_align_fence(align MarkdownAlign) string {
	return match align {
		.left { '::: {.htk-align-left style="text-align:left"}' }
		.center { '::: {.htk-align-center style="text-align:center"}' }
		.right { '::: {.htk-align-right style="text-align:right"}' }
		.justify { '::: {.htk-align-justify style="text-align:justify"}' }
		.none { '' }
	}
}

// Accept the class alone or the style attribute that htk writes for HTML.
fn markdown_align_open(line string) MarkdownAlign {
	trim := line.trim_space()
	if !trim.starts_with('::: {') || !trim.ends_with('}') { return .none }
	at := trim.index('text-align:') or {
		return match trim {
			'::: {.htk-align-left}' { .left }
			'::: {.htk-align-center}' { .center }
			'::: {.htk-align-right}' { .right }
			'::: {.htk-align-justify}' { .justify }
			else { .none }
		}
	}
	value := trim[at + 'text-align:'.len..].trim_left('"\'')
	mut end := 0
	for end < value.len && value[end] !in [u8(`"`), u8(`'`), u8(`}`), u8(` `)] {
		end++
	}
	return match value[..end] {
		'left' { .left }
		'center' { .center }
		'right' { .right }
		'justify' { .justify }
		else { .none }
	}
}

fn markdown_line_end(text string, at int) int {
	mut i := at
	for i < text.len && text[i] != `\n` {
		i++
	}
	return i
}

fn markdown_heading(trim string) bool {
	mut level := 0
	for level < trim.len && trim[level] == `#` {
		level++
	}
	return level >= 1 && level <= 6 && level < trim.len && trim[level] == ` `
}

// Tables and fenced code stay verbatim: alignment rewrites whole paragraphs.
fn markdown_table_start(text string, at int, line_end int) bool {
	if line_end >= text.len { return false }
	header := markdown_cells(text[at..line_end], 0)
	if header.len == 0 { return false }
	next_end := markdown_line_end(text, line_end + 1)
	alignments := markdown_table_alignments(text[line_end + 1..next_end]) or { return false }
	return header.len == alignments.len
}

struct MarkdownParagraph {
	start      int
	end        int
	body_start int
	body_end   int
	align      MarkdownAlign
	blank      bool
	verbatim   bool
}

fn markdown_paragraph(text string, at int) MarkdownParagraph {
	stop := markdown_line_end(text, at)
	line := text[at..stop]
	next := if stop < text.len { stop + 1 } else { text.len }
	trim := line.trim_space()
	if trim == '' { return MarkdownParagraph{ start: at, end: next, blank: true } }
	align := markdown_align_open(line)
	if align != .none { return markdown_align_block(text, at, next, align) }
	if trim.starts_with('```') || trim.starts_with('~~~') {
		marker := trim[..3]
		mut p := next
		for p < text.len {
			end := markdown_line_end(text, p)
			if text[p..end].trim_space().starts_with(marker) {
				return MarkdownParagraph{
					start:    at
					end:      if end < text.len { end + 1 } else { text.len }
					verbatim: true
				}
			}
			p = if end < text.len { end + 1 } else { text.len }
		}
		return MarkdownParagraph{ start: at, end: text.len, verbatim: true }
	}
	if line.starts_with('\t') || line.starts_with('    ') {
		return MarkdownParagraph{ start: at, end: next, verbatim: true }
	}
	if markdown_heading(trim) {
		return MarkdownParagraph{ start: at, end: next, body_start: at, body_end: stop }
	}
	if markdown_table_start(text, at, stop) {
		mut p := next
		for p < text.len {
			end := markdown_line_end(text, p)
			if text[p..end].trim_space() == '' { break }
			p = if end < text.len { end + 1 } else { text.len }
		}
		return MarkdownParagraph{ start: at, end: p, verbatim: true }
	}
	mut p := next
	for p < text.len {
		end := markdown_line_end(text, p)
		line_next := text[p..end]
		trim_next := line_next.trim_space()
		if trim_next == '' || markdown_align_open(line_next) != .none || trim_next == ':::'
			|| markdown_heading(trim_next) || trim_next.starts_with('```')
			|| trim_next.starts_with('~~~') || markdown_table_start(text, p, end) {
			break
		}
		p = if end < text.len { end + 1 } else { text.len }
	}
	return MarkdownParagraph{ start: at, end: p, body_start: at, body_end: p }
}

// Unclosed divs stay visible source text, as in htk.
fn markdown_align_closes(text string, at int) bool {
	mut depth := 1
	mut p := at
	for p < text.len {
		end := markdown_line_end(text, p)
		line := text[p..end]
		if markdown_align_open(line) != .none {
			depth++
		} else if line.trim_space() == ':::' {
			depth--
			if depth == 0 { return true }
		}
		p = if end < text.len { end + 1 } else { text.len }
	}
	return false
}

fn markdown_align_block(text string, at int, next int, align MarkdownAlign) MarkdownParagraph {
	mut depth := 1
	mut p := next
	for p < text.len {
		end := markdown_line_end(text, p)
		line := text[p..end]
		if markdown_align_open(line) != .none {
			depth++
		} else if line.trim_space() == ':::' {
			depth--
			if depth == 0 {
				return MarkdownParagraph{
					start:      at
					end:        if end < text.len { end + 1 } else { text.len }
					body_start: next
					body_end:   p
					align:      align
				}
			}
		}
		p = if end < text.len { end + 1 } else { text.len }
	}
	// An unclosed div stays visible source text, as in htk.
	return MarkdownParagraph{ start: at, end: next, verbatim: true }
}

// Blank lines are only filled when the caret, not a selection, reaches them.
fn markdown_align_eligible(p MarkdownParagraph, selected bool) bool {
	return !p.verbatim && (!p.blank || !selected)
}

fn markdown_align_hit(p MarkdownParagraph, start int, end int, selected bool, len int) bool {
	if selected { return p.end > start && p.start < end }
	return start >= p.start && (start < p.end || (start == len && p.end == len))
}

// markdown_align wraps every selected paragraph in the htk fenced div, replacing
// an existing alignment fence. Code blocks and tables are never rewritten.
pub fn (mut c Ctl) markdown_align(align MarkdownAlign) bool {
	if c.kind != .markdown || c.readonly || align == .none { return false }
	start, end := c.selection()
	selected := start != end
	mut a, mut b := -1, -1
	mut at := 0
	for at < c.text.len {
		p := markdown_paragraph(c.text, at)
		if markdown_align_eligible(p, selected) && markdown_align_hit(p, start, end, selected, c.text.len) {
			if a < 0 { a = p.start }
			b = p.end
		}
		at = p.end
	}
	if a < 0 { return false }
	fence := markdown_align_fence(align)
	mut out := ''
	mut mapped_cursor, mut mapped_anchor := c.cursor, c.anchor
	at = a
	for at < b {
		p := markdown_paragraph(c.text, at)
		wrap := markdown_align_eligible(p, selected) && (markdown_align_hit(p, start, end, selected, c.text.len)
			|| (!selected && p.blank))
		base := out.len
		if wrap {
			content := c.text[p.body_start..p.body_end]
			content_end := if content.ends_with('\n') { content.len - 1 } else { content.len }
			out += fence + '\n'
			body := out.len
			out += content
			if content_end == content.len { out += '\n' }
			out += ':::\n'
			if c.cursor >= p.start && c.cursor <= p.end {
				mapped_cursor = body + clamp(c.cursor - p.body_start, 0, content_end)
			}
			if c.anchor >= p.start && c.anchor <= p.end {
				mapped_anchor = body + clamp(c.anchor - p.body_start, 0, content_end)
			}
		} else {
			out += c.text[p.start..p.end]
			if c.cursor >= p.start && c.cursor <= p.end {
				mapped_cursor = base + c.cursor - p.start
			}
			if c.anchor >= p.start && c.anchor <= p.end {
				mapped_anchor = base + c.anchor - p.start
			}
		}
		at = p.end
	}
	delta := out.len - (b - a)
	if c.cursor > b { mapped_cursor = c.cursor + delta }
	if c.anchor > b { mapped_anchor = c.anchor + delta }
	changed := c.replace_range(a, b, out)
	c.cursor = clamp(mapped_cursor, 0, c.text.len)
	c.anchor = if c.anchor < 0 { -1 } else { clamp(mapped_anchor, 0, c.text.len) }
	c.scroll_hold = false
	return changed
}

// markdown_align_at reports the fence that contains a source offset.
pub fn (c &Ctl) markdown_align_at(at int) MarkdownAlign {
	mut p := 0
	for p < c.text.len {
		paragraph := markdown_paragraph(c.text, p)
		if at >= paragraph.start
			&& (at < paragraph.end || (at == c.text.len && paragraph.end == c.text.len)) {
			return paragraph.align
		}
		p = paragraph.end
	}
	return .none
}

// Aligned rows wrap inside the page minus their indent and then shift or
// stretch: center and right add leading columns, justify spreads word gaps.
fn align_rows(mut rows []TextRow, width int, tab_width int) {
	budget := max(1, width - markdown_align_indent)
	for i in 0 .. rows.len {
		if rows[i].align == .none || rows[i].glyphs.len == 0 { continue }
		pad := max(0, budget - markdown_row_width(rows[i], tab_width))
		rows[i].pad = markdown_align_indent
		match rows[i].align {
			.center { rows[i].pad += pad / 2 }
			.right { rows[i].pad += pad }
			.justify {
				if !markdown_align_final(rows, i) {
					rows[i].gapw = markdown_align_gaps(rows[i], pad)
				}
			}
			else {}
		}
	}
}

fn markdown_row_width(row TextRow, tab_width int) int {
	mut col := 0
	for g in row.glyphs {
		col += if g.r == `\t` { tab_width - col % tab_width } else { glyph_width(g) }
	}
	return col
}

// Only the last display row of a paragraph keeps ragged right edges.
fn markdown_align_final(rows []TextRow, i int) bool {
	if i + 1 >= rows.len { return true }
	row, next := rows[i], rows[i + 1]
	if next.align != row.align { return true }
	if next.line == row.line { return false }
	return next.glyphs.len == 0 || next.element == .heading || next.code
}

fn markdown_align_gaps(row TextRow, pad int) []int {
	mut gaps := []int{cap: 8}
	for i, g in row.glyphs {
		if !wrap_space(g.r) || i == 0 || wrap_space(row.glyphs[i - 1].r) { continue }
		mut next := i + 1
		for next < row.glyphs.len && wrap_space(row.glyphs[next].r) {
			next++
		}
		if next < row.glyphs.len { gaps << i }
	}
	if gaps.len == 0 { return []int{} }
	mut widths := []int{len: row.glyphs.len}
	for i, at in gaps {
		widths[at] = pad / gaps.len + int(i < pad % gaps.len)
	}
	return widths
}
