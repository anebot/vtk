module spread

import math
import vtk

fn test_selected_cells_chart_calculates_formulas_and_follows_view_order() ! {
	mut app := vtk.new_app()
	app.desktop = false
	mut view := create_view(mut app, demo_book())
	mut current := view.current() or { panic('missing sheet') }
	mut grid := current.grid
	assert grid.table_select(0, 0, 3, 3)
	options := current.selection_chart()!
	assert options.labels == ['Notebook', 'Pencils', 'Folders']
	assert options.series.map(it.name) == ['Quantity', 'Unit cost', 'Total']
	assert options.series[2].values == [f64(14), 9, 7.5]
	grid.table_sort(1, .descending)
	grid.table_select(0, 0, 3, 3)
	sorted := current.selection_chart()!
	assert sorted.labels == ['Pencils', 'Folders', 'Notebook']
	assert sorted.series[2].values == [f64(9), 7.5, 14]
	assert !view.book.dirty()
}

fn test_chart_handles_single_column_missing_values_and_empty_selection() ! {
	mut app := vtk.new_app()
	mut view := create_view(mut app, demo_book())
	mut current := view.current() or { panic('missing sheet') }
	mut grid := current.grid
	grid.table_select(1, 0, 1, 4)
	options := current.selection_chart()!
	assert options.labels == ['B2', 'B3', 'B4', 'B5']
	assert options.series[0].name == 'Quantity'
	assert options.series[0].values[..3] == [f64(4), 12, 6]
	assert math.is_nan(options.series[0].values[3])
	current.sheet.apply([vtk.TableCellEdit{row: 1, column: 1, value: '=1/0'}])!
	grid.table_select(1, 1, 1, 2)
	gaps := current.selection_chart()!
	assert gaps.labels == ['B2', 'B3']
	assert math.is_nan(gaps.series[0].values[0]) && gaps.series[0].values[1] == 12
	grid.table_select(0, 10, 2, 12)
	if _ := current.selection_chart() { assert false }
	grid.table.selection = .none
	if _ := current.selection_chart() { assert false }
}

fn test_chart_dialog_changes_styles_titles_bounds_and_restores_sheet_focus() {
	mut app := vtk.new_app()
	app.desktop = false
	app.dispatch(vtk.Event{kind: .resize, width: 100, height: 32})
	mut view := create_view(mut app, demo_book())
	mut current := view.current() or { panic('missing sheet') }
	current.grid.table_select(0, 0, 3, 3)
	app.after(0, fn (mut app vtk.App) {
		mut selector := app.focused_ctl() or { panic('missing selector') }
		mut settings := unsafe { &ChartView(selector.user) }
		settings.title.set_text('Budget overview')
		settings.minimum.set_text('-5')
		settings.maximum.set_text('20')
		settings.x_title.set_text('Products')
		settings.y_title.set_text('EUR')
		selector.set_value(1)
		assert settings.plot.chart.kind == .bars
		assert settings.plot.chart.x_axis.title == 'EUR'
		assert settings.plot.chart.y_axis.title == 'Products'
		assert settings.plot.chart.x_axis.minimum? == -5
		assert settings.plot.chart.x_axis.maximum? == 20
		settings.plot.chart.series[2].color = vtk.color_rgb(255, 100, 0)
		app.redraw()
		assert app.snapshot().contains('Budget overview') && app.snapshot().contains('Notebook')
		selector.set_value(2)
		assert settings.plot.chart.kind == .lines
		assert settings.plot.chart.x_axis.title == 'Products'
		assert settings.plot.chart.y_axis.title == 'EUR'
		settings.maximum.set_text('-10')
		chart_apply(mut selector, mut app)
		assert settings.message.text.contains('Minimum must be less')
		assert settings.plot.chart.y_axis.maximum? == 20
		settings.maximum.set_text('inf')
		chart_apply(mut selector, mut app)
		assert settings.message.text.contains('finite')
		settings.minimum.set_text(''); settings.maximum.set_text('')
		chart_apply(mut selector, mut app)
		assert settings.plot.chart.y_axis.minimum == none && settings.plot.chart.y_axis.maximum == none
		app.dispatch(vtk.Event{key: int(vtk.Key.escape)})
	})
	view.action(.chart, mut app)
	assert app.window_list().len == 1
	assert app.focused_ctl()? == current.grid
	assert !view.book.dirty()
}
