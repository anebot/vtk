// V translation of the HTK Markdown editor in examples/word.hc.
module main

import os
import vtk
import vtk.examples.support

@[heap]
struct Document {
mut:
	window  &vtk.Ctl = unsafe { nil }
	view    &vtk.Ctl = unsafe { nil }
	outline &vtk.Ctl = unsafe { nil }
	status  &vtk.Ctl = unsafe { nil }
	path    string
	saved   string
}

fn update(mut doc Document) {
	name := if doc.path == '' { '[Untitled]' } else { os.file_name(doc.path) }
	doc.window.text = name + (if doc.view.text != doc.saved { ' *' } else { '' }) + ' - VTK Word'
	doc.status.text = '${doc.view.text.fields().len} words | ${doc.view.text.runes().len} chars | ${name}'
	doc.outline.kids.clear()
	doc.outline.link = unsafe { nil }
	mut at := 0
	for line in doc.view.text.split('\n') {
		if line.starts_with('#') {
			mut node := doc.outline.tree_add(unsafe { nil }, line.trim_left('# '))
			node.data = at
		}
		at += line.len + 1
	}
}

fn changed(mut c vtk.Ctl, mut app vtk.App) {
	mut doc := unsafe { &Document(c.user) }
	update(mut doc)
	app.dirty = true
}

fn outline_hit(mut c vtk.Ctl, mut app vtk.App) {
	mut doc := unsafe { &Document(c.user) }
	if !isnil(c.link) {
		doc.view.cursor = int(c.link.data)
		doc.view.anchor = -1
		doc.view.scroll_hold = false
		app.set_focus(doc.view)
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
	support.save(path, doc.view.text) or {
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
		5 { doc.window.close() }
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
		16 {
			if query := app.prompt_for(doc.window, 'Find', 'Text:', '') {
				if query != '' {
					at := doc.view.text[doc.view.cursor..].index(query) or { -1 }
					hit := if at >= 0 {
						doc.view.cursor + at
					} else {
						doc.view.text.index(query) or { -1 }
					}
					if hit >= 0 {
						doc.view.anchor = hit
						doc.view.cursor = hit + query.len
						doc.view.scroll_hold = false
					} else {
						app.notify('Text not found', 2000)
					}
				}
			}
		}
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
		else {}
	}
	app.dirty = true
	app.set_focus(doc.view)
}

fn key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	if !e.ctrl { return false }
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
	if id == 0 { return false }
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
	mut doc := &Document{ path: path, saved: text }
	doc.window = app.window('VTK Word', 78, 24)
	doc.window.user = doc
	doc.window.closing = closing
	doc.view = vtk.markdown(text)
	doc.view.user = doc
	doc.view.changed = changed
	doc.view.keyfn = key
	doc.view.scrollbar = true
	doc.view.vim_mode(app.vim_mode)
	doc.outline = vtk.tree()
	doc.outline.min_w = 18
	doc.outline.user = doc
	doc.outline.changed = outline_hit
	doc.status = vtk.statusbar('')
	mut body := vtk.box(true)
	mut bar := vtk.toolbar()
	for i, name in ['B', 'I', 'Code', 'Emoji', 'Link', 'Find'] {
		mut b := vtk.toolbutton(name)
		b.user = doc
		b.data = 11 + i
		b.changed = action
		bar.add(mut b)
	}
	body.add(mut bar)
	mut panes := vtk.split(false, 230)
	panes.add(mut doc.outline)
	panes.add(mut doc.view)
	body.add(mut panes)
	body.add(mut doc.status)
	doc.window.add(mut body)
	mut file := doc.window.add_menu('File')
	for i, name in ['New   Ctrl-N', 'Open...   Ctrl-O', 'Save   Ctrl-S', 'Save as...', 'Close   Ctrl-W'] {
		menu_item(mut file, doc, name, i + 1)
	}
	file.menu_separator()
	menu_item(mut file, doc, 'Quit   Ctrl-Q', 25)
	mut edit := doc.window.add_menu('Edit')
	for i, name in ['Undo', 'Redo', 'Copy', 'Paste', 'Select all'] {
		menu_item(mut edit, doc, name, i + 6)
	}
	menu_item(mut edit, doc, 'History...', 21)
	mut view := doc.window.add_menu('View')
	for i, name in ['Outline', 'Source / rendered', 'Editable / read only', 'Vim mode'] {
		menu_item(mut view, doc, name, i + 17)
	}
	for i, name in ['Line numbers', 'Top ruler', 'Left ruler'] {
		menu_item(mut view, doc, name, i + 22)
	}
	mut format := doc.window.add_menu('Format')
	for i, name in ['Bold', 'Italic', 'Code', 'Emoji...', 'Link...', 'Find...'] {
		menu_item(mut format, doc, name, i + 11)
	}
	for i, name in ['Heading', 'List', 'Quote', 'Code block'] {
		menu_item(mut format, doc, name, i + 26)
	}
	update(mut doc)
	app.redraw()
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
