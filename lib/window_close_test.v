module vtk

fn test_close_checks_ownership_and_preserves_veto_and_focus() {
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
		return c.data > 1
	}
	app.dirty = false
	other.dirty = false
	assert !other.close(mut w)
	assert w.data == 0 && app.clipboard_text() == ''
	assert !app.close(mut w)
	assert !w.closed && app.focus == field && !app.dirty
	assert app.clipboard_text() == 'Owner' && other.clipboard_text() == ''
	assert app.close(mut w)
	assert w.closed && isnil(app.focus) && app.dirty
	assert app.close(mut w) && w.data == 2
	assert !other.close(mut w) && w.data == 2
	assert !untouched.closed && !other.dirty
}

fn test_close_propagates_owned_dialog_veto_and_closes_nested_dialogs() {
	mut app := new_app()
	mut owner := app.window('Owner', 30, 8)
	mut child := app.window('Child', 24, 6)
	child.modal_owner = owner
	mut nested := app.window('Nested', 24, 6)
	nested.modal_parent = child
	child.closing = fn (mut c Ctl, mut _ App) bool { return c.data == 1 }
	assert !app.close(mut owner)
	assert !owner.closed && !child.closed && !nested.closed
	child.data = 1
	assert app.close(mut owner)
	assert owner.closed && child.closed && nested.closed
}

fn test_close_rejects_detached_windows_and_nonwindow_controls() {
	mut app := new_app()
	mut detached := new_ctl(.window)
	assert !app.close(mut detached) && !detached.closed
	mut w := app.window('Window', 30, 8)
	mut field := entry('', 0)
	w.add(mut field)
	assert !app.close(mut field) && !field.closed && !w.closed
	w.detach()
	assert !app.close(mut w) && !w.closed
}

fn test_quit_checks_all_vetoes_before_closing_and_releasing_input() {
	mut app := new_app()
	defer { app.fini() }
	mut owner := app.window('Owner', 30, 8)
	mut terminal := &Ctl{kind: .terminal, term: new_terminal(10, 2), focusable: true}
	owner.add(mut terminal)
	mut dialog := app.window('Dialog', 24, 6)
	dialog.modal_owner = owner
	owner.closing = fn (mut c Ctl, mut _ App) bool {
		c.data++
		return true
	}
	dialog.closing = fn (mut c Ctl, mut _ App) bool {
		c.data++
		return c.data > 1
	}
	app.set_focus(terminal)
	app.drag, app.scroll_drag, app.placement, app.title_click = terminal, terminal, owner, owner
	mut menu := context_menu()
	menu.menu_item('Keep', fn (mut _ Ctl, mut _ App) {})
	app.open_menu(menu, 0, 0)
	app.quit()
	assert app.is_running() && !owner.is_closed() && !dialog.is_closed()
	assert owner.data == 1 && dialog.data == 1 && !terminal.term.has_exited()
	assert app.focused_ctl() == ?&Ctl(terminal) && app.popups.len == 1
	assert app.drag == terminal && app.placement == owner
	app.quit()
	assert !app.is_running() && owner.is_closed() && dialog.is_closed()
	assert owner.data == 2 && dialog.data == 2 && terminal.term.has_exited()
	assert owner.children() == [terminal] && app.window_list().len == 2
	assert app.focused_ctl() == none && app.popups.len == 0
	assert isnil(app.drag) && isnil(app.scroll_drag) && isnil(app.placement) && isnil(app.title_click)
}

fn test_fini_disposes_closed_and_vetoing_windows_once() {
	mut app := new_app()
	mut veto := app.window('Veto', 30, 8)
	veto.closing = fn (mut c Ctl, mut _ App) bool { c.data += 100; return false }
	veto.destroy = fn (mut c Ctl, mut app App) { c.data++; app.fini() }
	mut closed := app.window('Closed', 30, 8)
	mut child := button('Child')
	child.destroy = fn (mut c Ctl, mut app App) { c.data++; app.destroy_ctl(mut c) }
	mut menu := context_menu()
	menu.destroy = fn (mut c Ctl, mut _ App) { c.data++ }
	child.set_menu(mut menu)
	closed.add(mut child)
	assert app.close(mut closed)
	assert child.data == 0 && child.parent_ctl() == ?&Ctl(closed)
	app.after(0, fn (mut _ App) { assert false, 'fini must cancel pending hooks' })
	app.fini()
	assert !app.is_running() && app.window_list().len == 0 && app.focused_ctl() == none
	assert veto.data == 1 && child.data == 1 && menu.data == 1
	assert veto.is_closed() && closed.is_closed() && child.is_closed()
	assert closed.children().len == 0 && child.parent_ctl() == none && child.context_menu() == none
	assert app.hooks.len == 0 && !app.step(0)
	app.fini()
	app.destroy_ctl(mut child)
	app.destroy_ctl(mut veto)
	assert veto.data == 1 && child.data == 1 && menu.data == 1
	mut fresh := box(true)
	fresh.add(mut child)
	app.raise(mut veto)
	assert fresh.children().len == 0 && app.window_list().len == 0
}

fn test_destroy_respects_veto_and_survives_fini_from_a_child_callback() {
	mut app := new_app()
	mut w := app.window('Owner', 30, 8)
	w.closing = fn (mut c Ctl, mut _ App) bool { c.data++; return c.data > 1 }
	w.destroy = fn (mut c Ctl, mut _ App) { c.data += 10 }
	mut child := button('Child')
	child.destroy = fn (mut c Ctl, mut app App) { c.data++; app.fini() }
	w.add(mut child)
	app.destroy_ctl(mut w)
	assert !w.is_closed() && w.children() == [child] && child.data == 0 && w.data == 1
	app.destroy_ctl(mut w)
	assert w.is_closed() && w.children().len == 0 && child.data == 1 && w.data == 12
	assert app.window_list().len == 0 && !app.is_running()
	app.destroy_ctl(mut w)
	assert child.data == 1 && w.data == 12
}

fn test_close_rejects_reentry_and_quit_checks_callback_created_windows() {
	mut app := new_app()
	defer { app.fini() }
	mut w := app.window('Owner', 30, 8)
	w.closing = fn (mut c Ctl, mut app App) bool {
		c.data++
		assert !app.close(mut c)
		app.quit()
		mut created := app.window('Created', 24, 6)
		created.closing = fn (mut c Ctl, mut _ App) bool { c.data++; return false }
		return true
	}
	app.quit()
	assert app.is_running() && !w.is_closed() && w.data == 1
	created := app.window_list().last()
	assert !created.is_closed() && created.data == 1
}

fn test_close_callback_can_transfer_a_window_without_foreign_cleanup() {
	mut app := new_app()
	mut other := new_app()
	mut w := app.window('Transfer', 30, 8)
	w.user = other
	w.closing = fn (mut c Ctl, mut _ App) bool {
		mut other := unsafe { &App(c.user) }
		c.detach()
		other.raise(mut c)
		return true
	}
	assert !app.close(mut w)
	assert !w.is_closed() && w.app == other && app.window_list().len == 0
	assert other.window_list() == [w]
	other.fini()
}

fn test_quit_allows_a_closing_callback_to_run_a_confirmation_dialog() {
	mut app := new_app()
	defer { app.fini() }
	mut w := app.window('Owner', 30, 8)
	w.closing = fn (mut c Ctl, mut app App) bool {
		c.data++
		app.after(0, fn (mut app App) {
			mut dialog := app.top_window_ptr()
			dialog.dialog_result = 1
			assert app.close(mut dialog)
		})
		return app.confirm_for(&c, 'Confirm', 'Close window?')
	}
	app.quit()
	assert !app.is_running() && w.is_closed() && w.data == 1 && app.window_list() == [w]
}

fn test_destroy_callback_can_rescue_a_sibling_into_another_app() {
	mut app := new_app()
	mut other := new_app()
	defer { other.fini() }
	mut w := app.window('Owner', 30, 8)
	mut target := other.window('Target', 30, 8)
	mut first := button('First')
	mut moved := &Ctl{kind: .terminal, term: new_terminal(10, 2)}
	moved.destroy = fn (mut c Ctl, mut _ App) { c.data++ }
	first.link = target
	first.destroy = fn (mut c Ctl, mut _ App) {
		parent := c.parent_ctl() or { return }
		mut sibling := parent.children().last()
		mut target := c.link or { return }
		target.add(mut sibling)
	}
	w.add(mut first)
	w.add(mut moved)
	app.fini()
	assert moved.owner_window() == ?&Ctl(target) && moved.data == 0 && !moved.term.has_exited()
	assert target.children() == [moved] && w.children().len == 0
}

fn test_destroy_disposes_detached_windows_without_requesting_close() {
	mut app := new_app()
	mut w := new_ctl(.window)
	w.closing = fn (mut _ Ctl, mut _ App) bool {
		assert false, 'a detached window has no owning app to request closure'
		return false
	}
	w.destroy = fn (mut c Ctl, mut _ App) { c.data++ }
	mut control := &Ctl{kind: .terminal, term: new_terminal(10, 2)}
	w.add(mut control)
	app.destroy_ctl(mut w)
	assert w.is_closed() && w.data == 1 && w.children().len == 0
	assert control.term.has_exited() && control.parent_ctl() == none && app.window_list().len == 0
	app.destroy_ctl(mut w)
	assert w.data == 1
}
