module vtk

import math
import strconv

pub enum ChartKind {
	columns
	bars
	lines
}

const chart_palette = [cyan, green, yellow, magenta, red, bright_white]

// The category axis is X for columns/lines and Y for bars. Bounds and ticks
// apply to the numeric axis; category labels come from Chart.labels.
pub struct ChartAxis {
pub mut:
	title string
	minimum ?f64
	maximum ?f64
	ticks int = 5
	include_zero bool = true
}

pub struct ChartSeries {
pub mut:
	name string
	values []f64
	color int = -1 // Theme-independent palette when negative.
}

pub struct Chart {
pub mut:
	kind ChartKind
	title string
	labels []string
	series []ChartSeries
	x_axis ChartAxis
	y_axis ChartAxis
	legend bool = true
	grid bool = true
	fg int = -1 // Negative colors inherit the surrounding theme.
	bg int = -1
	axis_color int = -1
}

pub fn chart(options Chart) &Ctl {
	mut c := &Ctl{kind: .chart, expand: true}
	c.set_chart(options)
	return c
}

// set_chart copies the data and schedules a redraw without emitting changed.
pub fn (mut c Ctl) set_chart(options Chart) {
	if c.kind != .chart || c.destroyed { return }
	c.chart = options
	c.chart.labels = options.labels.clone()
	c.chart.series = options.series.map(ChartSeries{name: it.name, values: it.values.clone(), color: it.color})
	c.invalidate()
}

struct ChartRange {
	minimum f64
	maximum f64
}

fn chart_finite(value f64) bool { return !math.is_nan(value) && !math.is_inf(value, 0) }

fn (c &Chart) numeric_axis() ChartAxis { return if c.kind == .bars { c.x_axis } else { c.y_axis } }

fn (c &Chart) value_range() ?ChartRange {
	axis := c.numeric_axis()
	mut low, mut high := math.inf(1), math.inf(-1)
	for series in c.series {
		for value in series.values {
			if !chart_finite(value) { continue }
			low = math.min(low, value)
			high = math.max(high, value)
		}
	}
	if low > high { return none }
	if axis.include_zero { low = math.min(0, low); high = math.max(0, high) }
	if low == high {
		if low > 0 { low = math.min(low * 0.9, math.nextafter(low, 0)) }
		else if high < 0 { high = math.max(high * 0.9, math.nextafter(high, 0)) }
		else { high = 1 }
	}
	auto := ChartRange{low, high}
	if value := axis.minimum { if chart_finite(value) { low = value } }
	if value := axis.maximum { if chart_finite(value) { high = value } }
	// Ignore conflicting bounds, retaining a usable automatic scale.
	return if low < high { ChartRange{low, high} } else { auto }
}

fn (r ChartRange) fraction(value f64) f64 {
	// Normalize first so ranges near the limits of f64 do not overflow.
	scale := math.max(math.abs(r.minimum), math.abs(r.maximum))
	v := math.max(r.minimum, math.min(r.maximum, value)) / scale
	return (v - r.minimum / scale) / (r.maximum / scale - r.minimum / scale)
}

fn (r ChartRange) tick(fraction f64) f64 {
	return r.minimum * (1 - fraction) + r.maximum * fraction
}

fn chart_number(value f64) string {
	if value == 0 { return '0' }
	if math.abs(value) >= 1e6 || math.abs(value) < 0.001 { return strconv.f64_to_str(value, 3) }
	return '${value:.3f}'.trim_right('0').trim_right('.')
}

fn (c &Chart) category_count() int {
	mut count := c.labels.len
	for series in c.series { count = max(count, series.values.len) }
	return count
}

fn (c &Chart) category_label(index int) string {
	return if index < c.labels.len { c.labels[index] } else { (index + 1).str() }
}

fn chart_color(series ChartSeries, index int, disabled bool, dim int) int {
	if disabled { return dim }
	if series.color >= 0 { return series.color }
	return chart_palette[index % chart_palette.len]
}

fn (mut app App) draw_chart(c &Ctl, inherited_fg int, inherited_bg int) {
	plot_data := &c.chart
	fg := if c.disabled { app.theme.dim } else if plot_data.fg >= 0 { plot_data.fg } else { inherited_fg }
	bg := if plot_data.bg >= 0 { plot_data.bg } else { inherited_bg }
	axis_color := if c.disabled { app.theme.dim } else if plot_data.axis_color >= 0 { plot_data.axis_color } else { app.theme.dim }
	app.fill_ctl(c, fg, bg)
	mut s := &app.screen
	mut top := c.y
	if plot_data.title != '' {
		s.aligned_text(c.x, top, c.w, plot_data.title, .center, fg, bg, bold)
		top++
	}
	if plot_data.y_axis.title != '' {
		s.aligned_text(c.x, top, c.w, plot_data.y_axis.title, .left, fg, bg, 0)
		top++
	}
	mut bottom := c.y + c.h
	if plot_data.legend && plot_data.series.len > 0 {
		bottom--
		mut x := c.x
		for i, series in plot_data.series {
			name := if series.name == '' { 'Series ${i + 1}' } else { series.name }
			s.text(x, bottom, '■ ' + name, chart_color(series, i, c.disabled, app.theme.dim), bg, 0)
			x += text_width(name) + 3
			if x >= c.x + c.w { break }
		}
	}
	if plot_data.x_axis.title != '' {
		bottom--
		s.aligned_text(c.x, bottom, c.w, plot_data.x_axis.title, .center, fg, bg, 0)
	}
	range := plot_data.value_range() or {
		s.aligned_text(c.x, top, c.w, 'No data', .center, fg, bg, 0)
		return
	}
	count := plot_data.category_count()
	mut gutter := 1
	if plot_data.kind == .bars {
		for i in 0 .. count { gutter = max(gutter, text_width(plot_data.category_label(i))) }
	} else {
		for i in 0 .. clamp(plot_data.y_axis.ticks, 2, 20) {
			gutter = max(gutter, text_width(chart_number(range.tick(f64(i) / (clamp(plot_data.y_axis.ticks, 2, 20) - 1)))))
		}
	}
	gutter = min(gutter, c.w / 3)
	plot := Rect{c.x + gutter + 1, top, c.w - gutter - 1, bottom - top - 2}
	if plot.w < 2 || plot.h < 2 { return }
	s.fill(Rect{plot.x - 1, plot.y, 1, plot.h + 1}, `│`, axis_color, bg)
	s.fill(Rect{plot.x - 1, plot.y + plot.h, plot.w + 1, 1}, `─`, axis_color, bg)
	s.put(plot.x - 1, plot.y + plot.h, `└`, axis_color, bg, 0)
	axis := plot_data.numeric_axis()
	mut ticks := min(clamp(axis.ticks, 2, 20), plot.h)
	if plot_data.kind == .bars {
		label_width := max(text_width(chart_number(range.minimum)), text_width(chart_number(range.maximum)))
		ticks = min(clamp(axis.ticks, 2, 20), max(2, plot.w / (label_width + 2)))
	}
	for i in 0 .. ticks {
		fraction := f64(i) / (ticks - 1)
		tick_text := chart_number(range.tick(fraction))
		if plot_data.kind == .bars {
			x := plot.x + int(math.round(fraction * (plot.w - 1)))
			if plot_data.grid { s.fill(Rect{x, plot.y, 1, plot.h}, `│`, axis_color, bg) }
			start := clamp(x - text_width(tick_text) / 2, plot.x, plot.x + plot.w - text_width(tick_text))
			s.aligned_text(start, plot.y + plot.h + 1, plot.x + plot.w - start, tick_text, .left, fg, bg, 0)
		} else {
			y := plot.y + plot.h - 1 - int(math.round(fraction * (plot.h - 1)))
			if plot_data.grid { s.fill(Rect{plot.x, y, plot.w, 1}, `─`, axis_color, bg) }
			s.aligned_text(c.x, y, gutter, tick_text, .right, fg, bg, 0)
		}
	}
	zero := range.fraction(0)
	if plot_data.kind == .bars {
		s.fill(Rect{plot.x + int(math.round(zero * (plot.w - 1))), plot.y, 1, plot.h}, `│`, axis_color, bg)
	} else {
		s.fill(Rect{plot.x, plot.y + plot.h - 1 - int(math.round(zero * (plot.h - 1))), plot.w, 1}, `─`, axis_color, bg)
	}
	// Clip plotting separately so data never overwrites titles, ticks or legend.
	clip := s.set_clip(plot)
	for i, series in plot_data.series {
		color := chart_color(series, i, c.disabled, app.theme.dim)
		mut previous := false
		mut px, mut pv := 0, f64(0)
		for index, value in series.values {
			if !chart_finite(value) { previous = false; continue }
			extent := if plot_data.kind == .bars { plot.h } else { plot.w }
			start, end := index * extent / count, (index + 1) * extent / count
			if plot_data.kind == .lines {
				x := plot.x + (start + end - 1) / 2
				if previous { s.chart_segment(px, pv, x, value, plot, range, color, bg) }
				if value >= range.minimum && value <= range.maximum {
					y := plot.y + plot.h - 1 - int(math.round(range.fraction(value) * (plot.h - 1)))
					s.put(x, y, `•`, color, bg, 0)
				}
				px, pv, previous = x, value, true
				continue
			}
			band := end - start - int(end - start > plot_data.series.len + 1)
			a := start + i * band / plot_data.series.len
			b := start + (i + 1) * band / plot_data.series.len
			fraction := range.fraction(value)
			if plot_data.kind == .bars {
				base := plot.x + int(math.round(zero * (plot.w - 1)))
				x := plot.x + int(math.round(fraction * (plot.w - 1)))
				s.fill(Rect{min(base, x) + int(x > base), plot.y + a, abs(x - base), b - a}, `█`, color, bg)
			} else {
				base := plot.y + plot.h - 1 - int(math.round(zero * (plot.h - 1)))
				y := plot.y + plot.h - 1 - int(math.round(fraction * (plot.h - 1)))
				s.fill(Rect{plot.x + a, min(base, y) + int(y > base), b - a, abs(y - base)}, `█`, color, bg)
			}
		}
	}
	s.restore_clip(clip)
	mut label_end := plot.x
	for i in 0 .. count {
		if plot_data.kind == .bars {
			start, end := i * plot.h / count, (i + 1) * plot.h / count
			if end > start { s.aligned_text(c.x, plot.y + (start + end - 1) / 2, gutter, plot_data.category_label(i), .right, fg, bg, 0) }
		} else {
			start, end := i * plot.w / count, (i + 1) * plot.w / count
			tick_text := plot_data.category_label(i)
			x := max(plot.x, plot.x + (start + end - 1 - text_width(tick_text)) / 2)
			if end > start && x >= label_end {
				s.aligned_text(x, plot.y + plot.h + 1, plot.x + plot.w - x, tick_text, .left, fg, bg, 0)
				label_end = x + text_width(tick_text) + 1
			}
		}
	}
}

// Clip line segments in value space before rasterizing, including crossings
// whose endpoints are both outside the visible range.
fn (mut s Screen) chart_segment(x1 int, v1 f64, x2 int, v2 f64, plot Rect, range ChartRange, fg int, bg int) {
	if (v1 < range.minimum && v2 < range.minimum) || (v1 > range.maximum && v2 > range.maximum) { return }
	scale := math.max(math.max(math.abs(v1), math.abs(v2)), math.max(math.abs(range.minimum), math.abs(range.maximum)))
	a, b := v1 / scale, v2 / scale
	mut first, mut last := f64(0), f64(1)
	if v1 < range.minimum { first = (range.minimum / scale - a) / (b - a) }
	if v1 > range.maximum { first = (range.maximum / scale - a) / (b - a) }
	if v2 < range.minimum { last = (range.minimum / scale - a) / (b - a) }
	if v2 > range.maximum { last = (range.maximum / scale - a) / (b - a) }
	start := x1 + int(math.round(f64(x2 - x1) * first))
	end := x1 + int(math.round(f64(x2 - x1) * last))
	y1 := plot.y + plot.h - 1 - int(math.round(range.fraction(v1) * (plot.h - 1)))
	y2 := plot.y + plot.h - 1 - int(math.round(range.fraction(v2) * (plot.h - 1)))
	s.line(start, y1, end, y2, `•`, fg, bg)
}
