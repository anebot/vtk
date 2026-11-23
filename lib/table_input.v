module vtk

enum TableDrag { none range header resize row }

fn (mut c Ctl) table_select_to(x int, y int, extend bool) {
	mut ax, mut ay := x, y
	if extend && c.table.multi_select && c.value >= 0 {
		ax = c.table_view_column(if c.table.anchor_column >= 0 { c.table.anchor_column } else { c.table.column })
		ay = c.table_view_row(if c.table.anchor_row >= 0 { c.table.anchor_row } else { c.value })
	}
	c.table_select(max(0, ax), max(0, ay), x, y)
}

fn (mut c Ctl) table_cycle_sort(column int) {
	direction := if column != c.table.sort_column || c.table.sort_direction == .none { TableSortDirection.ascending }
		else if c.table.sort_direction == .ascending { TableSortDirection.descending } else { TableSortDirection.none }
	c.table_sort(column, direction)
}

fn (mut c Ctl) table_mouse(e Event, mut app App) bool {
	c.table_sync()
	if e.button.is_wheel() {
		if e.pressed && (e.shift || e.button in [.wheel_left, .wheel_right]) {
			c.table_scroll_horizontal(if e.button in [.wheel_left, .wheel_up] { -3 } else { 3 })
			return true
		}
		return false
	}
	if e.button != .left || !e.pressed || e.motion { return false }
	if c.scrollbar && e.x == c.x + c.w - 1 { return false }
	app.set_focus(&c)
	c.table.drag, c.table.drag_moved = .none, false
	c.table.drag_full_rows = false
	column := c.table_hit_column(e.x)
	if e.y == c.y {
		if c.table.resizable_columns {
			for view in 0 .. c.kids.len {
				col := c.table_column_at(view)
				r := c.table_column_rect(col)
				if e.x != r.x + r.w - 1 { continue }
				if c.table.last_boundary == col && app.now() - c.table.last_click_at < 400 {
					c.table.last_boundary = -1
					c.table_autofit(col, max(4, c.w - c.table_gutter()))
					return true
				}
				c.table.last_boundary, c.table.last_click_at = col, app.now()
				c.table.drag, c.table.drag_id = .resize, col
				app.drag_start = r
				app.drag_x, app.drag_y, app.drag = e.x, e.y, &c
				return true
			}
		}
		if column < 0 { return true }
		if c.table.selection == .columns && !e.ctrl && !e.alt && c.row_count > 0 {
			c.table_select_to(c.table_view_column(column), max(0, c.table_view_row(c.value)), e.shift)
			if c.destroyed || c.root().app != &app || !c.visible() { return true }
			if c.table.multi_select { c.table.drag = .range; app.drag = &c }
			return true
		}
		if !c.table.sortable && !c.table.reorderable_columns && c.table.selection !in [.cells, .columns] { return true }
		c.table.drag, c.table.drag_id = .header, column
		app.drag_start = c.table_column_rect(column)
		app.drag_x, app.drag_y, app.drag = e.x, e.y, &c
		return true
	}
	if e.y <= c.y || c.row_count == 0 || c.kids.len == 0 { return true }
	y := clamp(c.top + e.y - c.y - 1, 0, c.row_count - 1)
	if e.x < c.x + c.table_gutter() && e.alt && c.table.reorderable_rows {
		c.table.drag, c.table.drag_id = .row, c.table_row_at(y)
		app.drag = &c
		return true
	}
	if c.table.selection == .none { return true }
	x := if column >= 0 { c.table_view_column(column) } else { max(0, c.table_view_column(c.table.column)) }
	if e.x < c.x + c.table_gutter() && c.table.selection == .cells && c.table.multi_select {
		ay := if e.shift && c.table.anchor_row >= 0 { c.table_view_row(c.table.anchor_row) } else { y }
		c.table.drag_full_rows = true
		c.table_select(0, ay, c.kids.len - 1, y)
	} else { c.table_select_to(x, y, e.shift) }
	if c.destroyed || c.root().app != &app || !c.visible() { return true }
	if c.table.multi_select { c.table.drag = .range; app.drag = &c }
	return true
}

fn (mut c Ctl) table_drag(e Event, mut app App) {
	if e.button == .none && !e.pressed { app.drag = unsafe { nil }; return }
	if e.button != .left { return }
	if !e.pressed { app.drag = unsafe { nil } }
	if app.popups.len > 0 { app.drag = unsafe { nil }; return }
	c.table_sync()
	match c.table.drag {
		.resize {
			if !c.table.resizable_columns { app.drag = unsafe { nil }; return }
			if e.x != app.drag_x { c.table.last_boundary = -1 }
			c.table_set_column_width(c.table.drag_id, max(1, app.drag_start.w + e.x - app.drag_x))
		}
		.header {
			if e.x != app.drag_x || e.y != app.drag_y { c.table.drag_moved = true }
			if c.table.drag_moved {
				if !c.table.reorderable_columns || e.y != c.y { return }
				if e.x < c.x + c.table_gutter() { c.table_scroll_horizontal(-3) }
				else if e.x >= c.x + c.w - int(c.scrollbar) { c.table_scroll_horizontal(3) }
				target := c.table_hit_column(clamp(e.x, c.x + c.table_gutter(), c.x + c.w - int(c.scrollbar) - 1))
				if target < 0 { return }
				from, to := c.table_view_column(c.table.drag_id), c.table_view_column(target)
				r := c.table_column_rect(target)
				if (to > from && e.x >= r.x + r.w / 2) || (to < from && e.x < r.x + r.w / 2) { c.table_move_column(from, to) }
			} else if !e.pressed && e.y == c.y && c.table.drag_id >= 0 && c.table.drag_id < c.kids.len {
				if c.table.sortable && (c.table.selection == .rows || e.ctrl) { c.table.column = c.table.drag_id; c.table_cycle_sort(c.table.drag_id); return }
				if c.row_count > 0 {
					x := c.table_view_column(c.table.drag_id)
					if c.table.multi_select && c.table.selection == .cells { c.table_select(x, 0, x, c.row_count - 1) }
					else { c.table_select_to(x, max(0, c.table_view_row(c.value)), e.shift) }
				}
			}
		}
		.range, .row {
			if c.row_count == 0 || c.kids.len == 0 { app.drag = unsafe { nil }; return }
			if c.table.drag == .range && (!c.table.multi_select || c.table.selection == .none) { app.drag = unsafe { nil }; return }
			if c.table.drag == .row && !c.table.reorderable_rows { app.drag = unsafe { nil }; return }
			if c.table.selection != .columns {
				if e.y <= c.y { c.top = max(0, c.top - 1) }
				if e.y >= c.y + c.h { c.top = clamp(c.top + 1, 0, c.row_count - max(1, c.h - 1)) }
			}
			y := if c.table.selection == .columns { max(0, c.table_view_row(c.value)) } else { clamp(c.top + clamp(e.y - c.y - 1, 0, max(0, c.h - 2)), 0, c.row_count - 1) }
			if c.table.drag == .row { c.table_move_row(c.table_view_row(c.table.drag_id), y); return }
			if e.x < c.x + c.table_gutter() { c.table_scroll_horizontal(-3) }
			else if e.x >= c.x + c.w - int(c.scrollbar) { c.table_scroll_horizontal(3) }
			column := c.table_hit_column(clamp(e.x, c.x + c.table_gutter(), c.x + c.w - int(c.scrollbar) - 1))
			if c.table.drag_full_rows {
				c.table_select(0, max(0, c.table_view_row(c.table.anchor_row)), c.kids.len - 1, y)
			} else if column >= 0 { c.table_select_to(c.table_view_column(column), y, true) }
		}
		.none { app.drag = unsafe { nil } }
	}
}

fn (mut c Ctl) table_key(e Event, mut app App) bool {
	c.table_sync()
	if e.key == int(Key.f6) { app.focus_next(e.shift); return true }
	if e.ctrl && lower_key(e.key) == `v` && c.table.pasteable {
		c.table_paste(app.clipboard_text()) or { app.notify(err.msg(), 3000) }
		return true
	}
	if c.row_count <= 0 || c.kids.len == 0 || c.table.selection == .none { return false }
	mut x, mut y := max(0, c.table_view_column(c.table.column)), c.table_view_row(c.value)
	if e.alt && e.key in [int(Key.up), int(Key.down)] && c.table.sortable {
		c.table_sort(c.table.column, if e.key == int(Key.up) { .ascending } else { .descending })
		return true
	}
	if e.ctrl && lower_key(e.key) == `a` && c.table.multi_select { c.table_select(0, 0, c.kids.len - 1, c.row_count - 1); return true }
	if e.key in [int(Key.f2), int(Key.enter)] && c.table.editable && !c.readonly {
		c.table_edit_dialog(none, mut app)
		return true
	}
	if e.key == int(Key.enter) {
		if callback := c.submit { callback(mut c, mut app); return true }
	}
	if e.key in [int(Key.delete), int(Key.backspace)] && c.table.editable && !c.readonly {
		range := c.table_selection()
		if range.x < 0 { return true }
		mut edits := []TableCellEdit{}
		for row in range.y .. range.y2 + 1 {
			for column in range.x .. range.x2 + 1 { edits << TableCellEdit{row: c.table_row_at(row), column: c.table_column_at(column), value: ''} }
		}
		c.table_apply(edits) or { app.notify(err.msg(), 3000) }
		return true
	}
	if !e.ctrl && !e.alt && e.key >= 32 && e.key <= 0x10ffff && c.table.editable && !c.readonly {
		c.table_edit_dialog(rune(e.key).str(), mut app)
		return true
	}
	if e.key == int(Key.tab) {
		if !c.table.tab_navigation || c.table.selection != .cells { return false }
		x += if e.shift { -1 } else { 1 }
		if x < 0 { x = c.kids.len - 1; y-- } else if x >= c.kids.len { x = 0; y++ }
	} else if c.table.selection == .columns {
		if e.key in [int(Key.left), int(Key.up)] { x-- }
		else if e.key in [int(Key.right), int(Key.down)] { x++ }
		else if e.key == int(Key.home) { x = 0 }
		else if e.key == int(Key.end) { x = c.kids.len - 1 }
		else { return false }
		y = max(0, y)
	} else if e.key in [int(Key.up), int(Key.down), int(Key.page_up), int(Key.page_down)] {
		y += match e.key { int(Key.up) { -1 } int(Key.down) { 1 } int(Key.page_up) { -max(1, c.h - 2) } else { max(1, c.h - 2) } }
	} else if e.key in [int(Key.left), int(Key.right)] {
		if c.table.selection == .cells { x += if e.key == int(Key.left) { -1 } else { 1 }; y = max(0, y) }
		else { y += if e.key == int(Key.left) { -1 } else { 1 } }
	} else if e.key in [int(Key.home), int(Key.end)] {
		if c.table.selection == .rows || e.ctrl { y = if e.key == int(Key.home) { 0 } else { c.row_count - 1 } }
		if c.table.selection == .cells { x = if e.key == int(Key.home) { 0 } else { c.kids.len - 1 }; y = max(0, y) }
	} else { return false }
	c.table_select_to(clamp(x, 0, c.kids.len - 1), clamp(y, 0, c.row_count - 1), e.shift && e.key != int(Key.tab))
	return true
}

@[heap]
struct TableEditor {
	table &Ctl
	row int
	column int
	entry &Ctl
	message &Ctl
}

fn table_editor_accept(mut button Ctl, mut app App) {
	mut editor := unsafe { &TableEditor(button.user) }
	editor.table.table_apply([TableCellEdit{row: editor.row, column: editor.column, value: editor.entry.text}]) or {
		editor.message.set_text(err.msg()); return
	}
	if button.destroyed { return }
	mut window := button.owner_window() or { return }
	window.dialog_result = 1
	app.close(mut window)
}

pub fn (mut c Ctl) table_begin_edit() {
	mut app := c.root().app
	if !isnil(app) { c.table_edit_dialog(none, mut app) }
}

fn (mut c Ctl) table_edit_dialog(initial ?string, mut app App) {
	if c.value < 0 || c.value >= c.row_count || c.table.column < 0 || c.table.column >= c.kids.len || !c.table.editable || c.table.selection == .none || c.readonly || c.destroyed { return }
	if !c.table_options(c.table.column).editable { app.notify('Column is read only', 2000); return }
	mut body := box(true)
	mut input := entry(initial or { c.table_edit_text(c.value, c.table.column) }, 0)
	input.min_w = min(56, max(16, app.width - 8))
	input.expand = false
	mut message := label('')
	mut buttons := button_bar()
	mut save := button('Apply')
	mut cancel := dialog_button('Cancel', false)
	editor := &TableEditor{ table: &c, row: c.value, column: c.table.column, entry: input, message: message }
	save.user, input.user = editor, editor
	save.changed, input.submit = table_editor_accept, table_editor_accept
	buttons.add(mut save); buttons.add(mut cancel)
	body.add(mut input); body.add(mut message); body.add(mut buttons)
	mut dialog := app.dialog('Edit ${c.kids[c.table.column].text}, row ${c.value + 1}', mut body)
	app.set_default_button(mut dialog, save)
	app.set_focus(input)
	app.modal_for(mut dialog, c.owner_window())
	app.destroy_ctl(mut dialog)
	app.set_focus(&c)
}
