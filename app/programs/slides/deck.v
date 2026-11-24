module slides

import math
import os
import strconv
import vtk
import vtk.app.programs.common

const slide_separator = '<!-- slide -->'

const slide_separator_written = '\n\n<!-- slide -->\n\n'

const notes_open = '<!-- vtk:speaker-notes -->'

const notes_close = '<!-- /vtk:speaker-notes -->'

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

fn prefs_file() string {
	return os.join_path(os.home_dir(), '.vtk-slides.ini')
}

fn load_prefs() SlideTransition {
	text := os.read_file(prefs_file()) or { return .none }
	return parse_prefs(text)
}

fn parse_prefs(text string) SlideTransition {
	for line in text.split_into_lines() {
		trim := line.trim_space()
		if trim == '' || trim.starts_with('#') {
			continue
		}
		name, raw_value := trim.split_once('=') or { continue }
		if name.trim_space() == 'transition' {
			value := strconv.atoi(raw_value.trim_space()) or { return .none }
			return SlideTransition.from(value) or { SlideTransition.none }
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

fn (mut deck Deck) save(save_as bool, mut app vtk.App) bool {
	mut path := deck.path
	if path == '' || save_as {
		path = app.prompt_for(deck.window, 'Save slides', 'Slides path (.md):',
			if path == '' { 'slides.md' } else { path }) or { return false }
	}
	if path == '' || (path != deck.path && !common.confirm_replace(mut app, deck.window, path)) {
		return false
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
		deck.next_id = math.max(deck.next_id, slide.id + 1)
	}
	deck.path = path
	deck.dirty = false
	deck.current = 0
	deck.rebuild_thumbnails(mut app)
	deck.select(0, mut app)
	app.notify('Opened ${path}', 1500)
}
