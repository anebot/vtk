module vtk

fn test_detach_releases_desktop_and_resize_cache_references() {
	mut app := new_app()
	app.set_desktop_count(2)
	mut w := app.window('Window', 30, 8)
	mut child := button('Focus')
	w.add(mut child)
	app.set_focus(child)
	app.dispatch(Event{kind: .resize, width: 100, height: 30})
	assert app.window_layout.windows.len == 1
	assert app.switch_desktop(2) && app.desktop_focus[0] == ?&Ctl(child)
	app.destroy_ctl(mut w)
	assert app.desktop_focus[0] == none && app.window_layout.windows.len == 0
	app.fini()
	assert app.windows.cap == 0 && app.screen.cells.len == 0 && app.screen.front.len == 0
}

fn test_disposal_releases_callback_context_without_destroying_associations() {
	mut app := new_app()
	defer { app.fini() }
	mut w := app.window('Window', 30, 8)
	mut child := button('Child')
	child.user = w
	child.link = w
	child.changed = fn [w] (mut _ Ctl, mut app App) { app.clipboard_set(w.text) }
	child.destroy = fn (mut c Ctl, mut _ App) {
		assert c.link != none && c.user != voidptr(0)
		c.data++
	}
	w.add(mut child)
	app.destroy_ctl(mut child)
	assert child.data == 1 && child.link == none && child.user == voidptr(0)
	assert child.changed == none && child.destroy == none && !w.is_closed()
	app.clock_clicked = fn [w] (_ Event, mut app App) { app.clipboard_set(w.text) }
	app.ctrl_c_handler = fn [w] (mut app App) { app.clipboard_set(w.text) }
	app.notify('Notice', 0)
	app.fini()
	assert app.clock_clicked == none && app.ctrl_c_handler == none && app.notices.cap == 0
}

fn test_edit_reset_releases_old_group_and_history_storage() {
	mut c := entry('before', 0)
	c.begin_edit_group()
	assert c.replace_range(0, 6, 'after')
	c.end_edit_group()
	history := c.edit.undo_changes()
	assert c.undo() && c.redo()
	c.set_text('loaded')
	assert c.edit.undo.cap == 0 && c.edit.redo.cap == 0 && c.edit.group_text == ''
	assert history.len == 1 && history[0].before == 'before' && history[0].after == 'after'
}

fn test_event_loop_disposes_closed_windows_without_a_second_cleanup_call() {
	mut app := new_app()
	app.bar_clock = false
	app.register('Keep desktop running', fn (mut _ App, _ voidptr) {}, voidptr(0))
	mut w := app.window('Window', 30, 8)
	mut child := button('Child')
	child.destroy = fn (mut c Ctl, mut _ App) { c.data++ }
	w.add(mut child)
	assert app.close(mut w)
	assert w.children() == [child] && child.data == 0
	assert app.step(0)
	assert app.window_list().len == 0 && w.children().len == 0 && child.data == 1
	app.fini()
	assert child.data == 1
}

fn test_closed_terminal_drops_pending_input_and_ignores_future_writes() {
	mut terminal := new_terminal(10, 2)
	terminal.write('queued')
	assert terminal.pending == 'queued'
	terminal.close()
	terminal.write('ignored')
	assert terminal.pending == '' && terminal.has_exited()
}

fn test_menu_attachment_rechecks_cycles_after_leave_callbacks() {
	mut app := new_app()
	defer { app.fini() }
	mut w := app.window('Window', 30, 8)
	mut target := button('Target')
	w.add(mut target)
	mut menu := context_menu()
	mut item := menu.menu_item('Move target', fn (mut _ Ctl, mut _ App) {})
	item.link = target
	item.mouse_leave = fn (mut c Ctl, mut _ App) {
		mut menu := c.parent_ctl() or { return }
		mut target := c.link or { return }
		menu.add(mut target)
	}
	app.open_menu(menu, 0, 0)
	app.dispatch(Event{kind: .mouse, x: 1, y: 1, motion: true})
	assert item.is_hovered()
	target.set_menu(mut menu)
	assert target.context_menu() == none && target.parent_ctl() == ?&Ctl(menu)
	assert menu.parent_ctl() == none && menu.children() == [item, target]
	app.destroy_ctl(mut menu)
}

fn test_windows_remain_roots_when_added_to_containers() {
	mut app := new_app()
	defer { app.fini() }
	mut one := app.window('One', 30, 8)
	mut two := app.window('Two', 30, 8)
	mut body := box(true)
	one.add(mut body)
	body.add(mut two)
	assert body.children().len == 0 && two.parent_ctl() == none && app.window_list() == [one, two]
}

fn test_replacement_callbacks_cannot_duplicate_a_reparented_control() {
	mut app := new_app()
	defer { app.fini() }
	mut w := app.window('Window', 30, 8)
	mut body := box(true)
	mut old := button('Old')
	mut replacement := button('Replacement')
	old.link = replacement
	old.mouse_leave = fn (mut c Ctl, mut _ App) {
		mut parent := c.parent_ctl() or { return }
		mut replacement := c.link or { return }
		parent.add(mut replacement)
	}
	body.add(mut old)
	w.add(mut body)
	app.redraw()
	r := old.rect()
	app.dispatch(Event{kind: .mouse, x: r.x, y: r.y, motion: true})
	assert old.is_hovered()
	assert !body.replace(mut old, mut replacement)
	assert body.children() == [replacement] && old.parent_ctl() == none
	app.destroy_ctl(mut old)
}
