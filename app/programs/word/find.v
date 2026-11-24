module word

import vtk

enum FindCmd {
	prev
	next
	replace
	replace_all
	close
}

@[heap]
struct FindState {
mut:
	doc     &Document @[required]
	window  &vtk.Ctl @[required]
	query   &vtk.Ctl @[required]
	replace &vtk.Ctl @[required]
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
	mut state := c.context[FindState]() or { return }
	find_step(mut state, true, false, mut app)
}

fn find_replace_submit(mut c vtk.Ctl, mut app vtk.App) {
	mut state := c.context[FindState]() or { return }
	find_replace(mut state, mut app)
}

fn find_action(mut c vtk.Ctl, mut app vtk.App) {
	mut state := c.context[FindState]() or { return }
	cmd := FindCmd.from(c.data) or { return }
	match cmd {
		.prev { find_step(mut state, false, false, mut app) }
		.next { find_step(mut state, true, false, mut app) }
		.replace { find_replace(mut state, mut app) }
		.replace_all { find_replace_all(mut state, mut app) }
		.close { app.close(mut state.window) }
	}
}

fn find_dialog(mut doc Document, mut app vtk.App, focus_replace bool) {
	a, b := doc.view.selection()
	initial := if b > a && !doc.view.text[a..b].contains('\n') { doc.view.text[a..b] } else { '' }
	mut query := vtk.entry(initial, 0)
	query.min_w = 30
	query.expand = false
	query.submit = find_submit
	mut replace := vtk.entry('', 0)
	replace.min_w = 30
	replace.expand = false
	replace.submit = find_replace_submit
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
	find_cmds := [FindCmd.prev, .next, .replace, .replace_all, .close]
	for i, mut button in buttons {
		button.data = i64(int(find_cmds[i]))
		button.changed = find_action
		if i < 2 { nav.add(mut button) } else { actions.add(mut button) }
	}
	mut body := vtk.box(true)
	body.add(mut fields)
	body.add(mut nav)
	body.add(mut actions)
	mut w := app.dialog('Find / Replace', mut body)
	state := &FindState{ doc: doc, window: w, query: query, replace: replace }
	query.set_context(state)
	replace.set_context(state)
	for mut button in buttons { button.set_context(state) }
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
