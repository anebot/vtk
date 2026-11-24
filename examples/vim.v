// V translation of examples/vim.hc: shared buffers, split panes and :commands.
module main

import os
import vtk

@[heap]
struct Buffer {
mut:
	id      int
	path    string
	text    string
	saved   string
	history &vtk.Edit = &vtk.Edit{}
}

@[heap]
struct Editor {
mut:
	window      &vtk.Ctl = unsafe { nil }
	workspace   &vtk.Ctl = unsafe { nil }
	status      &vtk.Ctl = unsafe { nil }
	panes       []&vtk.Ctl
	buffers     []&Buffer
	search      string
	backward    bool
	prefix      bool
	force_close bool
}

@[heap]
struct Pane {
mut:
	editor &Editor
	buffer &Buffer
}

fn buffer_open(mut editor Editor, path string, mut app vtk.App) ?&Buffer {
	for buffer in editor.buffers {
		if path != '' && os.abs_path(buffer.path) == os.abs_path(path) { return buffer }
	}
	text := if path != '' && os.exists(path) {
		os.read_file(path) or {
			app.notify(err.msg(), 2500)
			return none
		}
	} else {
		''
	}
	mut buffer := &Buffer{ id: editor.buffers.len + 1, path: path, text: text, saved: text }
	editor.buffers << buffer
	return buffer
}

fn pane_changed(mut c vtk.Ctl, mut app vtk.App) {
	mut pane := unsafe { &Pane(c.user) }
	pane.buffer.text = c.text
	for mut other in pane.editor.panes {
		p := unsafe { &Pane(other.user) }
		if other != &c && p.buffer == pane.buffer {
			other.text = c.text
			other.cursor = vtk.clamp(other.cursor, 0, c.text.len)
			other.anchor = -1
		}
	}
	status(mut pane.editor, &c)
	app.invalidate()
}

fn status(mut editor Editor, c &vtk.Ctl) {
	pane := unsafe { &Pane(c.user) }
	line := c.text[..vtk.clamp(c.cursor, 0, c.text.len)].count('\n') + 1
	editor.status.text = '${c.vim.mode} | ${line} | ${if pane.buffer.path == '' {
		'[No Name]'
	} else {
		pane.buffer.path
	}}${if c.text != pane.buffer.saved { ' [+]' } else { '' }} | :help'
}

fn write_buffer(mut c vtk.Ctl, path string, force bool, mut app vtk.App) bool {
	mut pane := unsafe { &Pane(c.user) }
	name := if path != '' { path } else { pane.buffer.path }
	if name == '' {
		app.notify('Use :w path', 2500)
		return false
	}
	if !force && name != pane.buffer.path && os.exists(name) {
		app.notify('File exists; use :w! path', 2500)
		return false
	}
	c.end_edit_group()
	vtk.save_atomic(name, c.text) or {
		app.notify(err.msg(), 3000)
		return false
	}
	pane.buffer.path = name
	pane.buffer.saved = c.text
	status(mut pane.editor, &c)
	app.notify('Written ${name}', 1500)
	return true
}

fn make_pane(mut editor Editor, buffer &Buffer) &vtk.Ctl {
	mut pane := &Pane{ editor: editor, buffer: buffer }
	mut c := vtk.markdown(buffer.text)
	c.edit = buffer.history
	c.user = pane
	c.markdown_mode(.source)
	c.set_wrap_mode(.none)
	c.md.tab_width = 8
	c.md.hide_status = true
	c.md.task_interactive = false
	c.line_numbers = true
	c.scrollbar = true
	c.vim_mode(true)
	c.keyfn = pane_key
	c.changed = pane_changed
	editor.panes << c
	return c
}

fn split_pane(mut c vtk.Ctl, vertical bool, path string, fresh bool, mut app vtk.App) {
	mut pane := unsafe { &Pane(c.user) }
	mut buffer := pane.buffer
	if path != '' || fresh { buffer = buffer_open(mut pane.editor, path, mut app) or { return } }
	mut next := make_pane(mut pane.editor, buffer)
	mut parent := c.parent_ctl() or { return }
	mut container := vtk.split(!vertical, 500)
	if !parent.replace(mut c, mut container) { return }
	container.add(mut c)
	container.add(mut next)
	app.redraw()
	app.set_focus(next)
}

fn close_pane(mut c vtk.Ctl, force bool, mut app vtk.App) bool {
	mut pane := unsafe { &Pane(c.user) }
	mut editor := pane.editor
	refs := editor.panes.count(unsafe { &Pane(it.user) }.buffer == pane.buffer)
	if !force && refs == 1 && c.text != pane.buffer.saved {
		app.notify('Unsaved changes; use :w or :q!', 2500)
		return false
	}
	if editor.panes.len == 1 {
		editor.force_close = force
		return app.close(mut editor.window)
	}
	mut container := c.parent_ctl() or { return false }
	children := container.children()
	mut other := children[if children[0] == &c { 1 } else { 0 }]
	mut parent := container.parent_ctl() or { return false }
	if !parent.replace(mut container, mut other) { return false }
	container.clear()
	editor.panes = editor.panes.filter(it != &c)
	app.redraw()
	app.set_focus(other)
	return true
}

fn search(mut c vtk.Ctl, backward bool, mut app vtk.App) {
	mut pane := unsafe { &Pane(c.user) }
	query := pane.editor.search
	if query == '' { return }
	mut hit := -1
	if backward {
		hit = c.text[..c.cursor].last_index(query) or { c.text.last_index(query) or { -1 } }
	} else {
		start := vtk.clamp(c.cursor + 1, 0, c.text.len)
		rel := c.text[start..].index(query) or { -1 }
		hit = if rel >= 0 { start + rel } else { c.text.index(query) or { -1 } }
	}
	if hit >= 0 {
		c.cursor = hit
		c.anchor = -1
		c.scroll_hold = false
	} else {
		app.notify('Pattern not found', 2000)
	}
}

fn command(mut c vtk.Ctl, source string, mut app vtk.App) {
	mut pane := unsafe { &Pane(c.user) }
	mut editor := pane.editor
	parts := source.trim_space().trim_left(':').split_nth(' ', 2)
	name := parts[0].trim_right('!')
	force := parts[0].ends_with('!')
	arg := if parts.len > 1 { parts[1].trim_space().trim('"\'') } else { '' }
	match name {
		'' {}
		'w', 'write' { write_buffer(mut c, arg, force, mut app) }
		'wq', 'x' {
			if write_buffer(mut c, arg, force, mut app) { close_pane(mut c, force, mut app) }
		}
		'q', 'quit' { close_pane(mut c, force, mut app) }
		'qa', 'qall' {
			editor.force_close = force
			app.close(mut editor.window)
		}
		'sp', 'split', 'vs', 'vsplit', 'new', 'vnew' {
			split_pane(mut c, name in ['vs', 'vsplit', 'vnew'], arg, name in ['new', 'vnew'], mut app)
		}
		'e', 'edit', 'o', 'open', 'b', 'buffer', 'bn', 'bnext', 'bp', 'bprevious' {
			if !force && c.text != pane.buffer.saved {
				app.notify('Unsaved changes; use :w or :e!', 2500)
				return
			}
			mut buffer := pane.buffer
			if name in ['b', 'buffer'] {
				found := editor.buffers.filter(it.id == arg.int())
				if found.len == 0 {
					app.notify('No such buffer', 2000)
					return
				}
				buffer = found[0]
			} else if name in ['bn', 'bnext', 'bp', 'bprevious'] {
				at := editor.buffers.index(pane.buffer)
				buffer = editor.buffers[(at + if name in ['bp', 'bprevious'] {
					editor.buffers.len - 1
				} else {
					1
				}) % editor.buffers.len]
			} else {
				buffer = buffer_open(mut editor, arg, mut app) or { return }
			}
			pane.buffer = buffer
			c.text = buffer.text
			c.edit = buffer.history
			c.cursor = 0
			c.anchor = -1
			c.top = 0
		}
		'only' {
			for mut other in editor.panes.clone() {
				if other != &c {
					if !close_pane(mut other, force, mut app) { return }
				}
			}
		}
		'ls', 'buffers' {
			app.msgbox_for(editor.window, 'Buffers', editor.buffers.map('${it.id} ${it.path}${if it.text != it.saved {
				' [+]'
			} else {
				''
			}}').join('\n'))
		}
		'set' {
			for option in arg.fields() {
				match option {
					'number', 'nu' { c.line_numbers = true }
					'nonumber', 'nonu' { c.line_numbers = false }
					'wrap', 'charwrap' { c.set_wrap_mode(.character) }
					'nowrap' { c.set_wrap_mode(.none) }
					'wordwrap' { c.set_wrap_mode(.word) }
					'readonly', 'ro' { c.readonly = true }
					'noreadonly', 'noro' { c.readonly = false }
					'vim' { c.vim_mode(true) }
					'novim' { c.vim_mode(false) }
					else { app.notify('Unknown option: ${option}', 2000) }
				}
			}
		}
		'help' {
			app.msgbox_for(editor.window, 'VTK Vim', ':split / :vsplit [path]  :new / :vnew\nCtrl-W w cycles; s/v splits; c closes\n:e[!] path  :w[!] [path]  :q[!]  :wq  :qa[!]\n:only[!]  :ls  :b id  :bn / :bp\n:set [no]number [no]wrap [no]readonly [no]vim\n:set wordwrap / charwrap\n/ and ? search; n/N repeat; :number jumps\nF10 menus; Alt-A desktop; Esc Normal mode')
		}
		else {
			if name.int() > 0 {
				mut line, mut at := 1, 0
				for at < c.text.len && line < name.int() {
					if c.text[at] == `\n` { line++ }
					at++
				}
				c.cursor = at
				c.anchor = -1
				c.scroll_hold = false
			} else {
				app.notify('Unknown command; use :help', 2000)
			}
		}
	}
	status(mut editor, &c)
	app.invalidate()
}

fn pane_key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut pane := unsafe { &Pane(c.user) }
	mut editor := pane.editor
	status(mut editor, &c)
	if e.ctrl && e.key == `s` {
		command(mut c, 'w', mut app)
		return true
	}
	if editor.prefix {
		editor.prefix = false
		match e.key {
			`s` { command(mut c, 'split', mut app) }
			`v` { command(mut c, 'vsplit', mut app) }
			`c`, `q` { command(mut c, 'q', mut app) }
			`o` { command(mut c, 'only', mut app) }
			else {
				at := editor.panes.index(&c)
				app.set_focus(editor.panes[(at + 1) % editor.panes.len])
			}
		}
		return true
	}
	if e.ctrl && e.key == `w` && c.vim.mode != .insert {
		editor.prefix = true
		return true
	}
	if !e.ctrl && !e.alt && c.vim.mode == .normal {
		if e.key in [int(`:`), int(`/`), int(`?`)] {
			if text := app.prompt_for(editor.window, rune(e.key).str(), '', '') {
				if e.key == `:` {
					command(mut c, text, mut app)
				} else {
					editor.search = text
					editor.backward = e.key == `?`
					search(mut c, editor.backward, mut app)
				}
			}
			app.set_focus(&c)
			return true
		}
		if e.key in [int(`n`), int(`N`)] {
			search(mut c, if e.key == `N` { !editor.backward } else { editor.backward }, mut app)
			return true
		}
	}
	return false
}

fn closing(mut w vtk.Ctl, mut app vtk.App) bool {
	mut editor := unsafe { &Editor(w.user) }
	if editor.force_close { return true }
	if editor.buffers.any(it.text != it.saved) {
		app.notify('Unsaved buffers; use :w or :qa!', 2500)
		return false
	}
	return true
}

fn main() {
	mut app := vtk.new_app()
	app.native_clipboard = true
	app.init() or {
		eprintln(err)
		return
	}
	defer { app.fini() }
	mut editor := &Editor{}
	editor.window = app.window('VTK Vim', 90, 28)
	editor.window.user = editor
	editor.window.closing = closing
	editor.workspace = vtk.box(true)
	editor.workspace.expand = true
	editor.status = vtk.statusbar('')
	buffer := buffer_open(mut editor, if os.args.len > 1 { os.args[1] } else { '' }, mut app) or { return }
	mut pane := make_pane(mut editor, buffer)
	editor.workspace.add(mut pane)
	mut body := vtk.box(true)
	body.add(mut editor.workspace)
	body.add(mut editor.status)
	editor.window.add(mut body)
	app.redraw()
	app.set_focus(pane)
	status(mut editor, pane)
	app.run() or { eprintln(err) }
}
