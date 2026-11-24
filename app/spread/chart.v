module spread

import math
import strconv
import vtk

// A selected block uses its first column as categories when it has several
// columns. A text heading row names the series; one column uses row addresses.
fn (mut current SheetView) selection_chart() !vtk.Chart {
	grid := current.grid
	range := grid.table_selection()
	if range.x < 0 { return error('Select cells to chart first') }
	first_value := range.x + int(range.x2 > range.x)
	mut first_row := range.y
	mut heading := false
	for x in first_value .. range.x2 + 1 {
		row, column := grid.table_row_at(first_row), grid.table_column_at(x)
		raw := current.sheet.raw(row, column).trim_space()
		if raw == '' || raw.starts_with('=') { continue }
		strconv.atof64(raw) or { heading = true }
	}
	if heading { first_row++ }
	mut result := vtk.Chart{title: current.sheet.data.name, x_axis: vtk.ChartAxis{title: 'Category'}, y_axis: vtk.ChartAxis{title: 'Value'}}
	for y in first_row .. range.y2 + 1 {
		row := grid.table_row_at(y)
		result.labels << if first_value > range.x { current.sheet.display(row, grid.table_column_at(range.x)) } else { address(row, grid.table_column_at(first_value)) }
	}
	mut numeric := false
	for x in first_value .. range.x2 + 1 {
		column := grid.table_column_at(x)
		name := if heading { current.sheet.display(grid.table_row_at(range.y), column) } else { column_name(column) }
		mut series := vtk.ChartSeries{name: name}
		for y in first_row .. range.y2 + 1 {
			row := grid.table_row_at(y)
			if current.sheet.raw(row, column).trim_space() == '' { series.values << math.nan(); continue }
			mut visiting := map[string]bool{}
			value := current.sheet.number(row, column, mut visiting) or { series.values << math.nan(); continue }
			series.values << value
			if !math.is_nan(value) && !math.is_inf(value, 0) { numeric = true }
		}
		result.series << series
	}
	if !numeric { return error('The selected cells contain no numeric values to chart') }
	return result
}

@[heap]
struct ChartView {
mut:
	plot &vtk.Ctl
	kind &vtk.Ctl
	title &vtk.Ctl
	x_title &vtk.Ctl
	y_title &vtk.Ctl
	minimum &vtk.Ctl
	maximum &vtk.Ctl
	series &vtk.Ctl
	message &vtk.Ctl
	horizontal_values bool
}

fn chart_bound(text string) !f64 {
	value := strconv.atof64(text.trim_space()) or { return error('Axis bounds must be numbers, or blank for automatic') }
	if math.is_nan(value) || math.is_inf(value, 0) { return error('Axis bounds must be finite') }
	return value
}

fn (mut view ChartView) apply() ! {
	mut minimum, mut maximum := ?f64(none), ?f64(none)
	if view.minimum.text.trim_space() != '' { minimum = chart_bound(view.minimum.text)! }
	if view.maximum.text.trim_space() != '' { maximum = chart_bound(view.maximum.text)! }
	if low := minimum {
		if high := maximum { if low >= high { return error('Minimum must be less than maximum') } }
	}
	mut options := view.plot.chart
	kind := match view.kind.value { 1 { vtk.ChartKind.bars } 2 { vtk.ChartKind.lines } else { vtk.ChartKind.columns } }
	if (options.kind == .bars) != (kind == .bars) { options.x_axis, options.y_axis = options.y_axis, options.x_axis }
	options.kind = kind
	options.title = view.title.text
	options.x_axis.title, options.y_axis.title = view.x_title.text, view.y_title.text
	if kind == .bars {
		options.x_axis.minimum, options.x_axis.maximum = minimum, maximum
	} else {
		options.y_axis.minimum, options.y_axis.maximum = minimum, maximum
	}
	view.plot.set_chart(options)
}

fn chart_apply(mut c vtk.Ctl, mut _ vtk.App) {
	mut view := c.context[ChartView]() or { return }
	view.apply() or { view.message.set_text(err.msg()); return }
	view.message.set_text('Blank bounds use an automatic scale. Escape closes the chart.')
}

fn chart_kind_changed(mut c vtk.Ctl, mut app vtk.App) {
	mut view := c.context[ChartView]() or { return }
	if view.horizontal_values != (view.kind.value == 1) {
		text := view.x_title.text
		view.x_title.set_text(view.y_title.text)
		view.y_title.set_text(text)
	}
	view.horizontal_values = view.kind.value == 1
	chart_apply(mut c, mut app)
}

fn chart_pick_color(mut c vtk.Ctl, mut app vtk.App) {
	mut view := c.context[ChartView]() or { return }
	index := view.series.value
	if index < 0 || index >= view.plot.chart.series.len { return }
	color := view.plot.chart.series[index].color
	rgb := app.color_pick(c.owner_window(), 'Series color', if color >= 0 && color & 0x1000000 != 0 { color & 0xffffff } else { 0x28a0d0 }) or { return }
	view.plot.chart.series[index].color = 0x1000000 | rgb
	view.plot.invalidate()
}

fn chart_field(mut row vtk.Ctl, title string, text string, width int) &vtk.Ctl {
	mut caption := vtk.label(title)
	mut field := vtk.entry(text, 0)
	field.min_w = width
	row.add(mut caption)
	row.add(mut field)
	return field
}

fn (mut current SheetView) show_chart(mut app vtk.App) {
	options := current.selection_chart() or { app.notify(err.msg(), 3000); return }
	mut body := vtk.box(true)
	mut heading := vtk.flow()
	mut kind := vtk.combo()
	for name in ['Columns', 'Bars', 'Lines'] { kind.add_item(name) }
	kind.value = 0
	heading.add(mut kind)
	title := chart_field(mut heading, 'Title:', options.title, 24)
	mut axes := vtk.flow()
	x_title := chart_field(mut axes, 'X axis:', options.x_axis.title, 16)
	y_title := chart_field(mut axes, 'Y axis:', options.y_axis.title, 16)
	mut scale := vtk.flow()
	minimum := chart_field(mut scale, 'Value min:', '', 10)
	maximum := chart_field(mut scale, 'max:', '', 10)
	mut apply := vtk.button('Apply')
	scale.add(mut apply)
	mut colors := vtk.flow()
	mut series := vtk.combo()
	for item in options.series { series.add_item(item.name) }
	series.value = 0
	mut color := vtk.button('Series color...')
	colors.add(mut series)
	colors.add(mut color)
	mut plot := vtk.chart(options)
	mut message := vtk.label('Blank bounds use an automatic scale. Escape closes the chart.')
	mut view := &ChartView{plot: plot, kind: kind, title: title, x_title: x_title, y_title: y_title, minimum: minimum, maximum: maximum, series: series, message: message}
	mut fields := [title, x_title, y_title, minimum, maximum]
	for mut field in fields {
		field.set_context(view)
		field.submit = chart_apply
	}
	kind.set_context(view)
	kind.changed = chart_kind_changed
	apply.set_context(view)
	apply.changed = chart_apply
	color.set_context(view)
	color.changed = chart_pick_color
	body.add(mut heading); body.add(mut axes); body.add(mut scale); body.add(mut colors)
	body.add(mut plot); body.add(mut message)
	mut window := app.dialog('Chart · selected cells', mut body)
	app.maximize(mut window)
	app.set_focus(kind)
	app.modal_for(mut window, current.view.window)
	app.destroy_ctl(mut window)
}
