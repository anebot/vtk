module vtk

import math

fn test_chart_ranges_cover_signed_constant_and_extreme_values() {
	mut options := Chart{series: [ChartSeries{values: [f64(-5), 10, math.nan(), math.inf(1)]}]}
	assert options.value_range()? == ChartRange{-5, 10}
	options.y_axis.minimum, options.y_axis.maximum = f64(-20), f64(20)
	assert options.value_range()? == ChartRange{-20, 20}
	options.y_axis.minimum = f64(30)
	assert options.value_range()? == ChartRange{-5, 10}
	options.y_axis = ChartAxis{include_zero: false}
	options.series[0].values = [f64(5), 5]
	range := options.value_range()?
	assert range.minimum < 5 && range.maximum >= 5
	options.series[0].values = [f64(0)]
	assert options.value_range()? == ChartRange{0, 1}
	for value in [math.smallest_non_zero_f64, -math.smallest_non_zero_f64] {
		options.series[0].values = [value]
		tiny := options.value_range()?
		assert tiny.minimum < tiny.maximum && chart_finite(tiny.fraction(value))
	}
	options.series[0].values = [f64(-1.7e308), 1.7e308]
	extreme := options.value_range()?
	assert extreme.fraction(0) == 0.5
	assert extreme.fraction(-1.7e308) == 0 && extreme.fraction(1.7e308) == 1
	assert chart_finite(extreme.tick(0.5))
	options.kind = .bars
	options.x_axis = ChartAxis{minimum: f64(-2), maximum: f64(2)}
	assert options.value_range()? == ChartRange{-2, 2}
}

fn test_chart_styles_render_signed_series_titles_axes_and_legend() {
	for kind in [ChartKind.columns, .bars, .lines] {
		mut app := new_app()
		app.screen.resize(70, 22)
		app.screen.fill(Rect{0, 0, 70, 22}, `!`, white, black)
		mut plot := chart(Chart{kind: kind, title: 'Revenue', labels: ['North', 'South'],
			x_axis: ChartAxis{title: 'Horizontal', minimum: f64(-10), maximum: f64(10)},
			y_axis: ChartAxis{title: 'Vertical', minimum: f64(-10), maximum: f64(10)},
			series: [ChartSeries{name: 'Actual', values: [f64(10), -10], color: red},
				ChartSeries{name: 'Plan', values: [f64(-8), 8], color: green}],
			grid: false, bg: black, fg: white, axis_color: cyan})
		plot.padding = Insets{left: 1, top: 1, right: 1, bottom: 1}
		plot.layout(Rect{2, 2, 64, 18})
		app.draw_ctl(mut plot)
		image := app.screen.snapshot()
		for text in ['Revenue', 'Horizontal', 'Vertical', 'North', 'South', 'Actual', 'Plan', '-10', '10'] { assert image.contains(text), '${kind}: ${text}' }
		glyph := if kind == .lines { '•' } else { '█' }
		assert app.screen.cells.any(it.glyph == glyph && it.fg == red)
		assert app.screen.cells.any(it.glyph == glyph && it.fg == green)
		for y in 0 .. 22 {
			for x in 0 .. 70 {
				cell := app.screen.cells[y * 70 + x]
				if !plot.rect().contains(x, y) { assert cell.glyph == '!' }
				if plot.rect().contains(x, y) && !plot.content_rect().contains(x, y) { assert cell.glyph == ' ' && cell.bg == black }
			}
		}
	}
}

fn test_chart_line_gaps_and_fixed_range_clipping() {
	mut app := new_app()
	app.screen.resize(40, 14)
	mut plot := chart(Chart{kind: .lines, legend: false, grid: false,
		y_axis: ChartAxis{minimum: f64(0), maximum: f64(10), ticks: 2},
		series: [ChartSeries{values: [f64(-10), 20], color: red}]})
	plot.layout(Rect{0, 0, 40, 14})
	app.draw_ctl(mut plot)
	// The crossing is clipped in value space, not flattened against the bounds.
	points := app.screen.cells.filter(it.fg == vtk.red && it.glyph == '•')
	assert points.len > 5
	assert app.screen.cells[3 + 8].glyph != '•'
	assert app.screen.cells[11 * 40 + 3 + 26].glyph != '•'
	plot.set_chart(Chart{kind: .lines, legend: false, grid: false,
		y_axis: ChartAxis{minimum: f64(0), maximum: f64(10), ticks: 2},
		series: [ChartSeries{values: [f64(0), math.nan(), 10], color: red}]})
	app.draw_ctl(mut plot)
	assert app.screen.cells.count(it.fg == vtk.red && it.glyph == '•') == 2
	// Segments entirely above the fixed scale must disappear.
	plot.chart.series[0].values = [f64(20), 30]
	app.draw_ctl(mut plot)
	assert !app.screen.cells.any(it.fg == vtk.red && it.glyph == '•')
}

fn test_chart_update_owns_data_invalidates_and_disposal_releases_it() {
	mut app := new_app()
	mut window := app.window('Chart', 50, 20)
	mut options := Chart{labels: ['One'], series: [ChartSeries{values: [f64(1)]}]}
	mut plot := chart(options)
	window.add(mut plot)
	app.redraw()
	app.dirty = false
	options.labels[0] = 'Two'
	options.series[0].values[0] = 2
	assert plot.chart.labels == ['One'] && plot.chart.series[0].values == [f64(1)]
	plot.set_chart(options)
	assert app.dirty && plot.chart.labels == ['Two']
	options.series[0].values[0] = 3
	assert plot.chart.series[0].values == [f64(2)]
	app.destroy_ctl(mut plot)
	assert plot.chart.series.len == 0 && plot.chart.labels.len == 0
	plot.set_chart(options)
	assert plot.chart.series.len == 0
}

fn test_empty_tiny_and_ascii_charts_are_safe() {
	mut app := new_app()
	app.screen.resize(30, 15)
	mut plot := chart(Chart{title: 'Empty', series: [ChartSeries{values: [math.nan(), math.inf(-1)]}]})
	plot.layout(Rect{0, 0, 30, 15})
	app.draw_ctl(mut plot)
	assert app.screen.snapshot().contains('No data')
	for kind in [ChartKind.columns, .bars, .lines] {
		plot.set_chart(Chart{kind: kind, title: 'Title', labels: ['長い名前', 'Two'],
			series: [ChartSeries{name: 'A', values: [f64(0), -2]}]})
		for width in 0 .. 12 {
			for height in 0 .. 12 {
				plot.layout(Rect{2, 2, width, height})
				app.draw_ctl(mut plot)
			}
		}
		app.screen.ascii = true
		plot.layout(Rect{0, 0, 30, 15})
		app.draw_ctl(mut plot)
		assert app.screen.snapshot().runes().all(it < 128)
	}
}
