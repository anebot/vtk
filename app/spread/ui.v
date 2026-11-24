module spread

import os
import vtk

const app_name = 'VtkSheets'
const app_version = '0.1.0'

enum Action { new_sheet open save save_as import_csv export_csv quit edit apply copy paste undo redo ascending descending reset color clear_color chart help about }

@[heap]
struct BookView {
mut:
	book Book
	window &vtk.Ctl
	tabs &vtk.Ctl
	formula &vtk.Ctl
	address &vtk.Ctl
	status &vtk.Ctl
	mode &vtk.Ctl
	multiple &vtk.Ctl
	modified bool
}

@[heap]
struct SheetView {
mut:
	view &BookView
	sheet &Sheet
	grid &vtk.Ctl
}

fn sheet_cell(c &vtk.Ctl, row int, column int) string {
	mut context := unsafe { &SheetView(c.user) }
	return context.sheet.display(row, column)
}

fn sheet_raw(c &vtk.Ctl, row int, column int) string {
	context := unsafe { &SheetView(c.user) }
	return context.sheet.raw(row, column)
}

fn sheet_edit(mut c vtk.Ctl, edits []vtk.TableCellEdit) ! {
	mut context := unsafe { &SheetView(c.user) }
	context.sheet.apply(edits)!
	context.view.modified = context.view.book.dirty()
}

fn sheet_style(c &vtk.Ctl, row int, column int) vtk.TableCellStyle {
	mut context := unsafe { &SheetView(c.user) }
	if style := context.sheet.data.styles[address(row, column)] { return style }
	if row == 0 { return vtk.TableCellStyle{fg: vtk.white, bg: vtk.blue, attr: vtk.bold} }
	if context.sheet.raw(row, column).starts_with('=') {
		return vtk.TableCellStyle{fg: if context.sheet.display(row, column).starts_with('#') { vtk.red } else { vtk.cyan }}
	}
	return vtk.TableCellStyle{}
}

fn sheet_compare(c &vtk.Ctl, left int, right int, column int) int {
	mut context := unsafe { &SheetView(c.user) }
	mut visiting := map[string]bool{}
	a := context.sheet.number(left, column, mut visiting) or {
		context.sheet.number(right, column, mut visiting) or {
			return compare_strings(context.sheet.display(left, column).to_lower(), context.sheet.display(right, column).to_lower())
		}
		return 1
	}
	b := context.sheet.number(right, column, mut visiting) or { return -1 }
	return if a < b { -1 } else if a > b { 1 } else { 0 }
}

fn (view &BookView) current() ?&SheetView {
	pages := view.tabs.children()
	if view.tabs.value < 0 || view.tabs.value >= pages.len { return none }
	return unsafe { &SheetView(pages[view.tabs.value].user) }
}

fn (mut view BookView) update() {
	mut current := view.current() or { return }
	grid := current.grid
	view.window.set_text('VTK Sheets · ${if view.book.path == '' { 'Untitled' } else { os.file_name(view.book.path) }}${if view.modified { ' *' } else { '' }}')
	range := grid.table_selection()
	if range.x >= 0 {
		view.address.set_text(address(grid.value, grid.table_selected_column()))
		view.formula.set_text(current.sheet.raw(grid.value, grid.table_selected_column()))
	} else { view.address.set_text('—'); view.formula.set_text('') }
	view.status.set_text(if range.x < 0 { 'No selection' } else {
		'${range.x2 - range.x + 1} columns × ${range.y2 - range.y + 1} rows · F2 edit · Ctrl-click header: sort · Alt-drag row number: move'
	})
}

fn sheet_selected(mut c vtk.Ctl, mut _ vtk.App) {
	mut context := unsafe { &SheetView(c.user) }
	context.view.update()
}

fn sheet_changed(mut c vtk.Ctl, mut app vtk.App) {
	sheet_selected(mut c, mut app)
}

fn sheet_tab_changed(mut c vtk.Ctl, mut _ vtk.App) {
	mut view := unsafe { &BookView(c.user) }
	view.update()
}

fn sheet_tab_moved(mut c vtk.Ctl, from int, to int, mut _ vtk.App) {
	mut view := unsafe { &BookView(c.user) }
	sheet := view.book.sheets[from]
	view.book.sheets.delete(from)
	view.book.sheets.insert(to, sheet)
	view.modified = view.book.dirty()
	view.update()
}

fn configure_selection(mut c vtk.Ctl, mut app vtk.App) {
	mut view := unsafe { &BookView(c.user) }
	mut current := view.current() or { return }
	current.grid.table.selection = match view.mode.value { 0 { .rows } 1 { .columns } 2 { .cells } else { .none } }
	current.grid.table.multi_select = view.multiple.value != 0
	if current.grid.row_count > 0 {
		x := max(0, current.grid.table_view_column(current.grid.table_selected_column()))
		y := max(0, current.grid.table_view_row(current.grid.value))
		current.grid.table_select(x, y, x, y)
	}
	current.grid.invalidate()
	view.update()
	app.set_focus(current.grid)
}

fn book_action(mut c vtk.Ctl, mut app vtk.App) {
	mut view := unsafe { &BookView(c.user) }
	view.action(unsafe { Action(c.data) }, mut app)
}

fn book_key(mut c vtk.Ctl, event vtk.Event, mut app vtk.App) bool {
	mut view := unsafe { &BookView(c.user) }
	return view.key(event, mut app)
}

fn sheet_key(mut c vtk.Ctl, event vtk.Event, mut app vtk.App) bool {
	mut context := unsafe { &SheetView(c.user) }
	return context.view.key(event, mut app)
}

fn (mut view BookView) key(event vtk.Event, mut app vtk.App) bool {
	if !event.ctrl { return false }
	action := match event.key {
		`s` { if event.shift { Action.save_as } else { Action.save } }
		`o` { Action.open }
		`n` { Action.new_sheet }
		`q` { Action.quit }
		`z` { if event.shift { Action.redo } else { Action.undo } }
		`y` { Action.redo }
		else { return false }
	}
	view.action(action, mut app)
	return true
}

fn book_closing(mut c vtk.Ctl, mut app vtk.App) bool {
	view := unsafe { &BookView(c.user) }
	if view.book.dirty() && !app.confirm_for(&c, 'Unsaved workbook', 'Discard unsaved changes and quit?') { return false }
	return true
}

fn (mut view BookView) add_sheet(sheet &Sheet) {
	mut grid := vtk.table(sheet_cell, sheet.data.cells.len)
	for column in 0 .. sheet.columns() { grid.table_column(column_name(column), width: if column == 0 { 26 } else { 13 }, min_width: 4, numeric: true) }
	grid.table.selection = .cells
	grid.table.multi_select = true
	grid.table.sortable = true
	grid.table.reorderable_columns = true
	grid.table.resizable_columns = true
	grid.table.reorderable_rows = true
	grid.table.row_numbers = true
	grid.table.grid_lines = true
	grid.table.editable = true
	grid.table.pasteable = true
	grid.table.tab_navigation = true
	grid.table.edit = sheet_edit
	grid.table.edit_value = sheet_raw
	grid.table.cell_style = sheet_style
	grid.table.compare = sheet_compare
	grid.table.edited, grid.table.sorted = sheet_changed, sheet_changed
	context := &SheetView{view: &view, sheet: sheet, grid: grid}
	grid.user, grid.changed, grid.keyfn = context, sheet_selected, sheet_key
	mut page := view.tabs.add_tab(sheet.data.name, mut grid)
	page.user = context
	grid.table_select(0, 0, 0, 0)
}

fn (mut view BookView) replace_book(book Book, mut app vtk.App) {
	for mut page in view.tabs.children() { app.destroy_ctl(mut page) }
	view.book = book
	view.modified = view.book.dirty()
	view.tabs.value = 0
	for sheet in view.book.sheets { view.add_sheet(sheet) }
	view.update()
}

fn (mut view BookView) save(as_new bool, mut app vtk.App) {
	mut path := view.book.path
	if path == '' || as_new {
		path = app.prompt_for(view.window, 'Save workbook', 'Workbook path (.vtksheet):', if path == '' { 'workbook.vtksheet' } else { path }) or { return }
		if os.exists(path) && path != view.book.path && !app.confirm_for(view.window, 'Replace workbook', 'Replace ${path}?') { return }
	}
	view.book.save(path) or { app.notify(err.msg(), 4000); return }
	view.modified = false
	view.update()
	app.notify('Saved ${path}', 1500)
}

fn (mut view BookView) action(action Action, mut app vtk.App) {
	if action == .about {
		app.about_for(view.window, app_name, app_version)
		return
	}
	mut current := view.current() or { return }
	mut grid := current.grid
	match action {
		.new_sheet {
			name := app.prompt_for(view.window, 'New sheet', 'Sheet name:', 'Sheet ${view.book.sheets.len + 1}') or { return }
			if name.trim_space() == '' { return }
			mut id := 1
			for sheet in view.book.sheets { id = max(id, sheet.data.id + 1) }
			sheet := new_sheet(id, name.trim_space(), 40, 12)
			view.book.sheets << sheet
			view.add_sheet(sheet)
			view.tabs.set_value(view.tabs.children().len - 1)
		}
		.open {
			if view.book.dirty() && !app.confirm_for(view.window, 'Unsaved workbook', 'Discard changes and open another workbook?') { return }
			path := app.file_pick_for(view.window, os.getwd()) or { return }
			book := load_book(path) or { app.notify(err.msg(), 4000); return }
			view.replace_book(book, mut app)
		}
		.save, .save_as { view.save(action == .save_as, mut app) }
		.import_csv {
			path := app.file_pick_for(view.window, os.getwd()) or { return }
			text := os.read_file(path) or { app.notify(err.msg(), 4000); return }
			mut id := 1
			for sheet in view.book.sheets { id = max(id, sheet.data.id + 1) }
			sheet := import_csv(id, os.file_name(path), text) or { app.notify(err.msg(), 4000); return }
			view.book.sheets << sheet
			view.add_sheet(sheet)
			view.tabs.set_value(view.tabs.children().len - 1)
		}
		.export_csv {
			path := app.prompt_for(view.window, 'Export CSV', 'CSV path (raw source formulas):', '${current.sheet.data.name}.csv') or { return }
			if os.exists(path) && !app.confirm_for(view.window, 'Replace CSV', 'Replace ${path}?') { return }
			text := current.sheet.csv_text() or { app.notify(err.msg(), 4000); return }
			os.write_file(path, text) or { app.notify(err.msg(), 4000); return }
			app.notify('Exported ${path}', 1500)
		}
		.quit { app.close(mut view.window); return }
		.edit { grid.table_begin_edit() }
		.apply {
			if grid.table_selection().x < 0 { app.notify('Select a cell first', 1500); return }
			grid.table_apply([vtk.TableCellEdit{row: grid.value, column: grid.table_selected_column(), value: view.formula.text}]) or { app.notify(err.msg(), 3000) }
		}
		.copy { app.set_focus(grid); app.copy_focus() }
		.paste { grid.table_paste(app.clipboard_text()) or { app.notify(err.msg(), 3000) } }
		.undo, .redo { if current.sheet.undo_edit(action == .redo) { grid.table_refresh() } }
		.ascending, .descending { grid.table_sort(grid.table_selected_column(), if action == .ascending { .ascending } else { .descending }) }
		.reset { grid.table_sort(grid.table_selected_column(), .none) }
		.chart { current.show_chart(mut app) }
		.color, .clear_color {
			range := grid.table_selection()
			if range.x < 0 { return }
			color := if action == .clear_color { -1 } else { 0x1000000 | (app.color_pick(view.window, 'Cell background', 0x2850c8) or { return }) }
			brightness := (((color >> 16) & 255) * 299 + ((color >> 8) & 255) * 587 + (color & 255) * 114) / 1000
			style := if color < 0 { vtk.TableCellStyle{} } else { vtk.TableCellStyle{bg: color, fg: if brightness > 140 { vtk.black } else { vtk.white }} }
			mut changes := []Change{}
			for y in range.y .. range.y2 + 1 {
				for x in range.x .. range.x2 + 1 {
					row, column := grid.table_row_at(y), grid.table_column_at(x)
					before := current.sheet.data.styles[address(row, column)] or { vtk.TableCellStyle{} }
					changes << Change{row: row, column: column, style: true, before_style: before, after_style: style}
				}
			}
			current.sheet.record(changes)
			grid.invalidate()
		}
		.help { app.msgbox_for(view.window, 'VTK Sheets', 'Select Rows, Columns or Cells in the toolbar. Enable Multiple for ranges.\nDrag cells or Shift-click / Shift-arrows to extend. Ctrl-A selects all.\nCtrl-C copies TSV. Ctrl-V pastes one validated batch. Delete clears.\nEnter / F2 edits raw cell text; Escape cancels. Tab / Shift-Tab moves cells.\nCtrl-click column headers cycles ascending / descending / source order.\nDrag headers to reorder; drag boundaries to resize; double-click to fit.\nAlt-drag row numbers to move rows. Drag sheet tabs to reorder sheets.\nFormulas: arithmetic, A1 references, SUM/AVG/MIN/MAX/COUNT and ranges.\nReferences use source cell addresses, which stay fixed when sorting views.\nCtrl-S save, Ctrl-O open, Ctrl-N new sheet, Ctrl-Z/Y undo/redo, Ctrl-Q quit.') }
	}
	if action in [.new_sheet, .import_csv, .undo, .redo, .color, .clear_color] { view.modified = view.book.dirty() }
	view.update()
	if selected := view.current() { app.set_focus(selected.grid) }
}

fn create_view(mut app vtk.App, book Book) &BookView {
	width, height := app.size()
	mut window := app.window('VTK Sheets', width, height - 1)
	mut body := vtk.box(true)
	mut toolbar := vtk.flow()
	mut tabs := vtk.tabs()
	tabs.reorderable = true
	mut formula_row := vtk.box(false)
	mut address_label := vtk.label('A1')
	address_label.min_w = 6
	mut formula := vtk.entry('', 0)
	formula.expand = true
	mut apply := vtk.button('Apply')
	mut status := vtk.statusbar('')
	mut mode := vtk.combo()
	for name in ['Rows', 'Columns', 'Cells', 'No selection'] { mode.add_item(name) }
	mode.value = 2
	mut multiple := vtk.checkbox('Multiple', true)
	mut view := &BookView{book: book, window: window, tabs: tabs, formula: formula, address: address_label, status: status, mode: mode, multiple: multiple, modified: book.dirty()}
	window.user, window.closing, window.keyfn = view, book_closing, book_key
	tabs.user, tabs.changed, tabs.reordered = view, sheet_tab_changed, sheet_tab_moved
	formula.user, formula.submit, formula.keyfn = view, book_action, book_key
	formula.data = i64(Action.apply)
	apply.user, apply.changed, apply.data = view, book_action, i64(Action.apply)
	mode.user, mode.changed = view, configure_selection
	multiple.user, multiple.changed = view, configure_selection
	for title, actions in {
		'File': [Action.new_sheet, .open, .save, .save_as, .import_csv, .export_csv, .quit]
		'Edit': [Action.edit, .copy, .paste, .undo, .redo, .color, .clear_color]
		'Data': [Action.ascending, .descending, .reset, .chart, .help]
	} {
		mut menu := window.add_menu(title)
		for action in actions {
			mut item := menu.menu_item(action.str().replace('_', ' '), book_action)
			item.user, item.data = view, i64(action)
		}
	}
	mut help := window.add_menu('Help')
	mut about := help.menu_item('About', book_action)
	about.user, about.data = view, i64(Action.about)
	for title, action in {'Undo': Action.undo, 'Redo': .redo, 'Sort ↑': .ascending, 'Sort ↓': .descending, 'Edit': .edit, 'Color': .color, 'Chart': .chart, 'Help': .help} {
		mut button := vtk.button(title)
		button.user, button.changed, button.data = view, book_action, i64(action)
		toolbar.add(mut button)
	}
	toolbar.add(mut mode); toolbar.add(mut multiple)
	formula_row.add(mut address_label); formula_row.add(mut formula); formula_row.add(mut apply)
	body.add(mut toolbar); body.add(mut formula_row); body.add(mut tabs); body.add(mut status)
	window.add(mut body)
	for sheet in view.book.sheets { view.add_sheet(sheet) }
	view.update()
	app.maximize(mut window)
	if current := view.current() { app.set_focus(current.grid) }
	return view
}

pub fn launch(mut app vtk.App, _ voidptr) {
	_ := create_view(mut app, demo_book())
}

pub fn run() {
	mut app := vtk.new_app()
	app.ctrl_c = .copy
	app.native_clipboard = true
	snapshot := '--snapshot' in os.args
	if snapshot { app.desktop = false; app.dispatch(vtk.Event{kind: .resize, width: 100, height: 32}) }
	else { app.init() or { eprintln(err); return } }
	mut book := demo_book()
	for arg in os.args[1..] {
		if arg.starts_with('--') { continue }
		book = load_book(arg) or { app.fini(); eprintln(err); return }
		break
	}
	mut view := create_view(mut app, book)
	if '--chart' in os.args {
		if mut current := view.current() { current.grid.table_select(0, 0, min(3, current.sheet.columns() - 1), min(3, current.grid.row_count - 1)) }
		if snapshot {
			app.after(0, fn (mut app vtk.App) {
				app.redraw()
				println(app.snapshot())
				app.dispatch(vtk.Event{key: int(vtk.Key.escape)})
			})
		}
		view.action(.chart, mut app)
		if snapshot { app.fini(); return }
	}
	if snapshot { app.redraw(); println(app.snapshot()); app.fini(); return }
	app.run() or { eprintln(err) }
}
