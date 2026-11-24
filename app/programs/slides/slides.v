// VTK Slides: a Markdown presentation editor with slide previews, templates,
// full-screen presenting, and drawable shapes/charts/images inside Markdown.
module slides

import io
import math
import os
import strconv
import vtk
import image
import image.jpeg
import image.png

const app_name = 'VtkSlides'
const app_version = '0.1.0'
const slide_separator = '<!-- slide -->'
const slide_separator_written = '\n\n<!-- slide -->\n\n'
const notes_open = '<!-- vtk:speaker-notes -->'
const notes_close = '<!-- /vtk:speaker-notes -->'
const thumbnail_height = 12
const default_sidebar_share = 260
const chart_max_series = 6
const transition_frames = 16
const transition_frame_ms = 25
const bayer_thresholds = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]!

const font_styles = [vtk.FontStyle.none, .bold, .italic, .script, .doublestruck, .underline,
	.strikethrough, .fraktur, .bolditalic, .sansserif, .sansserifitalic, .monospace, .boldscript,
	.boldfraktur, .sansserifbold, .sansserifbolditalic, .openface, .smallcaps]

enum SlideTransition {
	none
	slide
	fade
}

enum Action {
	new_slide
	open
	save
	save_as
	quit
	clone_slide
	delete_slide
	move_up
	move_down
	toggle_sidebar
	toggle_notes
	source
	settings
	present
	present_start
	bold
	italic
	code
	strike
	font
	image
	chart_columns
	chart_bars
	chart_lines
	shape_rect
	shape_line
	shape_circle
	table
	bullet
	heading
	undo
	redo
	help
	about
}

struct Slide {
mut:
	id    int
	body  string
	notes string
}

struct SlideTemplate {
	name string
	body string
}

struct TemplatePicker {
mut:
	picked int      = -1
}

struct SettingsDialog {
mut:
	deck   &Deck @[required]
	window &vtk.Ctl @[required]
	radio  &vtk.Ctl @[required]
}

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

@[heap]
struct Deck {
mut:
	window              &vtk.Ctl @[required]
	sidebar_pane        &vtk.Ctl @[required]
	sidebar             &vtk.Ctl @[required]
	sidebar_list        &vtk.Ctl @[required]
	editor              &vtk.Ctl @[required]
	notes               &vtk.Ctl @[required]
	notes_sep           &vtk.Ctl @[required]
	status              &vtk.Ctl @[required]
	slides              []Slide
	thumbnails          []&vtk.Ctl
	path                string
	dirty               bool
	current             int
	next_id             int = 1
	source              bool
	sidebar_visible     bool = true
	notes_visible       bool = true
	transition          SlideTransition
	transition_active   bool
	transition_from     int
	transition_to       int
	transition_step     int
	transition_hook     int
	drag_id             int = -1
	drag_from           int = -1
	drag_to             int = -1
	images              ImageCache
	presentation        ?&vtk.Ctl
	presentation_index  int
}

fn min(a int, b int) int {
	return if a < b { a } else { b }
}

fn max(a int, b int) int {
	return if a > b { a } else { b }
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

fn transition_names() []string {
	return ['No transition', 'Slide', 'Fade out → in']
}

fn transition_from_int(value int) SlideTransition {
	return match value {
		1 { .slide }
		2 { .fade }
		3 { .fade }
		else { .none }
	}
}

fn transition_label(transition SlideTransition) string {
	return transition_names()[int(transition)]
}

fn prefs_file() string {
	return os.join_path(os.home_dir(), '.vtk-slides.ini')
}

fn load_prefs() SlideTransition {
	text := os.read_file(prefs_file()) or { return .none }
	for line in text.split_into_lines() {
		trim := line.trim_space()
		if trim == '' || trim.starts_with('#') {
			continue
		}
		parts := trim.split_nth('=', 2)
		if parts.len == 2 && parts[0].trim_space() == 'transition' {
			return transition_from_int(parts[1].trim_space().int())
		}
	}
	return .none
}

fn save_prefs(deck &Deck) {
	vtk.save_atomic(prefs_file(), 'transition = ${int(deck.transition)}\n') or { return }
}

fn templates() []SlideTemplate {
	return [
		SlideTemplate{'Title', '# New slide\n\nA subtitle or a short introduction.'},
		SlideTemplate{'Title + bullets', '# Topic\n\n- First point\n- Second point\n- Third point'},
		SlideTemplate{'Section', '# Section\n\nA short introduction to the next part.'},
		SlideTemplate{'Quote', '> A memorable quote goes here.\n\n— Author'},
		SlideTemplate{'Image', '# Image\n\n![Caption](image.png)'},
		SlideTemplate{'Chart', '# Chart\n\n```chart columns|Quarterly results\n|Q1|Q2|Q3|Q4\nRevenue|12|18|15|24\nPlan|10|14|18|20\n```'},
		SlideTemplate{'Shapes', '# Shapes\n\n```slide\nrect 8 12 40 34 #59adff\nline 8 78 92 78 #ffd114\ncircle 80 28 10 #79c942\n```'},
		SlideTemplate{'Blank', ''},
	]
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

fn plain_title(body string) string {
	for line in body.split_into_lines() {
		mut trim := line.trim_space()
		if trim == '' || trim.starts_with('```') || trim.starts_with('~~~') {
			continue
		}
		if trim.starts_with('#') {
			trim = trim.trim_left('#').trim_space()
		}
		title := inline_plain(trim).trim_space()
		if title != '' {
			return if title.runes().len > 48 { title.runes()[..48].string() + '…' } else { title }
		}
	}
	return 'Untitled slide'
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
	return vtk.clamp(int(value * f64(total) / 100), 0, max(0, total - 1))
}

fn percent_size(text string, total int) int {
	value := strconv.atof64(text.trim_space()) or { 0 }
	return vtk.clamp(int(value * f64(total) / 100), 1, max(1, total))
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
		radius := percent_size(fields[3], min(area.w, area.h * 2))
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
		max_values = max(max_values, values.len)
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
		draw_runs(mut screen, area.x + max(0, (area.w - width) / 2), y, area.w, runs, fg,
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
			label_width = max(label_width, vtk.text_width(inline_plain(label)))
		}
		label_width = min(label_width, max(3, area.w / 3))
		plot_x := area.x + label_width + 1
		plot_w := max(1, area.x + area.w - plot_x)
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
					screen.fill(vtk.Rect{plot_x, row, min(length, plot_w), 1}, `█`,
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
	plot := vtk.Rect{area.x, y, area.w, max(1, bottom - y + 1 - label_rows)}
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
				x := plot.x + i * max(1, plot.w - 1) / (data.labels.len - 1)
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
		group := max(1, plot.w / data.labels.len)
		bar := max(1, (group - 1) / max(1, data.series.len))
		for i, _ in data.labels {
			gx := plot.x + i * group
			for s, series in data.series {
				if i >= series.len {
					continue
				}
				py := chart_y(series[i], low, high, plot)
				x := gx + s * bar
				top := min(py, baseline)
				height := max(1, absi(baseline - py) + 1)
				if x < plot.x + plot.w {
					screen.fill(vtk.Rect{x, top, min(bar, plot.x + plot.w - x), height}, `█`,
						chart_color(s), bg)
				}
			}
		}
	}
	if label_rows > 0 {
		mut used := 0
		for i, label in data.labels {
			x := if data.labels.len > 1 {
				plot.x + i * max(1, plot.w - 1) / (data.labels.len - 1)
			} else {
				plot.x
			}
			text := truncate_plain(label, max(2, plot.w / max(1, data.labels.len)))
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

fn absi(value int) int {
	return if value < 0 { -value } else { value }
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
	width := max(1, int(f64(src_w) * scale))
	height := max(1, int(f64(src_h) * scale))
	mut pixels := []int{len: width * height, init: -1}
	for y in 0 .. height {
		for x in 0 .. width {
			sx := bounds.min.x + min(src_w - 1, x * src_w / width)
			sy := bounds.min.y + min(src_h - 1, y * src_h / height)
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
		return min(available, 3)
	}
	ideal := width * img.height / (img.width * 2)
	limit := if preview { min(available, 4) } else { min(available, 18) }
	return vtk.clamp(ideal, 1, max(1, limit))
}

fn draw_image(mut screen vtk.Screen, area vtk.Rect, alt string, path string, cache &ImageCache, bg int, preview bool) {
	img := cache.get(path)
	screen.fill(area, ` `, slide_foreground(), bg)
	if img.width == 0 || img.height == 0 {
		screen.frame(area, false, slide_dim(), bg)
		text := if alt == '' { '[image]' } else { '[${alt}]' }
		width := vtk.text_width(text)
		screen.text(area.x + max(0, (area.w - width) / 2), area.y + area.h / 2,
			truncate_plain(text, max(1, area.w - 2)), slide_dim(), bg, 0)
		return
	}
	cell_w := min(area.w, max(1, area.h * 2 * img.width / img.height))
	x := area.x + max(0, (area.w - cell_w) / 2)
	for row in 0 .. area.h {
		fy := f64(row * 2) / f64(max(1, area.h * 2))
		fy2 := f64(row * 2 + 1) / f64(max(1, area.h * 2))
		ty := min(img.height - 1, int(fy * f64(img.height)))
		by := min(img.height - 1, int(fy2 * f64(img.height)))
		for col in 0 .. cell_w {
			fx := f64(col) / f64(cell_w)
			tx := min(img.width - 1, int(fx * f64(img.width)))
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
		screen.text(area.x + max(0, (area.w - width) / 2), area.y + area.h - 1,
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
		widths[c] = max(widths[c], vtk.text_width(inline_plain(cell)))
	}
	for row in rows {
		for c in 0 .. min(columns, row.len) {
			widths[c] = max(widths[c], vtk.text_width(inline_plain(row[c])))
		}
	}
	available := max(1, area.w - columns - 1)
	mut total := 0
	for width in widths {
		total += width
	}
	if total > available {
		for c in 0 .. columns {
			widths[c] = max(1, widths[c] * available / total)
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
		return min(lines.len, at) - first
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
		pad_x := max(2, min(8, inner.w / 12))
		pad_y := max(0, min(2, inner.h / 16))
		inner = vtk.Rect{inner.x + pad_x, inner.y + pad_y, max(1, inner.w - 2 * pad_x), max(1, inner.h - 2 * pad_y)}
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
				height := if options.preview { min(7, bottom - y) } else { min(16, bottom - y) }
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
					screen.text(area.x + 1, y, truncate_plain(code, max(1, area.w - 2)),
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
			height := image_height(img, area.w, max(1, bottom - y), options.preview)
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
					area.x + max(0, (area.w - width) / 2)
				} else {
					area.x
				}
				attr := vtk.bold | if level >= 3 { vtk.underline } else { 0 }
				draw_runs(mut screen, x, y, area.w, runs, fg, bg, attr)
				y++
				if level == 1 && options.presentation && y < bottom {
					screen.fill(vtk.Rect{area.x + area.w / 3, y, max(1, area.w / 3), 1},
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
				y += min(consumed, bottom - y)
				i += max(1, consumed)
				continue
			}
		}
		if trim.starts_with('> ') || trim == '>' {
			text := trim[1..].trim_space()
			prefix := '│ '
			screen.text(area.x, y, prefix, slide_dim(), bg, 0)
			for wrapped in wrap_text(text, max(1, area.w - 2)) {
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
			wrapped := wrap_text(text, max(1, area.w - 2))
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
			for n, part in wrap_text(text, max(1, area.w - 2)) {
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
					for n, part in wrap_text(text, max(1, area.w - prefix.len)) {
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

fn find_slide(deck &Deck, id int) int {
	for i, slide in deck.slides {
		if slide.id == id {
			return i
		}
	}
	return -1
}

fn (deck &Deck) text() string {
	mut parts := []string{cap: deck.slides.len}
	for slide in deck.slides {
		body := slide.body.trim('\n')
		notes := slide.notes.trim('\n')
		if notes == '' {
			parts << body
		} else {
			parts << '${body}\n\n${notes_open}\n${notes}\n${notes_close}'
		}
	}
	return parts.join(slide_separator_written) + '\n'
}

fn split_notes(part string) (string, string) {
	lines := part.split_into_lines()
	mut open := -1
	mut close := -1
	for i, line in lines {
		trim := line.trim_space()
		if trim == notes_open && open < 0 {
			open = i
		} else if trim == notes_close && open >= 0 {
			close = i
			break
		}
	}
	if open < 0 || close < open {
		return part.trim('\n'), ''
	}
	mut body := lines[..open].clone()
	body << lines[close + 1..]
	return body.join('\n').trim('\n'), lines[open + 1..close].join('\n').trim('\n')
}

fn parse_deck(text string) []Slide {
	normalized := text.replace('\r\n', '\n')
	mut parts := normalized.split(slide_separator)
	if parts.len > 1 && parts.last().trim_space() == '' {
		parts.delete_last()
	}
	if parts.len == 0 {
		parts << ''
	}
	mut slides := []Slide{cap: parts.len}
	for i, part in parts {
		body, notes := split_notes(part)
		slides << Slide{
			id:    i + 1
			body:  body
			notes: notes
		}
	}
	if slides.len == 0 {
		slides << Slide{
			id: 1
		}
	}
	return slides
}

fn demo_deck() []Slide {
	mut slides := []Slide{}
	slides << Slide{
		id:    1
		body:  '# VTK Slides\n\nA terminal presentation tool built with **VTK**.\n\nPress **F5** to present.'
		notes: 'Welcome. These notes stay in the speaker view and are hidden while presenting.'
	}
	slides << Slide{
		id:    2
		body:  '# Features\n\n- Edit each slide in **Markdown**\n- Reorder, clone and delete slides\n- Draw rectangles and lines with colors\n- Insert images and charts\n\n```slide\nrect 62 10 30 30 #59adff\nline 8 84 92 84 #ffd114\n```'
		notes: 'Mention that shapes accept #rrggbb colors, and that charts and images also live inside Markdown.'
	}
	slides << Slide{
		id:    3
		body:  '# Quarterly results\n\n```chart columns|Revenue\n|Q1|Q2|Q3|Q4\nRevenue|12|18|15|24\nPlan|10|14|18|20\n```'
		notes: 'Walk through the two series. The chart is rendered from a fenced chart block.'
	}
	return slides
}

fn (deck &Deck) base_dir() string {
	return if deck.path == '' { os.getwd() } else { os.dir(deck.path) }
}

fn (mut deck Deck) select(index int, mut app vtk.App) {
	if deck.slides.len == 0 {
		return
	}
	deck.current = vtk.clamp(index, 0, deck.slides.len - 1)
	deck.editor.set_text(deck.slides[deck.current].body)
	deck.editor.cursor = 0
	deck.editor.anchor = -1
	deck.editor.top = 0
	deck.editor.markdown_mode(if deck.source { .source } else { .edit })
	deck.notes.set_text(deck.slides[deck.current].notes)
	deck.notes.cursor = 0
	deck.notes.anchor = -1
	deck.notes.top = 0
	deck.refresh()
	app.set_focus(deck.editor)
	app.invalidate()
}

fn (mut deck Deck) refresh() {
	name := if deck.path == '' { '[Untitled]' } else { os.file_name(deck.path) }
	deck.window.set_text('${name}${if deck.dirty { ' *' } else { '' }} - VTK Slides')
	if deck.current < 0 || deck.current >= deck.slides.len {
		deck.status.set_text('No slides')
		return
	}
	slide := deck.slides[deck.current]
	mode := if deck.source { 'Source' } else { 'Edit' }
	sidebar := if deck.sidebar_visible { 'Sidebar' } else { 'No sidebar' }
	notes := if slide.notes.trim_space() == '' { '' } else { ' · notes' }
	notes_view := if deck.notes_visible { 'Notes' } else { 'No notes' }
	deck.status.set_text('Slide ${deck.current + 1}/${deck.slides.len} · ${plain_title(slide.body)} · ${slide.body.len} bytes${notes} · ${mode} · ${sidebar} · ${notes_view} · F5 present')
}

fn (mut deck Deck) rebuild_thumbnails(mut app vtk.App) {
	for mut thumb in deck.thumbnails {
		app.destroy_ctl(mut thumb)
	}
	deck.thumbnails = []
	deck.sidebar_list.clear()
	for slide in deck.slides {
		mut thumb := vtk.canvas(20, thumbnail_height, paint_thumbnail)
		thumb.set_context(&deck)
		thumb.data = i64(slide.id)
		thumb.min_w = 12
		thumb.min_h = thumbnail_height
		thumb.focusable = false
		thumb.mousefn = thumbnail_mouse
		deck.sidebar_list.add(mut thumb)
		deck.thumbnails << thumb
	}
	deck.sidebar_list.measure()
	app.invalidate()
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

fn thumbnail_mouse(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut deck := c.context[Deck]() or { return false }
	if e.button != .left {
		return false
	}
	index := find_slide(deck, int(c.data))
	if index < 0 {
		return false
	}
	if e.pressed && !e.motion {
		deck.drag_id = int(c.data)
		deck.drag_from = index
		deck.drag_to = index
		deck.select(index, mut app)
		return true
	}
	if e.pressed && e.motion && deck.drag_id >= 0 {
		for thumb in deck.thumbnails {
			if thumb.rect().contains(e.x, e.y) {
				deck.drag_to = find_slide(deck, int(thumb.data))
				break
			}
		}
		app.invalidate()
		return true
	}
	if !e.pressed {
		from := deck.drag_from
		to := deck.drag_to
		deck.drag_id = -1
		deck.drag_from = -1
		deck.drag_to = -1
		if from >= 0 && to >= 0 && from != to && from < deck.slides.len {
			slide := deck.slides[from]
			deck.slides.delete(from)
			deck.slides.insert(vtk.clamp(to, 0, deck.slides.len), slide)
			deck.current = vtk.clamp(to, 0, deck.slides.len - 1)
			deck.dirty = true
			deck.rebuild_thumbnails(mut app)
			deck.refresh()
		}
		app.invalidate()
		return true
	}
	return false
}

fn notes_changed(mut c vtk.Ctl, mut app vtk.App) {
	mut deck := c.context[Deck]() or { return }
	if deck.current >= 0 && deck.current < deck.slides.len {
		deck.slides[deck.current].notes = c.text
		deck.dirty = true
		deck.refresh()
	}
	app.invalidate()
}

fn editor_changed(mut c vtk.Ctl, mut app vtk.App) {
	mut deck := c.context[Deck]() or { return }
	if deck.current >= 0 && deck.current < deck.slides.len {
		deck.slides[deck.current].body = c.text
		deck.dirty = true
		deck.refresh()
		for thumb in deck.thumbnails {
			thumb.invalidate()
		}
	}
	app.invalidate()
}

fn closing(mut w vtk.Ctl, mut app vtk.App) bool {
	mut deck := w.context[Deck]() or { return true }
	if !deck.dirty {
		return true
	}
	choice := app.choice_for(&w, 'Unsaved slides', ['Save', 'Discard', 'Cancel'], 3)
	if choice == 0 {
		return deck.save(false, mut app)
	}
	return choice == 1
}

fn (mut deck Deck) save(save_as bool, mut app vtk.App) bool {
	mut path := deck.path
	if path == '' || save_as {
		path = app.prompt_for(deck.window, 'Save slides', 'Slides path (.md):',
			if path == '' { 'slides.md' } else { path }) or { return false }
	}
	if path == '' {
		return false
	}
	if path != deck.path && os.exists(path) {
		if !app.confirm_for(deck.window, 'Replace file', 'Replace ${path}?') {
			return false
		}
	}
	vtk.save_atomic(path, deck.text()) or {
		app.notify(err.msg(), 3000)
		return false
	}
	deck.path = path
	deck.dirty = false
	deck.refresh()
	app.notify('Saved ${path}', 1500)
	return true
}

fn (mut deck Deck) open(mut app vtk.App) {
	if deck.dirty && !app.confirm_for(deck.window, 'Unsaved slides',
		'Discard unsaved changes and open another deck?') {
		return
	}
	path := app.file_pick_for(deck.window, if deck.path == '' {
		os.getwd()
	} else {
		os.dir(deck.path)
	}) or { return }
	text := os.read_file(path) or {
		app.notify(err.msg(), 3000)
		return
	}
	deck.slides = parse_deck(text)
	deck.next_id = deck.slides.len + 1
	for slide in deck.slides {
		deck.next_id = max(deck.next_id, slide.id + 1)
	}
	deck.path = path
	deck.dirty = false
	deck.current = 0
	deck.rebuild_thumbnails(mut app)
	deck.select(0, mut app)
	app.notify('Opened ${path}', 1500)
}

fn (mut deck Deck) insert_slide(body string, notes string, at int, mut app vtk.App) {
	index := vtk.clamp(at, 0, deck.slides.len)
	deck.slides.insert(index, Slide{
		id:    deck.next_id
		body:  body
		notes: notes
	})
	deck.next_id++
	deck.current = index
	deck.dirty = true
	deck.rebuild_thumbnails(mut app)
	deck.select(index, mut app)
}

fn (mut deck Deck) clone_slide(mut app vtk.App) {
	if deck.current < 0 || deck.current >= deck.slides.len {
		return
	}
	slide := deck.slides[deck.current]
	deck.insert_slide(slide.body, slide.notes, deck.current + 1, mut app)
	app.notify('Cloned slide', 1200)
}

fn (mut deck Deck) delete_slide(mut app vtk.App) {
	if deck.slides.len <= 1 {
		app.notify('A deck needs at least one slide', 1800)
		return
	}
	if deck.current < 0 || deck.current >= deck.slides.len {
		return
	}
	if !app.confirm_for(deck.window, 'Delete slide', 'Delete slide ${deck.current + 1}?') {
		return
	}
	deck.slides.delete(deck.current)
	deck.current = vtk.clamp(deck.current, 0, deck.slides.len - 1)
	deck.dirty = true
	deck.rebuild_thumbnails(mut app)
	deck.select(deck.current, mut app)
}

fn (mut deck Deck) move(delta int, mut app vtk.App) {
	target := deck.current + delta
	if deck.current < 0 || target < 0 || target >= deck.slides.len {
		return
	}
	slide := deck.slides[deck.current]
	deck.slides.delete(deck.current)
	deck.slides.insert(target, slide)
	deck.current = target
	deck.dirty = true
	deck.rebuild_thumbnails(mut app)
	deck.refresh()
	app.invalidate()
}

fn insert_text(mut deck Deck, text string, mut app vtk.App) {
	if deck.editor.readonly {
		app.notify('Switch to an editable mode first', 1800)
		return
	}
	deck.editor.replace_selection(text)
	deck.editor.invalidate()
	app.set_focus(deck.editor)
	app.invalidate()
}

fn insert_block(mut deck Deck, text string, mut app vtk.App) {
	a, _ := deck.editor.selection()
	before := if a == 0 { '' } else { deck.editor.text[a - 1..a] }
	prefix := if before == '' || before == '\n' { '' } else { '\n' }
	insert_text(mut deck, prefix + text + '\n', mut app)
}

fn wrap_selection(mut deck Deck, prefix string, suffix string, mut app vtk.App) {
	a, b := deck.editor.selection()
	if a == b {
		app.notify('Select text first', 1500)
		app.set_focus(deck.editor)
		return
	}
	text := deck.editor.text[a..b]
	deck.editor.replace_range(a, b, prefix + text + suffix)
	deck.editor.cursor = a + prefix.len + text.len
	app.set_focus(deck.editor)
	app.invalidate()
}

fn choose_font(mut deck Deck, mut app vtk.App) {
	a, b := deck.editor.selection()
	if a == b {
		app.notify('Select text to restyle', 1600)
		app.set_focus(deck.editor)
		return
	}
	mut names := []string{cap: font_styles.len}
	for style in font_styles {
		names << vtk.font_convert(style.str(), style)
	}
	at := app.choice_for(deck.window, 'Unicode text style', names, 2)
	if at < 0 {
		return
	}
	style := font_styles[at]
	if style == .underline {
		wrap_selection(mut deck, '<u>', '</u>', mut app)
	} else if style == .strikethrough {
		wrap_selection(mut deck, '~~', '~~', mut app)
	} else {
		text := deck.editor.text[a..b]
		deck.editor.replace_range(a, b, vtk.font_convert(text, style))
		deck.editor.cursor = a + vtk.font_convert(text, style).len
		app.set_focus(deck.editor)
		app.invalidate()
	}
}

fn stored_image_path(deck &Deck, path string) string {
	if deck.path == '' {
		return path
	}
	directory := os.dir(os.abs_path(deck.path))
	absolute := os.abs_path(path)
	prefix := directory + os.path_separator
	if absolute.starts_with(prefix) {
		return absolute[prefix.len..]
	}
	return path
}

fn insert_image(mut deck Deck, mut app vtk.App) {
	directory := if deck.path == '' { os.getwd() } else { os.dir(deck.path) }
	path := app.file_pick_for(deck.window, directory) or { return }
	alt := app.prompt_for(deck.window, 'Image caption', 'Caption (optional):', '') or { '' }
	stored := stored_image_path(deck, path)
	insert_block(mut deck, '![${alt}](${stored})', mut app)
}

fn insert_chart(mut deck Deck, kind string, mut app vtk.App) {
	block := '```chart ${kind}|Chart title\n|A|B|C\nSeries 1|10|20|15\nSeries 2|8|14|18\n```'
	insert_block(mut deck, block, mut app)
}

fn insert_shape(mut deck Deck, kind string, mut app vtk.App) {
	label, initial := match kind {
		'rect' { 'Rectangle: x y width height (percent)', '10 10 40 30' }
		'line' { 'Line: x1 y1 x2 y2 (percent)', '10 80 90 80' }
		else { 'Circle: center x, center y, radius (percent)', '75 25 10' }
	}
	spec := app.prompt_for(deck.window, 'Insert shape', '${label}:', initial) or { return }
	fields := spec.trim_space().fields()
	if fields.len < 3 {
		app.notify('Enter shape coordinates', 1800)
		return
	}
	rgb := app.color_pick(deck.window, 'Shape color', 0x59adff) or { return }
	color := '#${rgb:06x}'
	directive := match kind {
		'rect' {
			if fields.len < 4 { return }
			'rect ${fields[0]} ${fields[1]} ${fields[2]} ${fields[3]} ${color}'
		}
		'line' {
			if fields.len < 4 { return }
			'line ${fields[0]} ${fields[1]} ${fields[2]} ${fields[3]} ${color}'
		}
		else { 'circle ${fields[0]} ${fields[1]} ${fields[2]} ${color}' }
	}
	insert_block(mut deck, '```slide\n${directive}\n```', mut app)
}

fn new_slide_dialog(mut deck Deck, mut app vtk.App) {
	picker := &TemplatePicker{}
	mut body := vtk.box(true)
	mut heading := vtk.label('Choose a template for the new slide:')
	body.add(mut heading)
	mut grid := vtk.grid()
	items := templates()
	for i, item in items {
		mut button := vtk.button(item.name)
		button.set_context(picker)
		button.data = i64(i)
		button.changed = template_pick
		button.col = i % 2
		button.row = i / 2
		grid.add(mut button)
	}
	body.add(mut grid)
	mut row := vtk.button_bar()
	mut cancel := vtk.button('Cancel')
	cancel.changed = template_cancel
	row.add(mut cancel)
	body.add(mut row)
	mut window := app.dialog('New slide', mut body)
	app.modal_for(mut window, deck.window)
	picked := picker.picked
	app.destroy_ctl(mut window)
	if picked >= 0 && picked < items.len {
		deck.insert_slide(items[picked].body, '', deck.current + 1, mut app)
	}
}

fn template_pick(mut c vtk.Ctl, mut app vtk.App) {
	mut picker := c.context[TemplatePicker]() or { return }
	picker.picked = int(c.data)
	mut window := c.owner_window() or { return }
	app.close(mut window)
}

fn template_cancel(mut c vtk.Ctl, mut app vtk.App) {
	mut window := c.owner_window() or { return }
	app.close(mut window)
}

fn settings_ok(mut c vtk.Ctl, mut app vtk.App) {
	mut dialog := c.context[SettingsDialog]() or { return }
	dialog.deck.transition = transition_from_int(dialog.radio.value)
	save_prefs(dialog.deck)
	dialog.deck.refresh()
	app.close(mut dialog.window)
}

fn settings_cancel(mut c vtk.Ctl, mut app vtk.App) {
	mut dialog := c.context[SettingsDialog]() or { return }
	app.close(mut dialog.window)
}

fn settings_dialog(mut deck Deck, mut app vtk.App) {
	mut body := vtk.box(true)
	mut heading := vtk.label('Presentation transition')
	body.add(mut heading)
	mut radio := vtk.radio()
	for name in transition_names() {
		radio.add_item(name)
	}
	radio.value = int(deck.transition)
	body.add(mut radio)
	mut hint := vtk.label('Current: ${transition_label(deck.transition)}. Used when moving between slides in presentation mode.')
	body.add(mut hint)
	mut row := vtk.button_bar()
	mut ok := vtk.button(' OK ')
	mut cancel := vtk.button('Cancel')
	row.add(mut ok)
	row.add(mut cancel)
	body.add(mut row)
	mut window := app.dialog('Slides settings', mut body)
	dialog := &SettingsDialog{
		deck:   &deck
		window: window
		radio:  radio
	}
	ok.set_context(dialog)
	ok.changed = settings_ok
	cancel.set_context(dialog)
	cancel.changed = settings_cancel
	app.set_default_button(mut window, ok)
	app.set_focus(radio)
	app.modal_for(mut window, deck.window)
	app.destroy_ctl(mut window)
}

fn (mut deck Deck) toggle_sidebar(mut app vtk.App) {
	deck.sidebar_visible = !deck.sidebar_visible
	deck.sidebar_pane.hidden = !deck.sidebar_visible
	if !deck.sidebar_visible {
		app.set_focus(deck.editor)
	}
	deck.refresh()
	app.invalidate()
}

fn (mut deck Deck) toggle_notes(mut app vtk.App) {
	deck.notes_visible = !deck.notes_visible
	deck.notes_sep.hidden = !deck.notes_visible
	deck.notes.hidden = !deck.notes_visible
	if !deck.notes_visible {
		app.set_focus(deck.editor)
	}
	deck.refresh()
	app.invalidate()
}

fn (mut deck Deck) toggle_source(mut app vtk.App) {
	deck.source = !deck.source
	deck.editor.markdown_mode(if deck.source { .source } else { .edit })
	deck.refresh()
	app.set_focus(deck.editor)
	app.invalidate()
}

fn present_slide(mut deck Deck, start int, mut app vtk.App) {
	if deck.slides.len == 0 {
		return
	}
	deck.clear_transition(mut app)
	deck.presentation_index = vtk.clamp(start, 0, deck.slides.len - 1)
	width, height := app.size()
	mut window := app.window('VTK Slides - presentation', width, height - 1)
	window.controls = vtk.window_close
	window.dismissable = true
	window.set_context(&deck)
	window.keyfn = presentation_key
	window.closing = presentation_closing
	mut canvas := vtk.canvas(width, height, paint_presentation)
	canvas.expand = true
	canvas.focusable = true
	canvas.set_context(&deck)
	canvas.keyfn = presentation_key
	window.add(mut canvas)
	deck.presentation = window
	app.maximize(mut window)
	app.set_focus(canvas)
	app.invalidate()
}

fn presentation_closing(mut w vtk.Ctl, mut app vtk.App) bool {
	mut deck := w.context[Deck]() or { return true }
	deck.clear_transition(mut app)
	window := deck.presentation or {
		app.set_focus(deck.editor)
		return true
	}
	if window == &w {
		deck.presentation = none

	}
	app.set_focus(deck.editor)
	return true
}

fn (deck &Deck) presentation_paint(index int) SlidePaint {
	return SlidePaint{
		presentation: true
		cache:        &deck.images
		base_dir:     deck.base_dir()
		page:         index + 1
		pages:        deck.slides.len
	}
}

fn paint_presentation(mut c vtk.Ctl, mut screen vtk.Screen) {
	deck := c.context[Deck]() or { return }
	if deck.transition_active {
		deck.draw_transition(mut screen, c.rect())
		return
	}
	if deck.presentation_index < 0 || deck.presentation_index >= deck.slides.len {
		return
	}
	draw_slide(mut screen, c.rect(), deck.slides[deck.presentation_index].body,
		deck.presentation_paint(deck.presentation_index))
}

fn fade_mask(mut screen vtk.Screen, area vtk.Rect, coverage f64, bg int) {
	if coverage <= 0 {
		return
	}
	steps := f64(vtk.clamp(int(coverage * 16), 0, 16)) / 16
	for y in area.y .. area.y + area.h {
		for x in area.x .. area.x + area.w {
			threshold := f64(bayer_thresholds[(y & 3) * 4 + (x & 3)]) / 16
			if threshold < steps {
				screen.put(x, y, ` `, slide_foreground(), bg, 0)
			}
		}
	}
}

fn (deck &Deck) draw_transition(mut screen vtk.Screen, area vtk.Rect) {
	if deck.transition_from < 0 || deck.transition_from >= deck.slides.len
		|| deck.transition_to < 0 || deck.transition_to >= deck.slides.len {
		return
	}
	bg := slide_background()
	screen.fill(area, ` `, slide_foreground(), bg)
	progress := f64(deck.transition_step) / f64(transition_frames)
	from_paint := deck.presentation_paint(deck.transition_from)
	to_paint := deck.presentation_paint(deck.transition_to)
	match deck.transition {
		.slide {
			offset := int(f64(area.w) * progress)
			mut from := vtk.Rect{}
			mut to := vtk.Rect{}
			if deck.transition_to > deck.transition_from {
				// Next: the old slide exits left and the new one enters from the right.
				from = vtk.Rect{area.x - offset, area.y, area.w, area.h}
				to = vtk.Rect{area.x + area.w - offset, area.y, area.w, area.h}
			} else {
				// Previous: the old slide exits right and the new one enters from the left.
				from = vtk.Rect{area.x + offset, area.y, area.w, area.h}
				to = vtk.Rect{area.x - area.w + offset, area.y, area.w, area.h}
			}
			draw_slide(mut screen, to, deck.slides[deck.transition_to].body, to_paint)
			draw_slide(mut screen, from, deck.slides[deck.transition_from].body, from_paint)
		}
		.fade {
			if progress < 0.5 {
				draw_slide(mut screen, area, deck.slides[deck.transition_from].body, from_paint)
				fade_mask(mut screen, area, progress * 2, bg)
			} else {
				draw_slide(mut screen, area, deck.slides[deck.transition_to].body, to_paint)
				fade_mask(mut screen, area, (1 - progress) * 2, bg)
			}
		}
		.none {
			draw_slide(mut screen, area, deck.slides[deck.transition_to].body, to_paint)
		}
	}
}

fn (mut deck Deck) clear_transition(mut app vtk.App) {
	if deck.transition_hook > 0 {
		app.cancel_hook(deck.transition_hook)
		deck.transition_hook = 0
	}
	deck.transition_active = false
	deck.transition_step = 0
}

fn (mut deck Deck) start_transition(target int, mut app vtk.App) {
	deck.clear_transition(mut app)
	if deck.transition == .none || target == deck.presentation_index {
		deck.presentation_index = target
		app.invalidate()
		return
	}
	deck.transition_from = deck.presentation_index
	deck.transition_to = target
	deck.transition_active = true
	deck.transition_hook = app.every(transition_frame_ms, fn [mut deck] (mut app vtk.App) {
		deck.tick_transition(mut app)
	})
	app.invalidate()
}

fn (mut deck Deck) tick_transition(mut app vtk.App) {
	if !deck.transition_active || deck.presentation == none {
		deck.clear_transition(mut app)
		return
	}
	deck.transition_step++
	if deck.transition_step >= transition_frames {
		deck.finish_transition(mut app)
		return
	}
	app.invalidate()
}

fn (mut deck Deck) finish_transition(mut app vtk.App) {
	if !deck.transition_active {
		return
	}
	deck.presentation_index = deck.transition_to
	deck.clear_transition(mut app)
	app.invalidate()
}

fn (mut deck Deck) go_to(index int, mut app vtk.App) {
	if deck.slides.len == 0 {
		return
	}
	if deck.transition_active {
		deck.finish_transition(mut app)
	}
	target := vtk.clamp(index, 0, deck.slides.len - 1)
	if target == deck.presentation_index {
		return
	}
	if deck.transition == .none {
		deck.presentation_index = target
		app.invalidate()
	} else {
		deck.start_transition(target, mut app)
	}
}

fn presentation_key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut deck := c.context[Deck]() or { return false }
	if e.key == int(vtk.Key.escape) || (e.key == `q` && !e.ctrl) {
		deck.stop_presentation(mut app)
		return true
	}
	last := deck.slides.len - 1
	if deck.transition_active
		&& e.key in [int(vtk.Key.right), int(vtk.Key.down), int(vtk.Key.page_down), int(vtk.Key.space),
			int(vtk.Key.enter), int(vtk.Key.left), int(vtk.Key.up), int(vtk.Key.page_up),
			int(vtk.Key.backspace), int(vtk.Key.home), int(vtk.Key.end)] {
		deck.finish_transition(mut app)
		return true
	}
	if e.key in [int(vtk.Key.right), int(vtk.Key.down), int(vtk.Key.page_down), int(vtk.Key.space),
		int(vtk.Key.enter)] {
		deck.go_to(deck.presentation_index + 1, mut app)
		return true
	}
	if e.key in [int(vtk.Key.left), int(vtk.Key.up), int(vtk.Key.page_up), int(vtk.Key.backspace)] {
		deck.go_to(deck.presentation_index - 1, mut app)
		return true
	}
	if e.key == int(vtk.Key.home) {
		deck.go_to(0, mut app)
		return true
	}
	if e.key == int(vtk.Key.end) {
		deck.go_to(last, mut app)
		return true
	}
	return true
}

fn (mut deck Deck) stop_presentation(mut app vtk.App) {
	mut window := deck.presentation or { return }
	deck.clear_transition(mut app)
	deck.presentation = none

	app.destroy_ctl(mut window)
	app.set_focus(deck.editor)
}

fn window_key(mut w vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut deck := w.context[Deck]() or { return false }
	if e.key == int(vtk.Key.f5) {
		deck.action(if e.shift { .present_start } else { .present }, mut app)
		return true
	}
	if e.key == int(vtk.Key.f9) {
		deck.action(.toggle_sidebar, mut app)
		return true
	}
	if !e.ctrl || e.alt {
		return false
	}
	action := match e.key {
		`n` {
			if e.shift { Action.toggle_notes } else { Action.new_slide }
		}
		`o` { Action.open }
		`s` {
			if e.shift { Action.save_as } else { Action.save }
		}
		`q` { Action.quit }
		`d` {
			if e.shift { Action.delete_slide } else { Action.clone_slide }
		}
		`e` { Action.source }
		`,` { Action.settings }
		else { return false }
	}
	deck.action(action, mut app)
	return true
}

fn editor_key(mut c vtk.Ctl, e vtk.Event, mut app vtk.App) bool {
	mut deck := c.context[Deck]() or { return false }
	if e.key == int(vtk.Key.f5) {
		deck.action(if e.shift { .present_start } else { .present }, mut app)
		return true
	}
	if e.key == int(vtk.Key.f9) {
		deck.action(.toggle_sidebar, mut app)
		return true
	}
	if !e.ctrl || e.alt {
		return false
	}
	action := match e.key {
		`n` {
			if e.shift { Action.toggle_notes } else { Action.new_slide }
		}
		`o` { Action.open }
		`s` {
			if e.shift { Action.save_as } else { Action.save }
		}
		`q` { Action.quit }
		`d` {
			if e.shift { Action.delete_slide } else { Action.clone_slide }
		}
		`b` { Action.bold }
		`i` { Action.italic }
		`k` { Action.code }
		`e` { Action.source }
		`,` { Action.settings }
		`z` { Action.undo }
		`y` { Action.redo }
		else { return false }
	}
	deck.action(action, mut app)
	return true
}

fn menu_item(mut menu vtk.Ctl, deck &Deck, title string, action Action) {
	mut item := menu.menu_item(title, deck_action)
	item.set_context(deck)
	item.data = i64(action)
}

fn add_action_button(mut parent vtk.Ctl, deck &Deck, title string, action Action) {
	mut button := vtk.toolbutton(title)
	button.set_context(deck)
	button.data = i64(action)
	button.changed = deck_action
	parent.add(mut button)
}

fn deck_action(mut c vtk.Ctl, mut app vtk.App) {
	mut deck := c.context[Deck]() or { return }
	cmd := Action.from(c.data) or { return }
	deck.action(cmd, mut app)
}

fn (mut deck Deck) action(action Action, mut app vtk.App) {
	match action {
		.new_slide { new_slide_dialog(mut deck, mut app) }
		.open { deck.open(mut app) }
		.save { deck.save(false, mut app) }
		.save_as { deck.save(true, mut app) }
		.quit {
			app.close(mut deck.window)
			return
		}
		.clone_slide { deck.clone_slide(mut app) }
		.delete_slide { deck.delete_slide(mut app) }
		.move_up { deck.move(-1, mut app) }
		.move_down { deck.move(1, mut app) }
		.toggle_sidebar { deck.toggle_sidebar(mut app) }
		.toggle_notes { deck.toggle_notes(mut app) }
		.source { deck.toggle_source(mut app) }
		.settings { settings_dialog(mut deck, mut app) }
		.present { present_slide(mut deck, deck.current, mut app) }
		.present_start { present_slide(mut deck, 0, mut app) }
		.bold { wrap_selection(mut deck, '**', '**', mut app) }
		.italic { wrap_selection(mut deck, '*', '*', mut app) }
		.code { wrap_selection(mut deck, '`', '`', mut app) }
		.strike { wrap_selection(mut deck, '~~', '~~', mut app) }
		.font { choose_font(mut deck, mut app) }
		.image { insert_image(mut deck, mut app) }
		.chart_columns { insert_chart(mut deck, 'columns', mut app) }
		.chart_bars { insert_chart(mut deck, 'bars', mut app) }
		.chart_lines { insert_chart(mut deck, 'lines', mut app) }
		.shape_rect { insert_shape(mut deck, 'rect', mut app) }
		.shape_line { insert_shape(mut deck, 'line', mut app) }
		.shape_circle { insert_shape(mut deck, 'circle', mut app) }
		.table {
			insert_block(mut deck, '| Column | Column | Column |\n|---|---|---|\n| Cell | Cell | Cell |',
				mut app)
		}
		.bullet { insert_block(mut deck, '- New point', mut app) }
		.heading { insert_block(mut deck, '## New heading', mut app) }
		.undo {
			deck.editor.undo()
			app.invalidate()
		}
		.redo {
			deck.editor.redo()
			app.invalidate()
		}
		.about { app.about_for(deck.window, app_name, app_version) }
		.help {
			app.msgbox_for(deck.window, 'VTK Slides',
				'Edit slides as Markdown. **bold**, *italic*, `code`, lists, tables and images are rendered in previews and presentations.\n\nShape blocks:\n```slide\nrect 10 10 40 30 #59adff\nline 10 80 90 80 #ffd114\ncircle 75 25 10 #79c942\n```\n\nCoordinates are percentages of the slide. Shapes accept #rrggbb or named colors.\n\nChart blocks:\n```chart columns|Revenue\n|Q1|Q2|Q3|Q4\nRevenue|12|18|15|24\nPlan|10|14|18|20\n```\n\nImages are Markdown image links: ![caption](image.png). PNG and JPEG are decoded.\n\nDecks save as Markdown separated by <!-- slide -->. Speaker notes live below the slide editor and are saved in hidden HTML comments, so they never appear in previews or presentations. File > Settings chooses the presentation transition: none, slide (direction follows next/previous), or fade out/in. F5 presents, F9 toggles the sidebar, Ctrl-E shows source, Ctrl-Shift-N toggles notes.')
		}
	}
	deck.refresh()
	app.invalidate()
}

fn new_deck_state(window &vtk.Ctl) &Deck {
	return &Deck{
		window: window
		sidebar_pane: vtk.box(true)
		sidebar: vtk.scroll()
		sidebar_list: vtk.box(true)
		editor: vtk.markdown('')
		notes_sep: vtk.separator()
		notes: vtk.multiline('')
		status: vtk.statusbar('')
	}
}

fn new_deck(mut app vtk.App, path string) {
	transition := load_prefs()
	slides := if path == '' {
		demo_deck()
	} else {
		text := os.read_file(path) or {
			app.notify(err.msg(), 3000)
			return
		}
		parse_deck(text)
	}
	width, height := app.size()
	mut deck := new_deck_state(app.window('VTK Slides', if width > 20 { width } else { 100 },
		if height > 10 { height - 1 } else { 30 }))
	deck.slides = slides
	deck.path = path
	deck.transition = transition
	for slide in slides {
		deck.next_id = max(deck.next_id, slide.id + 1)
	}
	deck.window.set_context(deck)
	deck.window.closing = closing
	deck.window.keyfn = window_key
	mut body := vtk.box(true)
	mut toolbar := vtk.toolbar()
	add_action_button(mut toolbar, deck, '+ Slide', .new_slide)
	add_action_button(mut toolbar, deck, 'Clone', .clone_slide)
	add_action_button(mut toolbar, deck, 'Delete', .delete_slide)
	add_action_button(mut toolbar, deck, '↑', .move_up)
	add_action_button(mut toolbar, deck, '↓', .move_down)
	add_action_button(mut toolbar, deck, 'Present', .present)
	add_action_button(mut toolbar, deck, 'Sidebar', .toggle_sidebar)
	add_action_button(mut toolbar, deck, 'Notes', .toggle_notes)
	add_action_button(mut toolbar, deck, 'Source', .source)
	body.add(mut toolbar)
	mut split := vtk.split(false, default_sidebar_share)
	split.resizable = true
	deck.sidebar_pane.min_w = 14
	mut sidebar_tools := vtk.flow()
	add_action_button(mut sidebar_tools, deck, '+', .new_slide)
	add_action_button(mut sidebar_tools, deck, '⧉', .clone_slide)
	add_action_button(mut sidebar_tools, deck, '✕', .delete_slide)
	add_action_button(mut sidebar_tools, deck, '↑', .move_up)
	add_action_button(mut sidebar_tools, deck, '↓', .move_down)
	deck.sidebar_pane.add(mut sidebar_tools)
	deck.sidebar.scrollbar = true
	deck.sidebar.add(mut deck.sidebar_list)
	deck.sidebar_pane.add(mut deck.sidebar)
	split.add(mut deck.sidebar_pane)
	deck.editor.set_context(deck)
	deck.editor.changed = editor_changed
	deck.editor.keyfn = editor_key
	deck.editor.scrollbar = true
	deck.editor.line_numbers = true
	deck.editor.md.hide_status = true
	deck.editor.set_wrap_mode(.word)
	deck.editor.markdown_mode(.edit)
	mut editor_pane := vtk.box(true)
	editor_pane.add(mut deck.editor)
	editor_pane.add(mut deck.notes_sep)
	deck.notes.set_context(deck)
	deck.notes.changed = notes_changed
	deck.notes.expand = false
	deck.notes.min_h = 4
	deck.notes.scrollbar = true
	deck.notes.set_wrap_mode(.word)
	deck.notes.padding = vtk.Insets{ left: 1, right: 1 }
	editor_pane.add(mut deck.notes)
	split.add(mut editor_pane)
	body.add(mut split)
	body.add(mut deck.status)
	deck.window.add(mut body)
	mut file := deck.window.add_menu('File')
	menu_item(mut file, deck, 'New slide   Ctrl-N', .new_slide)
	menu_item(mut file, deck, 'Open...   Ctrl-O', .open)
	menu_item(mut file, deck, 'Save   Ctrl-S', .save)
	menu_item(mut file, deck, 'Save as...   Ctrl-Shift-S', .save_as)
	file.menu_separator()
	menu_item(mut file, deck, 'Settings...   Ctrl-,', .settings)
	file.menu_separator()
	menu_item(mut file, deck, 'Present   F5', .present)
	menu_item(mut file, deck, 'Present from start', .present_start)
	file.menu_separator()
	menu_item(mut file, deck, 'Quit   Ctrl-Q', .quit)
	mut edit := deck.window.add_menu('Edit')
	menu_item(mut edit, deck, 'Undo   Ctrl-Z', .undo)
	menu_item(mut edit, deck, 'Redo   Ctrl-Y', .redo)
	edit.menu_separator()
	menu_item(mut edit, deck, 'Clone slide   Ctrl-D', .clone_slide)
	menu_item(mut edit, deck, 'Delete slide   Ctrl-Shift-D', .delete_slide)
	menu_item(mut edit, deck, 'Move slide up', .move_up)
	menu_item(mut edit, deck, 'Move slide down', .move_down)
	mut view := deck.window.add_menu('View')
	menu_item(mut view, deck, 'Sidebar   F9', .toggle_sidebar)
	menu_item(mut view, deck, 'Speaker notes   Ctrl-Shift-N', .toggle_notes)
	menu_item(mut view, deck, 'Source mode   Ctrl-E', .source)
	view.menu_separator()
	menu_item(mut view, deck, 'Present   F5', .present)
	mut insert := deck.window.add_menu('Insert')
	menu_item(mut insert, deck, 'Image...', .image)
	menu_item(mut insert, deck, 'Table', .table)
	menu_item(mut insert, deck, 'Bullet list', .bullet)
	menu_item(mut insert, deck, 'Heading', .heading)
	insert.menu_separator()
	mut charts := insert.add_menu('Chart')
	menu_item(mut charts, deck, 'Columns', .chart_columns)
	menu_item(mut charts, deck, 'Bars', .chart_bars)
	menu_item(mut charts, deck, 'Lines', .chart_lines)
	mut shapes := insert.add_menu('Shape')
	menu_item(mut shapes, deck, 'Rectangle...', .shape_rect)
	menu_item(mut shapes, deck, 'Line...', .shape_line)
	menu_item(mut shapes, deck, 'Circle...', .shape_circle)
	mut format := deck.window.add_menu('Format')
	menu_item(mut format, deck, 'Bold   Ctrl-B', .bold)
	menu_item(mut format, deck, 'Italic   Ctrl-I', .italic)
	menu_item(mut format, deck, 'Code   Ctrl-K', .code)
	menu_item(mut format, deck, 'Strikethrough', .strike)
	menu_item(mut format, deck, 'Font...', .font)
	mut slide_menu := deck.window.add_menu('Slide')
	menu_item(mut slide_menu, deck, 'New slide...   Ctrl-N', .new_slide)
	menu_item(mut slide_menu, deck, 'Clone slide', .clone_slide)
	menu_item(mut slide_menu, deck, 'Delete slide', .delete_slide)
	menu_item(mut slide_menu, deck, 'Move up', .move_up)
	menu_item(mut slide_menu, deck, 'Move down', .move_down)
	slide_menu.menu_separator()
	menu_item(mut slide_menu, deck, 'Present from here   F5', .present)
	menu_item(mut slide_menu, deck, 'Present from start', .present_start)
	mut help := deck.window.add_menu('Help')
	menu_item(mut help, deck, 'Markdown and shapes', .help)
	help.menu_separator()
	menu_item(mut help, deck, 'About', .about)
	deck.rebuild_thumbnails(mut app)
	deck.select(0, mut app)
	app.maximize(mut deck.window)
	deck.refresh()
	app.set_focus(deck.editor)
}

pub fn launch(mut app vtk.App) {
	new_deck(mut app, '')
}

pub fn run() {
	mut app := vtk.new_app()
	app.ctrl_c = .copy
	app.native_clipboard = true
	snapshot := '--snapshot' in os.args
	if snapshot {
		app.desktop = false
		app.dispatch(vtk.Event{ kind: .resize, width: 120, height: 50 })
	} else {
		app.init() or {
			eprintln(err)
			return
		}
	}
	defer { app.fini() }
	mut path := ''
	for arg in os.args[1..] {
		if arg.starts_with('--') {
			continue
		}
		path = arg
		break
	}
	new_deck(mut app, path)
	if snapshot {
		app.redraw()
		println(app.snapshot())
		return
	}
	app.run() or { eprintln(err) }
}
