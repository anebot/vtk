module slides

import image
import image.jpeg
import image.png
import io
import math
import os
import strconv
import vtk

const chart_max_series = 6

struct Run {
	text string
	attr int
}

struct Shape {
mut:
	kind  string
	a     int
	b     int
	c     int
	d     int
	color int
}

struct ChartData {
mut:
	kind   string
	title  string
	labels []string
	names  []string
	series [][]f64
}

@[heap]
struct SlideImage {
mut:
	width  int
	height int
	pixels []int
}

@[heap]
struct ImageCache {
mut:
	entries map[string]&SlideImage
}

struct SlidePaint {
mut:
	preview      bool
	presentation bool
	selected     bool
	drag_target  bool
	cache        &ImageCache @[required]
	base_dir     string
	page         int
	pages        int
}

struct ImageLink {
	alt  string
	path string
}

struct BytesReader {
	bytes []u8
mut:
	pos int
}

fn (mut r BytesReader) read(mut buf []u8) !int {
	if r.pos >= r.bytes.len {
		return io.Eof{}
	}
	n := copy(mut buf, r.bytes[r.pos..])
	r.pos += n
	return n
}

fn slide_background() int {
	return vtk.color_rgb(14, 18, 26)
}

fn slide_foreground() int {
	return vtk.color_rgb(232, 236, 244)
}

fn slide_dim() int {
	return vtk.color_rgb(132, 144, 164)
}

fn slide_accent() int {
	return vtk.color_rgb(89, 173, 255)
}

fn slide_warm() int {
	return vtk.color_rgb(255, 209, 20)
}

fn image_line(line string) ?ImageLink {
	trim := line.trim_space()
	if !trim.starts_with('![') {
		return none
	}
	close := trim.index('](') or { return none }
	end := trim.index(')') or { return none }
	if close + 2 > end {
		return none
	}
	alt := trim[2..close].trim_space()
	path := trim[close + 2..end].trim_space().trim('"').trim("'")
	if path == '' {
		return none
	}
	return ImageLink{alt, path}
}

fn inline_plain(text string) string {
	mut out := ''
	for run in inline_runs(text) {
		out += run.text
	}
	return out
}

fn inline_runs(text string) []Run {
	mut runs := []Run{}
	mut attr := 0
	mut start := 0
	mut i := 0
	for i < text.len {
		if text[i] == `\\` && i + 1 < text.len {
			if i > start {
				runs << Run{text[start..i], attr}
			}
			r := text[i + 1..].runes()[0]
			runs << Run{r.str(), attr}
			i += 1 + r.str().len
			start = i
			continue
		}
		if text[i] == `<` {
			if close := text[i..].index('>') {
				tag := text[i + 1..i + close].to_lower()
				if tag in ['u', '/u', 'b', '/b', 'strong', '/strong', 'em', '/em', 'i', '/i'] {
					if i > start {
						runs << Run{text[start..i], attr}
					}
					bit := if tag.trim_left('/') == 'u' {
						vtk.underline
					} else if tag.trim_left('/') in ['b', 'strong'] {
						vtk.bold
					} else {
						vtk.italic
					}
					attr = if tag.starts_with('/') { attr & ~bit } else { attr | bit }
					i += close + 1
					start = i
					continue
				}
			}
		}
		if text[i] == 96 {
			if close := text[i + 1..].index('`') {
				if i > start {
					runs << Run{text[start..i], attr}
				}
				runs << Run{text[i + 1..i + 1 + close], attr | vtk.underline}
				i += close + 2
				start = i
				continue
			}
		}
		if i + 1 < text.len && text[i..i + 2] in ['**', '__', '~~'] {
			if i > start {
				runs << Run{text[start..i], attr}
			}
			attr = attr ^ (if text[i] == `~` { vtk.underline } else { vtk.bold })
			i += 2
			start = i
			continue
		}
		if text[i] in [u8(`*`), u8(`_`)] {
			if i > start {
				runs << Run{text[start..i], attr}
			}
			attr = attr ^ vtk.italic
			i++
			start = i
			continue
		}
		if text[i] == `[` {
			if close_rel := text[i + 1..].index('](') {
				close := i + 1 + close_rel
				if end_rel := text[close + 2..].index(')') {
					end := close + 2 + end_rel
					if i > start {
						runs << Run{text[start..i], attr}
					}
					runs << Run{text[i + 1..close], attr | vtk.underline}
					i = end + 1
					start = i
					continue
				}
			}
		}
		i++
	}
	if start < text.len {
		runs << Run{text[start..], attr}
	}
	return runs
}

fn runs_width(runs []Run) int {
	mut width := 0
	for run in runs {
		width += vtk.text_width(run.text)
	}
	return width
}

fn draw_runs(mut screen vtk.Screen, x int, y int, width int, runs []Run, fg int, bg int, attr int) {
	if width <= 0 {
		return
	}
	mut cx := x
	for run in runs {
		for r in run.text.runes() {
			w := vtk.rune_width(r)
			if cx + w > x + width {
				return
			}
			screen.put(cx, y, r, fg, bg, attr | run.attr)
			cx += w
		}
	}
}

fn wrap_text(text string, width int) []string {
	if width < 1 {
		return []
	}
	mut out := []string{}
	mut line := []rune{}
	mut line_w := 0
	for word in text.split(' ') {
		if word == '' {
			continue
		}
		ww := vtk.text_width(word)
		if line_w > 0 && line_w + 1 + ww > width {
			out << line.string()
			line = []rune{}
			line_w = 0
		}
		if line_w > 0 {
			line << ` `
			line_w++
		}
		for r in word.runes() {
			rw := vtk.rune_width(r)
			if line_w + rw > width && line_w > 0 {
				out << line.string()
				line = []rune{}
				line_w = 0
			}
			line << r
			line_w += rw
		}
	}
	if line_w > 0 {
		out << line.string()
	}
	return out
}

fn parse_color(text string, fallback int) int {
	value := text.trim_space()
	if value == '' {
		return fallback
	}
	if value.starts_with('#') && value.len == 7 {
		r := hex_byte(value[1..3])
		g := hex_byte(value[3..5])
		b := hex_byte(value[5..7])
		return vtk.color_rgb(r, g, b)
	}
	return match value.to_lower() {
		'black' { vtk.black }
		'red' { vtk.red }
		'green' { vtk.green }
		'yellow' { vtk.yellow }
		'blue' { vtk.blue }
		'magenta', 'purple' { vtk.magenta }
		'cyan' { vtk.cyan }
		'white' { vtk.white }
		'gray', 'grey' { vtk.gray }
		'orange' { vtk.color_rgb(255, 140, 0) }
		'pink' { vtk.color_rgb(238, 96, 168) }
		'lime' { vtk.color_rgb(121, 201, 66) }
		else { fallback }
	}
}

fn hex_byte(text string) int {
	mut value := 0
	for ch in text.bytes() {
		value *= 16
		if ch >= `0` && ch <= `9` {
			value += int(ch - `0`)
		} else if ch >= `a` && ch <= `f` {
			value += int(ch - `a`) + 10
		} else if ch >= `A` && ch <= `F` {
			value += int(ch - `A`) + 10
		}
	}
	return vtk.clamp(value, 0, 255)
}

fn percent(text string, total int) int {
	value := strconv.atof64(text.trim_space()) or { 0 }
	return vtk.clamp(int(value * f64(total) / 100), 0, math.max(0, total - 1))
}

fn percent_size(text string, total int) int {
	value := strconv.atof64(text.trim_space()) or { 0 }
	return vtk.clamp(int(value * f64(total) / 100), 1, math.max(1, total))
}

fn parse_shape(line string, area vtk.Rect, fallback int) ?Shape {
	fields := line.trim_space().fields()
	if fields.len < 2 {
		return none
	}
	kind := fields[0].to_lower()
	if kind.starts_with('#') {
		return none
	}
	mut color := fallback
	if kind == 'rect' || kind == 'square' || kind == 'fillrect' {
		if fields.len < 5 {
			return none
		}
		if fields.len > 5 {
			color = parse_color(fields[5], fallback)
		}
		return Shape{
			kind:  kind
			a:     percent(fields[1], area.w)
			b:     percent(fields[2], area.h)
			c:     percent_size(fields[3], area.w)
			d:     percent_size(fields[4], area.h)
			color: color
		}
	}
	if kind == 'line' {
		if fields.len < 5 {
			return none
		}
		if fields.len > 5 {
			color = parse_color(fields[5], fallback)
		}
		return Shape{
			kind:  kind
			a:     percent(fields[1], area.w)
			b:     percent(fields[2], area.h)
			c:     percent(fields[3], area.w)
			d:     percent(fields[4], area.h)
			color: color
		}
	}
	if kind == 'circle' {
		if fields.len < 4 {
			return none
		}
		if fields.len > 4 {
			color = parse_color(fields[4], fallback)
		}
		radius := percent_size(fields[3], math.min(area.w, area.h * 2))
		return Shape{
			kind:  kind
			a:     percent(fields[1], area.w)
			b:     percent(fields[2], area.h)
			c:     radius
			d:     radius
			color: color
		}
	}
	return none
}

fn draw_shapes(mut screen vtk.Screen, text string, area vtk.Rect, bg int, fallback int) {
	for line in text.split_into_lines() {
		shape := parse_shape(line, area, fallback) or { continue }
		r := vtk.Rect{area.x + shape.a, area.y + shape.b, shape.c, shape.d}
		match shape.kind {
			'rect', 'square' {
				screen.frame(r, false, shape.color, bg)
			}
			'fillrect' {
				screen.fill(r, `█`, shape.color, shape.color)
			}
			'line' {
				glyph := if shape.b == shape.d {
					`─`
				} else if shape.a == shape.c {
					`│`
				} else if (shape.c - shape.a) * (shape.d - shape.b) >= 0 {
					`\\`
				} else {
					`/`
				}
				screen.line(area.x + shape.a, area.y + shape.b, area.x + shape.c,
					area.y + shape.d, glyph, shape.color, bg)
			}
			'circle' {
				draw_circle(mut screen, area.x + shape.a, area.y + shape.b, shape.c, shape.color, bg)
			}
			else {}
		}
	}
}

fn draw_circle(mut screen vtk.Screen, cx int, cy int, radius int, color int, bg int) {
	if radius < 1 {
		return
	}
	mut x := radius
	mut y := 0
	mut err := 1 - radius
	for x >= y {
		points := [[x, y], [y, x], [-y, x], [-x, y], [-x, -y], [-y, -x], [y, -x], [x, -y]]
		for point in points {
			screen.put(cx + point[0], cy + point[1], `•`, color, bg, 0)
		}
		y++
		if err < 0 {
			err += 2 * y + 1
		} else {
			x--
			err += 2 * (y - x) + 1
		}
	}
}

fn chart_color(index int) int {
	return match index % 6 {
		0 { vtk.color_rgb(89, 173, 255) }
		1 { vtk.color_rgb(121, 201, 66) }
		2 { vtk.color_rgb(255, 209, 20) }
		3 { vtk.color_rgb(238, 96, 168) }
		4 { vtk.color_rgb(132, 61, 204) }
		else { vtk.color_rgb(255, 140, 0) }
	}
}

fn chart_row(line string) []string {
	text := line.trim_space()
	if text == '' {
		return []
	}
	sep := if text.contains('|') { '|' } else { ',' }
	mut cells := text.split(sep).map(it.trim_space())
	if cells.len > 0 && cells.first() == '' {
		cells.delete(0)
	}
	if cells.len > 0 && cells.last() == '' {
		cells.delete_last()
	}
	return cells
}

fn parse_chart(text string) ChartData {
	lines := text.split_into_lines().filter(it.trim_space() != '' && !it.trim_space().starts_with('#'))
	mut data := ChartData{ kind: 'columns' }
	if lines.len == 0 {
		return data
	}
	mut first := 0
	head := lines[0].trim_space()
	parts := head.split('|')
	kind := parts[0].trim_space().to_lower()
	if kind in ['columns', 'bars', 'lines'] {
		data.kind = kind
		if parts.len > 1 {
			data.title = parts[1].trim_space()
		}
		first = 1
	}
	mut rows := [][]string{}
	for i := first; i < lines.len; i++ {
		row := chart_row(lines[i])
		if row.len > 0 {
			rows << row
		}
	}
	if rows.len == 0 {
		return data
	}
	header := first < lines.len && lines[first].trim_space().starts_with('|')
	mut start_row := 0
	if header {
		data.labels = rows[0].clone()
		start_row = 1
	}
	if !header && rows.len > 0 && rows.all(it.len == 2) {
		data.names << 'Value'
		for row in rows {
			data.labels << row[0]
			value := strconv.atof64(row[1]) or { 0 }
			if data.series.len == 0 {
				data.series << []f64{}
			}
			data.series[0] << value
		}
		return data
	}
	mut max_values := 0
	for row in rows[start_row..] {
		if row.len < 2 {
			continue
		}
		data.names << if row[0] == '' { 'Series ${data.names.len + 1}' } else { row[0] }
		if data.names.len > chart_max_series {
			data.names.delete_last()
			break
		}
		mut values := []f64{}
		for cell in row[1..] {
			values << strconv.atof64(cell.trim_space()) or { 0 }
		}
		data.series << values
		max_values = math.max(max_values, values.len)
	}
	if data.labels.len == 0 {
		for i in 0 .. max_values {
			data.labels << '${i + 1}'
		}
	}
	return data
}

fn chart_value_range(data ChartData) (f64, f64) {
	mut low := 0.0
	mut high := 0.0
	mut any := false
	for series in data.series {
		for value in series {
			low = math.min(low, value)
			high = math.max(high, value)
			any = true
		}
	}
	if !any {
		return 0, 1
	}
	if high == low {
		high = low + 1
	}
	return low, high
}

fn chart_y(value f64, low f64, high f64, rect vtk.Rect) int {
	if high <= low {
		return rect.y + rect.h - 1
	}
	return rect.y + rect.h - 1 - int((value - low) * f64(rect.h - 1) / (high - low))
}

fn truncate_plain(text string, width int) string {
	if width <= 0 {
		return ''
	}
	mut out := ''
	mut used := 0
	for run in inline_runs(text) {
		for r in run.text.runes() {
			w := vtk.rune_width(r)
			if used + w > width {
				return out
			}
			out += r.str()
			used += w
		}
	}
	return out
}

fn draw_chart(mut screen vtk.Screen, area vtk.Rect, data ChartData, bg int, fg int, preview bool) {
	if data.series.len == 0 || data.labels.len == 0 {
		screen.text(area.x, area.y, '[chart: no data]', slide_dim(), bg, 0)
		return
	}
	mut y := area.y
	if data.title != '' {
		runs := inline_runs(data.title)
		width := runs_width(runs)
		draw_runs(mut screen, area.x + math.max(0, (area.w - width) / 2), y, area.w, runs, fg,
			bg, vtk.bold)
		y++
	}
	bottom := area.y + area.h - 1
	if y >= bottom {
		return
	}
	if data.kind == 'bars' {
		low, high := chart_value_range(data)
		mut label_width := 0
		for label in data.labels {
			label_width = math.max(label_width, vtk.text_width(inline_plain(label)))
		}
		label_width = math.min(label_width, math.max(3, area.w / 3))
		plot_x := area.x + label_width + 1
		plot_w := math.max(1, area.x + area.w - plot_x)
		mut row := y
		for i, label in data.labels {
			if row > bottom {
				break
			}
			screen.text(area.x, row, truncate_plain(label, label_width), fg, bg, 0)
			for s, series in data.series {
				if i >= series.len {
					continue
				}
				length := if high > low {
					int((series[i] - math.min(0.0, low)) * f64(plot_w) / (math.max(0.0, high) - math.min(0.0, low)))
				} else {
					0
				}
				if length > 0 {
					screen.fill(vtk.Rect{plot_x, row, math.min(length, plot_w), 1}, `█`,
						chart_color(s), bg)
				}
			}
			row++
		}
		return
	}
	label_rows := if area.h >= 6 && !preview {
		1
	} else if area.h >= 5 {
		1
	} else {
		0
	}
	plot := vtk.Rect{area.x, y, area.w, math.max(1, bottom - y + 1 - label_rows)}
	low, high := chart_value_range(data)
	if data.kind == 'lines' {
		if plot.h < 2 || plot.w < 2 {
			return
		}
		mut previous := []int{len: data.series.len, init: -1}
		mut previous_y := []int{len: data.series.len, init: -1}
		bottom_y := chart_y(0, low, high, plot)
		screen.line(plot.x, bottom_y, plot.x + plot.w - 1, bottom_y, `─`, slide_dim(), bg)
		for i in 0 .. data.labels.len {
			if data.labels.len > 1 {
				x := plot.x + i * math.max(1, plot.w - 1) / (data.labels.len - 1)
				for s, series in data.series {
					if i >= series.len {
						continue
					}
					py := chart_y(series[i], low, high, plot)
					if previous[s] >= 0 && i - previous[s] <= 2 {
						screen.line(previous[s], previous_y[s], x, py, `*`, chart_color(s), bg)
					}
					screen.put(x, py, `•`, chart_color(s), bg, 0)
					previous[s] = x
					previous_y[s] = py
				}
			}
		}
	} else {
		baseline := chart_y(0, low, high, plot)
		screen.line(plot.x, baseline, plot.x + plot.w - 1, baseline, `─`, slide_dim(), bg)
		group := math.max(1, plot.w / data.labels.len)
		bar := math.max(1, (group - 1) / math.max(1, data.series.len))
		for i, _ in data.labels {
			gx := plot.x + i * group
			for s, series in data.series {
				if i >= series.len {
					continue
				}
				py := chart_y(series[i], low, high, plot)
				x := gx + s * bar
				top := math.min(py, baseline)
			height := math.max(1, math.abs(baseline - py) + 1)
				if x < plot.x + plot.w {
					screen.fill(vtk.Rect{x, top, math.min(bar, plot.x + plot.w - x), height}, `█`,
						chart_color(s), bg)
				}
			}
		}
	}
	if label_rows > 0 {
		mut used := 0
		for i, label in data.labels {
			x := if data.labels.len > 1 {
				plot.x + i * math.max(1, plot.w - 1) / (data.labels.len - 1)
			} else {
				plot.x
			}
			text := truncate_plain(label, math.max(2, plot.w / math.max(1, data.labels.len)))
			if x + vtk.text_width(text) <= area.x + area.w && x - used >= 0 {
				screen.text(x, bottom, text, slide_dim(), bg, 0)
				used = x + vtk.text_width(text)
			}
		}
	}
	if !preview && data.names.len > 0 && area.h > 4 {
		mut x := area.x
		for s, name in data.names {
			text := '■ ${name}'
			if x + vtk.text_width(text) >= area.x + area.w {
				break
			}
			screen.text(x, area.y + area.h - 1, text, chart_color(s), bg, 0)
			x += vtk.text_width(text) + 2
		}
	}
}

fn (mut cache ImageCache) get(path string) &SlideImage {
	if image := cache.entries[path] { return image }
	loaded := load_slide_image(path) or {
		failed := &SlideImage{}
		cache.entries[path] = failed
		return failed
	}
	cache.entries[path] = loaded
	return loaded
}

fn load_slide_image(path string) !&SlideImage {
	data := os.read_bytes(path)!
	mut decoded := ?image.Image(none)
	if data.len >= 8 && data[0] == 0x89 && data[1] == `P` && data[2] == `N` && data[3] == `G` {
		decoded = png.decode(BytesReader{ bytes: data })!
	} else if data.len >= 3 && data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff {
		decoded = jpeg.decode(BytesReader{ bytes: data })!
	} else {
		decoded = png.decode(BytesReader{ bytes: data }) or {
			jpeg.decode(BytesReader{ bytes: data })!
		}
	}
	img := decoded or { return error('Unsupported image ${path}') }
	bounds := img.bounds()
	src_w, src_h := bounds.dx(), bounds.dy()
	if src_w <= 0 || src_h <= 0 {
		return error('Empty image ${path}')
	}
	max_w, max_h := 240, 240
	mut scale := math.min(f64(max_w) / f64(src_w), f64(max_h) / f64(src_h))
	if scale > 1 {
		scale = 1
	}
	width := math.max(1, int(f64(src_w) * scale))
	height := math.max(1, int(f64(src_h) * scale))
	mut pixels := []int{len: width * height, init: -1}
	for y in 0 .. height {
		for x in 0 .. width {
			sx := bounds.min.x + math.min(src_w - 1, x * src_w / width)
			sy := bounds.min.y + math.min(src_h - 1, y * src_h / height)
			color := img.at(sx, sy)
			r, g, b, a := color.rgba()
			if a == 0 {
				pixels[y * width + x] = -1
			} else {
				pixels[y * width + x] = vtk.color_rgb(int(r >> 8), int(g >> 8), int(b >> 8))
			}
		}
	}
	return &SlideImage{
		width:  width
		height: height
		pixels: pixels
	}
}

fn image_height(img &SlideImage, width int, available int, preview bool) int {
	if img.width <= 0 || img.height <= 0 {
		return math.min(available, 3)
	}
	ideal := width * img.height / (img.width * 2)
	limit := if preview { math.min(available, 4) } else { math.min(available, 18) }
	return vtk.clamp(ideal, 1, math.max(1, limit))
}

fn draw_image(mut screen vtk.Screen, area vtk.Rect, alt string, path string, cache &ImageCache, bg int, preview bool) {
	img := cache.get(path)
	screen.fill(area, ` `, slide_foreground(), bg)
	if img.width == 0 || img.height == 0 {
		screen.frame(area, false, slide_dim(), bg)
		text := if alt == '' { '[image]' } else { '[${alt}]' }
		width := vtk.text_width(text)
		screen.text(area.x + math.max(0, (area.w - width) / 2), area.y + area.h / 2,
			truncate_plain(text, math.max(1, area.w - 2)), slide_dim(), bg, 0)
		return
	}
	cell_w := math.min(area.w, math.max(1, area.h * 2 * img.width / img.height))
	x := area.x + math.max(0, (area.w - cell_w) / 2)
	for row in 0 .. area.h {
		fy := f64(row * 2) / f64(math.max(1, area.h * 2))
		fy2 := f64(row * 2 + 1) / f64(math.max(1, area.h * 2))
		ty := math.min(img.height - 1, int(fy * f64(img.height)))
		by := math.min(img.height - 1, int(fy2 * f64(img.height)))
		for col in 0 .. cell_w {
			fx := f64(col) / f64(cell_w)
			tx := math.min(img.width - 1, int(fx * f64(img.width)))
			top := img.pixels[ty * img.width + tx]
			bottom := img.pixels[by * img.width + tx]
			if top == -1 && bottom == -1 {
				continue
			}
			if top == -1 {
				screen.put(x + col, area.y + row, `▄`, bottom, bg, 0)
			} else if bottom == -1 {
				screen.put(x + col, area.y + row, `▀`, top, bg, 0)
			} else {
				screen.put(x + col, area.y + row, `▀`, top, bottom, 0)
			}
		}
	}
	if !preview && alt != '' && area.h > 1 {
		width := vtk.text_width(alt)
		screen.text(area.x + math.max(0, (area.w - width) / 2), area.y + area.h - 1,
			truncate_plain(alt, area.w), slide_dim(), bg, 0)
	}
}

fn table_cells(line string) []string {
	mut text := line.trim_space()
	if text.starts_with('|') {
		text = text[1..]
	}
	if text.ends_with('|') {
		text = text[..text.len - 1]
	}
	return text.split('|').map(it.trim_space())
}

fn table_separator(line string) bool {
	cells := table_cells(line)
	if cells.len == 0 {
		return false
	}
	for cell in cells {
		core := cell.trim(':')
		if core.len < 3 || !core.bytes().all(it == `-`) {
			return false
		}
	}
	return true
}

fn draw_table(mut screen vtk.Screen, area vtk.Rect, lines []string, first int, bg int, fg int, preview bool) int {
	header := table_cells(lines[first])
	mut rows := [][]string{}
	mut at := first + 2
	for at < lines.len {
		line := lines[at]
		if line.trim_space() == '' || !line.contains('|') {
			break
		}
		cells := table_cells(line)
		if cells.len == 0 {
			break
		}
		rows << cells
		at++
		if rows.len >= 24 {
			break
		}
	}
	columns := header.len
	if columns == 0 {
		return 0
	}
	mut widths := []int{len: columns, init: 1}
	for c, cell in header {
		widths[c] = math.max(widths[c], vtk.text_width(inline_plain(cell)))
	}
	for row in rows {
		for c in 0 .. math.min(columns, row.len) {
			widths[c] = math.max(widths[c], vtk.text_width(inline_plain(row[c])))
		}
	}
	available := math.max(1, area.w - columns - 1)
	mut total := 0
	for width in widths {
		total += width
	}
	if total > available {
		for c in 0 .. columns {
			widths[c] = math.max(1, widths[c] * available / total)
		}
	}
	mut y := area.y
	mut x := area.x
	for c, cell in header {
		if c == 0 {
			screen.put(x, y, `│`, slide_dim(), bg, 0)
		}
		x++
		runs := inline_runs(cell)
		draw_runs(mut screen, x, y, widths[c], runs, fg, bg, vtk.bold)
		x += widths[c]
		screen.put(x, y, `│`, slide_dim(), bg, 0)
		x++
	}
	y++
	x = area.x
	for c in 0 .. columns {
		screen.put(x, y, `┼`, slide_dim(), bg, 0)
		x++
		screen.fill(vtk.Rect{x, y, widths[c], 1}, `─`, slide_dim(), bg)
		x += widths[c]
	}
	screen.put(x, y, `┼`, slide_dim(), bg, 0)
	y++
	for row in rows {
		if y >= area.y + area.h {
			break
		}
		x = area.x
		for c in 0 .. columns {
			screen.put(x, y, `│`, slide_dim(), bg, 0)
			x++
			cell := if c < row.len { row[c] } else { '' }
			draw_runs(mut screen, x, y, widths[c], inline_runs(cell), fg, bg, 0)
			x += widths[c]
		}
		screen.put(x, y, `│`, slide_dim(), bg, 0)
		y++
	}
	if preview {
		return math.min(lines.len, at) - first
	}
	return at - first
}

fn draw_slide(mut screen vtk.Screen, area vtk.Rect, body string, options SlidePaint) {
	if area.w < 2 || area.h < 2 {
		return
	}
	old := screen.set_clip(area)
	bg := slide_background()
	fg := slide_foreground()
	frame_color := if options.selected || options.drag_target {
		slide_accent()
	} else {
		slide_dim()
	}
	screen.fill(area, ` `, fg, bg)
	if !options.presentation {
		screen.frame(area, options.selected || options.drag_target, frame_color, bg)
	}
	mut inner := vtk.Rect{area.x + 1, area.y + 1, area.w - 2, area.h - 2}
	if options.presentation {
		pad_x := math.max(2, math.min(8, inner.w / 12))
		pad_y := math.max(0, math.min(2, inner.h / 16))
		inner = vtk.Rect{inner.x + pad_x, inner.y + pad_y, math.max(1, inner.w - 2 * pad_x), math.max(1, inner.h - 2 * pad_y)}
	}
	render_slide_body(mut screen, inner, body, options, fg, bg)
	if options.presentation && options.pages > 0 {
		page := '${options.page} / ${options.pages}'
		width := vtk.text_width(page)
		screen.text(area.x + area.w - width - 2, area.y + area.h - 1, page, slide_dim(), bg, 0)
	}
	screen.restore_clip(old)
}

fn render_slide_body(mut screen vtk.Screen, area vtk.Rect, body string, options SlidePaint, fg int, bg int) {
	if area.w <= 0 || area.h <= 0 {
		return
	}
	lines := body.split_into_lines()
	bottom := area.y + area.h
	mut y := area.y
	mut i := 0
	for i < lines.len && y < bottom {
		line := lines[i]
		trim := line.trim_space()
		if trim == '' {
			y++
			i++
			continue
		}
		if trim.starts_with('```') || trim.starts_with('~~~') {
			marker := if trim.starts_with('```') { '```' } else { '~~~' }
			mut lang := trim.trim_left('`').trim_left('~').trim_space().to_lower()
			if space := lang.index(' ') {
				lang = lang[..space]
			}
			mut close := i + 1
			for close < lines.len {
				next := lines[close].trim_space()
				if next.starts_with(marker) {
					break
				}
				close++
			}
			content := if close > i + 1 { lines[i + 1..close].join('\n') } else { '' }
			if lang in ['slide', 'shapes', 'shape', 'vtk'] {
				draw_shapes(mut screen, content, area, bg, slide_accent())
			} else if lang == 'chart' {
				data := parse_chart(content)
				height := if options.preview { math.min(7, bottom - y) } else { math.min(16, bottom - y) }
				if height >= 3 {
					draw_chart(mut screen, vtk.Rect{area.x, y, area.w, height}, data, bg, fg,
						options.preview)
					y += height
				}
			} else if content != '' {
				for code in content.split_into_lines() {
					if y >= bottom {
						break
					}
					screen.fill(vtk.Rect{area.x, y, area.w, 1}, ` `, vtk.color_rgb(210, 220, 236),
						vtk.color_rgb(24, 29, 40))
					screen.text(area.x + 1, y, truncate_plain(code, math.max(1, area.w - 2)),
						vtk.color_rgb(210, 220, 236), vtk.color_rgb(24, 29, 40), 0)
					y++
				}
			}
			i = close + 1
			continue
		}
		if link := image_line(line) {
			resolved := if os.is_abs_path(link.path) || options.base_dir == '' {
				link.path
			} else {
				os.join_path(options.base_dir, link.path)
			}
			img := options.cache.get(resolved)
			height := image_height(img, area.w, math.max(1, bottom - y), options.preview)
			if height >= 1 {
				draw_image(mut screen, vtk.Rect{area.x, y, area.w, height}, link.alt, resolved,
					options.cache, bg, options.preview)
				y += height
			}
			i++
			continue
		}
		if trim.starts_with('#') {
			mut level := 0
			for level < trim.len && trim[level] == `#` {
				level++
			}
			if level <= 6 && level < trim.len && trim[level] == ` ` {
				text := trim[level + 1..]
				runs := inline_runs(text)
				width := runs_width(runs)
				x := if level == 1 {
					area.x + math.max(0, (area.w - width) / 2)
				} else {
					area.x
				}
				attr := vtk.bold | if level >= 3 { vtk.underline } else { 0 }
				draw_runs(mut screen, x, y, area.w, runs, fg, bg, attr)
				y++
				if level == 1 && options.presentation && y < bottom {
					screen.fill(vtk.Rect{area.x + area.w / 3, y, math.max(1, area.w / 3), 1},
						`─`, slide_accent(), bg)
					y++
				}
				i++
				continue
			}
		}
		if trim in ['---', '***', '___'] {
			screen.fill(vtk.Rect{area.x, y, area.w, 1}, `─`, slide_dim(), bg)
			y++
			i++
			continue
		}
		if i + 1 < lines.len && line.contains('|') && table_separator(lines[i + 1]) {
			consumed := draw_table(mut screen, vtk.Rect{area.x, y, area.w, bottom - y}, lines,
				i, bg, fg, options.preview)
			if consumed > 0 {
				y += math.min(consumed, bottom - y)
				i += math.max(1, consumed)
				continue
			}
		}
		if trim.starts_with('> ') || trim == '>' {
			text := trim[1..].trim_space()
			prefix := '│ '
			screen.text(area.x, y, prefix, slide_dim(), bg, 0)
			for wrapped in wrap_text(text, math.max(1, area.w - 2)) {
				if y >= bottom {
					break
				}
				draw_runs(mut screen, area.x + 2, y, area.w - 2, inline_runs(wrapped),
					slide_dim(), bg, vtk.italic)
				y++
			}
			i++
			continue
		}
		if trim.starts_with('- ') || trim.starts_with('* ') || trim.starts_with('+ ') {
			text := trim[2..]
			wrapped := wrap_text(text, math.max(1, area.w - 2))
			for n, part in wrapped {
				if y >= bottom {
					break
				}
				if n == 0 {
					screen.text(area.x, y, '• ', slide_accent(), bg, 0)
				}
				draw_runs(mut screen, area.x + 2, y, area.w - 2, inline_runs(part), fg, bg, 0)
				y++
			}
			i++
			continue
		}
		if trim.starts_with('- [ ] ') || trim.starts_with('- [x] ') || trim.starts_with('- [X] ') {
			mark := if trim[3] in [u8(`x`), u8(`X`)] { '☑ ' } else { '☐ ' }
			text := trim[6..]
			for n, part in wrap_text(text, math.max(1, area.w - 2)) {
				if y >= bottom {
					break
				}
				if n == 0 {
					screen.text(area.x, y, mark, slide_accent(), bg, 0)
				}
				draw_runs(mut screen, area.x + 2, y, area.w - 2, inline_runs(part), fg, bg, 0)
				y++
			}
			i++
			continue
		}
		if trim.len > 2 && trim[0] >= `0` && trim[0] <= `9` {
			if dot := trim.index('. ') {
				if dot > 0 && dot < 4 {
					prefix := trim[..dot + 2]
					text := trim[dot + 2..]
					for n, part in wrap_text(text, math.max(1, area.w - prefix.len)) {
						if y >= bottom {
							break
						}
						if n == 0 {
							screen.text(area.x, y, prefix, slide_accent(), bg, 0)
						}
						draw_runs(mut screen, area.x + prefix.len, y, area.w - prefix.len,
							inline_runs(part), fg, bg, 0)
						y++
					}
					i++
					continue
				}
			}
		}
		for wrapped in wrap_text(trim, area.w) {
			if y >= bottom {
				break
			}
			draw_runs(mut screen, area.x, y, area.w, inline_runs(wrapped), fg, bg, 0)
			y++
		}
		i++
	}
}

fn paint_thumbnail(mut c vtk.Ctl, mut screen vtk.Screen) {
	deck := c.context[Deck]() or { return }
	index := find_slide(deck, int(c.data))
	if index < 0 {
		return
	}
	selected := index == deck.current
	paint := SlidePaint{
		preview:     true
		selected:    selected
		drag_target: deck.drag_id >= 0 && index == deck.drag_to
		cache:       &deck.images
		base_dir:    deck.base_dir()
	}
	draw_slide(mut screen, c.rect(), deck.slides[index].body, paint)
	number := ' ${index + 1} '
	bg := slide_background()
	fg := if selected { slide_warm() } else { slide_dim() }
	screen.text(c.rect().x + 2, c.rect().y, number, fg, bg, vtk.bold)
}
