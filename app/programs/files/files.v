// VTK Files is a file manager for the VTK desktop. It offers Windows Explorer
// style list, icon and column views, sorting, Shift/Ctrl multi-selection and
// drag and drop between its own windows and from the host terminal.
module files

import arrays
import os
import time
import vtk

enum View {
	list
	icons
	columns
}

enum SortBy {
	name
	size
	kind
	date
}

struct SortEntry {
	label string
	by    SortBy
}

const sort_entries = [SortEntry{'Name', .name}, SortEntry{'Size', .size}, SortEntry{'Type', .kind},
	SortEntry{'Modified', .date}]

const title_prefix = 'Files - '
const header_rows = 2
const tile_width = 14
const tile_height = 4
const column_min = 20
const scan_limit = 5000
const glyph_dir = `▣`
const glyph_file = `□`
const glyph_text = `═`
const glyph_image = `■`
const glyph_sound = `•`
const glyph_movie = `►`
const glyph_pack = `▒`
const glyph_binary = `█`

struct Entry {
	name     string
	path     string
	dir      bool
	link     bool
	size     i64
	modified i64
	ext      string
}

// Drag carries the payload between Files windows while the button is held.
struct Drag {
mut:
	active     bool
	origin     int = -1
	paths      []string
	x          int
	y          int
	copy       bool
	target     int = -1
	target_dir string
	target_col int = -1
	target_row int = -1
	valid      bool
}

// Shared state is heap allocated once and referenced by every Files window, so
// any window can read the drag state without module globals.
struct Shared {
mut:
	app   &vtk.App @[required]
	panes []&Pane
	next  int
	drag  Drag
}

struct Column {
	path    string
	entries []Entry
	cursor  int = -1
}

@[heap]
struct Pane {
mut:
	id          int
	shared      &Shared @[required]
	win         &vtk.Ctl @[required]
	canvas      &vtk.Ctl @[required]
	status      &vtk.Ctl @[required]
	path_field  &vtk.Ctl @[required]
	hidden_btn  &vtk.Ctl @[required]
	path        string
	issue       string
	entries     []Entry
	selected    map[string]bool
	cursor      int = -1
	cursor_path string
	anchor      int = -1
	anchor_path string
	top         int
	view        View
	sort        SortBy
	descending  bool
	show_hidden bool
	history     []string
	ahead       []string
	cols        []Column
	pressing    bool
	press_row   int = -1
	press_empty bool
	press_x     int
	press_y     int
	marquee     bool
	mq_x        int
	mq_y        int
	mq_x2       int
	mq_y2       int
	last_click  i64
	last_path   string
	typed       string
	typed_at    i64
}

fn imin(a int, b int) int {
	return if a < b { a } else { b }
}

fn imax(a int, b int) int {
	return if a > b { a } else { b }
}

fn iclamp(n int, low int, high int) int {
	return imax(low, imin(n, imax(low, high)))
}

fn cmp_text(a string, b string) int {
	return if a < b {
		-1
	} else if a > b {
		1
	} else {
		0
	}
}

fn cmp_nums(a i64, b i64) int {
	return if a < b {
		-1
	} else if a > b {
		1
	} else {
		0
	}
}

// pane_from resolves the window or control that owns a Pane.
fn pane_from(c &vtk.Ctl) ?&Pane {
	return c.context[Pane]()
}

// files_window identifies the windows Files created.
fn files_window(w &vtk.Ctl) bool {
	return w.kind == .window && pane_from(w) != none
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

// ---------------------------------------------------------------------------
// File system
// ---------------------------------------------------------------------------

fn read_entries(dir string, hidden bool) ![]Entry {
	mut names := os.ls(dir)!
	if names.len > scan_limit { names = names[..scan_limit] }
	mut entries := []Entry{cap: names.len}
	for name in names {
		if name.starts_with('.') && !hidden { continue }
		path := os.join_path(dir, name)
		st := os.stat(path) or { continue }
		is_dir := os.is_dir(path)
		entries << Entry{
			name:     name
			path:     path
			dir:      is_dir
			link:     os.is_link(path)
			size:     i64(st.size)
			modified: st.mtime
			ext:      if is_dir { '' } else { os.file_ext(name).to_lower() }
		}
	}
	return entries
}

fn compare_entries(a Entry, b Entry, by SortBy, desc bool) int {
	if a.dir != b.dir { return if a.dir { -1 } else { 1 } }
	mut order := match by {
		.name { cmp_text(a.name.to_lower(), b.name.to_lower()) }
		.size { cmp_nums(a.size, b.size) }
		.kind {
			cmp_text(kind_name(&a) + ' ' + a.name.to_lower(), kind_name(&b) + ' ' + b.name.to_lower())
		}
		.date { cmp_nums(a.modified, b.modified) }
	}
	if order == 0 { order = cmp_text(a.name.to_lower(), b.name.to_lower()) }
	return if desc { -order } else { order }
}

fn sort_entries(mut entries []Entry, by SortBy, desc bool) {
	arrays.stable_sort(mut entries, fn [by, desc] (a Entry, b Entry) bool {
		return compare_entries(a, b, by, desc) < 0
	})
}

fn unique_target(source string, dest string) string {
	name := os.base(source)
	path := os.join_path(dest, name)
	if !os.exists(path) { return path }
	ext := if os.is_dir(source) { '' } else { os.file_ext(name) }
	stem := if ext != '' && ext.len < name.len { name[..name.len - ext.len] } else { name }
	for i in 2 .. 1000 {
		candidate := os.join_path(dest, '${stem} (${i})${ext}')
		if !os.exists(candidate) { return candidate }
	}
	return os.join_path(dest, '${stem} (${time.now().unix()})${ext}')
}

fn drop_allowed(paths []string, dir string, copy bool) bool {
	if dir == '' { return false }
	for path in paths {
		if dir == path || dir.starts_with(path + os.path_separator) { return false }
		if !copy && os.dir(path) == dir { return false }
	}
	return true
}

fn open_path(path string) {
	os.open_uri(path) or {}
}

// paste_paths turns pasted text (plain paths, quoted paths or file:// URLs)
// into existing absolute paths. Terminals that accept host file drops paste
// the dropped file list here.
fn paste_paths(text string) []string {
	mut paths := []string{}
	for raw in text.split_any('\r\n') {
		mut item := raw.trim_space()
		if item == '' { continue }
		if item.starts_with("'") && item.ends_with("'") && item.len > 1 {
			item = item[1..item.len - 1]
		} else if item.starts_with('"') && item.ends_with('"') && item.len > 1 {
			item = item[1..item.len - 1]
		}
		item = item.replace('\\ ', ' ')
		if item.starts_with('file://') {
			item = decode_uri(item.all_after('file://').trim_left('/'))
			item = os.path_separator + item
		}
		if os.exists(item) { paths << os.real_path(item) }
	}
	return paths
}

fn decode_uri(text string) string {
	if !text.contains_u8(`%`) { return text }
	mut out := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		if text[i] == `%` && i + 2 < text.len && text[i + 1].is_hex_digit()
			&& text[i + 2].is_hex_digit() {
			value := text[i + 1..i + 3].parse_uint(16, 8) or { 0 }
			// NUL cannot appear in a file path.
			if value > 0 {
				out << u8(value)
				i += 3
				continue
			}
		}
		out << text[i]
		i++
	}
	return out.bytestr()
}

// ---------------------------------------------------------------------------
// Pane state
// ---------------------------------------------------------------------------

fn (mut p Pane) index_of(path string) int {
	for i, e in p.entries {
		if e.path == path { return i }
	}
	return -1
}

fn (mut p Pane) refresh() {
	p.issue = ''
	p.entries = read_entries(p.path, p.show_hidden) or {
		p.issue = err.msg()
		[]Entry{}
	}
	sort_entries(mut p.entries, p.sort, p.descending)
	mut keep := map[string]bool{}
	for e in p.entries {
		if p.selected[e.path] { keep[e.path] = true }
	}
	p.selected = keep
	p.cursor = p.index_of(p.cursor_path)
	p.anchor = p.index_of(p.anchor_path)
	if p.cursor < 0 && p.entries.len > 0 {
		p.cursor = 0
		p.cursor_path = p.entries[0].path
	}
	if p.cursor < 0 { p.cursor_path = '' }
	if p.view == .columns { p.build_columns() }
	p.hidden_btn.value = int(p.show_hidden)
	p.path_field.set_text(p.path)
	p.path_field.cursor = 0
	p.win.set_text(title_prefix + os.base(p.path))
	p.ensure_visible()
	p.update_status()
	p.canvas.invalidate()
}

fn (mut p Pane) navigate(path string, remember bool) {
	target := os.real_path(path)
	if !os.is_dir(target) {
		p.issue = 'Not a folder: ${path}'
		p.canvas.invalidate_paint()
		return
	}
	if target == p.path {
		p.refresh()
		return
	}
	if remember {
		p.history << p.path
		p.ahead = []string{}
	}
	p.path = target
	p.selected = map[string]bool{}
	p.cursor = -1
	p.cursor_path = ''
	p.anchor = -1
	p.anchor_path = ''
	p.top = 0
	p.refresh()
}

fn (mut p Pane) build_columns() {
	mut paths := [p.path]
	mut at := p.path
	for paths.len < 6 {
		parent := os.dir(at)
		if parent == at || parent == '' { break }
		paths.insert(0, parent)
		at = parent
	}
	mut cols := []Column{cap: paths.len}
	for i, path in paths {
		mut entries := read_entries(path, p.show_hidden) or { []Entry{} }
		sort_entries(mut entries, p.sort, p.descending)
		mut cursor := -1
		if i + 1 < paths.len {
			child := os.base(paths[i + 1])
			for j, e in entries {
				if e.name == child {
					cursor = j
					break
				}
			}
		}
		cols << Column{ path: path, entries: entries, cursor: cursor }
	}
	p.cols = cols
}

fn (mut p Pane) list_rows() int {
	return imax(1, p.canvas.rect().h - header_rows)
}

fn (mut p Pane) icon_cols() int {
	return imax(1, p.canvas.rect().w / tile_width)
}

fn (mut p Pane) icon_rows() int {
	return imax(1, p.canvas.rect().h / tile_height)
}

fn (mut p Pane) ensure_visible() {
	if p.entries.len == 0 {
		p.top = 0
		return
	}
	if p.view == .icons {
		cols := p.icon_cols()
		rows := p.icon_rows()
		row := imax(0, p.cursor) / cols
		first := p.top / cols
		if row < first { p.top = row * cols }
		if row >= first + rows { p.top = (row - rows + 1) * cols }
		p.top = iclamp(p.top, 0, imax(0, p.entries.len - 1))
		return
	}
	rows := p.list_rows()
	cursor := imax(0, p.cursor)
	if cursor < p.top { p.top = cursor }
	if cursor >= p.top + rows { p.top = cursor - rows + 1 }
	p.top = iclamp(p.top, 0, imax(0, p.entries.len - rows))
}

fn (mut p Pane) scroll(delta int) {
	if p.entries.len == 0 { return }
	if p.view == .icons {
		step := delta * p.icon_cols()
		p.top = iclamp(p.top + step, 0, imax(0, p.entries.len - 1))
	} else {
		p.top = iclamp(p.top + delta, 0, imax(0, p.entries.len - p.list_rows()))
	}
	p.canvas.invalidate_paint()
}

fn (mut p Pane) update_status() {
	mut parts := []string{}
	if p.issue != '' {
		parts << p.issue
	} else {
		parts << '${p.entries.len} items'
		mut chosen := []Entry{}
		mut total := i64(0)
		for e in p.entries {
			if p.selected[e.path] {
				chosen << e
				total += e.size
			}
		}
		if chosen.len > 0 {
			parts << '${chosen.len} selected (${size_text(total)})'
		}
		if p.view == .list {
			parts << 'List'
		} else if p.view == .icons {
			parts << 'Icons'
		} else {
			parts << 'Columns'
		}
		parts << 'Sort: ${p.sort} ${if p.descending { 'desc' } else { 'asc' }}'
	}
	p.status.set_text(parts.join(' · '))
}

fn (mut p Pane) select_only(index int) {
	p.selected = map[string]bool{}
	if index >= 0 && index < p.entries.len {
		p.selected[p.entries[index].path] = true
		p.anchor = index
		p.anchor_path = p.entries[index].path
	}
}

fn (mut p Pane) range_to(index int) {
	from := if p.anchor >= 0 { p.anchor } else { index }
	lo, hi := if from <= index { from, index } else { index, from }
	p.selected = map[string]bool{}
	for i in lo .. hi + 1 {
		if i >= 0 && i < p.entries.len { p.selected[p.entries[i].path] = true }
	}
}

fn (mut p Pane) toggle(index int) {
	if index < 0 || index >= p.entries.len { return }
	path := p.entries[index].path
	if p.selected[path] { p.selected.delete(path) } else { p.selected[path] = true }
	p.anchor = index
	p.anchor_path = path
}

fn (mut p Pane) chosen() []Entry {
	mut list := []Entry{}
	for e in p.entries {
		if p.selected[e.path] { list << e }
	}
	return list
}

fn (mut p Pane) chosen_paths() []string {
	mut paths := []string{}
	for e in p.entries {
		if p.selected[e.path] { paths << e.path }
	}
	if paths.len == 0 {
		if p.cursor >= 0 && p.cursor < p.entries.len { paths << p.entries[p.cursor].path }
	}
	return paths
}

fn (mut p Pane) cursor_entry() ?Entry {
	if p.cursor < 0 || p.cursor >= p.entries.len { return none }
	return p.entries[p.cursor]
}

fn (mut p Pane) set_cursor(index int, extend bool) {
	if p.entries.len == 0 { return }
	next := iclamp(index, 0, p.entries.len - 1)
	p.cursor = next
	p.cursor_path = p.entries[next].path
	if extend {
		if p.anchor_path == '' {
			p.anchor = next
			p.anchor_path = p.entries[next].path
		}
		p.range_to(next)
	} else {
		p.select_only(next)
	}
	p.ensure_visible()
	p.update_status()
	p.canvas.invalidate_paint()
}

fn (mut p Pane) move_cursor(delta int, extend bool) {
	if p.entries.len == 0 { return }
	base := if p.cursor < 0 { 0 } else { p.cursor + delta }
	p.set_cursor(base, extend)
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
	c.name_w = imax(4, c.size_x - c.name_x - 1)
	return c
}

fn paint_pane(mut c vtk.Ctl, mut s vtk.Screen) {
	mut p := pane_from(c) or { return }
	t := theme_of(p)
	r := c.rect()
	s.fill(r, ` `, t.fg, t.bg)
	if p.issue != '' {
		s.text(r.x + 1, r.y, clip_text(p.issue, imax(1, r.w - 2), ellipsis(s)), vtk.red, t.bg, 0)
		return
	}
	match p.view {
		.list { p.paint_list(mut s, r, t) }
		.icons { p.paint_icons(mut s, r, t) }
		.columns { p.paint_columns(mut s, r, t) }
	}
	if p.marquee {
		band := vtk.Rect{r.x + p.mq_x, r.y + p.mq_y, imax(2, p.mq_x2 - p.mq_x + 1), imax(2, p.mq_y2 - p.mq_y + 1)}
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
	fw := imin(tile.w - 2, 9)
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
	name_x := tile.x + imax(0, (tile.w - vtk.text_width(name)) / 2)
	s.text(name_x, fy + 3, name, fg, bg, attr)
}

fn (p &Pane) column_layout() (int, int) {
	width := p.canvas.rect().w
	if p.cols.len == 0 { return 0, imax(1, width) }
	fit := imax(1, width / column_min)
	first := imax(0, p.cols.len - fit)
	shown := p.cols.len - first
	return first, imax(1, width / imax(1, shown))
}

fn (p &Pane) paint_columns(mut s vtk.Screen, r vtk.Rect, t vtk.Theme) {
	if p.cols.len == 0 { return }
	first, cw := p.column_layout()
	has_focus := focused(p.canvas, p)
	arrow := if p.descending { '▾' } else { '▴' }
	for i := first; i < p.cols.len; i++ {
		col := p.cols[i]
		x := r.x + (i - first) * cw
		last := i == p.cols.len - 1
		w := if last { r.x + r.w - x } else { cw - 1 }
		if w < 4 { continue }
		cursor := if last { p.cursor } else { col.cursor }
		rows := imax(1, r.h - 1)
		top := if last { p.top } else { imax(0, cursor - rows + 1) }
		s.fill(vtk.Rect{x, r.y, w, 1}, ` `, t.accent, t.bg)
		s.text(x, r.y, clip_text(' ${os.base(col.path)} ' + arrow, w, ellipsis(s)), t.accent,
			t.bg, vtk.bold)
		for row in 0 .. rows {
			index := top + row
			if index >= col.entries.len { break }
			e := col.entries[index]
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
	thumb := imax(1, height * visible / imax(1, total))
	at := if total > visible { top * (height - thumb) / imax(1, total - visible) } else { 0 }
	s.fill(vtk.Rect{r.x + r.w - 1, r.y, 1, height}, `░`, t.dim, t.bg)
	s.fill(vtk.Rect{r.x + r.w - 1, r.y + at, 1, thumb}, `█`, t.frame, t.bg)
}

// ---------------------------------------------------------------------------
// Overlay: the floating drag ghost
// ---------------------------------------------------------------------------

fn drag_label(drag Drag, ascii bool) string {
	noun := if drag.paths.len == 1 { '1 item' } else { '${drag.paths.len} items' }
	arrow := if ascii { '>' } else { '→' }
	if drag.target < 0 || drag.target_dir == '' {
		return '${noun} · drop on a folder'
	}
	if !drag.valid {
		return '${noun} · cannot drop here'
	}
	verb := if drag.copy { 'Copy' } else { 'Move' }
	return '${verb} ${noun} ${arrow} ${os.base(drag.target_dir)}'
}

fn ghost_rect(x int, y int, width int, height int) vtk.Rect {
	w := iclamp(width, 8, imax(8, width))
	return vtk.Rect{iclamp(x + 2, 0, imax(0, width - 12)), iclamp(y - 1, 1, imax(1, height - 5)), w, 3}
}

fn draw_overlay(mut app vtk.App, mut s vtk.Screen) {
	mut shared := ?&Shared(none)
	for w in app.window_list() {
		if !files_window(w) { continue }
		if p := pane_from(w) {
			shared = p.shared
			break
		}
	}
	sh := shared or { return }
	drag := sh.drag
	if !drag.active { return }
	t := app.theme
	width, height := app.size()
	label := drag_label(drag, s.ascii)
	w := imin(imax(14, vtk.text_width(label) + 8), imax(8, width - 4))
	mut card := ghost_rect(drag.x, drag.y, width, height)
	card.w = w
	card.x = iclamp(card.x, 0, imax(0, width - w - 1))
	mut back := vtk.Rect{card.x + 1, card.y - 1, card.w, card.h}
	if back.y < 0 { back.y = 0 }
	frame := if drag.target_dir != '' && drag.valid { t.accent } else { vtk.red }
	s.fill(vtk.Rect{card.x + 2, card.y + 1, card.w, card.h}, ` `, vtk.black, vtk.black)
	s.fill(back, ` `, t.menu_fg, t.menu_bg)
	s.frame(back, false, t.dim, t.menu_bg)
	s.fill(card, ` `, t.menu_fg, t.menu_bg)
	s.frame(card, true, frame, t.menu_bg)
	s.text(card.x + 2, card.y + 1, if drag.copy {
		'+'
	} else if s.ascii {
		'>'
	} else {
		'▸'
	},
		frame, t.menu_bg, vtk.bold)
	s.text(card.x + 4, card.y + 1, clip_text(label, card.w - 5, ellipsis(&s)), t.menu_fg,
		t.menu_bg, vtk.bold)
}

// ---------------------------------------------------------------------------
// Drag and drop
// ---------------------------------------------------------------------------

// files_owned reports whether a control lives in a Files window.
fn files_owned(c &vtk.Ctl) bool {
	if c.kind == .window { return files_window(c) }
	parent := c.parent_ctl() or { return false }
	return files_owned(parent)
}

fn pane_at_ctl(c &vtk.Ctl) ?&Pane {
	if !files_owned(c) { return none }
	if c.kind == .canvas {
		if p := pane_from(c) { return p }
	}
	parent := c.parent_ctl() or { return none }
	return pane_at_ctl(parent)
}

fn pane_under(mut app vtk.App, x int, y int) ?&Pane {
	windows := app.window_list()
	for i := windows.len - 1; i >= 0; i-- {
		w := windows[i]
		if w.is_closed() || w.is_minimized() || !w.rect().contains(x, y) { continue }
		if c := w.hit(x, y) { return pane_at_ctl(c) }
	}
	return none
}

fn hit_entry(p &Pane, x int, y int) (int, int) {
	if x < 0 || y < 0 { return -1, -1 }
	match p.view {
		.list {
			if y < header_rows { return -1, -1 }
			index := p.top + y - header_rows
			if index >= p.entries.len { return -1, -1 }
			return -1, index
		}
		.icons {
			cols := p.icon_cols()
			start := (p.top / cols) * cols
			index := start + (y / tile_height) * cols + x / tile_width
			if index >= p.entries.len { return -1, -1 }
			return -1, index
		}
		.columns {
			first, cw := p.column_layout()
			column := first + x / cw
			if column >= p.cols.len { return -1, -1 }
			if y < 1 { return -1, -1 }
			col := p.cols[column]
			rows := imax(1, p.canvas.rect().h - 1)
			top := if column == p.cols.len - 1 { p.top } else { imax(0, col.cursor - rows + 1) }
			index := top + y - 1
			if index >= col.entries.len { return -1, -1 }
			return column, index
		}
	}
}

fn entry_at(p &Pane, column int, row int) ?Entry {
	if column < 0 {
		if row < 0 || row >= p.entries.len { return none }
		return p.entries[row]
	}
	if column >= p.cols.len { return none }
	col := p.cols[column]
	if row < 0 || row >= col.entries.len { return none }
	return col.entries[row]
}

fn update_drag(mut app vtk.App, mut p Pane, e vtk.Event) {
	mut sh := p.shared
	sh.drag.x = e.x
	sh.drag.y = e.y
	sh.drag.copy = e.ctrl
	app.invalidate_area(vtk.Rect{e.x - 2, e.y - 4, 70, 10})
	mut pane_id := -1
	mut dir := ''
	mut column := -1
	mut row := -1
	if over := pane_under(mut app, e.x, e.y) {
		pane_id = over.id
		area := over.canvas.rect()
		col, index := hit_entry(over, e.x - area.x, e.y - area.y)
		if found := entry_at(over, col, index) {
			if found.dir {
				dir = found.path
				column = col
				row = index
			} else {
				dir = if col >= 0 && col < over.cols.len { over.cols[col].path } else { over.path }
			}
		} else {
			dir = if col >= 0 && col < over.cols.len { over.cols[col].path } else { over.path }
		}
	}
	old_pane := sh.drag.target
	sh.drag.target = pane_id
	sh.drag.target_dir = dir
	sh.drag.target_col = column
	sh.drag.target_row = row
	sh.drag.valid = drop_allowed(sh.drag.paths, dir, sh.drag.copy)
	for other in sh.panes {
		if other.id == old_pane || other.id == pane_id { other.canvas.invalidate_paint() }
	}
	app.invalidate_area(vtk.Rect{e.x - 2, e.y - 4, 70, 10})
}

fn begin_drag(mut app vtk.App, mut p Pane, e vtk.Event) {
	mut paths := []string{}
	for entry in p.chosen() { paths << entry.path }
	if paths.len == 0 { return }
	p.pressing = false
	p.shared.drag = Drag{
		active: true
		origin: p.id
		paths:  paths
		x:      e.x
		y:      e.y
	}
	update_drag(mut app, mut p, e)
	app.invalidate()
}

fn cancel_drag(mut app vtk.App, mut p Pane) {
	mut sh := p.shared
	if !sh.drag.active { return }
	old := sh.drag
	sh.drag = Drag{}
	for other in sh.panes {
		if other.id == old.origin || other.id == old.target { other.canvas.invalidate_paint() }
	}
	app.invalidate_area(vtk.Rect{old.x - 2, old.y - 4, 70, 10})
}

fn finish_drag(mut app vtk.App, mut p Pane, e vtk.Event) {
	update_drag(mut app, mut p, e)
	drag := p.shared.drag
	for other in p.shared.panes {
		if other.id == drag.origin || other.id == drag.target { other.canvas.invalidate_paint() }
	}
	app.invalidate_area(vtk.Rect{drag.x - 2, drag.y - 4, 70, 10})
	if drag.target < 0 || !drag.valid {
		p.shared.drag = Drag{}
		return
	}
	transfer(mut app, mut p, drag.paths, drag.target_dir, drag.copy)
	p.shared.drag = Drag{}
}

fn transfer(mut app vtk.App, mut p Pane, paths []string, dest string, copy bool) {
	sh := p.shared
	mut moved := 0
	mut failures := []string{}
	for path in paths {
		target := unique_target(path, dest)
		if copy {
			os.cp_all(path, target, false) or {
				failures << '${os.base(path)}: ${err.msg()}'
				continue
			}
		} else {
			os.mv(path, target, overwrite: false) or {
				failures << '${os.base(path)}: ${err.msg()}'
				continue
			}
		}
		moved++
	}
	for other in sh.panes {
		if other.path == dest || paths.any(os.dir(it) == other.path) { other.refresh() }
	}
	if failures.len > 0 {
		app.notify(failures[0], 4000)
	}
	if moved > 0 {
		verb := if copy { 'Copied' } else { 'Moved' }
		noun := if moved == 1 { '1 item' } else { '${moved} items' }
		app.notify('${verb} ${noun} to ${os.base(dest)}', 2500)
	}
	p.update_status()
}

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

fn (mut p Pane) press(x int, y int, e vtk.Event, mut app vtk.App) {
	column, row := hit_entry(p, x, y)
	p.pressing = true
	p.press_x = e.x
	p.press_y = e.y
	p.press_row = row
	p.press_empty = row < 0
	p.marquee = false
	if row < 0 {
		p.press_empty = true
		if !e.ctrl && !e.shift {
			p.selected = map[string]bool{}
			p.anchor = -1
			p.anchor_path = ''
			p.update_status()
			p.canvas.invalidate_paint()
		}
		return
	}
	entry := entry_at(p, column, row) or { return }
	now := time.ticks()
	double := now - p.last_click < 400 && p.last_path == entry.path
	p.last_click = now
	p.last_path = entry.path
	if double {
		p.open(mut app, entry)
		p.pressing = false
		return
	}
	if column >= 0 && column < p.cols.len - 1 {
		// Ancestor column: jump to that folder.
		dir := if entry.dir { entry.path } else { p.cols[column].path }
		p.navigate(dir, true)
		p.pressing = false
		return
	}
	index := if column < 0 { row } else { row }
	if column >= 0 && column < p.cols.len {
		// Rows in an ancestor column are mapped through that column's entries.
		p.selected = map[string]bool{
			entry.path: true
		}
		p.anchor = -1
		p.anchor_path = entry.path
		p.update_status()
		p.canvas.invalidate_paint()
		return
	}
	if e.ctrl {
		p.toggle(index)
		p.cursor = index
		p.cursor_path = entry.path
	} else if e.shift && p.anchor >= 0 {
		p.range_to(index)
		p.cursor = index
		p.cursor_path = entry.path
	} else if !p.selected[entry.path] {
		p.select_only(index)
		p.cursor = index
		p.cursor_path = entry.path
	} else {
		p.cursor = index
		p.cursor_path = entry.path
	}
	p.ensure_visible()
	p.update_status()
	p.canvas.invalidate_paint()
}

fn (mut p Pane) drag_motion(x int, y int, e vtk.Event, mut app vtk.App) {
	dx := e.x - p.press_x
	dy := e.y - p.press_y
	if p.press_empty {
		if dx * dx + dy * dy < 4 { return }
		p.marquee = true
		p.marquee_select(x, y)
		return
	}
	if !p.marquee && dx * dx + dy * dy >= 4 {
		begin_drag(mut app, mut p, e)
	}
}

fn (mut p Pane) marquee_select(x int, y int) {
	area := p.canvas.rect()
	lo_x := imin(p.press_x - area.x, x)
	lo_y := imin(p.press_y - area.y, y)
	hi_x := imax(p.press_x - area.x, x)
	hi_y := imax(p.press_y - area.y, y)
	p.mq_x, p.mq_y, p.mq_x2, p.mq_y2 = lo_x, lo_y, hi_x, hi_y
	p.selected = map[string]bool{}
	match p.view {
		.icons {
			cols := p.icon_cols()
			start := (p.top / cols) * cols
			for index, entry in p.entries {
				slot := index - start
				if slot < 0 { continue }
				tx := (slot % cols) * tile_width
				ty := (slot / cols) * tile_height
				if tx + tile_width > lo_x && tx <= hi_x && ty + tile_height > lo_y && ty <= hi_y {
					p.selected[entry.path] = true
				}
			}
		}
		.list {
			for index, entry in p.entries {
				row_y := index - p.top + header_rows
				if row_y >= lo_y && row_y <= hi_y { p.selected[entry.path] = true }
			}
		}
		.columns {}
	}
	p.update_status()
	p.canvas.invalidate_paint()
}

fn (mut p Pane) release(x int, y int, mut app vtk.App) {
	p.pressing = false
	p.marquee = false
	_ = x
	_ = y
	_ = app
}

fn pane_mouse(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut p := pane_from(c) or { return false }
	if e.button == .wheel_up || e.button == .wheel_down {
		if e.button == .wheel_up { p.scroll(-3) } else { p.scroll(3) }
		return true
	}
	area := c.rect()
	lx, ly := e.x - area.x, e.y - area.y
	if e.pressed && !e.motion && e.button == .left {
		if p.shared.drag.active {
			cancel_drag(mut app, mut p)
			return true
		}
		p.press(lx, ly, e, mut app)
		return true
	}
	if p.shared.drag.active {
		if !e.pressed && !e.motion && e.button == .left {
			finish_drag(mut app, mut p, e)
		} else {
			update_drag(mut app, mut p, e)
		}
		return true
	}
	if p.pressing {
		if e.motion {
			p.drag_motion(lx, ly, e, mut app)
		} else if !e.pressed && !e.motion {
			p.release(lx, ly, mut app)
		}
		return true
	}
	return true
}

// ---------------------------------------------------------------------------
// Opening, renaming, deleting
// ---------------------------------------------------------------------------

fn (mut p Pane) open(mut app vtk.App, e Entry) {
	if e.dir {
		p.navigate(e.path, true)
		return
	}
	spawn open_path(e.path)
	app.notify('Opening ${e.name}', 1500)
}

fn (mut p Pane) activate(mut app vtk.App) {
	if entry := p.cursor_entry() { p.open(mut app, entry) }
}

fn (mut p Pane) rename_cursor(mut app vtk.App) {
	entry := p.cursor_entry() or { return }
	name := app.prompt_for(none, 'Rename', 'New name for ${entry.name}', entry.name) or { return }
	if name == '' || name == entry.name { return }
	target := os.join_path(p.path, name)
	if os.exists(target) {
		app.msgbox_for(none, 'Rename', '${name} already exists')
		return
	}
	os.mv(entry.path, target) or {
		app.msgbox_for(none, 'Rename', err.msg())
		return
	}
	p.cursor_path = target
	p.refresh()
}

fn (mut p Pane) delete_selection(mut app vtk.App) {
	paths := p.chosen_paths()
	if paths.len == 0 { return }
	question := if paths.len == 1 {
		'Delete ${os.base(paths[0])}?'
	} else {
		'Delete ${paths.len} items?'
	}
	if !app.confirm_for(none, 'Delete', question) { return }
	mut failed := ''
	for path in paths {
		if os.is_dir(path) {
			os.rmdir_all(path) or { failed = err.msg() }
		} else {
			os.rm(path) or { failed = err.msg() }
		}
	}
	if failed != '' { app.msgbox_for(none, 'Delete', failed) }
	p.selected = map[string]bool{}
	p.refresh()
}

fn (mut p Pane) new_folder(mut app vtk.App) {
	name := app.prompt_for(none, 'New folder', 'Folder name', 'untitled') or { return }
	if name == '' { return }
	path := os.join_path(p.path, name)
	os.mkdir(path) or {
		app.msgbox_for(none, 'New folder', err.msg())
		return
	}
	p.cursor_path = path
	p.refresh()
}

// import_text copies paths pasted or dropped from the host into the pane.
fn (mut p Pane) import_text(mut app vtk.App, text string) bool {
	paths := paste_paths(text)
	if paths.len == 0 { return false }
	transfer(mut app, mut p, paths, p.path, true)
	return true
}

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

fn pane_key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut p := pane_from(c) or { return false }
	if e.kind == .paste {
		return p.import_text(mut app, e.text)
	}
	if e.kind != .key { return false }
	key := e.key
	if p.shared.drag.active && key == int(vtk.Key.escape) {
		cancel_drag(mut app, mut p)
		return true
	}
	if key == int(vtk.Key.escape) {
		if p.selected.len > 0 {
			p.selected = map[string]bool{}
			p.update_status()
			p.canvas.invalidate_paint()
			return true
		}
		return false
	}
	if e.ctrl {
		match key {
			`a` {
				p.selected = map[string]bool{}
				for entry in p.entries { p.selected[entry.path] = true }
				p.update_status()
				p.canvas.invalidate_paint()
				return true
			}
			`h` {
				p.show_hidden = !p.show_hidden
				p.refresh()
				return true
			}
			`n` {
				new_files_window(mut app, p.shared, p.path)
				return true
			}
			`q` {
				app.close(mut p.win)
				return true
			}
			`r` {
				p.refresh()
				return true
			}
			`l` {
				app.set_focus(p.path_field)
				return true
			}
			`v` {
				return p.import_text(mut app, app.clipboard_text())
			}
			else {}
		}
	}
	if e.alt && key == int(vtk.Key.left) {
		p.go_back()
		return true
	}
	if e.alt && key == int(vtk.Key.right) {
		p.go_forward()
		return true
	}
	match key {
		int(vtk.Key.up) {
			step := if p.view == .icons { -p.icon_cols() } else { -1 }
			p.move_cursor(step, e.shift)
			return true
		}
		int(vtk.Key.down) {
			step := if p.view == .icons { p.icon_cols() } else { 1 }
			p.move_cursor(step, e.shift)
			return true
		}
		int(vtk.Key.left) {
			if p.view == .icons && !e.shift {
				p.move_cursor(-1, false)
			} else {
				p.go_up()
			}
			return true
		}
		int(vtk.Key.right) {
			if p.view == .icons && !e.shift {
				p.move_cursor(1, false)
			} else {
				p.activate(mut app)
			}
			return true
		}
		int(vtk.Key.home) {
			p.set_cursor(0, e.shift)
			return true
		}
		int(vtk.Key.end) {
			p.set_cursor(p.entries.len - 1, e.shift)
			return true
		}
		int(vtk.Key.page_up) {
			step := if p.view == .icons { -p.icon_cols() * p.icon_rows() } else { -p.list_rows() }
			p.move_cursor(step, e.shift)
			return true
		}
		int(vtk.Key.page_down) {
			step := if p.view == .icons { p.icon_cols() * p.icon_rows() } else { p.list_rows() }
			p.move_cursor(step, e.shift)
			return true
		}
		int(vtk.Key.enter) {
			p.activate(mut app)
			return true
		}
		int(vtk.Key.backspace) {
			p.go_up()
			return true
		}
		int(vtk.Key.delete) {
			p.delete_selection(mut app)
			return true
		}
		int(vtk.Key.space) {
			if p.cursor >= 0 {
				p.toggle(p.cursor)
				p.update_status()
				p.canvas.invalidate_paint()
			}
			return true
		}
		int(vtk.Key.f2) {
			p.rename_cursor(mut app)
			return true
		}
		int(vtk.Key.f3) {
			p.cycle_view()
			return true
		}
		int(vtk.Key.f5) {
			p.refresh()
			return true
		}
		else {
			if !e.ctrl && !e.alt && key >= 32 && key < 127 {
				p.type_ahead(rune(key).str())
				return true
			}
		}
	}
	return false
}

fn (mut p Pane) type_ahead(text string) {
	if time.ticks() - p.typed_at > 900 { p.typed = '' }
	p.typed += text.to_lower()
	p.typed_at = time.ticks()
	for i, entry in p.entries {
		if entry.name.to_lower().starts_with(p.typed) {
			p.set_cursor(i, false)
			p.scroll_cursor()
			return
		}
	}
}

fn (mut p Pane) scroll_cursor() {
	p.ensure_visible()
	p.canvas.invalidate_paint()
}

fn (mut p Pane) cycle_view() {
	p.view = match p.view {
		.list { View.icons }
		.icons { View.columns }
		.columns { View.list }
	}
	p.top = 0
	if p.view == .columns { p.build_columns() }
	p.update_status()
	p.canvas.invalidate()
}

fn (mut p Pane) go_up() {
	parent := os.dir(p.path)
	if parent != p.path { p.navigate(parent, true) }
}

fn (mut p Pane) go_back() {
	if p.history.len == 0 { return }
	previous := p.history.pop()
	p.ahead << p.path
	p.navigate(previous, false)
}

fn (mut p Pane) go_forward() {
	if p.ahead.len == 0 { return }
	next := p.ahead.pop()
	p.history << p.path
	p.navigate(next, false)
}

// ---------------------------------------------------------------------------
// Toolbar and window creation
// ---------------------------------------------------------------------------

fn toolbar_back(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.go_back()
}

fn toolbar_forward(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.go_forward()
}

fn toolbar_up(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.go_up()
}

fn toolbar_home(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.navigate(os.home_dir(), true)
}

fn toolbar_refresh(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.refresh()
}

fn toolbar_new_folder(mut c vtk.Ctl, mut app vtk.App) {
	mut p := pane_from(c) or { return }
	p.new_folder(mut app)
}

fn toolbar_hidden(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	p.show_hidden = !p.show_hidden
	c.value = int(p.show_hidden)
	p.refresh()
}

fn toolbar_new_window(mut c vtk.Ctl, mut app vtk.App) {
	mut p := pane_from(c) or { return }
	new_files_window(mut app, p.shared, p.path)
}

fn set_view(mut p Pane, view View) {
	p.view = view
	p.top = 0
	if view == .columns { p.build_columns() }
	p.update_status()
	p.canvas.invalidate()
}

fn toolbar_list(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	set_view(mut p, .list)
}

fn toolbar_icons(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	set_view(mut p, .icons)
}

fn toolbar_columns(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	set_view(mut p, .columns)
}

fn toolbar_sort(mut c vtk.Ctl, mut app vtk.App) {
	menu := c.context_menu() or { return }
	area := c.rect()
	app.open_menu(menu, area.x, area.y + 1)
}

fn choose_sort(mut c vtk.Ctl, mut _ vtk.App) {
	mut p := pane_from(c) or { return }
	by := SortBy.from(c.data) or { return }
	if p.sort == by {
		p.descending = !p.descending
	} else {
		p.sort = by
		p.descending = false
	}
	p.entries = read_entries(p.path, p.show_hidden) or { []Entry{} }
	sort_entries(mut p.entries, p.sort, p.descending)
	p.cursor = p.index_of(p.cursor_path)
	if p.view == .columns { p.build_columns() }
	p.update_status()
	p.canvas.invalidate_paint()
}

fn path_submitted(mut c vtk.Ctl, mut app vtk.App) {
	mut p := pane_from(c) or { return }
	text := c.text.trim_space()
	if text == '' { return }
	target := os.expand_tilde_to_home(text)
	if os.is_file(target) && os.is_abs_path(target) {
		p.navigate(os.dir(target), true)
		p.cursor_path = os.real_path(target)
		p.cursor = p.index_of(p.cursor_path)
		p.select_only(p.cursor)
		p.ensure_visible()
	} else {
		p.navigate(target, true)
	}
	app.set_focus(p.canvas)
}

fn copy_focused_selection(mut app vtk.App) {
	if f := app.focused_ctl() {
		if p := pane_from(f) {
			mut paths := []string{}
			for path in p.chosen_paths() { paths << path }
			app.clipboard_set(paths.join('\n'))
			if paths.len > 0 { app.notify('Copied ${paths.len} path(s)', 1500) }
			return
		}
	}
}

fn window_destroyed(mut c vtk.Ctl, mut _ vtk.App) {
	p := pane_from(c) or { return }
	mut sh := p.shared
	if sh.drag.active && sh.drag.origin == p.id {
		sh.drag = Drag{}
	}
	for i, other in sh.panes {
		if other.id == p.id {
			sh.panes.delete(i)
			break
		}
	}
}

fn next_id(sh &Shared) int {
	mut highest := -1
	for p in sh.panes { highest = imax(highest, p.id) }
	return highest + 1
}

fn new_files_window(mut app vtk.App, shared &Shared, path string) &Pane {
	// The drag ghost spans every window, so Files owns the app overlay.
	app.overlay = draw_overlay
	resolved := os.real_path(path)
	start := if os.is_dir(resolved) { resolved } else { os.home_dir() }
	mut win := app.window('Files', 84, 24)
	win.destroy = window_destroyed
	win.set_size_limits(40, 8, 0, 0)

	mut tools := vtk.toolbar()
	mut back := vtk.toolbutton('←')
	mut fwd := vtk.toolbutton('→')
	mut up := vtk.toolbutton('↑')
	mut home := vtk.toolbutton('~')
	mut refresh := vtk.toolbutton('R')
	mut folder := vtk.toolbutton('+')
	mut hidden := vtk.toolbutton('H')
	mut newwin := vtk.toolbutton('New window')
	mut list := vtk.toolbutton('List')
	mut icons := vtk.toolbutton('Icons')
	mut columns := vtk.toolbutton('Cols')
	mut sort_btn := vtk.toolbutton('Sort')
	mut field := vtk.entry(start, 0)
	mut status := vtk.statusbar('')
	mut canvas := vtk.canvas(20, 10, paint_pane)
	mut p := &Pane{
		id:         next_id(shared)
		shared:     shared
		win:        win
		canvas:     canvas
		status:     status
		path_field: field
		hidden_btn: hidden
		path:       start
		selected:   map[string]bool{}
		sort:       .name
		view:       .list
	}
	win.set_context(p)
	field.expand = true
	field.submit = path_submitted

	mut buttons := [back, fwd, up, home, refresh, folder, hidden, newwin, list, icons, columns,
		sort_btn]
	for mut button in buttons {
		button.set_context(p)
	}
	back.changed = toolbar_back
	fwd.changed = toolbar_forward
	up.changed = toolbar_up
	home.changed = toolbar_home
	refresh.changed = toolbar_refresh
	folder.changed = toolbar_new_folder
	hidden.changed = toolbar_hidden
	newwin.changed = toolbar_new_window
	list.changed = toolbar_list
	icons.changed = toolbar_icons
	columns.changed = toolbar_columns
	sort_btn.changed = toolbar_sort

	mut sort_menu := vtk.context_menu()
	for entry in sort_entries {
		mut item := sort_menu.menu_item(entry.label, choose_sort)
		item.data = i64(int(entry.by))
		item.set_context(p)
	}
	sort_btn.set_menu(mut sort_menu)

	canvas.expand = true
	canvas.focusable = true
	canvas.mouse_capture = true
	canvas.set_context(p)
	canvas.mousefn = pane_mouse
	canvas.keyfn = pane_key

	tools.add(mut back)
	tools.add(mut fwd)
	tools.add(mut up)
	tools.add(mut home)
	tools.add(mut refresh)
	tools.add(mut folder)
	tools.add(mut hidden)
	tools.add(mut newwin)
	tools.add(mut list)
	tools.add(mut icons)
	tools.add(mut columns)
	tools.add(mut sort_btn)
	tools.add(mut field)

	mut body := vtk.box(true)
	body.add(mut tools)
	body.add(mut canvas)
	body.add(mut status)
	win.add(mut body)
	p.shared.panes << p
	p.refresh()
	app.set_focus(canvas)
	return p
}

// shared_for reuses the drag state of an open Files window, so dropping works
// between windows opened from the desktop menu as well.
fn shared_for(mut app vtk.App) &Shared {
	for w in app.window_list() {
		if w.is_closed() || !files_window(w) { continue }
		if p := pane_from(w) { return p.shared }
	}
	return &Shared{ app: app }
}

pub fn launch(mut app vtk.App) {
	new_files_window(mut app, shared_for(mut app), os.home_dir())
}

pub fn run() {
	mut app := vtk.new_app()
	app.start_programs = true
	app.ctrl_c = .callback
	app.ctrl_c_handler = copy_focused_selection
	app.native_clipboard = true
	mut rest := os.args[1..].filter(!it.starts_with('--'))
	start := if rest.len > 0 { rest[0] } else { os.home_dir() }
	snapshot := '--snapshot' in os.args
	if snapshot {
		app.dispatch(vtk.Event{ kind: .resize, width: 100, height: 30 })
	} else {
		app.init() or {
			eprintln(err)
			return
		}
	}
	defer { app.fini() }
	mut pane := new_files_window(mut app, shared_for(mut app), start)
	if '--icons' in os.args { set_view(mut pane, .icons) }
	if '--columns' in os.args { set_view(mut pane, .columns) }
	if snapshot {
		app.redraw()
		println(app.snapshot())
		return
	}
	app.notify('Ctrl-N opens another Files window. Drag with the mouse; Ctrl copies, Shift moves. Pasting file paths imports them.', 7000)
	app.run() or { eprintln(err) }
}
