module vtk

import encoding.utf8

pub enum TextWrapMode {
	none
	character
	word
}

// Keep wrap/md.no_wrap source compatible; the setter controls all three modes.
pub fn (c &Ctl) wrap_mode() TextWrapMode {
	if c.kind !in [.multiline, .markdown] || !(c.wrap || (c.kind == .markdown && !c.md.no_wrap)) { return .none }
	return if c.wrap_words { .word } else { .character }
}

pub fn (mut c Ctl) set_wrap_mode(mode TextWrapMode) bool {
	if c.destroyed || c.kind !in [.multiline, .markdown] { return false }
	c.wrap = mode != .none
	c.wrap_words = mode == .word
	if c.kind == .markdown { c.md.no_wrap = mode == .none }
	if mode != .none { c.left = 0 }
	c.invalidate()
	return true
}

pub struct Change {
pub:
	at           int
	before       string
	after        string
	cursor       int
	anchor       int
	after_cursor int
}

@[heap]
pub struct Edit {
mut:
	undo     []Change
	redo     []Change
	revision u64
	grouping     bool
	group_text   string
	group_cursor int
	group_anchor int
}

pub fn (mut edit Edit) reset() {
	edit = Edit{revision: edit.revision + 1}
}

pub fn entry(text string, byte_limit int) &Ctl {
	return &Ctl{ kind: .entry, text: text, byte_limit: max(0, byte_limit), cursor: text.len, expand: true, focusable: true }
}

pub fn multiline(text string) &Ctl {
	return &Ctl{ kind: .multiline, text: text, expand: true, focusable: true }
}

pub fn (c &Ctl) selection() (int, int) {
	if c.anchor < 0 { return c.cursor, c.cursor }
	return min(c.anchor, c.cursor), max(c.anchor, c.cursor)
}

pub fn (mut c Ctl) begin_edit_group() {
	if c.edit.grouping { return }
	c.edit.grouping = true
	c.edit.group_text = c.text
	c.edit.group_cursor = c.cursor
	c.edit.group_anchor = c.anchor
}

pub fn (mut c Ctl) end_edit_group() {
	if !c.edit.grouping { return }
	c.edit.grouping = false
	if c.text != c.edit.group_text {
		c.edit.undo << Change{0, c.edit.group_text, c.text, c.edit.group_cursor, c.edit.group_anchor, c.cursor}
	}
}

// replace_range validates byte boundaries and byte limits before mutation.
// The result reports whether an edit occurred; read-only editors are inert.
pub fn (mut c Ctl) replace_range(from int, to int, text string) bool {
	if c.readonly || from < 0 || to < from || to > c.text.len || boundary(c.text, from) != from || boundary(c.text, to) != to {
		return false
	}
	mut insertion := text
	if c.kind == .entry { insertion = insertion.replace('\r', '').replace('\n', '') }
	if !utf8.validate_str(insertion) { return false }
	if c.kind == .entry && c.byte_limit > 0 && c.text.len - (to - from) + insertion.len > c.byte_limit {
		return false
	}
	before := c.text[from..to]
	if before == insertion {
		c.cursor = from + insertion.len
		c.anchor = -1
		c.invalidate()
		return false
	}
	if !c.edit.grouping {
		c.edit.undo << Change{from, before, insertion, c.cursor, c.anchor, from + insertion.len}
	}
	c.edit.redo = []
	c.edit.revision++
	c.text = c.text[..from] + insertion + c.text[to..]
	c.cursor = from + insertion.len
	c.anchor = -1
	c.scroll_hold = false
	c.fire()
	return true
}

pub fn (mut c Ctl) replace_selection(text string) bool {
	a, b := c.selection()
	return c.replace_range(a, b, text)
}

pub fn (mut c Ctl) undo() bool {
	c.end_edit_group()
	if c.readonly || c.edit.undo.len == 0 { return false }
	change := c.edit.undo.last()
	c.edit.undo.delete_last()
	c.text = c.text[..change.at] + change.before + c.text[change.at + change.after.len..]
	c.cursor = change.cursor
	c.anchor = change.anchor
	c.edit.redo << change
	c.edit.revision++
	c.scroll_hold = false
	c.fire()
	return true
}

pub fn (mut c Ctl) redo() bool {
	if c.readonly || c.edit.redo.len == 0 { return false }
	change := c.edit.redo.last()
	c.edit.redo.delete_last()
	c.text = c.text[..change.at] + change.after + c.text[change.at + change.before.len..]
	c.cursor = change.after_cursor
	c.anchor = -1
	c.edit.undo << change
	c.edit.revision++
	c.scroll_hold = false
	c.fire()
	return true
}

fn line_start(text string, at int) int {
	mut i := clamp(at, 0, text.len)
	for i > 0 && text[i - 1] != `\n` { i-- }
	return i
}

fn line_end(text string, at int) int {
	mut i := clamp(at, 0, text.len)
	for i < text.len && text[i] != `\n` { i++ }
	return i
}

fn word_forward(text string, at int, big bool) int {
	mut i := at
	if i >= text.len { return text.len }
	class := word_class(text, i, big)
	for i < text.len && word_class(text, i, big) == class { i = next_char(text, i) }
	for i < text.len && word_class(text, i, big) == 0 { i = next_char(text, i) }
	return i
}

fn word_back(text string, at int, big bool) int {
	mut i := prev_char(text, at)
	for i > 0 && word_class(text, i, big) == 0 { i = prev_char(text, i) }
	class := word_class(text, i, big)
	for i > 0 {
		p := prev_char(text, i)
		if word_class(text, p, big) != class { break }
		i = p
	}
	return i
}

fn word_class(text string, at int, big bool) int {
	if at >= text.len { return 0 }
	r, _ := utf8.decode_rune_at(text, at)
	if utf8.is_space(r) { return 0 }
	if big || utf8.is_letter(r) || utf8.is_number(r) || r == `_` { return 1 }
	return 2
}

struct Glyph {
	r    rune
	text string
	at   int
	end  int
	attr int
	color ?int
	element MarkdownElement
	task int = -1
	link string
}

struct TextRow {
mut:
	start   int
	end     int
	line    int
	glyphs  []Glyph
	code    bool
	element MarkdownElement
	no_wrap bool
	color   ?int
	attr    int
}

fn (c &Ctl) editor_gutter() int {
	return (if c.line_numbers { 5 } else { 0 }) + (if c.kind == .markdown && c.md.ruler_left {
		3
	} else {
		0
	})
}

fn (c &Ctl) editor_height() int {
	return max(1, c.h - if c.kind == .markdown {
		int(!c.md.hide_status) + int(c.md.ruler_top)
	} else {
		0
	})
}

fn (c &Ctl) editor_rows() []TextRow {
	mut lines := if c.kind == .markdown {
		c.markdown_rows()
	} else if c.kind == .multiline && c.syntax == .diff {
		diff_rows(c.text)
	} else {
		plain_rows(c.text)
	}
	mode := c.wrap_mode()
	if mode == .none { return lines }
	mut width := max(1, c.w - c.editor_gutter() - int(c.scrollbar))
	if c.kind == .markdown && c.md.column_width > 0 { width = min(width, c.md.column_width) }
	mut result := []TextRow{}
	for row in lines {
		if row.no_wrap || row.glyphs.len == 0 { result << row; continue }
		mut start := 0
		for start < row.glyphs.len {
			end := text_wrap_end(row.glyphs, start, width, max(1, c.md.tab_width), mode)
			result << TextRow{ ...row,
				start: if start == 0 { row.start } else { row.glyphs[start].at },
				end: if end == row.glyphs.len { row.end } else { row.glyphs[end].at },
				glyphs: row.glyphs[start..end].clone() }
			start = end
		}
	}
	return result
}

fn wrap_space(r rune) bool {
	// NBSP and narrow NBSP join words rather than providing a soft break.
	return utf8.is_space(r) && r !in [rune(0x00a0), rune(0x202f)]
}

fn text_wrap_end(glyphs []Glyph, start int, width int, tab_width int, mode TextWrapMode) int {
	mut col, mut last_break := 0, start
	for i := start; i < glyphs.len; i++ {
		glyph := glyphs[i]
		space := wrap_space(glyph.r)
		gw := if glyph.r == `\t` { tab_width - col % tab_width } else { glyph_width(glyph) }
		// Trailing whitespace may hang past the edge in word mode. Keep its
		// original glyph/span so selection and copying never lose source bytes.
		if col > 0 && col + gw > width && !(mode == .word && space) {
			return if mode == .word && last_break > start { last_break } else { i }
		}
		col += gw
		if space { last_break = i + 1 }
	}
	return glyphs.len
}

fn plain_rows(text string) []TextRow {
	mut result := []TextRow{}
	mut row := TextRow{}
	mut at := 0
	for at < text.len {
		r, n := utf8.decode_rune_at(text, at)
		if r == `\n` {
			row.end = at
			result << row
			row = TextRow{ start: at + 1, line: row.line + 1 }
		} else {
			row.glyphs << Glyph{ r: r, at: at, end: at + max(1, n) }
		}
		at += max(1, n)
	}
	for mut existing in result { existing.glyphs = grapheme_glyphs(existing.glyphs) }
	row.glyphs = grapheme_glyphs(row.glyphs)
	row.end = text.len
	result << row
	return result
}

fn row_column(row TextRow, at int, tab_width int, secret bool) int {
	mut col := 0
	for g in row.glyphs {
		if g.at >= at { break }
		col += if secret {
			1
		} else if g.r == `\t` {
			tab_width - col % tab_width
		} else {
			glyph_width(g)
		}
	}
	return col
}

fn row_hit(row TextRow, column int, tab_width int, secret bool) int {
	mut col := 0
	for g in row.glyphs {
		width := if secret {
			1
		} else if g.r == `\t` {
			tab_width - col % tab_width
		} else {
			glyph_width(g)
		}
		if column < col + max(1, width) { return g.at }
		col += width
	}
	return row.end
}

fn (c &Ctl) caret_row(rows []TextRow) int {
	caret := c.caret_position()
	// Wrapped table cells can share a source line; locate the actual glyph
	// before falling back to the source row range. Synthetic borders have
	// zero-length spans and must not steal the caret.
	for i, row in rows {
		if row.no_wrap {
			for glyph in row.glyphs {
				if caret >= glyph.at && caret < glyph.end { return i }
			}
		}
	}
	for i, row in rows {
		if caret == row.end && i + 1 < rows.len && rows[i + 1].start == row.end
			&& rows[i + 1].line == row.line { continue }
		if caret >= row.start && (caret <= row.end || i == rows.len - 1) { return i }
	}
	return max(0, rows.len - 1)
}

pub fn (c &Ctl) caret_position() int {
	return if c.vim.enabled && c.vim.mode in [.visual, .visual_line] {
		c.vim.visual_head
	} else {
		c.cursor
	}
}

fn (mut app App) draw_editor(mut c Ctl) {
	t := app.theme
	rows := c.editor_rows()
	height := c.editor_height()
	caret := c.caret_row(rows)
	c.scroll_into_view(caret, height)
	c.top = clamp(c.top, 0, rows.len - height)
	mut fg := if c.disabled {
		t.dim
	} else if c.kind == .entry {
		t.field_fg
	} else {
		t.fg
	}
	mut bg := if c.kind == .entry { t.field_bg } else { t.bg }
	if c.kind == .markdown {
		paint := c.md.styles.paint(.text, t, MarkdownPaint{ fg: fg, bg: bg })
		fg, bg = paint.fg, paint.bg
	}
	app.screen.fill(c.rect(), ` `, fg, bg)
	margin := c.editor_gutter()
	inset := if c.kind == .markdown { int(c.md.ruler_top) } else { 0 }
	tab_width := max(1, c.md.tab_width)
	caret_col := row_column(rows[caret], c.caret_position(), tab_width, c.secret)
	view_w := max(1, c.w - margin - int(c.scrollbar))
	if c.wrap_mode() == .none
		|| (rows[caret].no_wrap && markdown_glyph_width(rows[caret].glyphs) > view_w) {
		if !c.scroll_hold {
			if caret_col < c.left { c.left = caret_col }
			if caret_col >= c.left + view_w { c.left = caret_col - view_w + 1 }
		}
	} else {
		c.left = 0
	}
	a, b := c.selection()
	for i := c.top; i < rows.len && i < c.top + height; i++ {
		row := rows[i]
		y := c.y + inset + i - c.top
		if c.line_numbers { app.screen.text(c.x, y, '${row.line + 1:4} ', t.dim, bg, 0) }
		if c.kind == .markdown && c.md.ruler_left {
			app.screen.text(c.x + margin - 3, y, ' | ', t.dim, bg, 0)
		}
		old := app.screen.set_clip(Rect{c.x + margin, y, view_w, 1})
		if c.kind == .markdown && row.element == .code_block {
			text_paint := c.md.styles.paint(.text, t, MarkdownPaint{ fg: fg, bg: bg })
			paint := c.md.styles.paint(.code_block, t, text_paint)
			app.screen.fill(Rect{c.x + margin, y, view_w, 1}, ` `, paint.fg, paint.bg)
		}
		mut col := 0
		for g in row.glyphs {
			selected := g.at >= a && g.at < b
			mut paint := MarkdownPaint{ fg: fg, bg: bg, attr: g.attr | row.attr }
			if c.kind == .markdown {
				paint = c.md.styles.paint(.text, t, paint)
				if row.element != .text { paint = c.md.styles.paint(row.element, t, paint) }
				if g.link != '' { paint = c.md.styles.paint(.link, t, paint) }
				if g.element != .text { paint = c.md.styles.paint(g.element, t, paint) }
			}
			if c.kind != .markdown || c.md.styles.code_block.fg == none {
				paint = MarkdownPaint{ ...paint, fg: g.color or { row.color or { paint.fg } } }
			}
			gfg := if selected { t.sel_fg } else if c.disabled { t.dim } else { paint.fg }
			gbg := if selected { t.sel_bg } else { paint.bg }
			attribute := if selected && c.kind == .markdown { paint.attr & ~reverse } else { paint.attr }
			if g.r == `\t` {
				n := tab_width - col % tab_width
				app.screen.fill(Rect{c.x + margin + col - c.left, y, n, 1}, ` `, gfg, gbg)
				col += n
			} else {
				if c.secret { app.screen.put(c.x + margin + col - c.left, y, `*`, gfg, gbg, attribute) }
				else { app.screen.put_grapheme(c.x + margin + col - c.left, y, glyph_text(g), glyph_width(g), gfg, gbg, attribute) }
				col += if c.secret { 1 } else { glyph_width(g) }
			}
		}
		app.screen.restore_clip(old)
	}
	if c.kind == .markdown {
		if c.md.ruler_top {
			app.screen.text(c.x + margin, c.y, '1---5----10---15---20---25---30---35---40---45---50---55---60---65---70---75---80', t.dim, bg, 0)
		}
		if !c.md.hide_status {
			mode := if c.md.mode in [.read, .source_read] { 'View' } else { 'Edit' }
			app.screen.fill(Rect{c.x, c.y + c.h - 1, c.w, 1}, ` `, t.bar_fg, t.bar_bg)
			app.screen.text(c.x, c.y + c.h - 1, '${mode} | ${caret + 1}:${caret_col + 1} | ${c.text.len} bytes' + if c.vim.enabled {
				' | ${c.vim.mode}'
			} else {
				''
			}, t.bar_fg, t.bar_bg, 0)
		}
	}
	app.draw_scrollbar(&c, rows.len, height, inset)
	if app.focus == &c && !c.disabled && caret >= c.top && caret < c.top + height {
		visible_col := if c.wrap_mode() != .none && !rows[caret].no_wrap { min(caret_col, view_w - 1) } else { caret_col - c.left }
		app.screen.cursor_x = c.x + margin + visible_col
		app.screen.cursor_y = c.y + inset + caret - c.top
		app.screen.cursor_shape = if c.vim.enabled && c.vim.mode != .insert {
			CursorShape.block
		} else {
			c.cursor_shape
		}
	}
}

fn (mut c Ctl) move_cursor(at int, selecting bool) {
	c.end_edit_group()
	if selecting {
		if c.anchor < 0 { c.anchor = c.cursor }
	} else {
		c.anchor = -1
	}
	c.cursor = boundary(c.text, clamp(at, 0, c.text.len))
	c.scroll_hold = false
}

fn (mut c Ctl) vertical_move(direction int, selecting bool) {
	rows := c.editor_rows()
	at := c.caret_row(rows)
	mut col := row_column(rows[at], c.cursor, max(1, c.md.tab_width), c.secret)
	if c.wrap_mode() != .none && !rows[at].no_wrap { col = min(col, max(0, c.w - c.editor_gutter() - int(c.scrollbar) - 1)) }
	target := clamp(at + direction, 0, rows.len - 1)
	c.move_cursor(row_hit(rows[target], col, max(1, c.md.tab_width), c.secret), selecting)
}

fn (mut c Ctl) editor_key(e Event, mut app App) bool {
	if c.vim.enabled && c.kind != .entry {
		if c.vim_key(e, mut app) { return true }
	}
	if c.kind == .markdown && e.key == int(Key.space) && c.md.mode in [.read, .source_read] {
		return c.toggle_task(c.cursor)
	}
	if e.ctrl {
		match lower_key(e.key) {
			`a` { c.move_cursor(line_start(c.text, c.cursor), e.shift) }
			`e` { c.move_cursor(line_end(c.text, c.cursor), e.shift) }
			`z` {
				if e.shift { c.redo() } else { c.undo() }
			}
			`r`, `y` { c.redo() }
			`v` { c.replace_selection(app.clipboard) }
			`x` {
				a, b := c.selection()
				if b > a && !c.secret {
					app.clipboard_set(c.text[a..b])
					c.replace_selection('')
				}
			}
			`w` {
				if c.anchor < 0 || c.anchor == c.cursor {
					c.anchor = word_back(c.text, c.cursor, false)
				}
				c.replace_selection('')
			}
			`k` {
				c.replace_range(c.cursor, if c.cursor == line_end(c.text, c.cursor) {
					min(c.text.len, c.cursor + 1)
				} else {
					line_end(c.text, c.cursor)
				}, '')
			}
			`u` { c.replace_range(line_start(c.text, c.cursor), c.cursor, '') }
			else { return false }
		}
		return true
	}
	match e.key {
		int(Key.left) { c.move_cursor(prev_char(c.text, c.cursor), e.shift) }
		int(Key.right) { c.move_cursor(next_char(c.text, c.cursor), e.shift) }
		int(Key.home) { c.move_cursor(line_start(c.text, c.cursor), e.shift) }
		int(Key.end) { c.move_cursor(line_end(c.text, c.cursor), e.shift) }
		int(Key.up) { c.vertical_move(-1, e.shift) }
		int(Key.down) { c.vertical_move(1, e.shift) }
		int(Key.page_up) { c.vertical_move(-max(1, c.editor_height() - 2), e.shift) }
		int(Key.page_down) { c.vertical_move(max(1, c.editor_height() - 2), e.shift) }
		int(Key.backspace) {
			a, b := c.selection()
			c.replace_range(if a == b { prev_char(c.text, c.cursor) } else { a }, b, '')
		}
		int(Key.delete) {
			a, b := c.selection()
			c.replace_range(a, if a == b { next_char(c.text, c.cursor) } else { b }, '')
		}
		int(Key.enter) {
			if c.kind == .entry {
				if f := c.submit { f(mut c, mut app) } else { return false }
			} else {
				c.replace_selection('\n')
			}
		}
		else {
			if e.alt || e.key < 32 || e.key >= 0x110000 { return false }
			c.replace_selection(rune(e.key).str())
		}
	}
	return true
}

fn (mut c Ctl) editor_mouse(e Event, mut app App) {
	rows := c.editor_rows()
	inset := if c.kind == .markdown { int(c.md.ruler_top) } else { 0 }
	row := clamp(c.top + e.y - c.y - inset, 0, rows.len - 1)
	column := max(0, e.x - c.x - c.editor_gutter() + c.left)
	at := row_hit(rows[row], column, max(1, c.md.tab_width), c.secret)
	if c.kind == .markdown && !e.motion && (c.readonly || e.ctrl) {
		for glyph in rows[row].glyphs {
			if glyph.at == at && glyph.link != '' {
				if f := c.md.linkfn {
					f(mut c, glyph.link, mut app)
					return
				}
			}
		}
	}
	if c.kind == .markdown && c.md.task_interactive && !e.motion {
		for g in rows[row].glyphs {
			if g.at == at && g.task >= 0 {
				if c.md.mode in [.read, .source_read] || (c.md.last_task == g.task && app.now() - c.md.last_click < 400) {
					c.toggle_task(g.task)
					return
				}
				c.md.last_task = g.task
				c.md.last_click = app.now()
			}
		}
	}
	c.vim.visual_start = -1
	if c.vim.mode in [.visual, .visual_line] { c.vim.mode = .normal }
	if e.motion {
		if c.anchor < 0 { c.anchor = c.cursor }
		c.cursor = at
	} else {
		c.move_cursor(at, e.shift)
		if !e.shift { c.anchor = at }
	}
	c.scroll_hold = false
	app.dirty = true
}
