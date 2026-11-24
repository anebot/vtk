module files

import arrays
import math
import os
import time
import vtk

enum SortBy {
	name
	size
	kind
	date
}

const scan_limit = 5000

struct Entry {
	name     string
	path     string
	dir      bool
	link     bool
	size     i64
	modified i64
	ext      string
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

// ---------------------------------------------------------------------------
// File system
// ---------------------------------------------------------------------------

fn read_entries(dir string, hidden bool) !([]Entry, bool) {
	names := os.ls(dir)!
	limit := math.min(names.len, scan_limit)
	mut entries := []Entry{cap: limit}
	for name in names[..limit] {
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
	return entries, names.len > scan_limit
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

fn (mut p Pane) index_of(path string) int {
	for i, e in p.entries {
		if e.path == path { return i }
	}
	return -1
}

fn (mut p Pane) sort_listing() {
	sort_entries(mut p.entries, p.sort, p.descending)
	p.cursor = p.index_of(p.cursor_path)
	p.anchor = p.index_of(p.anchor_path)
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
	for path in paths[..paths.len - 1] {
		entries, capped := read_entries(path, p.show_hidden) or { []Entry{}, false }
		cols << Column{ path: path, entries: entries, scan_capped: capped }
	}
	// The last column displays the pane's current listing.
	cols << Column{ path: p.path }
	p.cols = cols
	p.sort_columns()
}

fn (mut p Pane) sort_columns() {
	for i in 0 .. p.cols.len - 1 {
		child := os.base(p.cols[i + 1].path)
		mut col := &p.cols[i]
		sort_entries(mut col.entries, p.sort, p.descending)
		col.cursor = -1
		for j, entry in col.entries {
			if entry.name == child {
				col.cursor = j
				break
			}
		}
	}
}

// import_text copies paths pasted or dropped from the host into the pane.
fn (mut p Pane) import_text(mut app vtk.App, text string) bool {
	paths := paste_paths(text)
	if paths.len == 0 { return false }
	transfer(mut app, mut p, paths, p.path, true)
	return true
}
