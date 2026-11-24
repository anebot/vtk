module vtk

import encoding.csv
import math
import strconv

pub enum TableSelectionMode { none rows columns cells }
pub enum TableSortDirection { none ascending descending }

@[params]
pub struct TableColumnOptions {
pub:
	width int
	min_width int = 1
	max_width int
	align TextAlign
	numeric bool
	editable bool = true
}

pub struct TableRange {
pub:
	x int = -1
	y int = -1
	x2 int = -1
	y2 int = -1
}

pub struct TableCellEdit {
pub:
	row int
	column int
	value string
}

pub struct TableCellStyle {
pub:
	fg int = -1
	bg int = -1
	attr int
}

pub type TableStyleCallback = fn (&Ctl, int, int) TableCellStyle

// Edits use source IDs. Validate the whole batch before changing application
// data; returning an error must leave that data unchanged.
pub type TableEditCallback = fn (mut Ctl, []TableCellEdit) !
pub type TableCompareCallback = fn (&Ctl, int, int, int) int
pub type TableMoveCallback = fn (mut Ctl, int, int, mut App)

pub struct Table {
pub mut:
	selection TableSelectionMode = .rows
	multi_select bool
	sortable bool
	resizable_columns bool
	reorderable_columns bool
	reorderable_rows bool
	row_numbers bool
	grid_lines bool
	editable bool
	pasteable bool
	copyable bool = true
	tab_navigation bool
	compare ?TableCompareCallback
	cell_style ?TableStyleCallback
	edit_value ?CellCallback
	edit ?TableEditCallback
	sorted ?Callback
	edited ?Callback
	column_resized ?Callback
	column_reordered ?TableMoveCallback
	row_reordered ?TableMoveCallback
mut:
	columns map[int]TableColumnOptions
	widths map[int]int
	styles map[u64]TableCellStyle
	rows []int
	column_order []int
	known_rows int = -1
	known_columns int = -1
	sort_column int = -1
	sort_direction TableSortDirection
	column int
	anchor_row int = -1
	anchor_column int = -1
	left_hold bool
	drag TableDrag
	drag_id int = -1
	drag_moved bool
	drag_full_rows bool
	last_boundary int = -1
	last_click_at i64
}

pub fn (mut c Ctl) table_set_cell_style(row int, column int, style TableCellStyle) bool {
	if c.kind != .table || c.destroyed || row < 0 || row >= c.row_count || column < 0 || column >= c.kids.len { return false }
	c.table.styles[(u64(row) << 32) | u64(column)] = style
	c.invalidate()
	return true
}

pub fn (mut c Ctl) table_clear_cell_styles() {
	c.table.styles = map[u64]TableCellStyle{}
	c.invalidate()
}

fn (c &Ctl) table_cell_style(row int, column int) TableCellStyle {
	base := c.table.styles[(u64(row) << 32) | u64(column)] or { TableCellStyle{} }
	if callback := c.table.cell_style {
		style := callback(c, row, column)
		return TableCellStyle{ fg: if style.fg >= 0 { style.fg } else { base.fg },
			bg: if style.bg >= 0 { style.bg } else { base.bg }, attr: base.attr | style.attr }
	}
	return base
}

fn (c &Ctl) table_options(column int) TableColumnOptions {
	return c.table.columns[column] or { TableColumnOptions{} }
}

// Source IDs are callback coordinates; top/left and TableRange are view coordinates.
pub fn (c &Ctl) table_row_at(view_row int) int {
	if view_row < 0 || view_row >= c.row_count { return -1 }
	if c.table.rows.len == c.row_count { return c.table.rows[view_row] }
	return view_row
}

pub fn (c &Ctl) table_column_at(view_column int) int {
	if view_column < 0 || view_column >= c.kids.len { return -1 }
	if c.table.column_order.len == c.kids.len { return c.table.column_order[view_column] }
	return view_column
}

pub fn (c &Ctl) table_view_row(source_row int) int {
	if source_row < 0 || source_row >= c.row_count { return -1 }
	return if c.table.rows.len == c.row_count { c.table.rows.index(source_row) } else { source_row }
}

pub fn (c &Ctl) table_view_column(source_column int) int {
	if source_column < 0 || source_column >= c.kids.len { return -1 }
	return if c.table.column_order.len == c.kids.len { c.table.column_order.index(source_column) } else { source_column }
}

pub fn (c &Ctl) table_selected_column() int { return c.table.column }

pub fn (mut c Ctl) table_configure_column(column int, options TableColumnOptions) bool {
	if c.kind != .table || c.destroyed || column < 0 || column >= c.kids.len { return false }
	c.table.columns[column] = options
	c.table.widths.delete(column)
	if c.table.sort_column == column && c.table.sort_direction != .none { c.table_refresh() }
	c.invalidate()
	return true
}

pub fn (c &Ctl) table_sort_state() (int, TableSortDirection) {
	return c.table.sort_column, c.table.sort_direction
}

fn (mut c Ctl) table_sync() {
	if c.table.known_columns != c.kids.len {
		c.table.column_order = []int{len: c.kids.len, init: index}
		c.table.known_columns = c.kids.len
		c.table.column = clamp(c.table.column, 0, c.kids.len - 1)
		if c.table.sort_column >= c.kids.len { c.table.sort_direction = .none; c.table.sort_column = -1 }
	}
	if c.table.known_rows != c.row_count {
		c.table_refresh()
	}
}

// Call after changing source data. A refresh resets manual row order and
// reapplies the current sort. Selection stays attached to the same source row.
pub fn (mut c Ctl) table_refresh() {
	if c.kind != .table || c.destroyed { return }
	c.table.known_rows = c.row_count
	c.table.rows = []int{}
	c.table.anchor_row, c.table.anchor_column = -1, -1
	if c.value >= c.row_count { c.value = -1 }
	if c.table.sort_direction != .none && c.table.sort_column >= 0 && c.table.sort_column < c.kids.len {
		c.table.rows = []int{len: math.max(0, c.row_count), init: index}
		c.table_sort_rows()
	}
	c.invalidate()
}

fn (c &Ctl) table_compare_rows(a int, b int) int {
	column := c.table.sort_column
	mut order := 0
	if compare := c.table.compare {
		order = compare(c, a, b, column)
	} else {
		left, right := c.table_cell(a, column), c.table_cell(b, column)
		if c.table_options(column).numeric {
			na := strconv.atof64(left.trim_space()) or { math.nan() }
			nb := strconv.atof64(right.trim_space()) or { math.nan() }
			if !math.is_nan(na) && !math.is_nan(nb) {
				order = if na < nb { -1 } else if na > nb { 1 } else { 0 }
			} else if math.is_nan(na) != math.is_nan(nb) {
				order = if math.is_nan(na) { 1 } else { -1 }
			} else { order = compare_strings(left.to_lower(), right.to_lower()) }
		} else { order = compare_strings(left.to_lower(), right.to_lower()) }
	}
	// Avoid negating a caller's minimum int comparator result.
	sign := if order < 0 { -1 } else if order > 0 { 1 } else { 0 }
	return if c.table.sort_direction == .descending { -sign } else { sign }
}

fn (mut c Ctl) table_sort_rows() {
	mut buffer := []int{len: c.table.rows.len}
	mut width := 1
	for width < c.table.rows.len {
		for start := 0; start < c.table.rows.len; start += width * 2 {
			middle, end := math.min(start + width, c.table.rows.len), math.min(start + width * 2, c.table.rows.len)
			mut a, mut b := start, middle
			for target in start .. end {
				if a < middle && (b >= end || c.table_compare_rows(c.table.rows[a], c.table.rows[b]) <= 0) {
					buffer[target] = c.table.rows[a]; a++
				} else { buffer[target] = c.table.rows[b]; b++ }
			}
		}
		c.table.rows, buffer = buffer, c.table.rows
		width *= 2
	}
}

pub fn (mut c Ctl) table_sort(column int, direction TableSortDirection) bool {
	if c.kind != .table || c.destroyed || column < 0 || column >= c.kids.len { return false }
	c.table_sync()
	c.table.sort_column, c.table.sort_direction = column, direction
	c.table.rows = []int{}
	if direction != .none { c.table.rows = []int{len: math.max(0, c.row_count), init: index}; c.table_sort_rows() }
	c.table.anchor_row, c.table.anchor_column = -1, -1
	c.scroll_hold = false
	c.invalidate()
	if mut app := c.root().app { if callback := c.table.sorted { callback(mut c, mut app) } }
	return true
}

// Coordinates are zero-based view columns/rows, inclusive at both ends.
pub fn (mut c Ctl) table_select(x int, y int, x2 int, y2 int) bool {
	if c.kind != .table || c.destroyed || c.table.selection == .none { return false }
	c.table_sync()
	if x < 0 || y < 0 || x2 < 0 || y2 < 0 || x >= c.kids.len || x2 >= c.kids.len || y >= c.row_count || y2 >= c.row_count { return false }
	if !c.table.multi_select && (x != x2 || y != y2) { return false }
	changed := c.table.anchor_row != c.table_row_at(y) || c.table.anchor_column != c.table_column_at(x)
		|| c.value != c.table_row_at(y2) || c.table.column != c.table_column_at(x2)
	c.table.anchor_row, c.table.anchor_column = c.table_row_at(y), c.table_column_at(x)
	c.value, c.table.column = c.table_row_at(y2), c.table_column_at(x2)
	c.scroll_hold, c.table.left_hold = false, false
	if changed { c.fire() } else { c.invalidate() }
	return true
}

pub fn (c &Ctl) table_selection() TableRange {
	if c.kind != .table || c.table.selection == .none || c.value < 0 || c.value >= c.row_count || c.kids.len == 0 { return TableRange{} }
	x, y := c.table_view_column(c.table.column), c.table_view_row(c.value)
	ax := if c.table.multi_select && c.table.anchor_column >= 0 && c.table.anchor_column < c.kids.len { c.table_view_column(c.table.anchor_column) } else { x }
	ay := if c.table.multi_select && c.table.anchor_row >= 0 && c.table.anchor_row < c.row_count { c.table_view_row(c.table.anchor_row) } else { y }
	return TableRange{
		x: if c.table.selection == .rows { 0 } else { math.min(ax, x) }
		x2: if c.table.selection == .rows { c.kids.len - 1 } else { math.max(ax, x) }
		y: if c.table.selection == .columns { 0 } else { math.min(ay, y) }
		y2: if c.table.selection == .columns { c.row_count - 1 } else { math.max(ay, y) }
	}
}

pub fn (mut c Ctl) table_move_column(from int, to int) bool {
	if c.kind != .table || c.destroyed || from < 0 || to < 0 || from >= c.kids.len || to >= c.kids.len { return false }
	c.table_sync()
	if from == to { return true }
	column := c.table.column_order[from]
	c.table.column_order.delete(from)
	c.table.column_order.insert(to, column)
	c.table.anchor_row, c.table.anchor_column = -1, -1
	c.invalidate()
	if mut app := c.root().app { if callback := c.table.column_reordered { callback(mut c, from, to, mut app) } }
	return true
}

pub fn (mut c Ctl) table_move_row(from int, to int) bool {
	if c.kind != .table || c.destroyed || from < 0 || to < 0 || from >= c.row_count || to >= c.row_count { return false }
	c.table_sync()
	if from == to { return true }
	if c.table.rows.len != c.row_count { c.table.rows = []int{len: math.max(0, c.row_count), init: index} }
	row := c.table.rows[from]
	c.table.rows.delete(from)
	c.table.rows.insert(to, row)
	c.table.sort_column, c.table.sort_direction = -1, .none
	c.table.anchor_row, c.table.anchor_column = -1, -1
	c.invalidate()
	if mut app := c.root().app { if callback := c.table.row_reordered { callback(mut c, from, to, mut app) } }
	return true
}

pub fn (mut c Ctl) table_set_column_width(column int, width int) bool {
	if c.kind != .table || c.destroyed || column < 0 || column >= c.kids.len || width < 1 { return false }
	options := c.table_options(column)
	limit := if options.max_width > 0 { math.max(options.min_width, options.max_width) } else { 10000 }
	c.table.widths[column] = clamp(width, math.max(1, options.min_width), limit)
	c.invalidate()
	if mut app := c.root().app { if callback := c.table.column_resized { callback(mut c, mut app) } }
	return true
}

pub fn (mut c Ctl) table_autofit(column int, limit int) bool {
	if c.kind != .table || column < 0 || column >= c.kids.len { return false }
	mut width := text_width(c.kids[column].text) + 3
	for row in 0 .. math.max(0, c.row_count) { width = math.max(width, text_width(c.table_cell(row, column)) + 1) }
	return c.table_set_column_width(column, math.min(width, math.max(1, limit)))
}

pub fn (c &Ctl) table_edit_text(row int, column int) string {
	if callback := c.table.edit_value { return callback(c, row, column) }
	return c.table_cell(row, column)
}

pub fn (mut c Ctl) table_apply(edits []TableCellEdit) ! {
	if c.kind != .table || c.destroyed || c.readonly || !c.table.editable { return error('Table is read only') }
	callback := c.table.edit or { return error('No table edit callback') }
	for edit in edits {
		if edit.row < 0 || edit.row >= c.row_count || edit.column < 0 || edit.column >= c.kids.len { return error('Cell is outside the table') }
		if !c.table_options(edit.column).editable { return error('Column is read only') }
	}
	if edits.len == 0 { return }
	callback(mut c, edits)!
	if c.destroyed { return }
	if c.table.sort_direction != .none || c.table.known_rows != c.row_count { c.table_refresh() } else { c.invalidate() }
	if mut app := c.root().app { if edited := c.table.edited { edited(mut c, mut app) } }
}

pub fn (c &Ctl) table_selection_text() string {
	if !c.table.copyable { return '' }
	range := c.table_selection()
	if range.x < 0 { return '' }
	mut writer := csv.new_writer(delimiter: `\t`)
	for y in range.y .. range.y2 + 1 {
		mut cells := []string{cap: range.x2 - range.x + 1}
		for x in range.x .. range.x2 + 1 { cells << c.table_cell(c.table_row_at(y), c.table_column_at(x)) }
		writer.write(cells) or { return '' }
	}
	result := writer.str()
	return if result.len > 0 { result[..result.len - 1] } else { '' }
}

pub fn (mut c Ctl) table_paste(text string) ! {
	if !c.table.pasteable { return error('Table paste is disabled') }
	c.table_sync()
	range := c.table_selection()
	if range.x < 0 { return error('Select a cell first') }
	data := parse_table_data(text, `\t`)!
	mut edits := []TableCellEdit{}
	for dy, row in data {
		for dx, value in row {
			x, y := range.x + dx, range.y + dy
			if x >= c.kids.len || y >= c.row_count { return error('Paste extends past the table') }
			edits << TableCellEdit{ row: c.table_row_at(y), column: c.table_column_at(x), value: value }
		}
	}
	c.table_apply(edits)!
}

// Strict CSV/TSV parsing shared with applications importing table data.
pub fn parse_table_data(text string, delimiter u8) ![][]string {
	if delimiter in [`\n`, `\r`, `"`] { return error('Invalid delimiter') }
	mut rows := [][]string{}
	mut row := []string{}
	mut field := []u8{}
	mut quoted, mut closed := false, false
	mut i := 0
	for i < text.len {
		ch := text[i]
		if quoted {
			if ch == `"` {
				if i + 1 < text.len && text[i + 1] == `"` { field << ch; i += 2; continue }
				quoted, closed = false, true
			} else { field << ch }
		} else if ch == delimiter || ch in [`\r`, `\n`] {
			row << field.bytestr(); field = []; closed = false
			if ch != delimiter {
				rows << row; row = []
				if ch == `\r` && i + 1 < text.len && text[i + 1] == `\n` { i++ }
			}
		} else if ch == `"` && field.len == 0 && !closed { quoted = true }
		else {
			if closed || ch == `"` { return error('Invalid quoted field') }
			field << ch
		}
		i++
	}
	if quoted { return error('Unterminated quoted field') }
	if field.len > 0 || row.len > 0 || closed || text.len == 0 { row << field.bytestr(); rows << row }
	return rows
}
