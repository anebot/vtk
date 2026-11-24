module slides

import vtk

const transition_frames = 16

const transition_frame_ms = 25

const bayer_thresholds = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]!

enum SlideTransition {
	none
	slide
	fade
}

fn transition_names() []string {
	return ['No transition', 'Slide', 'Fade out → in']
}

fn transition_label(transition SlideTransition) string {
	return transition_names()[int(transition)]
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
