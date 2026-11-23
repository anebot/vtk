module vtk

fn test_close_uses_owning_app_and_preserves_veto_and_focus() {
	mut app := new_app()
	mut other := new_app()
	mut w := app.window('Owner', 30, 8)
	mut field := entry('', 0)
	w.add(mut field)
	app.set_focus(field)
	mut untouched := other.window('Other app', 30, 8)
	w.closing = fn (mut c Ctl, mut owner App) bool {
		c.data++
		owner.clipboard_set(c.text)
		return c.value == 1
	}
	app.dirty = false
	other.dirty = false
	assert !w.close()
	assert !w.closed && app.focus == field && !app.dirty
	assert app.clipboard_text() == 'Owner' && other.clipboard_text() == ''
	w.value = 1
	assert w.close()
	assert w.closed && isnil(app.focus) && app.dirty
	assert w.close() && w.data == 2
	assert !untouched.closed && !other.dirty
}

fn test_close_propagates_owned_dialog_veto_and_closes_nested_dialogs() {
	mut app := new_app()
	mut owner := app.window('Owner', 30, 8)
	mut child := app.window('Child', 24, 6)
	child.modal_owner = owner
	mut nested := app.window('Nested', 24, 6)
	nested.modal_parent = child
	child.closing = fn (mut c Ctl, mut _ App) bool { return c.value == 1 }
	assert !owner.close()
	assert !owner.closed && !child.closed && !nested.closed
	child.value = 1
	assert owner.close()
	assert owner.closed && child.closed && nested.closed
}

fn test_close_rejects_detached_windows_and_nonwindow_controls() {
	mut detached := new_ctl(.window)
	assert !detached.close() && !detached.closed
	mut app := new_app()
	mut w := app.window('Window', 30, 8)
	mut field := entry('', 0)
	w.add(mut field)
	assert !field.close() && !field.closed && !w.closed
	w.detach()
	assert !w.close() && !w.closed
}
