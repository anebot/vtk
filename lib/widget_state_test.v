module vtk

fn test_table_row_count_drives_navigation_scrolling_copy_and_clicks() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Table', 32, 7)
	mut rows := table(fn (_ &Ctl, row int, col int) string { return '${row}:${col}' }, 8)
	rows.table_column('First')
	rows.table_column('Second')
	w.add(mut rows)
	app.set_focus(rows)
	app.redraw()
	app.dispatch(Event{ key: int(Key.end) })
	app.redraw()
	assert rows.value == 7 && rows.top == 4
	assert app.copy_focus() && app.clipboard_text() == '7:0\t7:1'
	assert app.scroll_ctl(mut rows, -100)
	app.redraw()
	assert rows.top == 0 && rows.value == 7
	app.dispatch(Event{ kind: .mouse, x: rows.x + 1, y: rows.y + 2, button: .left, pressed: true })
	assert rows.value == 1 && !rows.scroll_hold
	assert app.copy_focus() && app.clipboard_text() == '1:0\t1:1'
	rows.row_count = 0
	rows.invalidate()
	app.redraw()
	assert !app.copy_focus()
}

fn test_tree_selection_and_expansion_preserve_callback_associations() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Tree', 32, 10)
	mut body := box(true)
	mut nodes := tree()
	mut status := label('Ready')
	nodes.link = status
	nodes.changed = fn (mut c Ctl, mut _ App) {
		if mut status := c.link { status.set_text((c.selected_node or { panic('expected selected node') }).text) }
	}
	mut root := nodes.tree_add(none, 'Root')
	child := nodes.tree_add(root, 'Child')
	other := nodes.tree_add(none, 'Other')
	body.add(mut nodes)
	body.add(mut status)
	w.add(mut body)
	app.set_focus(nodes)
	app.redraw()
	assert same_ctl(nodes.selected_node, root) && nodes.tree_rows().len == 3
	app.dispatch(Event{ key: int(Key.left) })
	assert !root.expanded && nodes.tree_rows().len == 2 && status.text == 'Root'
	app.dispatch(Event{ key: int(Key.down) })
	assert same_ctl(nodes.selected_node, other) && status.text == 'Other'
	app.dispatch(Event{ key: int(Key.home) })
	app.dispatch(Event{ key: int(Key.right) })
	assert root.expanded && nodes.tree_rows().len == 3
	app.dispatch(Event{ key: int(Key.down) })
	assert same_ctl(nodes.selected_node, child) && status.text == 'Child'
	app.dispatch(Event{ kind: .mouse, x: nodes.x + 2, y: nodes.y, button: .left, pressed: true })
	assert same_ctl(nodes.selected_node, root) && !root.expanded && status.text == 'Root'
	app.dispatch(Event{ key: int(Key.enter) })
	assert root.expanded
	nodes.submit = fn (mut c Ctl, mut app App) { app.clipboard_set((c.selected_node or { panic('expected selected node') }).text) }
	app.dispatch(Event{ key: int(Key.enter) })
	assert root.expanded && app.clipboard_text() == 'Root'
	assert nodes.link == ?&Ctl(status)
}

fn test_dialog_result_and_default_button_preserve_callback_associations() {
	mut app := new_app()
	mut body := box(true)
	mut field := entry('', 0)
	mut accept := button('Accept')
	accept.data = 7
	accept.changed = dialog_accept
	mut associated := button('Context')
	associated.data = 99
	associated.changed = dialog_accept
	body.add(mut field)
	body.add(mut accept)
	body.add(mut associated)
	mut dialog := app.dialog('Default button', mut body)
	dialog.default_button = accept
	dialog.link = associated
	app.set_focus(field)
	app.after(0, fn [dialog, associated, accept] (mut app App) {
		app.dispatch(Event{ key: int(Key.enter) })
		assert dialog.link == ?&Ctl(associated) && same_ctl(dialog.default_button, accept)
		app.quit() // A regression must fail instead of blocking the modal loop.
	})
	assert app.modal_for(mut dialog, none) == 7
	assert dialog.link == none && dialog.get_default_button() == none && associated.data == 99
	app.destroy_ctl(mut dialog)
}
