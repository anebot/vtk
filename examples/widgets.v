module main

import vtk

fn table_cell(_ &vtk.Ctl, row int, col int) string {
	return if col == 0 { 'Row ${row + 1}' } else { '${row * row}' }
}

fn changed(mut c vtk.Ctl, mut app vtk.App) { app.notify('${c.kind}: ${c.value}', 1200) }

fn hover_status(mut c vtk.Ctl, mut app vtk.App) {
	mut status := unsafe { &vtk.Ctl(c.user) }
	status.set_text(if c.hovered { 'Mouse over ${c.kind}' } else { 'Tab cycles controls | F10 menus | Ctrl-C quits' })
	app.dirty = true
}

fn main() {
	mut app := vtk.new_app()
	app.set_mouse_cursor(vtk.MouseCursor{ enabled: true })
	mut w := app.window('VTK widgets', 74, 24)
	mut body := vtk.box(true)
	mut controls := vtk.flow()
	mut check := vtk.checkbox('Checkbox', true)
	check.changed = changed
	mut switch := vtk.switch_ctl('Switch', true)
	switch.changed = changed
	mut combo := vtk.combo()
	combo.add_item('Borland')
	combo.add_item('Modern')
	combo.add_item('Serial')
	combo.value = 0
	combo.changed = changed
	controls.add(mut check)
	controls.add(mut switch)
	controls.add(mut combo)
	body.add(mut controls)
	mut values := vtk.box(false)
	mut slider := vtk.slider(0, 100)
	slider.value = 40
	slider.changed = changed
	mut spin := vtk.spin(-10, 10)
	spin.changed = changed
	values.add(mut slider)
	values.add(mut spin)
	body.add(mut values)
	mut activity := vtk.spinner('Working')
	body.add(mut activity)
	mut tabs := vtk.tabs()
	mut table := vtk.table(table_cell)
	table.table_column('Name')
	table.table_column('Square')
	table.high = 100
	tabs.add_tab('Table', mut table)
	mut tree := vtk.tree()
	root := tree.tree_add(unsafe { nil }, 'Library')
	tree.tree_add(root, 'Controls')
	tree.tree_add(root, 'Layouts')
	tree.tree_add(root, 'Editors')
	tabs.add_tab('Tree', mut tree)
	mut radio := vtk.radio()
	radio.add_item('One')
	radio.add_item('Two')
	radio.add_item('Three')
	radio.value = 0
	tabs.add_tab('Radio', mut radio)
	body.add(mut tabs)
	mut status := vtk.statusbar('Tab cycles controls | F10 menus | Ctrl-C quits')
	mut hovered_controls := [check, switch, combo, slider, spin, table, tree, radio]
	for mut ctl in hovered_controls {
		ctl.user = status
		ctl.mouse_enter = hover_status
		ctl.mouse_leave = hover_status
	}
	body.add(mut status)
	w.add(mut body)
	app.run() or { eprintln(err) }
}
