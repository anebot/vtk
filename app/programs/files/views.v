module files

import math
import os
import time
import vtk

enum View {
	list
	icons
	columns
}

const header_rows = 2
const tile_width = 14
const tile_height = 4
const column_min = 20

const glyph_dir = `▣`
const glyph_file = `□`
const glyph_text = `═`
const glyph_image = `■`
const glyph_sound = `•`
const glyph_movie = `►`
const glyph_pack = `▒`
const glyph_binary = `█`

struct Column {
	path        string
	scan_capped bool
mut:
	entries []Entry
	cursor  int = -1
}

fn theme_of(p &Pane) vtk.Theme {
	return p.shared.app.theme
}

fn focused(c &vtk.Ctl, p &Pane) bool {
	if f := p.shared.app.focused_ctl() { return f == c }
	return false
}

fn ellipsis(s &vtk.Screen) string {
	return if s.ascii { '~' } else { '…' }
}

fn clip_text(text string, width int, tail string) string {
	if width <= 0 { return '' }
	if vtk.text_width(text) <= width { return text }
	mut out := ''
	mut used := 0
	for r in text.runes() {
		w := vtk.rune_width(r)
		if used + w > width - 1 { break }
		out += r.str()
		used += w
	}
	return out + tail
}

fn size_text(size i64) string {
	if size < 0 { return '' }
	if size < 1000 { return '${size}B' }
	mut value := f64(size)
	mut unit := 0
	units := ['k', 'M', 'G', 'T']
	for value >= 999.95 && unit < 3 {
		value /= 1000.0
		unit++
	}
	scaled := int(value * 10.0 + 0.5)
	if scaled < 100 {
		return '${scaled / 10}.${scaled % 10}${units[unit]}'
	}
	return '${scaled / 10}${units[unit]}'
}

fn kind_name(e &Entry) string {
	if e.dir { return 'Folder' }
	return match e.ext {
		'.txt', '.md', '.markdown', '.v', '.c', '.h', '.json', '.toml', '.ini', '.cfg', '.yaml',
		'.yml',
		'.sh', '.py', '.js', '.ts', '.go', '.rs', '.css', '.html' {
			'Text'
		}
		'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.svg', '.webp', '.ico' {
			'Image'
		}
		'.mp3', '.wav', '.flac', '.ogg', '.m4a', '.aiff' {
			'Audio'
		}
		'.mp4', '.mkv', '.mov', '.avi', '.webm' {
			'Video'
		}
		'.zip', '.tar', '.gz', '.bz2', '.xz', '.7z', '.rar' {
			'Archive'
		}
		'.pdf' {
			'PDF'
		}
		else {
			if e.ext != '' { e.ext[1..].to_upper() } else { 'File' }
		}
	}
}

fn entry_glyph(e &Entry) rune {
	if e.dir { return glyph_dir }
	return match e.ext {
		'.txt', '.md', '.markdown', '.v', '.c', '.h', '.json', '.toml', '.ini', '.cfg', '.yaml',
		'.yml',
		'.sh', '.py', '.js', '.ts', '.go', '.rs', '.css', '.html' {
			glyph_text
		}
		'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.svg', '.webp', '.ico' {
			glyph_image
		}
		'.mp3', '.wav', '.flac', '.ogg', '.m4a', '.aiff' {
			glyph_sound
		}
		'.mp4', '.mkv', '.mov', '.avi', '.webm' {
			glyph_movie
		}
		'.zip', '.tar', '.gz', '.bz2', '.xz', '.7z', '.rar' {
			glyph_pack
		}
		'.o', '.a', '.so', '.dylib', '.exe', '.bin' {
			glyph_binary
		}
		else {
			glyph_file
		}
	}
}

fn entry_color(e &Entry, t vtk.Theme) int {
	if e.dir { return t.accent }
	if e.link { return vtk.cyan }
	return match e.ext {
		'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.svg', '.webp', '.ico' {
			vtk.magenta
		}
		'.zip', '.tar', '.gz', '.bz2', '.xz', '.7z', '.rar' {
			vtk.yellow
		}
		'.o', '.a', '.so', '.dylib', '.exe', '.bin', '.sh' {
			vtk.green
		}
		else {
			t.fg
		}
	}
}

fn (p &Pane) column_entries(column int) []Entry {
	return if column == p.cols.len - 1 { p.entries } else { p.cols[column].entries }
}

fn (mut p Pane) list_rows() int {
	return math.max(1, p.canvas.rect().h - header_rows)
}

fn (mut p Pane) icon_cols() int {
	return math.max(1, p.canvas.rect().w / tile_width)
}

fn (mut p Pane) icon_rows() int {
	return math.max(1, p.canvas.rect().h / tile_height)
}

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

struct ListColumns {
mut:
	name_x int = 3
	name_w int
	size_x int
	size_w int
	kind_x int
	kind_w int
	date_x int
	date_w int
}

fn list_columns(width int) ListColumns {
	mut c := ListColumns{}
	right := width - 2
	if width >= 56 { c.date_w = 11 }
	if width >= 38 { c.kind_w = 10 }
	if width >= 26 { c.size_w = 8 }
	c.date_x = right - c.date_w
	c.kind_x = c.date_x - c.kind_w - 1
	c.size_x = c.kind_x - c.size_w - 1
	c.name_w = math.max(4, c.size_x - c.name_x - 1)
	return c
}

fn paint_pane(mut c vtk.Ctl, mut s vtk.Screen) {
	mut p := pane_from(c) or { return }
	t := theme_of(p)
	r := c.rect()
	s.fill(r, ` `, t.fg, t.bg)
	if p.issue != '' {
		s.text(r.x + 1, r.y, clip_text(p.issue, math.max(1, r.w - 2), ellipsis(s)), vtk.red, t.bg, 0)
		return
	}
	match p.view {
		.list { p.paint_list(mut s, r, t) }
		.icons { p.paint_icons(mut s, r, t) }
		.columns { p.paint_columns(mut s, r, t) }
	}
	if p.marquee {
		band := vtk.Rect{r.x + p.mq_x, r.y + p.mq_y, math.max(2, p.mq_x2 - p.mq_x + 1), math.max(2, p.mq_y2 - p.mq_y + 1)}
		s.frame(band, false, t.accent, t.bg)
	}
}

fn (p &Pane) row_style(e Entry, index int, selected bool, has_focus bool, t vtk.Theme) (int, int, int) {
	drag := p.shared.drag
	drop := drag.active && drag.target == p.id && drag.target_col == -1 && drag.target_row == index
	sel := selected
	mut fg := if e.dir { t.accent } else { t.fg }
	mut bg := t.bg
	mut attr := if e.dir { vtk.bold } else { 0 }
	if sel {
		bg = if has_focus { t.focus_bg } else { t.sel_bg }
		fg = if has_focus { t.focus_fg } else { t.sel_fg }
	}
	if drag.active && drag.paths.any(it == e.path) {
		fg = t.dim
		attr |= vtk.italic
	}
	if drop {
		bg = t.sel_bg
		fg = t.sel_fg
		attr |= vtk.bold | vtk.reverse
	}
	return fg, bg, attr
}

fn (p &Pane) paint_list(mut s vtk.Screen, r vtk.Rect, t vtk.Theme) {
	if r.h < 3 { return }
	cols := list_columns(r.w)
	has_focus := focused(p.canvas, p)
	arrow := if p.descending { '▾' } else { '▴' }
	head_bg := t.bg
	head_fg := t.dim
	for i in 0 .. p.list_rows() + header_rows {
		y := r.y + i
		if y >= r.y + r.h { break }
		if i == 0 {
			s.fill(vtk.Rect{r.x, y, r.w, 1}, ` `, head_fg, head_bg)
			name_attr := if p.sort == .name { vtk.bold | vtk.underline } else { vtk.bold }
			s.text(r.x + cols.name_x, y, 'Name', head_fg, head_bg, name_attr)
			if p.sort == .name {
				s.text(r.x + cols.name_x + 5, y, arrow, head_fg, head_bg, 0)
			}
			if cols.size_w > 0 {
				label := 'Size'
				s.text(r.x + cols.size_x + cols.size_w - vtk.text_width(label), y, label, head_fg,
					head_bg, if p.sort == .size { vtk.bold | vtk.underline } else { vtk.bold })
			}
			if cols.kind_w > 0 {
				s.text(r.x + cols.kind_x, y, 'Type', head_fg, head_bg, if p.sort == .kind {
					vtk.bold | vtk.underline
				} else {
					vtk.bold
				})
			}
			if cols.date_w > 0 {
				s.text(r.x + cols.date_x, y, 'Modified', head_fg, head_bg, if p.sort == .date {
					vtk.bold | vtk.underline
				} else {
					vtk.bold
				})
			}
			continue
		}
		if i == 1 {
			s.fill(vtk.Rect{r.x, y, r.w, 1}, `─`, t.dim, t.bg)
			continue
		}
		index := p.top + i - header_rows
		if index < 0 || index >= p.entries.len { break }
		e := p.entries[index]
		sel := p.selected[e.path]
		fg, bg, attr := p.row_style(e, index, sel, has_focus, t)
		s.fill(vtk.Rect{r.x, y, r.w, 1}, ` `, fg, bg)
		if index == p.cursor {
			s.text(r.x, y, '▸', if sel { fg } else { t.accent }, bg, 0)
		}
		s.put(r.x + 1, y, entry_glyph(&e), if sel { fg } else { entry_color(&e, t) }, bg, 0)
		s.text(r.x + cols.name_x, y, clip_text(e.name, cols.name_w, ellipsis(s)), fg, bg, attr)
		if cols.size_w > 0 && !e.dir {
			label := size_text(e.size)
			s.text(r.x + cols.size_x + cols.size_w - vtk.text_width(label), y, label, fg, bg, 0)
		}
		if cols.kind_w > 0 {
			s.text(r.x + cols.kind_x, y, clip_text(kind_name(&e), cols.kind_w - 1, ellipsis(s)), fg,
				bg, 0)
		}
		if cols.date_w > 0 && e.modified > 0 {
			stamp := time.unix(e.modified).ymmdd()
			s.text(r.x + cols.date_x, y, stamp, fg, bg, 0)
		}
	}
	p.paint_scrollbar(mut s, r, t, p.list_rows(), p.entries.len, p.top)
}

fn (p &Pane) paint_icons(mut s vtk.Screen, r vtk.Rect, t vtk.Theme) {
	cols := p.icon_cols()
	rows := p.icon_rows()
	has_focus := focused(p.canvas, p)
	start := (p.top / cols) * cols
	for slot in 0 .. rows * cols {
		index := start + slot
		if index >= p.entries.len { break }
		x := r.x + (slot % cols) * tile_width
		y := r.y + (slot / cols) * tile_height
		if y + tile_height > r.y + r.h { break }
		e := p.entries[index]
		sel := p.selected[e.path]
		fg, bg, attr := p.row_style(e, index, sel, has_focus, t)
		p.paint_tile(mut s, vtk.Rect{x, y, tile_width, tile_height}, e, fg, bg, attr, index == p.cursor, sel)
	}
	visible := rows * cols
	p.paint_scrollbar(mut s, r, t, visible, p.entries.len, start)
}

fn (p &Pane) paint_tile(mut s vtk.Screen, tile vtk.Rect, e Entry, fg int, bg int, attr int, cursor bool, sel bool) {
	s.fill(tile, ` `, fg, bg)
	fw := math.min(tile.w - 2, 9)
	fx := tile.x + (tile.w - fw) / 2
	fy := tile.y
	top_l := if cursor { `╔` } else { `╭` }
	top_r := if cursor { `╗` } else { `╮` }
	low_l := if cursor { `╚` } else { `╰` }
	low_r := if cursor { `╝` } else { `╯` }
	line := if cursor { `═` } else { `─` }
	edge := if cursor { `║` } else { `│` }
	s.put(fx, fy, top_l, fg, bg, attr)
	s.fill(vtk.Rect{fx + 1, fy, fw - 2, 1}, line, fg, bg)
	s.put(fx + fw - 1, fy, top_r, fg, bg, attr)
	s.put(fx, fy + 1, edge, fg, bg, attr)
	s.put(fx + fw - 1, fy + 1, edge, fg, bg, attr)
	icon := entry_glyph(&e)
	s.put(fx + fw / 2, fy + 1, icon, if sel { fg } else { entry_color(&e, theme_of(p)) }, bg, attr)
	s.put(fx, fy + 2, low_l, fg, bg, attr)
	s.fill(vtk.Rect{fx + 1, fy + 2, fw - 2, 1}, line, fg, bg)
	s.put(fx + fw - 1, fy + 2, low_r, fg, bg, attr)
	name := clip_text(e.name, tile.w - 1, ellipsis(s))
	name_x := tile.x + math.max(0, (tile.w - vtk.text_width(name)) / 2)
	s.text(name_x, fy + 3, name, fg, bg, attr)
}

fn (p &Pane) column_layout() (int, int) {
	width := p.canvas.rect().w
	if p.cols.len == 0 { return 0, math.max(1, width) }
	fit := math.max(1, width / column_min)
	first := math.max(0, p.cols.len - fit)
	shown := p.cols.len - first
	return first, math.max(1, width / math.max(1, shown))
}

fn (p &Pane) paint_columns(mut s vtk.Screen, r vtk.Rect, t vtk.Theme) {
	if p.cols.len == 0 { return }
	first, cw := p.column_layout()
	has_focus := focused(p.canvas, p)
	arrow := if p.descending { '▾' } else { '▴' }
	for i := first; i < p.cols.len; i++ {
		col := p.cols[i]
		entries := p.column_entries(i)
		x := r.x + (i - first) * cw
		last := i == p.cols.len - 1
		w := if last { r.x + r.w - x } else { cw - 1 }
		if w < 4 { continue }
		cursor := if last { p.cursor } else { col.cursor }
		rows := math.max(1, r.h - 1)
		top := if last { p.top } else { math.max(0, cursor - rows + 1) }
		s.fill(vtk.Rect{x, r.y, w, 1}, ` `, t.accent, t.bg)
		s.text(x, r.y, clip_text(' ${os.base(col.path)} ' + arrow, w, ellipsis(s)), t.accent,
			t.bg, vtk.bold)
		for row in 0 .. rows {
			index := top + row
			if index >= entries.len { break }
			e := entries[index]
			y := r.y + 1 + row
			sel := if last { p.selected[e.path] } else { index == col.cursor }
			drag := p.shared.drag
			drop := drag.active && drag.target == p.id && drag.target_col == i && drag.target_row == index
			fg := if sel || drop {
				if has_focus || drop { t.focus_fg } else { t.sel_fg }
			} else if e.dir {
				t.accent
			} else {
				t.fg
			}
			bg := if drop {
				t.sel_bg
			} else if sel && !last {
				t.sel_bg
			} else if sel {
				if has_focus { t.focus_bg } else { t.sel_bg }
			} else {
				t.bg
			}
			attr := if e.dir { vtk.bold } else { 0 }
			s.fill(vtk.Rect{x, y, w, 1}, ` `, fg, bg)
			s.put(x, y, entry_glyph(&e), if sel || drop { fg } else { entry_color(&e, t) }, bg, 0)
			if index == cursor { s.text(x + 1, y, '▸', fg, bg, 0) }
			s.text(x + 2, y, clip_text(e.name, w - 3, ellipsis(s)), fg, bg, attr)
		}
		if !last {
			s.fill(vtk.Rect{x + w, r.y, 1, r.h}, `│`, t.dim, t.bg)
		}
	}
}

fn (p &Pane) paint_scrollbar(mut s vtk.Screen, r vtk.Rect, t vtk.Theme, visible int, total int, top int) {
	if total <= visible || r.w < 3 || r.h < 3 { return }
	height := r.h
	thumb := math.max(1, height * visible / math.max(1, total))
	at := if total > visible { top * (height - thumb) / math.max(1, total - visible) } else { 0 }
	s.fill(vtk.Rect{r.x + r.w - 1, r.y, 1, height}, `░`, t.dim, t.bg)
	s.fill(vtk.Rect{r.x + r.w - 1, r.y + at, 1, thumb}, `█`, t.frame, t.bg)
}
