// V translation of the HTK Markdown editor in examples/word.hc.
module word

import os
import vtk
import vtk.app.programs.common

enum Cmd {
	new_document
	open_file
	save
	save_as
	close_window
	undo
	redo
	copy
	paste
	select_all
	bold
	italic
	code
	emoji
	link
	find
	find_replace
	toggle_outline
	toggle_source
	toggle_read_only
	toggle_vim
	history
	line_numbers
	ruler_top
	ruler_left
	insert_heading
	insert_list
	insert_quote
	insert_code_block
	wrap_none
	wrap_character
	wrap_word
	page_width
	toggle_toolbar
	align_left
	align_center
	align_right
	align_justify
	insert_table
	choose_font
	about
}

struct MenuEntry {
	label string
	cmd   Cmd
}

@[heap]
struct Document {
mut:
	window      &vtk.Ctl @[required]
	view        &vtk.Ctl @[required]
	outline     &vtk.Ctl @[required]
	status      &vtk.Ctl @[required]
	toolbar     &vtk.Ctl @[required]
	path        string
	standalone  bool
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
		mut doc := c.context[Document]() or { return false }
		schedule_status(mut app, mut doc)
	}
	return false
}

fn changed(mut c vtk.Ctl, mut app vtk.App) {
	mut doc := c.context[Document]() or { return }
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
		name, raw_value := trim.split_once('=') or { continue }
		value := raw_value.trim_space()
		match name.trim_space() {
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
			'page_width' {
				width := value.int()
				prefs.page_width = if width > 0 { width } else { 0 }
			}
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

const view_entries = [MenuEntry{'Outline', .toggle_outline}, MenuEntry{'Toolbar', .toggle_toolbar},
	MenuEntry{'Source', .toggle_source}, MenuEntry{'Read only', .toggle_read_only},
	MenuEntry{'Vim mode', .toggle_vim}]
const wrap_entries = [MenuEntry{'Disabled', .wrap_none}, MenuEntry{'Character', .wrap_character},
	MenuEntry{'Word', .wrap_word}]
const page_entries = [MenuEntry{'Line numbers', .line_numbers}, MenuEntry{'Top ruler', .ruler_top},
	MenuEntry{'Left ruler', .ruler_left}]
const align_entries = [MenuEntry{'Left', .align_left}, MenuEntry{'Center', .align_center},
	MenuEntry{'Right', .align_right}, MenuEntry{'Justify', .align_justify}]
const app_name = 'VtkWord'
const app_version = '0.1.0'

fn ticked(name string, on bool) string {
	return if on { '✓ ${name}' } else { '  ${name}' }
}

fn sync_view_menu(mut doc Document) {
	mode := doc.view.md.mode
	shown := [!doc.outline.hidden, !doc.toolbar.hidden, mode in [.source, .source_read],
		mode in [.read, .source_read], doc.view.vim.enabled]
	for i, mut item in doc.view_items {
		item.text = ticked(view_entries[i].label, shown[i])
	}
}

fn sync_wrap_menu(mut doc Document) {
	mode := int(doc.view.wrap_mode())
	for i, mut item in doc.wrap_items {
		item.text = ticked(wrap_entries[i].label, i == mode)
	}
}

fn sync_page_menu(mut doc Document) {
	shown := [doc.view.line_numbers, doc.view.md.ruler_top, doc.view.md.ruler_left]
	for i, mut item in doc.page_items {
		item.text = ticked(page_entries[i].label, shown[i])
	}
}

fn sync_align_menu(mut doc Document) {
	start, _ := doc.view.selection()
	align := doc.view.markdown_align_at(start)
	for i, mut item in doc.align_items {
		item.text = ticked(align_entries[i].label, int(align) == i + 1)
	}
}

fn outline_hit(mut c vtk.Ctl, mut app vtk.App) {
	mut doc := c.context[Document]() or { return }
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
	if path != doc.path && !common.confirm_replace(mut app, doc.window, path) { return false }
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
	mut doc := w.context[Document]() or { return true }
	if doc.view.text == doc.saved { return true }
	return match common.ask_unsaved(mut app, w, 'Unsaved changes') {
		.save { save(mut doc, false, mut app) }
		.discard { true }
		.cancel { false }
	}
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
	window  &vtk.Ctl @[required]
	columns &vtk.Ctl @[required]
	rows    &vtk.Ctl @[required]
	result  string
}

fn table_prompt_accept(mut c vtk.Ctl, mut app vtk.App) {
	mut prompt := c.context[TablePrompt]() or { return }
	prompt.result = table_markdown(prompt.columns.value, prompt.rows.value)
	app.close(mut prompt.window)
}

fn table_prompt_cancel(mut c vtk.Ctl, mut app vtk.App) {
	mut prompt := c.context[TablePrompt]() or { return }
	app.close(mut prompt.window)
}

fn choose_font(mut doc Document, mut app vtk.App) {
	if doc.view.readonly {
		app.notify('Read only', 1500)
		return
	}
	style := common.pick_font_style(mut app, doc.window) or { return }
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
	insert.changed = table_prompt_accept
	mut cancel := vtk.button(' Cancel ')
	cancel.changed = table_prompt_cancel
	bar.add(mut insert)
	bar.add(mut cancel)
	body.add(mut bar)
	mut w := app.dialog('Insert table', mut body)
	prompt := &TablePrompt{
		window:  w
		columns: columns
		rows:    rows
	}
	insert.set_context(prompt)
	cancel.set_context(prompt)
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
	mut doc := c.context[Document]() or { return }
	cmd := Cmd.from(c.data) or { return }
	document_action(mut doc, cmd, mut app)
}

fn document_action(mut doc Document, cmd Cmd, mut app vtk.App) {
	match cmd {
		.new_document { new_document(mut app, '', doc.standalone) }
		.open_file {
			if path := app.file_pick_for(doc.window, if doc.path == '' {
				'.'
			} else {
				os.dir(doc.path)
			}) {
				new_document(mut app, path, doc.standalone)
			}
		}
		.save { save(mut doc, false, mut app) }
		.save_as { save(mut doc, true, mut app) }
		.close_window {
			app.close(mut doc.window)
			return
		}
		.undo { doc.view.undo() }
		.redo { doc.view.redo() }
		.copy {
			app.set_focus(doc.view)
			app.copy_focus()
		}
		.paste { doc.view.replace_selection(app.clipboard_text()) }
		.select_all {
			doc.view.anchor = 0
			doc.view.cursor = doc.view.text.len
		}
		.bold { wrap(mut doc, '**', '**') }
		.italic { wrap(mut doc, '*', '*') }
		.code { wrap(mut doc, '`', '`') }
		.emoji {
			if emoji := app.emoji_pick(doc.window) { doc.view.replace_selection(emoji) }
		}
		.link {
			if target := app.prompt_for(doc.window, 'Link', 'Target URL or path:', '') {
				wrap(mut doc, '[', '](${target})')
			}
		}
		.find { find_dialog(mut doc, mut app, false) }
		.find_replace { find_dialog(mut doc, mut app, true) }
		.toggle_outline { doc.outline.hidden = !doc.outline.hidden }
		.toggle_source {
			mode := match doc.view.md.mode {
				.edit { vtk.MarkdownMode.source }
				.source { vtk.MarkdownMode.edit }
				.read { vtk.MarkdownMode.source_read }
				.source_read { vtk.MarkdownMode.read }
			}
			doc.view.markdown_mode(mode)
		}
		.toggle_read_only {
			mode := match doc.view.md.mode {
				.edit { vtk.MarkdownMode.read }
				.source { vtk.MarkdownMode.source_read }
				.read { vtk.MarkdownMode.edit }
				.source_read { vtk.MarkdownMode.source }
			}
			doc.view.markdown_mode(mode)
		}
		.toggle_vim { doc.view.vim_mode(!doc.view.vim.enabled) }
		.history { app.history_for(doc.window, mut doc.view) }
		.line_numbers { doc.view.line_numbers = !doc.view.line_numbers }
		.ruler_top { doc.view.md.ruler_top = !doc.view.md.ruler_top }
		.ruler_left { doc.view.md.ruler_left = !doc.view.md.ruler_left }
		.insert_heading { wrap(mut doc, '\n# ', '') }
		.insert_list { wrap(mut doc, '\n- ', '') }
		.insert_quote { wrap(mut doc, '\n> ', '') }
		.insert_code_block { wrap(mut doc, '\n```\n', '\n```\n') }
		.wrap_none { doc.view.set_wrap_mode(.none) }
		.wrap_character { doc.view.set_wrap_mode(.character) }
		.wrap_word { doc.view.set_wrap_mode(.word) }
		.page_width {
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
		.toggle_toolbar { doc.toolbar.hidden = !doc.toolbar.hidden }
		.align_left { doc.view.markdown_align(.left) }
		.align_center { doc.view.markdown_align(.center) }
		.align_right { doc.view.markdown_align(.right) }
		.align_justify { doc.view.markdown_align(.justify) }
		.insert_table { insert_table(mut doc, mut app) }
		.choose_font { choose_font(mut doc, mut app) }
		.about { app.about_for(doc.window, app_name, app_version) }
		else {}
	}
	sync_view_menu(mut doc)
	sync_wrap_menu(mut doc)
	sync_page_menu(mut doc)
	sync_align_menu(mut doc)
	if cmd in [.toggle_outline, .toggle_source, .toggle_read_only, .toggle_vim,
		.line_numbers, .ruler_top, .ruler_left, .wrap_none, .wrap_character, .wrap_word, .page_width,
		.toggle_toolbar] {
		save_prefs(doc)
	}
	refresh_status(mut doc)
	app.invalidate()
	app.set_focus(doc.view)
}

fn key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut doc := c.context[Document]() or { return false }
	if !e.ctrl {
		schedule_status(mut app, mut doc)
		return false
	}
	cmd := shortcut_cmd(e) or {
		schedule_status(mut app, mut doc)
		return false
	}
	document_action(mut doc, cmd, mut app)
	return true
}

fn shortcut_cmd(e vtk.Event) ?Cmd {
	match e.key {
		`n` { return Cmd.new_document }
		`o` { return Cmd.open_file }
		`s` {
			if e.shift { return Cmd.save_as }
			return Cmd.save
		}
		`w` { return Cmd.close_window }
		`z` {
			if e.shift { return Cmd.redo }
			return Cmd.undo
		}
		`y` { return Cmd.redo }
		`v` { return Cmd.paste }
		`a` { return Cmd.select_all }
		`b` { return Cmd.bold }
		`i` { return Cmd.italic }
		`f` { return Cmd.find }
		`q` { return Cmd.close_window }
		else {}
	}
	return none
}

fn menu_item(mut menu vtk.Ctl, doc &Document, text string, cmd Cmd) {
	mut item := menu.menu_item(text, action)
	item.set_context(doc)
	item.data = i64(int(cmd))
}

fn menu_items(mut menu vtk.Ctl, doc &Document, entries []MenuEntry) {
	for entry in entries {
		menu_item(mut menu, doc, entry.label, entry.cmd)
	}
}

fn new_document(mut app vtk.App, path string, standalone bool) {
	text := if path != '' {
		os.read_file(path) or {
			app.notify(err.msg(), 3000)
			return
		}
	} else {
		'# Welcome to VTK Word\n\nA Markdown document, rendered in terminal cells.\n\n- [ ] Try the task checkbox\n- [x] Open File, Edit, View and Format with F10\n\nSelect text, then use the toolbar to format it.\n'
	}
	prefs := load_prefs()
	mut doc := &Document{
		path: path
		saved: text
		standalone: standalone
		window: app.window('VTK Word', 78, 24)
		view: vtk.markdown(text)
		outline: vtk.tree()
		status: vtk.statusbar('')
		toolbar: vtk.toolbar()
	}
	doc.window.set_context(doc)
	doc.window.closing = closing
	doc.view.set_context(doc)
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
	doc.outline.hidden = prefs.outline_hidden
	doc.outline.set_context(doc)
	doc.outline.changed = outline_hit
	mut body := vtk.box(true)
	doc.toolbar.hidden = prefs.toolbar_hidden
	toolbar_cmds := [Cmd.bold, .italic, .code, .emoji, .link, .find]
	for i, name in ['B', 'I', 'Code', 'Emoji', 'Link', 'Find'] {
		mut b := vtk.toolbutton(name)
		b.set_context(doc)
		b.data = i64(int(toolbar_cmds[i]))
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
	menu_items(mut file, doc, [
		MenuEntry{'New   Ctrl-N', .new_document},
		MenuEntry{'Open...   Ctrl-O', .open_file},
		MenuEntry{'Save   Ctrl-S', .save},
		MenuEntry{'Save as...', .save_as},
		MenuEntry{'Close   Ctrl-W', .close_window},
	])
	file.menu_separator()
	menu_item(mut file, doc, 'Quit   Ctrl-Q', .close_window)
	mut edit := doc.window.add_menu('Edit')
	menu_items(mut edit, doc, [MenuEntry{'Undo', .undo}, MenuEntry{'Redo', .redo}])
	menu_item(mut edit, doc, 'History...', .history)
	edit.menu_separator()
	menu_items(mut edit, doc, [
		MenuEntry{'Copy', .copy},
		MenuEntry{'Paste', .paste},
		MenuEntry{'Select all', .select_all},
	])
	edit.menu_separator()
	menu_item(mut edit, doc, 'Find...   Ctrl-F', .find)
	menu_item(mut edit, doc, 'Replace...', .find_replace)
	mut view := doc.window.add_menu('View')
	for entry in view_entries {
		mut item := view.menu_item(entry.label, action)
		item.set_context(doc)
		item.data = i64(int(entry.cmd))
		doc.view_items << item
	}
	view.menu_separator()
	mut wrap_menu := view.add_menu('Wrap')
	for entry in wrap_entries {
		mut item := wrap_menu.menu_item(entry.label, action)
		item.set_context(doc)
		item.data = i64(int(entry.cmd))
		doc.wrap_items << item
	}
	mut page := view.add_menu('Page')
	for entry in page_entries {
		mut item := page.menu_item(entry.label, action)
		item.set_context(doc)
		item.data = i64(int(entry.cmd))
		doc.page_items << item
	}
	page.menu_separator()
	menu_item(mut page, doc, 'Page width...', .page_width)
	mut insert := doc.window.add_menu('Insert')
	menu_item(mut insert, doc, 'Emoji...', .emoji)
	menu_item(mut insert, doc, 'Link...', .link)
	insert.menu_separator()
	menu_items(mut insert, doc, [
		MenuEntry{'Heading', .insert_heading},
		MenuEntry{'List', .insert_list},
		MenuEntry{'Quote', .insert_quote},
		MenuEntry{'Code block', .insert_code_block},
	])
	menu_item(mut insert, doc, 'Table...', .insert_table)
	mut format := doc.window.add_menu('Format')
	menu_items(mut format, doc, [
		MenuEntry{'Bold', .bold},
		MenuEntry{'Italic', .italic},
		MenuEntry{'Code', .code},
	])
	menu_item(mut format, doc, 'Font...', .choose_font)
	format.menu_separator()
	mut align_menu := format.add_menu('Align')
	for entry in align_entries {
		mut item := align_menu.menu_item(entry.label, action)
		item.set_context(doc)
		item.data = i64(int(entry.cmd))
		doc.align_items << item
	}
	mut help := doc.window.add_menu('Help')
	menu_item(mut help, doc, 'About', .about)
	sync_view_menu(mut doc)
	sync_wrap_menu(mut doc)
	sync_page_menu(mut doc)
	sync_align_menu(mut doc)
	update(mut doc)
	app.redraw()
	schedule_status(mut app, mut doc)
	app.set_focus(doc.view)
}

pub fn launch(mut app vtk.App) { new_document(mut app, '', false) }

fn standalone_launch(mut app vtk.App) { new_document(mut app, '', true) }

pub fn run() {
	mut app := vtk.new_app()
	app.ctrl_c = .copy
	app.native_clipboard = true
	common.run(mut app, fn (mut app vtk.App) {
		app.register('Word', standalone_launch)
		new_document(mut app, if os.args.len > 1 { os.args[1] } else { '' }, true)
	})
}
