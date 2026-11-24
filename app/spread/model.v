module spread

import encoding.csv
import json2
import math
import os
import strconv
import vtk

const max_rows = 1000
const max_columns = 100

struct SheetData {
mut:
	id int
	name string
	cells [][]string
	styles map[string]vtk.TableCellStyle
}

struct SavedBook {
	version int = 1
	sheets []SheetData
}

struct Change {
	row int
	column int
	before string
	after string
	style bool
	before_style vtk.TableCellStyle
	after_style vtk.TableCellStyle
}

@[heap]
struct Sheet {
mut:
	data SheetData
	cache map[string]string
	undo [][]Change
	redo [][]Change
}

struct Book {
mut:
	sheets []&Sheet
	path string
	saved string
}

fn column_name(column int) string {
	mut n := column + 1
	mut name := ''
	for n > 0 { n--; name = rune(`A` + n % 26).str() + name; n /= 26 }
	return name
}

fn address(row int, column int) string { return '${column_name(column)}${row + 1}' }

fn cell_address(text string) !(int, int) {
	name := text.trim_space().to_upper()
	mut i, mut column := 0, 0
	for i < name.len && name[i] >= `A` && name[i] <= `Z` {
		column = column * 26 + int(name[i] - `A`) + 1
		if column > max_columns { return error('#REF!') }
		i++
	}
	if i == 0 || i == name.len { return error('#REF!') }
	for ch in name[i..] { if ch < `0` || ch > `9` { return error('#REF!') } }
	row := strconv.atoi(name[i..]) or { return error('#REF!') }
	if row < 1 || row > max_rows { return error('#REF!') }
	return row - 1, column - 1
}

fn new_sheet(id int, name string, rows int, columns int) &Sheet {
	return &Sheet{data: SheetData{id: id, name: name, cells: [][]string{len: rows, init: []string{len: columns}}}}
}

fn (sheet &Sheet) columns() int { return if sheet.data.cells.len > 0 { sheet.data.cells[0].len } else { 0 } }

fn (sheet &Sheet) raw(row int, column int) string {
	if row < 0 || row >= sheet.data.cells.len || column < 0 || column >= sheet.columns() { return '#REF!' }
	return sheet.data.cells[row][column]
}

fn (mut sheet Sheet) display(row int, column int) string {
	text := sheet.raw(row, column)
	if !text.starts_with('=') { return text }
	key := address(row, column)
	if cached := sheet.cache[key] {
		value := strconv.atof64(cached) or { return cached }
		return display_number(value)
	}
	mut visiting := map[string]bool{}
	value := sheet.number(row, column, mut visiting) or { sheet.cache[key] = err.msg(); return err.msg() }
	return display_number(value)
}

fn display_number(value f64) string {
	if math.abs(value) >= 1e12 || (value != 0 && math.abs(value) < 1e-6) { return strconv.f64_to_str(value, 6) }
	result := '${value:.6f}'.trim_right('0').trim_right('.')
	return if result == '-0' { '0' } else { result }
}

fn (mut sheet Sheet) number(row int, column int, mut visiting map[string]bool) !f64 {
	if row < 0 || row >= sheet.data.cells.len || column < 0 || column >= sheet.columns() { return error('#REF!') }
	key := address(row, column)
	if visiting[key] { return error('#CYCLE!') }
	if visiting.len >= 128 { return error('#DEPTH!') }
	raw := sheet.raw(row, column).trim_space()
	if raw == '' { return 0 }
	if !raw.starts_with('=') { return strconv.atof64(raw) or { return error('#VALUE!') } }
	if cached := sheet.cache[key] { return strconv.atof64(cached) or { return error(cached) } }
	visiting[key] = true
	defer { visiting.delete(key) }
	mut formula := Formula{sheet: &sheet, text: raw[1..], visiting: visiting}
	value := formula.expression()!
	formula.space()
	if formula.pos != formula.text.len { return error('#SYNTAX!') }
	if math.is_nan(value) || math.is_inf(value, 0) { return error('#NUM!') }
	sheet.cache[key] = strconv.f64_to_str(value, 17)
	return value
}

fn (mut sheet Sheet) apply(edits []vtk.TableCellEdit) ! {
	for edit in edits {
		if edit.row < 0 || edit.row >= sheet.data.cells.len || edit.column < 0 || edit.column >= sheet.columns() { return error('Cell is outside the sheet') }
	}
	mut changes := []Change{}
	for edit in edits {
		if sheet.raw(edit.row, edit.column) != edit.value {
			changes << Change{row: edit.row, column: edit.column, before: sheet.raw(edit.row, edit.column), after: edit.value}
		}
	}
	sheet.record(changes)
}

fn (mut sheet Sheet) record(changes []Change) {
	if changes.len == 0 { return }
	for change in changes { sheet.apply_change(change, false) }
	sheet.undo << changes
	sheet.redo = []
	sheet.cache = map[string]string{}
}

fn (mut sheet Sheet) apply_change(change Change, reverse bool) {
	if change.style {
		style := if reverse { change.before_style } else { change.after_style }
		key := address(change.row, change.column)
		if style == vtk.TableCellStyle{} { sheet.data.styles.delete(key) } else { sheet.data.styles[key] = style }
	} else { sheet.data.cells[change.row][change.column] = if reverse { change.before } else { change.after } }
}

fn (mut sheet Sheet) undo_edit(redo bool) bool {
	if (redo && sheet.redo.len == 0) || (!redo && sheet.undo.len == 0) { return false }
	changes := if redo { sheet.redo.last() } else { sheet.undo.last() }
	if redo { sheet.redo.delete_last() } else { sheet.undo.delete_last() }
	if redo {
		for change in changes { sheet.apply_change(change, false) }
		sheet.undo << changes
	} else {
		for i := changes.len - 1; i >= 0; i-- { sheet.apply_change(changes[i], true) }
		sheet.redo << changes
	}
	sheet.cache = map[string]string{}
	return true
}

fn (sheet &Sheet) csv_text() !string {
	mut writer := csv.new_writer()
	for row in sheet.data.cells { writer.write(row)! }
	return writer.str()
}

fn import_csv(id int, name string, text string) !&Sheet {
	data := vtk.parse_table_data(text, `,`)!
	if data.len == 0 || data.len > max_rows { return error('CSV must have 1–${max_rows} rows') }
	mut columns := 1
	for row in data { columns = max(columns, row.len) }
	if columns > max_columns { return error('CSV supports up to ${max_columns} columns') }
	mut sheet := new_sheet(id, name, max(40, data.len), max(12, columns))
	for r, row in data { for c, cell in row { sheet.data.cells[r][c] = cell } }
	return sheet
}

fn (book &Book) snapshot() string {
	return json2.encode(SavedBook{sheets: book.sheets.map(it.data)})
}

fn (book &Book) dirty() bool { return book.snapshot() != book.saved }

fn (mut book Book) save(path string) ! {
	text := book.snapshot()
	vtk.save_atomic(path, text)!
	book.path, book.saved = path, text
}

fn load_book(path string) !Book {
	data := json2.decode[SavedBook](os.read_file(path)!)!
	if data.version != 1 || data.sheets.len == 0 { return error('Unsupported or empty workbook') }
	mut book := Book{path: path}
	mut ids := map[int]bool{}
	for item in data.sheets {
		if ids[item.id] || item.name.trim_space() == '' || item.cells.len == 0 || item.cells.len > max_rows { return error('Invalid sheet') }
		ids[item.id] = true
		columns := item.cells[0].len
		if columns == 0 || columns > max_columns || item.cells.any(it.len != columns) { return error('Invalid sheet dimensions') }
		book.sheets << &Sheet{data: item}
	}
	book.saved = book.snapshot()
	return book
}

fn demo_book() Book {
	mut budget := new_sheet(1, 'Budget', 40, 12)
	rows := [
		['Item', 'Quantity', 'Unit cost', 'Total'],
		['Notebook', '4', '3.5', '=B2*C2'],
		['Pencils', '12', '0.75', '=B3*C3'],
		['Folders', '6', '1.25', '=B4*C4'],
		['Total', '', '', '=SUM(D2:D4)'],
		['Average', '', '', '=AVG(D2:D4)'],
	]
	for r, row in rows { for c, value in row { budget.data.cells[r][c] = value } }
	mut notes := new_sheet(2, 'Notes', 40, 12)
	notes.data.cells[0][0] = 'Try =SUM(B2:C4), =A2*2 or =MAX(B2:B9)'
	notes.data.cells[1][0] = 'F2 / Enter edits. Shift-arrows or drag selects a rectangle.'
	notes.data.cells[2][0] = 'Ctrl-click a header sorts. Drag headers to reorder columns.'
	mut book := Book{sheets: [budget, notes]}
	book.saved = book.snapshot()
	return book
}
