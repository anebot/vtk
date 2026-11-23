module vtk

@[heap]
struct GridData {
mut:
	cells [][]string = [['pear', '10', 'a'], ['Apple', '2', 'b'], ['apple', '2', 'c'], ['banana', '-3', 'd']]
	batches int
}

fn grid_get(c &Ctl, row int, col int) string {
	data := unsafe { &GridData(c.user) }
	return data.cells[row][col]
}

fn grid_edit(mut c Ctl, edits []TableCellEdit) ! {
	mut data := unsafe { &GridData(c.user) }
	for edit in edits { if edit.value == 'reject' { return error('Rejected batch') } }
	for edit in edits { data.cells[edit.row][edit.column] = edit.value }
	data.batches++
}

fn grid_setup(mut app App) (&Ctl, &GridData) {
	app.desktop = false
	mut window := app.window('Grid', 58, 12)
	data := &GridData{}
	mut grid := table(grid_get, data.cells.len)
	grid.user = data
	grid.table_column('Fruit', width: 14)
	grid.table_column('Count', width: 12, numeric: true, align: .right, min_width: 4, max_width: 30)
	grid.table_column('Note', width: 16)
	window.add(mut grid)
	app.set_focus(grid)
	app.redraw()
	return grid, data
}

fn grid_click(mut app App, x int, y int, ctrl bool) {
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: x, y: y, ctrl: ctrl})
	app.dispatch(Event{kind: .mouse, button: .left, x: x, y: y, ctrl: ctrl})
}

fn test_table_defaults_and_stable_sort_keep_source_ids() {
	mut app := new_app()
	mut grid, _ := grid_setup(mut app)
	assert grid.table.selection == .rows
	assert !grid.table.sortable && !grid.table.editable && !grid.table.pasteable
	assert !grid.table.reorderable_columns && !grid.table.resizable_columns && !grid.table.reorderable_rows
	assert grid.table.rows.len == 0
	grid.set_value(0)
	assert grid.table_sort(1, .ascending)
	assert grid.table.rows == [3, 1, 2, 0]
	assert grid.value == 0 && grid.table_cell(0, 1) == '10'
	app.dispatch(Event{key: int(Key.up)})
	assert grid.value == 2
	assert grid.table_sort(0, .ascending)
	assert grid.table.rows == [1, 2, 3, 0]
	assert grid.table_sort(1, .descending)
	assert grid.table.rows == [0, 1, 2, 3]
	assert grid.table_sort(1, .none)
	assert grid.table_row_at(2) == 2 && grid.table.rows.len == 0
	assert !grid.table_sort(-1, .ascending) && !grid.table_move_column(0, 8)
}

fn test_table_header_sort_and_column_drag_and_resize_are_opt_in() {
	mut app := new_app()
	mut grid, _ := grid_setup(mut app)
	header := grid.table_column_rect(1)
	grid_click(mut app, header.x + 2, header.y, false)
	_, direction := grid.table_sort_state()
	assert direction == .none
	grid.table.sortable = true
	for expected in [TableSortDirection.ascending, .descending, .none] {
		grid_click(mut app, header.x + 2, header.y, false)
		_, actual := grid.table_sort_state()
		assert actual == expected
	}
	grid.table.resizable_columns = true
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: header.x + header.w - 1, y: header.y})
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, motion: true, x: header.x + 100, y: header.y})
	assert grid.table_column_width(1) == 30 && app.drag == grid
	app.dispatch(Event{kind: .mouse})
	assert isnil(app.drag)
	grid.table.reorderable_columns = true
	first := grid.table_column_rect(0)
	last := grid.table_column_rect(2)
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: first.x + 1, y: first.y})
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, motion: true, x: last.x + last.w - 2, y: last.y})
	assert grid.table.column_order == [1, 2, 0]
	assert grid.table_cell(0, 0) == 'pear'
	app.dispatch(Event{kind: .mouse, button: .left, x: last.x + last.w - 2, y: last.y})
	assert isnil(app.drag)
}

fn test_table_row_column_and_rectangular_selections_use_view_coordinates() {
	mut app := new_app()
	mut grid, _ := grid_setup(mut app)
	grid.table.multi_select = true
	grid.table_sort(1, .ascending)
	grid.table_move_column(2, 0)
	grid.table.selection = .cells
	assert grid.table_select(0, 0, 1, 1)
	assert grid.table_selection() == TableRange{x: 0, y: 0, x2: 1, y2: 1}
	assert grid.value == 1 && grid.table_selected_column() == 0
	assert grid.table_selection_text() == 'd\tbanana\nb\tApple'
	grid.table.selection = .rows
	assert grid.table_selection() == TableRange{x: 0, y: 0, x2: 2, y2: 1}
	grid.table.selection = .columns
	assert grid.table_selection() == TableRange{x: 0, y: 0, x2: 1, y2: 3}
	grid.table.selection = .none
	assert !grid.table_select(0, 0, 0, 0) && grid.table_selection().x == -1
	assert !app.copy_focus()
}

fn test_table_keyboard_extends_ranges_and_tabs_between_cells() {
	mut app := new_app()
	mut grid, _ := grid_setup(mut app)
	grid.table.selection = .cells
	grid.table.multi_select = true
	grid.table.tab_navigation = true
	grid.table_select(0, 0, 0, 0)
	app.dispatch(Event{key: int(Key.right), shift: true})
	app.dispatch(Event{key: int(Key.down), shift: true})
	assert grid.table_selection() == TableRange{x: 0, y: 0, x2: 1, y2: 1}
	app.dispatch(Event{key: int(Key.tab)})
	assert grid.value == 1 && grid.table_selected_column() == 2
	app.dispatch(Event{key: int(Key.tab)})
	assert grid.value == 2 && grid.table_selected_column() == 0
	app.dispatch(Event{key: int(Key.tab), shift: true})
	assert grid.value == 1 && grid.table_selected_column() == 2
	app.dispatch(Event{key: `a`, ctrl: true})
	assert grid.table_selection() == TableRange{x: 0, y: 0, x2: 2, y2: 3}
}

fn test_table_paste_batches_edits_and_never_mutates_on_validation_failure() ! {
	mut app := new_app()
	mut grid, data := grid_setup(mut app)
	grid.table.selection = .cells
	grid.table.multi_select = true
	grid.table.editable = true
	grid.table.pasteable = true
	grid.table.edit = grid_edit
	grid.table_sort(1, .ascending)
	grid.table_move_column(2, 0)
	grid.table_select(0, 0, 0, 0)
	grid.table_paste('note\tfruit\nother\tfruit2')!
	assert data.batches == 1
	assert data.cells[3][2] == 'note' && data.cells[3][0] == 'fruit'
	assert data.cells[1][2] == 'other' && data.cells[1][0] == 'fruit2'
	before := data.cells.clone()
	for text in ['ok\treject', 'one\ttwo\tthree\tfour', '"unterminated'] {
		mut rejected := false
		grid.table_paste(text) or { rejected = true }
		assert rejected && data.cells == before && data.batches == 1
	}
	grid.readonly = true
	mut rejected := false
	grid.table_paste('new') or { rejected = true }
	assert rejected && data.cells == before
}

fn table_test_style(_ &Ctl, row int, column int) TableCellStyle {
	return if row == 1 && column == 1 { TableCellStyle{fg: yellow, attr: bold} } else { TableCellStyle{} }
}

fn test_table_cell_colors_follow_source_ids_and_selection_stays_legible() {
	mut app := new_app()
	mut grid, _ := grid_setup(mut app)
	assert grid.table_set_cell_style(1, 1, TableCellStyle{bg: blue})
	assert !grid.table_set_cell_style(9, 0, TableCellStyle{bg: red})
	grid.table.cell_style = table_test_style
	grid.table_sort(1, .ascending)
	grid.table_move_column(1, 0)
	app.redraw()
	cell := grid.table_cell_rect(1, 1)
	painted := app.screen.cells[cell.y * app.width + cell.x + cell.w - 2]
	assert painted.bg == blue && painted.fg == yellow && painted.attr & bold != 0
	grid.table.selection = .cells
	grid.table_select(0, 1, 0, 1)
	app.redraw()
	selected := app.screen.cells[cell.y * app.width + cell.x]
	assert selected.bg == app.theme.focus_bg && selected.fg == app.theme.focus_fg
	grid.table_clear_cell_styles()
	assert grid.table.styles.len == 0
}

fn test_table_data_parser_round_trips_quoted_cells_and_rejects_malformed_paste() ! {
	assert parse_table_data('"a\tb"\t"line1\nline2"\r\n"a""b"\t', `\t`)! == [['a\tb', 'line1\nline2'], ['a"b', '']]
	assert parse_table_data('a,b\r\nc,d\r\n', `,`)! == [['a', 'b'], ['c', 'd']]
	for invalid in ['"unterminated', 'bad"quote', '"closed"junk'] {
		mut failed := false
		parse_table_data(invalid, `\t`) or { failed = true }
		assert failed
	}
}

fn test_table_row_drag_uses_source_row_ids_and_refresh_clears_manual_order() {
	mut app := new_app()
	mut grid, _ := grid_setup(mut app)
	grid.table.reorderable_rows = true
	app.redraw()
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, alt: true, x: grid.x, y: grid.y + 1})
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, motion: true, alt: true, x: grid.x, y: grid.y + 4})
	assert grid.table.rows == [1, 2, 3, 0]
	app.dispatch(Event{kind: .mouse})
	grid.table_refresh()
	assert grid.table.rows.len == 0 && grid.table_row_at(0) == 0
}

fn test_column_header_drag_selects_columns_and_gutter_drag_selects_rows() {
	mut app := new_app()
	mut grid, _ := grid_setup(mut app)
	grid.table.selection = .columns
	grid.table.multi_select = true
	grid.table.reorderable_columns = true
	first, last := grid.table_column_rect(0), grid.table_column_rect(2)
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: first.x + 1, y: first.y})
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, motion: true, x: last.x + 1, y: last.y})
	assert grid.table_selection() == TableRange{x: 0, y: 0, x2: 2, y2: 3}
	assert grid.table.column_order == [0, 1, 2]
	app.dispatch(Event{kind: .mouse})
	grid.table.selection = .cells
	grid.table.row_numbers = true
	app.redraw()
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: grid.x, y: grid.y + 2})
	app.dispatch(Event{kind: .mouse, button: .left, pressed: true, motion: true, x: grid.x, y: grid.y + 4})
	assert grid.table_selection() == TableRange{x: 0, y: 1, x2: 2, y2: 3}
	app.dispatch(Event{kind: .mouse})
}

fn test_read_only_columns_reject_a_whole_batch_and_manual_row_order_survives_editing() ! {
	mut app := new_app()
	mut grid, data := grid_setup(mut app)
	grid.table.editable = true
	grid.table.edit = grid_edit
	grid.table_move_row(0, 3)
	grid.table_apply([TableCellEdit{row: 0, column: 0, value: 'updated'}])!
	assert grid.table.rows == [1, 2, 3, 0]
	assert grid.table_configure_column(1, editable: false)
	mut rejected := false
	grid.table_apply([TableCellEdit{row: 0, column: 0, value: 'partial'}, TableCellEdit{row: 0, column: 1, value: 'blocked'}]) or { rejected = true }
	assert rejected && data.cells[0][0] == 'updated' && data.batches == 1
}

fn test_table_editor_rejects_without_losing_the_draft_then_cancel_restores_focus() {
	mut app := new_app()
	mut grid, data := grid_setup(mut app)
	grid.table.selection = .cells
	grid.table.editable = true
	grid.table.edit = grid_edit
	grid.table_select(0, 0, 0, 0)
	app.after(0, fn (mut app App) {
		mut input := app.focus
		assert input.kind == .entry
		input.set_text('reject')
		app.dispatch(Event{key: int(Key.enter)})
		assert input.text == 'reject' && !app.top_window_ptr().closed
		app.dispatch(Event{key: int(Key.escape)})
	})
	grid.table_begin_edit()
	assert data.cells[0][0] == 'pear' && data.batches == 0 && app.focus == grid
}

fn destroy_table_on_sort(mut c Ctl, mut app App) { app.destroy_ctl(mut c) }

fn test_table_callbacks_can_destroy_controls_and_capture_cancels_on_lifecycle_changes() {
	for action in ['disable', 'close', 'focus_out', 'resize', 'destroy'] {
		mut app := new_app()
		mut grid, _ := grid_setup(mut app)
		grid.table.resizable_columns = true
		r := grid.table_column_rect(0)
		app.dispatch(Event{kind: .mouse, button: .left, pressed: true, x: r.x + r.w - 1, y: r.y})
		assert app.drag == grid
		match action {
			'disable' { grid.table.resizable_columns = false }
			'close' { mut window := grid.owner_window_ptr(); app.close(mut window) }
			'focus_out' { app.dispatch(Event{kind: .focus_out}) }
			'resize' { app.dispatch(Event{kind: .resize, width: 90, height: 30}) }
			'destroy' { app.destroy_ctl(mut grid) }
			else {}
		}
		app.dispatch(Event{kind: .mouse, button: .left, pressed: true, motion: true, x: r.x + 20, y: r.y})
		assert isnil(app.drag), action
	}
	mut app := new_app()
	mut grid, _ := grid_setup(mut app)
	grid.table.sorted = destroy_table_on_sort
	assert grid.table_sort(0, .ascending) && grid.destroyed
	assert grid.table.edit == none && grid.table.cell_style == none && grid.table.rows.cap == 0
}

fn test_virtual_unsorted_tables_do_not_allocate_per_row_state_and_stale_anchors_are_safe() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Virtual', 30, 8)
	mut grid := table(fn (_ &Ctl, row int, _ int) string { return row.str() }, 1000000)
	grid.table_column('Row')
	window.add(mut grid)
	app.redraw()
	assert grid.table.rows.cap == 0 && grid.table_row_at(999999) == 999999
	grid.table.selection = .cells
	grid.table.multi_select = true
	grid.table_select(0, 20, 0, 1)
	grid.row_count = 2
	grid.table_refresh()
	assert grid.table_selection() == TableRange{x: 0, y: 1, x2: 0, y2: 1}
	assert grid.table_selection_text() == '1'
}
