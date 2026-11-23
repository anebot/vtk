module vtk

import encoding.utf8

pub enum MarkdownMode {
	edit
	source
	read
	source_read
}

pub enum MarkdownLayout {
	continuous
	pages
	section
}

pub struct Markdown {
pub mut:
	mode             MarkdownMode
	layout           MarkdownLayout
	no_wrap          bool
	hide_status      bool
	ruler_top        bool
	ruler_left       bool
	tab_width        int = 4
	page_lines       int = 40
	column_width     int
	section_at       int
	task_interactive bool = true
	linkfn           ?fn (mut Ctl, string, mut App)
	styles           MarkdownStyles
mut:
	last_task  int = -1
	last_click i64
}

pub fn markdown(text string) &Ctl {
	return &Ctl{ kind: .markdown, text: text, expand: true, focusable: true }
}

pub fn (mut c Ctl) markdown_mode(mode MarkdownMode) {
	c.md.mode = mode
	c.readonly = mode in [.read, .source_read]
	c.invalidate()
}

// Parsing and hit testing share byte positions. Fences retain a display row
// even when their syntax is hidden, so source navigation stays stable.
fn (c &Ctl) markdown_rows() []TextRow {
	mut rows := []TextRow{}
	mut offset := 0
	mut fence := ''
	mut fence_len := 0
	mut highlighter := code_highlighter('')
	section_a, section_b := c.markdown_section_range()
	source := c.md.mode in [.source, .source_read]
	lines := c.text.split('\n')
	mut line_no := 0
	for line_no < lines.len {
		line := lines[line_no]
		mut row := TextRow{ start: offset, end: offset + line.len, line: line_no }
		trim := line.trim_left(' ')
		indent := line.len - trim.len
		mut fence_run := 0
		if trim.len > 0 && trim[0] in [u8(96), u8(`~`)] {
			for fence_run < trim.len && trim[fence_run] == trim[0] { fence_run++ }
		}
		is_fence := indent <= 3 && fence_run >= 3 && (fence == '' || (trim[0].ascii_str() == fence && fence_run >= fence_len && trim[fence_run..].trim_space() == ''))
		was_code := fence != ''
		if is_fence {
			if fence == '' {
				fence = trim[0].ascii_str()
				fence_len = fence_run
				highlighter = code_highlighter(trim[fence_run..])
			} else {
				fence = ''
				fence_len = 0
				highlighter = code_highlighter('')
			}
		}
		row.code = was_code || line.starts_with('\t') || line.starts_with('    ')
		if row.code && !is_fence { row.element = .code_block }
		if !source && !row.code && !is_fence {
			if table := parse_markdown_table(lines, line_no, offset) {
				if offset >= section_a && offset <= section_b {
					rows << c.render_markdown_table(table)
				}
				for consumed in lines[line_no..line_no + table.lines] { offset += consumed.len + 1 }
				line_no += table.lines
				continue
			}
		}
		if source || (row.code && !is_fence) {
			row.glyphs = line_glyphs(line, offset, 0, -1)
		} else if !is_fence {
			mut skip := 0
			if trim.starts_with('#') {
				mut n := 0
				for n < trim.len && trim[n] == `#` { n++ }
				if n <= 6 && n < trim.len && trim[n] == ` ` {
					skip = indent + n + 1
					row.element = .heading
				}
			}
			if trim.starts_with('> ') {
				row.element = .quote
				skip = indent + 2
				row.glyphs << Glyph{ r: `│`, at: offset, end: offset + skip }
			}
			task := task_offset(line)
			if task >= 0 {
				row.glyphs << Glyph{ r: `[`, at: offset + task - 1, end: offset + task, task: offset + task }
				row.glyphs << Glyph{ r: rune(line[task]), at: offset + task, end: offset + task + 1, task: offset + task }
				row.glyphs << Glyph{ r: `]`, at: offset + task + 1, end: offset + task + 2, task: offset + task }
				row.glyphs << Glyph{ r: ` `, at: offset + task + 2, end: offset + task + 3 }
				skip = min(line.len, task + 3)
			} else if trim.starts_with('- ') || trim.starts_with('* ') || trim.starts_with('+ ') {
				row.glyphs << Glyph{ r: `•`, at: offset + indent, end: offset + indent + 1 }
				row.glyphs << Glyph{ r: ` `, at: offset + indent + 1, end: offset + indent + 2 }
				skip = indent + 2
			}
			if trim in ['---', '***', '___'] {
				row.glyphs = line_glyphs('────────────────', offset, 0, -1)
			} else {
				row.glyphs << inline_markdown(line[skip..], offset + skip, 0)
			}
		}
		if source && c.md.task_interactive {
			task := if !was_code && !is_fence && !row.code { task_offset(line) } else { -1 }
			if task >= 0 {
				for i, g in row.glyphs {
					if g.at >= offset + task - 1 && g.at <= offset + task + 1 {
						row.glyphs[i] = Glyph{ ...g, task: offset + task }
					}
				}
			}
		}
		if row.code && !is_fence {
			highlighter.highlight(line, mut row)
		} else if !is_fence {
			highlighter = code_highlighter('')
		}
		if offset >= section_a && offset <= section_b { rows << row }
		if c.md.layout == .pages && (line_no + 1) % max(1, c.md.page_lines) == 0 {
			rows << TextRow{ start: offset + line.len, end: offset + line.len, line: line_no, glyphs: line_glyphs('──── Page ${(line_no + 1) / max(1, c.md.page_lines) + 1} ────', offset + line.len, 0, -1) }
		}
		offset += line.len + 1
		line_no++
	}
	if rows.len == 0 { rows << TextRow{ start: section_a, end: section_a } }
	return rows
}

fn (c &Ctl) markdown_section_range() (int, int) {
	if c.md.layout != .section { return 0, c.text.len }
	mut start, mut end, mut depth, mut at := 0, c.text.len, 0, 0
	mut fenced := false
	for line in c.text.split('\n') {
		if line.starts_with('```') || line.starts_with('~~~') { fenced = !fenced }
		if !fenced && line.starts_with('#') {
			mut level := 0
			for level < line.len && line[level] == `#` { level++ }
			if level <= 6 && level < line.len && line[level] == ` ` {
				if at <= c.md.section_at {
					start = at
					depth = level
				} else if depth == 0 || level <= depth {
					end = at
					break
				}
			}
		}
		at += line.len + 1
	}
	return start, end
}

fn line_glyphs(text string, offset int, attr int, task int) []Glyph {
	mut out := []Glyph{}
	mut i := 0
	for i < text.len {
		r, n := utf8.decode_rune_at(text, i)
		out << Glyph{ r: r, at: offset + i, end: offset + i + max(1, n), attr: attr, task: task }
		i += max(1, n)
	}
	return grapheme_glyphs(out)
}

fn inline_markdown(text string, offset int, initial_attr int) []Glyph {
	mut out := []Glyph{}
	mut i, mut attr := 0, initial_attr
	for i < text.len {
		if text[i] == `<` {
			if close := text[i..].index('>') {
				tag := text[i + 1..i + close].to_lower()
				if tag in ['u', '/u', 'b', '/b', 'strong', '/strong', 'em', '/em', 'i', '/i'] {
					bit := if tag.trim_left('/') == 'u' {
						underline
					} else if tag.trim_left('/') in ['b', 'strong'] {
						bold
					} else {
						italic
					}
					if tag.starts_with('/') { attr &= ~bit } else { attr |= bit }
					i += close + 1
					continue
				}
			}
		}
		if text[i] == `\\` && i + 1 < text.len {
			r, n := utf8.decode_rune_at(text, i + 1)
			out << Glyph{ r: r, at: offset + i + 1, end: offset + i + 1 + n, attr: attr }
			i += 1 + n
			continue
		}
		if text[i] == 96 {
			end, span_end := markdown_code_span(text, i)
			if span_end > i {
				mut opening := i
				for opening < text.len && text[opening] == 96 { opening++ }
				for glyph in line_glyphs(text[opening..end], offset + opening, attr, -1) {
					out << Glyph{ ...glyph, element: .inline_code }
				}
				i = span_end
				continue
			}
		}
		if i + 1 < text.len && text[i..i + 2] in ['**', '__', '~~'] {
			attr ^= if text[i] == `~` { underline } else { bold }
			i += 2
			continue
		}
		if text[i] in [u8(`*`), u8(`_`)] {
			attr ^= italic
			i++
			continue
		}
		if text[i] == `[` {
			if close_rel := text[i + 1..].index('](') {
				close := i + 1 + close_rel
				if end_rel := text[close + 2..].index(')') {
					end := close + 2 + end_rel
					for g in line_glyphs(text[i + 1..close], offset + i + 1, attr, -1) {
						out << Glyph{ ...g, link: text[close + 2..end] }
					}
					i = end + 1
					continue
				}
			}
		}
		r, n := utf8.decode_rune_at(text, i)
		out << Glyph{
			r:    r
			at:   offset + i
			end:  offset + i + max(1, n)
			attr: attr
		}
		i += max(1, n)
	}
	return grapheme_glyphs(out)
}

fn task_offset(line string) int {
	trim := line.trim_left(' ')
	if line.starts_with('\t') || line.len - trim.len >= 4 { return -1 }
	if trim.len >= 6 && trim[0] in [u8(`-`), u8(`*`), u8(`+`)] && trim[1] == ` ` && trim[2] == `[` && trim[3] in [
		u8(` `),
		u8(`x`),
		u8(`X`),
	] && trim[4] == `]` && trim[5] == ` ` {
		return line.len - trim.len + 3
	}
	return -1
}

pub fn (mut c Ctl) toggle_task(at int) bool {
	if !c.md.task_interactive { return false }
	rows := c.markdown_rows()
	mut task := -1
	for row in rows {
		if at >= row.start && at <= row.end && !row.code {
			rel := task_offset(c.text[row.start..row.end])
			if rel >= 0 { task = row.start + rel }
			break
		}
	}
	if task < 0 { return false }
	// Task interaction is the sole permitted mutation in a read-only view.
	// Keep that state and the selection intact while notifying observers.
	c.end_edit_group()
	after := if c.text[task] == ` ` { 'x' } else { ' ' }
	c.edit.undo << Change{task, c.text[task..task + 1], after, c.cursor, c.anchor, c.cursor}
	c.edit.redo = []
	c.edit.revision++
	c.text = c.text[..task] + after + c.text[task + 1..]
	c.fire()
	return true
}
