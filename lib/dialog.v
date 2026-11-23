module vtk

import os

fn dialog_accept(mut c Ctl, mut app App) {
	mut w := c.owner_window_ptr()
	w.dialog_result = int(c.data)
	app.close(mut w)
}

fn dialog_button(text string, accepted bool) &Ctl {
	mut c := button(text)
	c.changed = dialog_accept
	c.data = i64(accepted)
	return c
}

pub fn (mut app App) dialog(title string, mut body Ctl) &Ctl {
	body.measure()
	area := app.work_area()
	mut w := app.window(title, min(app.width, max(24, body.pw + 4)), min(area.h, max(6, body.ph + 4)))
	w.x = max(0, (app.width - w.w) / 2)
	w.y = area.y + max(0, (area.h - w.h) / 2)
	w.dismissable = true
	w.controls = window_close
	w.dialog_result = -1
	w.add(mut body)
	return w
}

pub fn (mut app App) modal_for(mut dialog Ctl, owner ?&Ctl) int {
	if !app.can_access(&dialog) || !app.can_access(owner) { return -1 }
	owner_ptr := owner or { unsafe { nil } }
	if !isnil(owner_ptr) { dialog.desktop_id = owner_ptr.desktop_id }
	app.close_popups()
	app.drag = unsafe { nil }
	app.scroll_drag = unsafe { nil }
	if !isnil(app.placement) { app.placement_key(Event{ key: int(Key.escape) }) }
	dialog.modal_parent = app.blocker(owner_ptr)
	dialog.modal_owner = owner_ptr
	dialog.modal = true
	dialog.dismissable = true
	top := dialog.always_on_top
	old_focus := app.focus
	dialog.always_on_top = true
	app.raise(mut dialog)
	for app.running && !dialog.closed { app.step(20) }
	dialog.modal = false
	dialog.modal_owner = unsafe { nil }
	dialog.modal_parent = unsafe { nil }
	dialog.always_on_top = top
	if !isnil(old_focus) && old_focus.visible() { app.set_focus(old_focus) }
	app.dirty = true
	return dialog.dialog_result
}

fn dialog_body(body string) &Ctl {
	mut b := box(true)
	mut text := label(body)
	b.add(mut text)
	return b
}

pub fn (mut app App) msgbox_for(owner ?&Ctl, title string, text string) {
	if !app.can_access(owner) { return }
	mut body := dialog_body(text)
	mut row := button_bar()
	mut ok := dialog_button('  OK  ', true)
	row.add(mut ok)
	body.add(mut row)
	mut w := app.dialog(title, mut body)
	w.default_button = ok
	app.set_focus(ok)
	app.modal_for(mut w, owner)
	app.destroy_ctl(mut w)
}

pub fn (mut app App) msgbox(title string, text string) {
	app.msgbox_for(app.top_window(), title, text)
}

pub fn (mut app App) confirm_for(owner ?&Ctl, title string, text string) bool {
	if !app.can_access(owner) { return false }
	mut body := dialog_body(text)
	mut row := button_bar()
	mut yes := dialog_button(' Yes ', true)
	mut no := dialog_button(' No ', false)
	row.add(mut yes)
	row.add(mut no)
	body.add(mut row)
	mut w := app.dialog(title, mut body)
	w.default_button = yes
	app.set_focus(no)
	result := app.modal_for(mut w, owner) == 1
	app.destroy_ctl(mut w)
	return result
}

pub fn (mut app App) confirm_quit() {
	if app.confirm_for(none, 'Quit', 'Close all windows?') { app.quit() }
}

pub fn (mut app App) prompt_for(owner ?&Ctl, title string, text string, initial string) ?string {
	if !app.can_access(owner) { return none }
	mut body := dialog_body(text)
	mut field := entry(initial, 0)
	field.min_w = 30
	field.expand = false
	mut row := button_bar()
	mut ok := dialog_button('  OK  ', true)
	mut cancel := dialog_button('Cancel', false)
	body.add(mut field)
	row.add(mut ok)
	row.add(mut cancel)
	body.add(mut row)
	mut w := app.dialog(title, mut body)
	w.default_button = ok
	app.set_focus(field)
	accepted := app.modal_for(mut w, owner) == 1
	result := field.text
	app.destroy_ctl(mut w)
	if !accepted { return none }
	return result
}

pub fn (mut app App) prompt(title string, text string, initial string) ?string {
	return app.prompt_for(app.top_window(), title, text, initial)
}

pub fn (mut app App) choice_for(owner ?&Ctl, title string, items []string, columns int) int {
	if !app.can_access(owner) { return -1 }
	mut body := grid()
	cols := clamp(columns, 1, 64)
	for i, text in items {
		if i / cols >= 64 { break }
		mut b := toolbutton(text)
		b.col = i % cols
		b.row = i / cols
		b.data = i
		b.changed = dialog_accept
		body.add(mut b)
	}
	mut w := app.dialog(title, mut body)
	result := app.modal_for(mut w, owner)
	app.destroy_ctl(mut w)
	return result
}

fn list_accept(mut c Ctl, mut app App) {
	mut list := if c.kind == .tree { &c } else { c.link or { return } }
	if isnil(list.selected_node) { return }
	mut w := c.owner_window_ptr()
	w.dialog_result = int(list.selected_node.data)
	app.close(mut w)
}

pub fn (mut app App) list_choice_for(owner ?&Ctl, title string, items []string, selected int) int {
	if !app.can_access(owner) { return -1 }
	mut body := box(true)
	mut list := tree()
	list.min_w = 54
	list.min_h = 12
	list.submit = list_accept
	for i, text in items {
		mut node := list.tree_add(none, text)
		node.data = i
		if i == selected { list.selected_node = node }
	}
	mut apply := toolbutton('Apply')
	apply.link = list
	apply.changed = list_accept
	body.add(mut list)
	body.add(mut apply)
	mut w := app.dialog(title, mut body)
	app.set_focus(list)
	result := app.modal_for(mut w, owner)
	app.destroy_ctl(mut w)
	return result
}

pub fn (mut app App) emoji_pick(owner ?&Ctl) ?string {
	items := ['😀', '😃', '😄', '😁', '😆', '😅', '😂', '🙂', '🙃', '😉', '😊',
		'😍', '🤔', '😎', '😭', '😴', '👍', '👎', '👏', '🙌', '🙏', '💪',
		'👋', '🤝', '🔥', '✨', '💡', '🎉', '🎯', '🚀', '✅', '❌', '🐱', '🐶',
		'🐧', '🐝', '🌱', '🌳', '🌻', '🍀', '🍎', '🍕', '☕', '🌍', '🏠',
		'📁', '📝', '🔗']
	at := app.choice_for(owner, 'Emoji', items, 8)
	if at < 0 { return none }
	return items[at]
}

pub fn (mut app App) history_for(owner ?&Ctl, mut editor Ctl) {
	if !app.can_access(owner) || !app.can_access(&editor) { return }
	editor.end_edit_group()
	mut labels := []string{}
	mut steps := []int{}
	for i := editor.edit.undo.len - 1; i >= 0 && labels.len < 128; i-- {
		change := editor.edit.undo[i]
		steps << -(editor.edit.undo.len - i)
		labels << 'Undo ${-steps.last()}: ' + history_label(change)
	}
	for i := editor.edit.redo.len - 1; i >= 0 && labels.len < 256; i-- {
		change := editor.edit.redo[i]
		steps << editor.edit.redo.len - i
		labels << 'Redo ${steps.last()}: ' + history_label(change)
	}
	if labels.len == 0 {
		app.notify('No edit history', 1500)
		return
	}
	at := app.list_choice_for(owner, 'History - restore through selected change', labels, 0)
	if at < 0 { return }
	for _ in 0 .. abs(steps[at]) {
		if steps[at] < 0 { editor.undo() } else { editor.redo() }
	}
}

fn history_label(change Change) string {
	text := if change.after == '' { 'delete ' + change.before } else { change.after }
	mut out := ''
	for r in text.runes()[..min(64, text.runes().len)] {
		out += if r < 32 || r == 127 { ' ' } else { r.str() }
	}
	return out
}

@[heap]
struct FilePicker {
mut:
	window    &Ctl = unsafe { nil }
	field     &Ctl = unsafe { nil }
	list      &Ctl = unsafe { nil }
	directory string
	result    string
}

fn (mut pick FilePicker) fill(path string) ! {
	directory := os.abs_path(path)
	mut names := os.ls(directory)!
	names.sort()
	pick.directory = directory
	pick.field.set_text(directory)
	pick.list.kids.clear()
	pick.list.selected_node = unsafe { nil }
	pick.list.top = 0
	mut parent := pick.list.tree_add(none, '..')
	parent.text = '..'
	for name in names { pick.list.tree_add(none, name) }
}

fn file_select(mut list Ctl, mut app App) {
	mut pick := unsafe { &FilePicker(list.user) }
	if !isnil(list.selected_node) { pick.field.set_text(os.join_path(pick.directory, list.selected_node.text)) }
	app.dirty = true
}

fn file_accept(mut c Ctl, mut app App) {
	mut pick := unsafe { &FilePicker(c.user) }
	if c.kind == .tree { file_select(mut c, mut app) }
	path := pick.field.text
	if os.is_dir(path) {
		pick.fill(path) or { app.notify(err.msg(), 2500) }
	} else if path != '' {
		pick.result = path
		app.close(mut pick.window)
	}
}

pub fn (mut app App) file_pick_for(owner ?&Ctl, directory string) ?string {
	if !app.can_access(owner) { return none }
	mut pick := &FilePicker{}
	mut body := box(true)
	pick.field = entry(directory, 0)
	pick.field.expand = false
	pick.field.user = pick
	pick.field.submit = file_accept
	pick.list = tree()
	pick.list.user = pick
	pick.list.changed = file_select
	pick.list.submit = file_accept
	mut open := button('Open file / enter folder')
	open.user = pick
	open.changed = file_accept
	body.add(mut pick.field)
	body.add(mut pick.list)
	body.add(mut open)
	pick.window = app.window('Open - Enter opens, Esc cancels', 60, 18)
	pick.window.dismissable = true
	pick.window.controls = window_close
	pick.window.add(mut body)
	pick.fill(directory) or { app.notify(err.msg(), 2500) }
	app.set_focus(pick.list)
	app.modal_for(mut pick.window, owner)
	result := pick.result
	app.destroy_ctl(mut pick.window)
	if result == '' { return none }
	return result
}

@[heap]
struct ColorPicker {
mut:
	sliders []&Ctl
	preview &Ctl = unsafe { nil }
}

fn draw_color_preview(mut c Ctl, mut screen Screen) {
	screen.fill(c.rect(), ` `, c.value, c.value)
}

fn color_picker_changed(mut c Ctl, mut app App) {
	mut picker := unsafe { &ColorPicker(c.user) }
	picker.preview.value = color_rgb(picker.sliders[0].value, picker.sliders[1].value, picker.sliders[2].value)
	app.dirty = true
}

// Returns an RGB value (0xRRGGBB), or none on cancel.
pub fn (mut app App) color_pick(owner ?&Ctl, title string, rgb int) ?int {
	if !app.can_access(owner) { return none }
	mut body := box(true)
	mut r := slider(0, 255)
	r.value = (rgb >> 16) & 255
	mut g := slider(0, 255)
	g.value = (rgb >> 8) & 255
	mut b := slider(0, 255)
	b.value = rgb & 255
	mut sliders := [r, g, b]
	mut preview := canvas(4, 2, draw_color_preview)
	preview.value = 0x1000000 | rgb
	picker := &ColorPicker{ sliders: sliders, preview: preview }
	for i, mut ctl in sliders {
		ctl.user = picker
		ctl.changed = color_picker_changed
		mut name := label(['Red', 'Green', 'Blue'][i])
		body.add(mut name)
		body.add(mut ctl)
	}
	mut preview_row := box(false)
	mut preview_label := label('Preview:')
	preview_row.add(mut preview_label)
	preview_row.add(mut preview)
	body.add(mut preview_row)
	mut row := button_bar()
	mut ok := dialog_button('OK', true)
	mut cancel := dialog_button('Cancel', false)
	row.add(mut ok)
	row.add(mut cancel)
	body.add(mut row)
	mut w := app.dialog(title, mut body)
	w.default_button = ok
	accepted := app.modal_for(mut w, owner) == 1
	result := r.value << 16 | g.value << 8 | b.value
	app.destroy_ctl(mut w)
	if !accepted { return none }
	return result
}
