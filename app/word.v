// V translation of the HTK Markdown editor in examples/word.hc.
module main

import os
import vtk

@[heap]
struct Document {
mut:
	window      &vtk.Ctl = unsafe { nil }
	view        &vtk.Ctl = unsafe { nil }
	outline     &vtk.Ctl = unsafe { nil }
	status      &vtk.Ctl = unsafe { nil }
	toolbar     &vtk.Ctl = unsafe { nil }
	path        string
	saved       string
	view_items  []&vtk.Ctl
	wrap_items  []&vtk.Ctl
	page_items  []&vtk.Ctl
	align_items []&vtk.Ctl
}

fn update(mut doc Document) {
	name := if doc.path == '' { '[Untitled]' } else { os.file_name(doc.path) }
	doc.window.text = name + (if doc.view.text != doc.saved { ' *' } else { '' }) + ' - VTK Word'
	doc.outline.clear()
	mut at := 0
	for line in doc.view.text.split('\n') {
		if line.starts_with('#') {
			mut node := doc.outline.tree_add(none, line.trim_left('# '))
			node.data = at
		}
		at += line.len + 1
	}
	refresh_status(mut doc)
}

fn status_text(mut doc Document) string {
	line, col := doc.view.caret_line_column()
	name := if doc.path == '' { '[Untitled]' } else { os.file_name(doc.path) }
	mode := if doc.view.md.mode in [.read, .source_read] { 'View' } else { 'Edit' }
	mut text := '${mode} | ${line}:${col} | ${doc.view.text.len} bytes | ${doc.view.text.fields().len} words | ${doc.view.text.runes().len} chars | ${name}'
	if doc.view.vim.enabled { text += ' | ${doc.view.vim.mode}' }
	return text
}

fn refresh_status(mut doc Document) bool {
	text := status_text(mut doc)
	if text == doc.status.text { return false }
	doc.status.text = text
	return true
}

fn schedule_status(mut app vtk.App, mut doc Document) {
	app.after(0, fn [mut doc] (mut app vtk.App) {
		if refresh_status(mut doc) { app.invalidate() }
	})
}

fn mouse_status(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	if e.button == .left {
		mut doc := unsafe { &Document(c.user) }
		schedule_status(mut app, mut doc)
	}
	return false
}

fn changed(mut c vtk.Ctl, mut app vtk.App) {
	mut doc := unsafe { &Document(c.user) }
	update(mut doc)
	app.invalidate()
}

struct Prefs {
mut:
	outline_hidden bool
	toolbar_hidden bool
	mode           vtk.MarkdownMode
	wrap           vtk.TextWrapMode
	vim            bool
	vim_set        bool
	line_numbers   bool
	ruler_top      bool
	ruler_left     bool
	page_width     int = 80
}

fn prefs_file() string {
	return os.join_path(os.home_dir(), '.vtk-word.ini')
}

fn markdown_mode_from_int(value int) vtk.MarkdownMode {
	return match value {
		1 { .source }
		2 { .read }
		3 { .source_read }
		else { .edit }
	}
}

fn wrap_mode_from_int(value int) vtk.TextWrapMode {
	return match value {
		1 { .character }
		2 { .word }
		else { .none }
	}
}

fn load_prefs() Prefs {
	mut prefs := Prefs{}
	text := os.read_file(prefs_file()) or { return prefs }
	for line in text.split_into_lines() {
		trim := line.trim_space()
		if trim == '' || trim.starts_with('#') { continue }
		parts := trim.split_nth('=', 2)
		if parts.len != 2 { continue }
		name := parts[0].trim_space()
		value := parts[1].trim_space()
		match name {
			'outline_hidden' { prefs.outline_hidden = value == '1' }
			'toolbar_hidden' { prefs.toolbar_hidden = value == '1' }
			'mode' { prefs.mode = markdown_mode_from_int(value.int()) }
			'wrap' { prefs.wrap = wrap_mode_from_int(value.int()) }
			'vim' {
				prefs.vim = value == '1'
				prefs.vim_set = true
			}
			'line_numbers' { prefs.line_numbers = value == '1' }
			'ruler_top' { prefs.ruler_top = value == '1' }
			'ruler_left' { prefs.ruler_left = value == '1' }
			'page_width' { prefs.page_width = if value.int() > 0 { value.int() } else { 0 } }
			else {}
		}
	}
	return prefs
}

fn save_prefs(doc &Document) {
	lines := [
		'outline_hidden = ${int(doc.outline.hidden)}',
		'toolbar_hidden = ${int(doc.toolbar.hidden)}',
		'mode = ${int(doc.view.md.mode)}',
		'wrap = ${int(doc.view.wrap_mode())}',
		'vim = ${int(doc.view.vim.enabled)}',
		'line_numbers = ${int(doc.view.line_numbers)}',
		'ruler_top = ${int(doc.view.md.ruler_top)}',
		'ruler_left = ${int(doc.view.md.ruler_left)}',
		'page_width = ${doc.view.md.column_width}',
	]
	os.write_file(prefs_file(), lines.join('\n') + '\n') or { return }
}

const view_names = ['Outline', 'Toolbar', 'Source', 'Read only', 'Vim mode']
const view_ids = [17, 34, 18, 19, 20]
const wrap_names = ['Disabled', 'Character', 'Word']
const page_names = ['Line numbers', 'Top ruler', 'Left ruler']
const align_names = ['Left', 'Center', 'Right', 'Justify']
const app_name = 'VtkWord'
const app_version = '0.1.0'
const font_styles = [vtk.FontStyle.none, .bold, .italic, .script, .doublestruck, .underline,
	.strikethrough, .fraktur, .bolditalic, .sansserif, .sansserifitalic, .monospace, .boldscript,
	.boldfraktur, .sansserifbold, .sansserifbolditalic, .openface, .smallcaps]

fn ticked(name string, on bool) string {
	return if on { '✓ ${name}' } else { '  ${name}' }
}

fn sync_view_menu(mut doc Document) {
	mode := doc.view.md.mode
	shown := [!doc.outline.hidden, !doc.toolbar.hidden, mode in [.source, .source_read],
		mode in [.read, .source_read], doc.view.vim.enabled]
	for i, mut item in doc.view_items {
		item.text = ticked(view_names[i], shown[i])
	}
}

fn sync_wrap_menu(mut doc Document) {
	mode := int(doc.view.wrap_mode())
	for i, mut item in doc.wrap_items {
		item.text = ticked(wrap_names[i], i == mode)
	}
}

fn sync_page_menu(mut doc Document) {
	shown := [doc.view.line_numbers, doc.view.md.ruler_top, doc.view.md.ruler_left]
	for i, mut item in doc.page_items {
		item.text = ticked(page_names[i], shown[i])
	}
}

fn sync_align_menu(mut doc Document) {
	start, _ := doc.view.selection()
	align := doc.view.markdown_align_at(start)
	for i, mut item in doc.align_items {
		item.text = ticked(align_names[i], int(align) == i + 1)
	}
}

fn outline_hit(mut c vtk.Ctl, mut app vtk.App) {
	mut doc := unsafe { &Document(c.user) }
	if node := c.tree_selection() {
		doc.view.scroll_to_offset(int(node.data))
		app.set_focus(doc.view)
		refresh_status(mut doc)
		app.invalidate()
	}
}

fn save(mut doc Document, save_as bool, mut app vtk.App) bool {
	mut path := doc.path
	if path == '' || save_as {
		path = app.prompt_for(doc.window, 'Save Markdown', 'File path:', path) or { return false }
	}
	if path == '' { return false }
	if path != doc.path && os.exists(path) {
		if !app.confirm_for(doc.window, 'Replace file', 'Replace ${path}?') { return false }
	}
	doc.view.end_edit_group()
	vtk.save_atomic(path, doc.view.text) or {
		app.notify(err.msg(), 3000)
		return false
	}
	doc.path = path
	doc.saved = doc.view.text
	update(mut doc)
	app.notify('Saved ${path}', 1500)
	return true
}

fn closing(mut w vtk.Ctl, mut app vtk.App) bool {
	mut doc := unsafe { &Document(w.user) }
	if doc.view.text == doc.saved { return true }
	choice := app.choice_for(w, 'Unsaved changes', ['Save', 'Discard', 'Cancel'], 3)
	if choice == 0 { return save(mut doc, false, mut app) }
	return choice == 1
}

fn wrap(mut doc Document, prefix string, suffix string) {
	a, b := doc.view.selection()
	text := doc.view.text[a..b]
	doc.view.replace_range(a, b, prefix + text + suffix)
	doc.view.cursor = a + prefix.len + text.len
}

const table_max_columns = 12
const table_max_rows = 50

fn table_markdown(columns int, rows int) string {
	mut out := '|'
	for _ in 0 .. columns { out += '   |' }
	out += '\n|'
	for _ in 0 .. columns { out += '---|' }
	for _ in 0 .. rows {
		out += '\n|'
		for _ in 0 .. columns { out += '   |' }
	}
	return out
}

@[heap]
struct TablePrompt {
mut:
	window  &vtk.Ctl = unsafe { nil }
	columns &vtk.Ctl = unsafe { nil }
	rows    &vtk.Ctl = unsafe { nil }
	result  string
}

fn table_prompt_accept(mut c vtk.Ctl, mut app vtk.App) {
	mut prompt := unsafe { &TablePrompt(c.user) }
	if int(c.data) == 1 {
		prompt.result = table_markdown(prompt.columns.value, prompt.rows.value)
	}
	app.close(mut prompt.window)
}

@[heap]
struct FindState {
mut:
	doc     &Document = unsafe { nil }
	window  &vtk.Ctl  = unsafe { nil }
	query   &vtk.Ctl  = unsafe { nil }
	replace &vtk.Ctl  = unsafe { nil }
}

fn find_hit(text string, query string, from int, forward bool) int {
	start := vtk.clamp(from, 0, text.len)
	if forward {
		at := text[start..].index(query) or { -1 }
		if at >= 0 { return start + at }
		if start > 0 { return text[..start].index(query) or { -1 } }
	} else {
		if start > 0 {
			at := text[..start].last_index(query) or { -1 }
			if at >= 0 { return at }
		}
		if start < text.len {
			at := text[start..].last_index(query) or { -1 }
			if at >= 0 { return start + at }
		}
	}
	return -1
}

fn find_step(mut state FindState, forward bool, quiet bool, mut app vtk.App) {
	query := state.query.text
	if query == '' {
		app.notify('Enter text to find', 1500)
		app.set_focus(state.query)
		return
	}
	mut doc := state.doc
	mut view := doc.view
	a, b := view.selection()
	hit := find_hit(view.text, query, if forward { b } else { a }, forward)
	if hit < 0 {
		if !quiet { app.notify('Text not found', 1500) }
		return
	}
	view.anchor = hit
	view.cursor = hit + query.len
	view.scroll_hold = false
	view.invalidate()
	if refresh_status(mut doc) { app.invalidate() }
}

fn find_replace(mut state FindState, mut app vtk.App) {
	query := state.query.text
	if query == '' {
		app.notify('Enter text to find', 1500)
		app.set_focus(state.query)
		return
	}
	mut doc := state.doc
	mut view := doc.view
	if view.readonly {
		app.notify('Read only', 1500)
		return
	}
	a, b := view.selection()
	mut at := a
	if b - a != query.len || view.text[a..b] != query {
		at = find_hit(view.text, query, b, true)
		if at < 0 {
			app.notify('Text not found', 1500)
			return
		}
	}
	view.replace_range(at, at + query.len, state.replace.text)
	find_step(mut state, true, true, mut app)
}

fn find_replace_all(mut state FindState, mut app vtk.App) {
	query := state.query.text
	replacement := state.replace.text
	if query == '' {
		app.notify('Enter text to find', 1500)
		app.set_focus(state.query)
		return
	}
	mut doc := state.doc
	mut view := doc.view
	if view.readonly {
		app.notify('Read only', 1500)
		return
	}
	if query == replacement {
		app.notify('Replacement is the same', 1500)
		return
	}
	text := view.text
	mut out := ''
	mut at := 0
	mut count := 0
	for {
		hit := text[at..].index(query) or { break }
		out += text[at..at + hit] + replacement
		at += hit + query.len
		count++
	}
	if count == 0 {
		app.notify('Text not found', 1500)
		return
	}
	out += text[at..]
	first := text.index(query) or { 0 }
	view.replace_range(0, text.len, out)
	view.anchor = first
	view.cursor = first + replacement.len
	view.scroll_hold = false
	view.invalidate()
	if refresh_status(mut doc) { app.invalidate() }
	app.notify('${count} replacement${if count == 1 { '' } else { 's' }}', 1500)
}

fn find_submit(mut c vtk.Ctl, mut app vtk.App) {
	mut state := unsafe { &FindState(c.user) }
	find_step(mut state, true, false, mut app)
}

fn find_replace_submit(mut c vtk.Ctl, mut app vtk.App) {
	mut state := unsafe { &FindState(c.user) }
	find_replace(mut state, mut app)
}

fn find_action(mut c vtk.Ctl, mut app vtk.App) {
	mut state := unsafe { &FindState(c.user) }
	match c.data {
		1 { find_step(mut state, false, false, mut app) }
		2 { find_step(mut state, true, false, mut app) }
		3 { find_replace(mut state, mut app) }
		4 { find_replace_all(mut state, mut app) }
		else { app.close(mut state.window) }
	}
}

fn find_dialog(mut doc Document, mut app vtk.App, focus_replace bool) {
	a, b := doc.view.selection()
	initial := if b > a && !doc.view.text[a..b].contains('\n') { doc.view.text[a..b] } else { '' }
	mut state := &FindState{ doc: doc }
	mut query := vtk.entry(initial, 0)
	query.min_w = 30
	query.expand = false
	query.user = state
	query.submit = find_submit
	mut replace := vtk.entry('', 0)
	replace.min_w = 30
	replace.expand = false
	replace.user = state
	replace.submit = find_replace_submit
	state.query = query
	state.replace = replace
	mut query_label := vtk.label('Find:')
	query_label.col, query_label.row = 0, 0
	query.col, query.row = 1, 0
	mut replace_label := vtk.label('Replace:')
	replace_label.col, replace_label.row = 0, 1
	replace.col, replace.row = 1, 1
	mut fields := vtk.grid()
	fields.add(mut query_label)
	fields.add(mut query)
	fields.add(mut replace_label)
	fields.add(mut replace)
	mut nav := vtk.button_bar()
	mut actions := vtk.button_bar()
	mut buttons := [vtk.button(' < Prev '), vtk.button(' Next > '), vtk.button(' Replace '),
		vtk.button(' Replace all '), vtk.button(' Close ')]
	ids := [1, 2, 3, 4, 0]
	for i, mut button in buttons {
		button.user = state
		button.data = ids[i]
		button.changed = find_action
		if i < 2 { nav.add(mut button) } else { actions.add(mut button) }
	}
	mut body := vtk.box(true)
	body.add(mut fields)
	body.add(mut nav)
	body.add(mut actions)
	mut w := app.dialog('Find / Replace', mut body)
	state.window = w
	if initial != '' {
		query.anchor = 0
		query.cursor = initial.len
	}
	_, height := app.size()
	rect := w.rect()
	app.move(mut w, rect.x, if height > rect.h { height - rect.h - 1 } else { 0 })
	app.set_focus(if focus_replace { replace } else { query })
	app.modal_for(mut w, doc.window)
	app.destroy_ctl(mut w)
}

fn choose_font(mut doc Document, mut app vtk.App) {
	if doc.view.readonly {
		app.notify('Read only', 1500)
		return
	}
	// Each style name previews the font it applies.
	mut names := []string{cap: font_styles.len}
	for style in font_styles {
		name := style.str()
		names << vtk.font_convert(name, style)
	}
	at := app.choice_for(doc.window, 'Unicode text style', names, 2)
	if at < 0 { return }
	style := font_styles[at]
	// Underline and strikethrough stay as portable Markdown tags.
	if style == .underline {
		wrap(mut doc, '<u>', '</u>')
	} else if style == .strikethrough {
		wrap(mut doc, '~~', '~~')
	} else {
		a, b := doc.view.selection()
		if a != b { doc.view.replace_selection(vtk.font_convert(doc.view.text[a..b], style)) }
	}
}

fn insert_table(mut doc Document, mut app vtk.App) {
	if doc.view.readonly {
		app.notify('Read only', 1500)
		return
	}
	mut columns := vtk.spin(1, table_max_columns)
	columns.value = 3
	mut rows := vtk.spin(1, table_max_rows)
	rows.value = 2
	mut column_label := vtk.label('Columns')
	column_label.col, column_label.row = 0, 0
	columns.col, columns.row = 1, 0
	mut row_label := vtk.label('Rows')
	row_label.col, row_label.row = 0, 1
	rows.col, rows.row = 1, 1
	mut fields := vtk.grid()
	fields.add(mut column_label)
	fields.add(mut columns)
	fields.add(mut row_label)
	fields.add(mut rows)
	mut body := vtk.box(true)
	body.add(mut fields)
	mut bar := vtk.button_bar()
	mut insert := vtk.button(' Insert ')
	insert.data = 1
	insert.changed = table_prompt_accept
	mut cancel := vtk.button(' Cancel ')
	cancel.data = 0
	cancel.changed = table_prompt_accept
	bar.add(mut insert)
	bar.add(mut cancel)
	body.add(mut bar)
	mut w := app.dialog('Insert table', mut body)
	prompt := &TablePrompt{
		window:  w
		columns: columns
		rows:    rows
	}
	insert.user = prompt
	cancel.user = prompt
	app.set_default_button(mut w, insert)
	app.set_focus(columns)
	app.modal_for(mut w, doc.window)
	app.destroy_ctl(mut w)
	if prompt.result == '' { return }
	a, _ := doc.view.selection()
	before := if a == 0 { '' } else { doc.view.text[a - 1..a] }
	prefix := if before == '' || before == '\n' { '' } else { '\n' }
	doc.view.replace_selection(prefix + prompt.result + '\n')
	doc.view.cursor = a + prefix.len + 1
}

fn action(mut c vtk.Ctl, mut app vtk.App) {
	mut doc := unsafe { &Document(c.user) }
	match c.data {
		1 { new_document(mut app, '') }
		2 {
			if path := app.file_pick_for(doc.window, if doc.path == '' {
				'.'
			} else {
				os.dir(doc.path)
			}) {
				new_document(mut app, path)
			}
		}
		3 { save(mut doc, false, mut app) }
		4 { save(mut doc, true, mut app) }
		5 { app.close(mut doc.window) }
		6 { doc.view.undo() }
		7 { doc.view.redo() }
		8 {
			app.set_focus(doc.view)
			app.copy_focus()
		}
		9 { doc.view.replace_selection(app.clipboard_text()) }
		10 {
			doc.view.anchor = 0
			doc.view.cursor = doc.view.text.len
		}
		11 { wrap(mut doc, '**', '**') }
		12 { wrap(mut doc, '*', '*') }
		13 { wrap(mut doc, '`', '`') }
		14 {
			if emoji := app.emoji_pick(doc.window) { doc.view.replace_selection(emoji) }
		}
		15 {
			if target := app.prompt_for(doc.window, 'Link', 'Target URL or path:', '') {
				wrap(mut doc, '[', '](${target})')
			}
		}
		16 { find_dialog(mut doc, mut app, false) }
		40 { find_dialog(mut doc, mut app, true) }
		17 { doc.outline.hidden = !doc.outline.hidden }
		18 {
			mode := match doc.view.md.mode {
				.edit { vtk.MarkdownMode.source }
				.source { vtk.MarkdownMode.edit }
				.read { vtk.MarkdownMode.source_read }
				.source_read { vtk.MarkdownMode.read }
			}
			doc.view.markdown_mode(mode)
		}
		19 {
			mode := match doc.view.md.mode {
				.edit { vtk.MarkdownMode.read }
				.source { vtk.MarkdownMode.source_read }
				.read { vtk.MarkdownMode.edit }
				.source_read { vtk.MarkdownMode.source }
			}
			doc.view.markdown_mode(mode)
		}
		20 { doc.view.vim_mode(!doc.view.vim.enabled) }
		21 { app.history_for(doc.window, mut doc.view) }
		22 { doc.view.line_numbers = !doc.view.line_numbers }
		23 { doc.view.md.ruler_top = !doc.view.md.ruler_top }
		24 { doc.view.md.ruler_left = !doc.view.md.ruler_left }
		25 { app.quit() }
		26 { wrap(mut doc, '\n# ', '') }
		27 { wrap(mut doc, '\n- ', '') }
		28 { wrap(mut doc, '\n> ', '') }
		29 { wrap(mut doc, '\n```\n', '\n```\n') }
		30 { doc.view.set_wrap_mode(.none) }
		31 { doc.view.set_wrap_mode(.character) }
		32 { doc.view.set_wrap_mode(.word) }
		33 {
			initial := if doc.view.md.column_width > 0 {
				doc.view.md.column_width.str()
			} else {
				'0'
			}
			if text := app.prompt_for(doc.window, 'Page width', 'Columns (0 = full width):', initial) {
				n := text.trim_space().int()
				doc.view.md.column_width = if n > 0 { n } else { 0 }
			}
		}
		34 { doc.toolbar.hidden = !doc.toolbar.hidden }
		35 { doc.view.markdown_align(.left) }
		36 { doc.view.markdown_align(.center) }
		37 { doc.view.markdown_align(.right) }
		38 { doc.view.markdown_align(.justify) }
		39 { insert_table(mut doc, mut app) }
		41 { choose_font(mut doc, mut app) }
		42 { app.msgbox_for(doc.window, 'About ${app_name}', '${app_name} version ${app_version}\nAuthor: pancake') }
		else {}
	}
	sync_view_menu(mut doc)
	sync_wrap_menu(mut doc)
	sync_page_menu(mut doc)
	sync_align_menu(mut doc)
	if int(c.data) in [17, 18, 19, 20, 22, 23, 24, 30, 31, 32, 33, 34] { save_prefs(doc) }
	refresh_status(mut doc)
	app.invalidate()
	app.set_focus(doc.view)
}

fn key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut doc := unsafe { &Document(c.user) }
	if !e.ctrl {
		schedule_status(mut app, mut doc)
		return false
	}
	id := match e.key {
		`n` { 1 }
		`o` { 2 }
		`s` {
			if e.shift { 4 } else { 3 }
		}
		`w` { 5 }
		`z` {
			if e.shift { 7 } else { 6 }
		}
		`y` { 7 }
		`v` { 9 }
		`a` { 10 }
		`b` { 11 }
		`i` { 12 }
		`f` { 16 }
		`q` { 25 }
		else { 0 }
	}
	if id == 0 {
		schedule_status(mut app, mut doc)
		return false
	}
	mut trigger := vtk.Ctl{ user: c.user, data: id }
	action(mut trigger, mut app)
	return true
}

fn menu_item(mut menu vtk.Ctl, doc &Document, text string, id int) {
	mut item := menu.menu_item(text, action)
	item.user = doc
	item.data = id
}

fn new_document(mut app vtk.App, path string) {
	text := if path != '' {
		os.read_file(path) or {
			app.notify(err.msg(), 3000)
			return
		}
	} else {
		'# Welcome to VTK Word\n\nA Markdown document, rendered in terminal cells.\n\n- [ ] Try the task checkbox\n- [x] Open File, Edit, View and Format with F10\n\nSelect text, then use the toolbar to format it.\n'
	}
	prefs := load_prefs()
	mut doc := &Document{ path: path, saved: text }
	doc.window = app.window('VTK Word', 78, 24)
	doc.window.user = doc
	doc.window.closing = closing
	doc.view = vtk.markdown(text)
	doc.view.user = doc
	doc.view.changed = changed
	doc.view.keyfn = key
	doc.view.mousefn = mouse_status
	doc.view.scrollbar = true
	doc.view.markdown_mode(prefs.mode)
	doc.view.md.hide_status = true
	doc.view.vim_mode(if prefs.vim_set { prefs.vim } else { app.vim_mode })
	doc.view.set_wrap_mode(prefs.wrap)
	doc.view.line_numbers = prefs.line_numbers
	doc.view.md.ruler_top = prefs.ruler_top
	doc.view.md.ruler_left = prefs.ruler_left
	doc.view.md.column_width = prefs.page_width
	doc.outline = vtk.tree()
	doc.outline.hidden = prefs.outline_hidden
	doc.outline.user = doc
	doc.outline.changed = outline_hit
	doc.status = vtk.statusbar('')
	mut body := vtk.box(true)
	doc.toolbar = vtk.toolbar()
	doc.toolbar.hidden = prefs.toolbar_hidden
	for i, name in ['B', 'I', 'Code', 'Emoji', 'Link', 'Find'] {
		mut b := vtk.toolbutton(name)
		b.user = doc
		b.data = 11 + i
		b.changed = action
		doc.toolbar.add(mut b)
	}
	body.add(mut doc.toolbar)
	mut panes := vtk.split(false, 230)
	panes.resizable = true
	panes.add(mut doc.outline)
	panes.add(mut doc.view)
	body.add(mut panes)
	body.add(mut doc.status)
	doc.window.add(mut body)
	app.maximize(mut doc.window)
	mut file := doc.window.add_menu('File')
	for i, name in ['New   Ctrl-N', 'Open...   Ctrl-O', 'Save   Ctrl-S', 'Save as...', 'Close   Ctrl-W'] {
		menu_item(mut file, doc, name, i + 1)
	}
	file.menu_separator()
	menu_item(mut file, doc, 'Quit   Ctrl-Q', 25)
	mut edit := doc.window.add_menu('Edit')
	for i, name in ['Undo', 'Redo'] {
		menu_item(mut edit, doc, name, i + 6)
	}
	menu_item(mut edit, doc, 'History...', 21)
	edit.menu_separator()
	for i, name in ['Copy', 'Paste', 'Select all'] {
		menu_item(mut edit, doc, name, i + 8)
	}
	edit.menu_separator()
	menu_item(mut edit, doc, 'Find...   Ctrl-F', 16)
	menu_item(mut edit, doc, 'Replace...', 40)
	mut view := doc.window.add_menu('View')
	for i, name in view_names {
		mut item := view.menu_item(name, action)
		item.user = doc
		item.data = view_ids[i]
		doc.view_items << item
	}
	view.menu_separator()
	mut wrap_menu := view.add_menu('Wrap')
	for i, name in wrap_names {
		mut item := wrap_menu.menu_item(name, action)
		item.user = doc
		item.data = 30 + i
		doc.wrap_items << item
	}
	mut page := view.add_menu('Page')
	for i, name in page_names {
		mut item := page.menu_item(name, action)
		item.user = doc
		item.data = 22 + i
		doc.page_items << item
	}
	page.menu_separator()
	menu_item(mut page, doc, 'Page width...', 33)
	mut insert := doc.window.add_menu('Insert')
	menu_item(mut insert, doc, 'Emoji...', 14)
	menu_item(mut insert, doc, 'Link...', 15)
	insert.menu_separator()
	for i, name in ['Heading', 'List', 'Quote', 'Code block'] {
		menu_item(mut insert, doc, name, i + 26)
	}
	menu_item(mut insert, doc, 'Table...', 39)
	mut format := doc.window.add_menu('Format')
	for i, name in ['Bold', 'Italic', 'Code'] {
		menu_item(mut format, doc, name, i + 11)
	}
	menu_item(mut format, doc, 'Font...', 41)
	format.menu_separator()
	mut align_menu := format.add_menu('Align')
	for i, name in align_names {
		mut item := align_menu.menu_item(name, action)
		item.user = doc
		item.data = 35 + i
		doc.align_items << item
	}
	mut help := doc.window.add_menu('Help')
	menu_item(mut help, doc, 'About', 42)
	sync_view_menu(mut doc)
	sync_wrap_menu(mut doc)
	sync_page_menu(mut doc)
	sync_align_menu(mut doc)
	update(mut doc)
	app.redraw()
	schedule_status(mut app, mut doc)
	app.set_focus(doc.view)
}

fn launcher(mut app vtk.App, _ voidptr) { new_document(mut app, '') }

fn main() {
	mut app := vtk.new_app()
	app.ctrl_c = .copy
	app.native_clipboard = true
	app.init() or {
		eprintln(err)
		return
	}
	defer { app.fini() }
	app.register('Word', launcher, unsafe { nil })
	new_document(mut app, if os.args.len > 1 { os.args[1] } else { '' })
	app.run() or { eprintln(err) }
}
