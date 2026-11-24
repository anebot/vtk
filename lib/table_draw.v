module vtk

import math { max, min }

fn (c &Ctl) table_gutter() int {
	return if c.table.row_numbers || c.table.reorderable_rows { max(3, max(0, c.row_count).str().len + 2) } else { 0 }
}

pub fn (c &Ctl) table_column_width(column int) int {
	if column < 0 || column >= c.kids.len { return 0 }
	options := c.table_options(column)
	width := c.table.widths[column] or { options.width }
	actual := if width > 0 { width } else { (c.w - int(c.scrollbar) - c.table_gutter()) / max(1, c.kids.len) }
	return clamp(actual, max(1, options.min_width), if options.max_width > 0 { max(options.min_width, options.max_width) } else { 10000 })
}

pub fn (c &Ctl) table_column_rect(column int) Rect {
	if column < 0 || column >= c.kids.len { return Rect{} }
	mut x := c.x + c.table_gutter() - c.left
	for view in 0 .. c.kids.len {
		col := c.table_column_at(view)
		width := c.table_column_width(col)
		if col == column { return Rect{x, c.y, width, c.h} }
		x += width
	}
	return Rect{}
}

pub fn (c &Ctl) table_cell_rect(row int, column int) Rect {
	r := c.table_column_rect(column)
	view := c.table_view_row(row)
	return if r.w > 0 && view >= 0 { Rect{r.x, c.y + 1 + view - c.top, r.w, 1} } else { Rect{} }
}

fn (c &Ctl) table_hit_column(x int) int {
	if x < c.x + c.table_gutter() || x >= c.x + c.w - int(c.scrollbar) { return -1 }
	for view in 0 .. c.kids.len {
		column := c.table_column_at(view)
		r := c.table_column_rect(column)
		if x >= r.x && x < r.x + r.w { return column }
	}
	return -1
}

fn (mut c Ctl) table_scroll_horizontal(delta int) {
	mut total := 0
	for column in 0 .. c.kids.len { total += c.table_column_width(column) }
	c.left = clamp(c.left + delta, 0, total - max(1, c.w - int(c.scrollbar) - c.table_gutter()))
	c.table.left_hold = true
	c.invalidate()
}

fn (mut app App) draw_table(mut c Ctl, fg int, bg int) {
	padding_clip := app.screen.set_clip(c.rect())
	defer { app.screen.restore_clip(padding_clip) }
	c.table_sync()
	if c.kids.len == 0 { return }
	if c.value >= 0 { c.scroll_into_view(c.table_view_row(c.value), c.h - 1) }
	c.top = clamp(c.top, 0, c.row_count - max(1, c.h - 1))
	if !c.table.left_hold && c.table.selection in [.cells, .columns] && (!same_ctl(app.drag, c) || c.table.drag == .range) {
		r := c.table_column_rect(c.table.column)
		left, right := c.x + c.table_gutter(), c.x + c.w - int(c.scrollbar)
		if r.w > right - left { c.left = max(0, c.left + r.x - left) }
		else if r.x < left { c.left = max(0, c.left - (left - r.x)) }
		else if r.x + r.w > right { c.left += r.x + r.w - right }
	}
	range := c.table_selection()
	active := same_ctl(app.focus, c) && !c.disabled
	t := app.theme
	selected_fg, selected_bg := if active { t.focus_fg } else { t.sel_fg }, if active { t.focus_bg } else { t.sel_bg }
	app.fill_ctl(c, fg, bg)
	first := c.top + max(0, max(app.screen.paint_y, app.screen.clip.y) - c.y - 1)
	last := min(c.row_count, c.top + min(c.h - 1, min(app.screen.paint_end, app.screen.clip.y + app.screen.clip.h) - c.y - 1))
	for y in first .. last {
		if c.table.selection == .rows && range.x >= 0 && y >= range.y && y <= range.y2 {
			app.screen.fill(Rect{c.x, c.y + y - c.top + 1, c.w, 1}, ` `, selected_fg, selected_bg)
		}
	}
	body := Rect{c.x + c.table_gutter(), c.y, max(0, c.w - int(c.scrollbar) - c.table_gutter()), c.h}
	clip := app.screen.set_clip(body)
	mut left := body.x - c.left
	right := app.screen.clip.x + app.screen.clip.w
	for x in 0 .. c.kids.len {
		if left >= right { break }
		column := c.table_column_at(x)
		width := c.table_column_width(column)
		r := Rect{left, c.y, width, c.h}
		left += width
		if left <= app.screen.clip.x { continue }
		if app.screen.paints(Rect{r.x, c.y, r.w, 1})
			&& !(same_ctl(app.drag, c) && c.table.drag == .header && c.table.drag_moved && c.table.reorderable_columns && c.table.drag_id == column) {
			app.draw_table_header(c, column, r.x, fg, bg)
		}
		for y in first .. last {
			row := c.table_row_at(y)
			style := c.table_cell_style(row, column)
			selected := range.x >= 0 && x >= range.x && x <= range.x2 && y >= range.y && y <= range.y2
			cell_fg := if selected { selected_fg } else if c.disabled { t.dim } else if style.fg >= 0 { style.fg } else { fg }
			cell_bg := if selected { selected_bg } else if style.bg >= 0 { style.bg } else { bg }
			cy := c.y + y - c.top + 1
			app.screen.fill(Rect{r.x, cy, r.w, 1}, ` `, cell_fg, cell_bg)
			cell_clip := app.screen.set_clip(Rect{r.x, cy, max(0, r.w - 1), 1})
			attr := style.attr | if selected && c.table.selection == .cells && row == c.value && column == c.table.column { bold | underline } else { 0 }
			app.screen.aligned_text(r.x, cy, max(0, r.w - 1), c.table_cell(row, column).replace('\n', ' ').replace('\r', ''), c.table_options(column).align, cell_fg, cell_bg, attr)
			app.screen.restore_clip(cell_clip)
			if c.table.grid_lines { app.screen.put(r.x + r.w - 1, cy, `│`, t.dim, cell_bg, 0) }
		}
	}
	if same_ctl(app.drag, c) && c.table.drag == .header && c.table.drag_moved && c.table.reorderable_columns {
		column := c.table.drag_id
		if column >= 0 && column < c.kids.len {
			x := clamp(app.drag_start.x + app.mouse_x - app.drag_x, body.x, max(body.x, body.x + body.w - c.table_column_width(column)))
			app.draw_table_header(c, column, x, t.focus_fg, t.focus_bg)
		}
	}
	app.screen.restore_clip(clip)
	if c.table_gutter() > 0 {
		app.screen.fill(Rect{c.x, c.y, c.table_gutter(), c.h}, ` `, t.dim, bg)
		for y in first .. last {
			app.screen.aligned_text(c.x, c.y + y - c.top + 1, c.table_gutter() - 1, (c.table_row_at(y) + 1).str(), .right, t.dim, bg, 0)
		}
	}
	app.draw_scrollbar(c, c.row_count, max(1, c.h - 1), 1)
}

fn (mut app App) draw_table_header(c &Ctl, column int, x int, fg int, bg int) {
	width := c.table_column_width(column)
	marked := c.table.sort_column == column && c.table.sort_direction != .none
	text := c.kids[column].text + if marked {
		if c.table.sort_direction == .ascending { ' ▲' } else { ' ▼' }
	} else { '' }
	app.screen.fill(Rect{x, c.y, width, 1}, ` `, fg, bg)
	clip := app.screen.set_clip(Rect{x, c.y, max(0, width - 1), 1})
	app.screen.aligned_text(x, c.y, max(0, width - 1), text, c.table_options(column).align, fg, bg, bold | underline)
	app.screen.restore_clip(clip)
	if c.table.grid_lines { app.screen.put(x + width - 1, c.y, `│`, app.theme.dim, bg, 0) }
}
