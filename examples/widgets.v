module main

import vtk
import time

fn table_cell(_ &vtk.Ctl, row int, col int) string {
	return if col == 0 { 'Row ${row + 1}' } else { '${row * row}' }
}

fn changed(mut c vtk.Ctl, mut app vtk.App) { app.notify('${c.kind}: ${c.value}', 1200) }

fn selected_date(mut c vtk.Ctl, mut app vtk.App) { app.notify('Selected ${c.text}', 1500) }

fn show_calendar(mut app vtk.App) {
	if date := app.date_pick(app.top_window(), 'Calendar', time.now()) {
		app.notify('Selected ${date.year:04}-${date.month:02}-${date.day:02}', 1500)
	}
}

fn calendar_action(mut _ vtk.Ctl, mut app vtk.App) { show_calendar(mut app) }

fn clock_clicked(event vtk.Event, mut app vtk.App) {
	if event.button == .right {
		mut menu := vtk.context_menu()
		menu.menu_item('Calendar...', calendar_action)
		app.open_menu(menu, event.x, event.y)
	} else { show_calendar(mut app) }
}

fn hover_status(mut c vtk.Ctl, mut _ vtk.App) {
	mut status := unsafe { &vtk.Ctl(c.user) }
	status.set_text(if c.is_hovered() { 'Mouse over ${c.kind}' } else { 'Tab cycles controls | F10 menus | Ctrl-C quits' })
}

fn main() {
	mut app := vtk.new_app()
	app.clock_clicked = clock_clicked
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
	mut blocks := vtk.progress()
	blocks.blocky = true
	blocks.value = 60
	values.add(mut blocks)
	body.add(mut values)
	mut activity := vtk.spinner('Working')
	body.add(mut activity)
	mut tabs := vtk.tabs()
	tabs.reorderable = true
	mut table := vtk.table(table_cell, 100)
	table.table_column('Name', min_width: 8)
	table.table_column('Square', numeric: true, align: .right, min_width: 8)
	table.table.sortable = true
	table.table.resizable_columns = true
	table.table.reorderable_columns = true
	table.table.multi_select = true
	tabs.add_tab('Table', mut table)
	mut text := vtk.multiline('Word wrapping keeps words together while retaining the original text.\nLong words such as abcdefghijklmnopqrstuvwxyz still wrap when necessary.\nUnicode: café 👩‍💻 🇪🇸 and tabs\tstay intact.')
	text.set_wrap_mode(.word)
	text.scrollbar = true
	tabs.add_tab('Text', mut text)
	mut tree := vtk.tree()
	root := tree.tree_add(none, 'Library')
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
	mut calendar := vtk.date_picker(time.now())
	calendar.changed = selected_date
	tabs.add_tab('Calendar', mut calendar)
	body.add(mut tabs)
	mut status := vtk.statusbar('Tab cycles controls | F10 menus | Ctrl-C quits')
	mut hovered_controls := [check, switch, combo, slider, spin, table, tree, radio, calendar]
	for mut ctl in hovered_controls {
		ctl.user = status
		ctl.mouse_enter = hover_status
		ctl.mouse_leave = hover_status
	}
	body.add(mut status)
	w.add(mut body)
	app.run() or { eprintln(err) }
}
