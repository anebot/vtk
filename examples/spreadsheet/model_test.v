module spreadsheet

import io.util
import os
import vtk

fn test_formulas_arithmetic_ranges_cycles_errors_and_cache_invalidation() ! {
	mut sheet := new_sheet(1, 'Test', 10, 8)
	sheet.apply([
		vtk.TableCellEdit{row: 0, column: 0, value: '2'},
		vtk.TableCellEdit{row: 1, column: 0, value: '3'},
		vtk.TableCellEdit{row: 2, column: 0, value: 'text'},
		vtk.TableCellEdit{row: 0, column: 1, value: '=SUM(A1:A3)*2+(3-1)/2'},
		vtk.TableCellEdit{row: 1, column: 1, value: '=AVG(A1:A2)'},
		vtk.TableCellEdit{row: 2, column: 1, value: '=MIN(A2:A1)+MAX(A1,A2)+COUNT(A1:A3)'},
	])!
	assert sheet.display(0, 1) == '11'
	assert sheet.display(1, 1) == '2.5'
	assert sheet.display(2, 1) == '7'
	sheet.apply([vtk.TableCellEdit{row: 0, column: 0, value: '7'}])!
	assert sheet.display(0, 1) == '21'
	assert sheet.undo_edit(false)
	assert sheet.display(0, 1) == '11'
	assert sheet.undo_edit(true)
	assert sheet.display(0, 1) == '21'
	for formula, expected in {
		'=B4': '#CYCLE!'
		'=1/0': '#DIV/0!'
		'=Z999': '#REF!'
		'=A3+1': '#VALUE!'
		'=UNKNOWN(1)': '#NAME?'
		'=SUM(A1:A2': '#SYNTAX!'
		'=1+': '#SYNTAX!'
		'=1e309': '#NUM!'
	} {
		sheet.apply([vtk.TableCellEdit{row: 3, column: 1, value: formula}])!
		assert sheet.display(3, 1) == expected, formula
	}
	sheet.apply([vtk.TableCellEdit{row: 3, column: 1, value: '=C4'}, vtk.TableCellEdit{row: 3, column: 2, value: '=B4'}])!
	assert sheet.display(3, 1) == '#CYCLE!'
	assert sheet.display(3, 2) == '#CYCLE!'
}

fn test_workbook_round_trip_csv_colors_and_undo() ! {
	root := util.temp_dir(pattern: 'vtk-sheets-')!
	defer { os.rmdir_all(root) or {} }
	mut book := demo_book()
	assert !book.dirty()
	mut sheet := book.sheets[0]
	sheet.apply([vtk.TableCellEdit{row: 1, column: 1, value: '8'}, vtk.TableCellEdit{row: 1, column: 2, value: '2'}])!
	assert sheet.display(1, 3) == '16' && book.dirty()
	sheet.record([Change{row: 1, column: 1, style: true, after_style: vtk.TableCellStyle{bg: vtk.blue}}])
	assert sheet.data.styles['B2'].bg == vtk.blue
	assert sheet.undo_edit(false) && sheet.data.styles.len == 0
	assert sheet.undo_edit(true) && sheet.data.styles['B2'].bg == vtk.blue
	path := os.join_path(root, 'budget.vtksheet')
	book.save(path)!
	assert !book.dirty()
	mut loaded := load_book(path)!
	assert loaded.sheets.len == 2 && loaded.sheets[0].display(1, 3) == '16'
	assert loaded.sheets[0].data.styles['B2'].bg == vtk.blue
	assert loaded.sheets[0].undo.len == 0 && !loaded.dirty()
	text := sheet.csv_text()!
	mut imported := import_csv(3, 'Imported', text)!
	assert imported.raw(1, 3) == '=B2*C2' && imported.display(1, 3) == '16'
	mut invalid := false
	sheet.apply([vtk.TableCellEdit{row: 0, column: 0, value: 'partial'}, vtk.TableCellEdit{row: 999, column: 0, value: 'bad'}]) or { invalid = true }
	assert invalid && sheet.raw(0, 0) == 'Item'
}

fn test_csv_and_addresses_handle_quotes_unicode_and_bounds() ! {
	mut sheet := import_csv(1, 'CSV', '"α,β","a""b"\r\n"line1\nline2",=1+2\r\n')!
	assert sheet.raw(0, 0) == 'α,β' && sheet.raw(0, 1) == 'a"b'
	assert sheet.raw(1, 0) == 'line1\nline2' && sheet.display(1, 1) == '3'
	row, col := cell_address('AA12')!
	assert row == 11 && col == 26 && address(row, col) == 'AA12'
	for bad in ['A0', 'A-1', '1A', 'ZZ9999999999999999999999', 'A1x'] {
		mut rejected := false
		cell_address(bad) or { rejected = true }
		assert rejected
	}
}
