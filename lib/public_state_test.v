module vtk

fn test_public_lookups_return_none_and_present_controls() {
	mut app := new_app()
	assert app.top_window() == none && app.focused_ctl() == none && app.hovered_ctl() == none
	mut button := button('OK')
	assert button.parent_ctl() == none && button.owner_window() == none
	assert button.context_menu() == none && button.tree_selection() == none
	assert button.get_default_button() == none && button.get_modal_owner() == none
	assert button.terminal_state() == none && button.hit(0, 0) == none
	app.set_focus(button)
	assert app.focused_ctl() == none
	mut w := app.window('Queries', 30, 8)
	w.add(mut button)
	app.set_focus(button)
	app.redraw()
	assert app.top_window() == ?&Ctl(w) && app.focused_ctl() == ?&Ctl(button)
	assert button.parent_ctl() == ?&Ctl(w) && button.owner_window() == ?&Ctl(w)
	r := button.rect()
	assert button.hit(r.x, r.y) == ?&Ctl(button)
	assert button.hit(r.x - 1, r.y) == none
	assert app.snapshot().contains('OK') && app.is_running()
	assert !w.is_closed() && !w.is_minimized() && !w.is_maximized() && !w.is_modal()
	assert app.get_desktop_count() == 1 && app.get_active_desktop() == 1 && w.get_desktop_id() == 1
	mut windows := app.window_list()
	mut children := w.children()
	windows.clear()
	children.clear()
	assert app.window_list().len == 1 && w.children().len == 1
	mut menu := context_menu()
	button.set_menu(mut menu)
	assert button.context_menu() == ?&Ctl(menu)
	assert !button.replace(mut menu, mut w)
	assert button.context_menu() == ?&Ctl(menu) && app.top_window() == ?&Ctl(w)
	menu.detach()
	assert button.context_menu() == none && menu.owner_window() == none
}

fn test_optional_control_references_compare_identity() {
	first := ?&Ctl(button('Same text'))
	second := ?&Ctl(button('Same text'))
	assert first != second
	assert first == first
}

fn test_control_replacement_preserves_order_and_repairs_references() {
	mut app := new_app()
	mut w := app.window('Replace', 40, 12)
	mut body := box(true)
	mut first := button('First')
	mut last := button('Last')
	mut next := button('Next')
	body.add(mut first)
	body.add(mut last)
	w.add(mut body)
	mut panes := split(false, 500)
	assert body.replace(mut first, mut panes)
	panes.add(mut first)
	panes.add(mut next)
	assert body.children() == [panes, last] && panes.children() == [first, next]
	app.set_focus(next)
	assert body.replace(mut panes, mut first)
	panes.clear()
	assert body.children() == [first, last] && panes.children().len == 0
	assert first.parent_ctl() == ?&Ctl(body) && next.parent_ctl() == none
	assert next.owner_window() == none && app.focused_ctl() != ?&Ctl(next)
	assert !body.replace(mut last, mut w)
	assert body.children() == [first, last] && w.parent_ctl() == none
	assert app.set_default_button(mut w, first)
	assert w.get_default_button() == ?&Ctl(first)
	assert !app.set_default_button(mut w, next)
	app.set_focus(first)
	first.detach()
	assert w.get_default_button() == none && app.focused_ctl() != ?&Ctl(first)
	assert first.parent_ctl() == none && first.owner_window() == none
	w.detach()
	assert app.window_list().len == 0 && app.top_window() == none && app.focused_ctl() == none
}

fn test_tree_selection_rejects_foreign_nodes_and_clears_on_detach() {
	mut nodes := tree()
	mut root := nodes.tree_add(none, 'Root')
	child := nodes.tree_add(root, 'Child')
	mut other := tree()
	foreign := other.tree_add(none, 'Foreign')
	assert nodes.tree_select(child) && nodes.tree_selection() == ?&Ctl(child)
	assert !nodes.tree_select(foreign) && nodes.tree_selection() == ?&Ctl(child)
	root.detach()
	assert nodes.tree_selection() == none && nodes.children().len == 0
	assert nodes.tree_select(none)
}

fn test_render_and_history_snapshots_do_not_expose_mutable_storage() {
	mut screen := Screen{}
	screen.resize(2, 1)
	screen.text(0, 0, 'A', white, black, 0)
	mut cells := screen.cell_snapshot()
	cells[0].glyph = 'B'
	assert screen.snapshot() == 'A '
	width, height := screen.size()
	assert width == 2 && height == 1
	assert screen.set_cursor(1, 0, .block)
	screen.resize(1, 1)
	assert screen.cursor_x == -1 && screen.cursor_y == -1
	assert !screen.set_cursor(1, 0, .block)
	mut terminal := new_terminal(2, 1)
	terminal.feed('A')
	mut terminal_cells := terminal.cell_snapshot()
	terminal_cells[0].glyph = 'B'
	assert terminal.cell_snapshot()[0].glyph == 'A'
	cols, rows := terminal.size()
	assert cols == 2 && rows == 1 && !terminal.has_exited()
	x, y, hidden := terminal.cursor()
	assert x == 1 && y == 0 && !hidden
	terminal.close()
	assert terminal.has_exited()
	mut editor := entry('', 0)
	assert editor.replace_selection('A')
	mut undo := editor.edit.undo_changes()
	undo.clear()
	assert editor.edit.undo_changes().len == 1 && editor.edit.revision_number() == 1
	assert editor.undo() && editor.edit.redo_changes().len == 1
}
