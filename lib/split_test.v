module vtk

@[heap]
struct SplitDragProbe {
mut:
	changes int
}

fn split_changed(mut c Ctl, mut _ App) {
	mut probe := unsafe { &SplitDragProbe(c.user) }
	probe.changes++
	first, second := c.split_panes() or { panic('missing panes') }
	space := (if c.vertical { c.h } else { c.w }) - 1
	assert (if c.vertical { first.h } else { first.w }) == space * c.value / 1000
	assert (if c.vertical { first.h + second.h } else { first.w + second.w }) == space
}

fn split_test_panes(mut app App, vertical bool) (&Ctl, &Ctl, &Ctl) {
	app.desktop = false
	mut window := app.window('Panes', 63, 23)
	mut panes := split(vertical, 500)
	mut first := entry('unsaved draft', 0)
	first.cursor = 4
	first.anchor = 1
	mut second := label('Second pane')
	panes.add(mut first)
	panes.add(mut second)
	window.add(mut panes)
	app.redraw()
	app.set_focus(first)
	return panes, first, second
}

fn split_test_move(mut app App, panes &Ctl, position int, pressed bool, motion bool) {
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: pressed, motion: motion,
		x: if panes.vertical { panes.x + 2 } else { panes.x + position },
		y: if panes.vertical { panes.y + position } else { panes.y + 2 } })
}

fn test_split_drag_is_opt_in_and_resizes_both_orientations_live() {
	for vertical in [false, true] {
		for enabled in [false, true] {
			for ascii in [false, true] {
				mut app := new_app()
				app.theme.ascii = ascii
				mut panes, first, second := split_test_panes(mut app, vertical)
				assert !panes.resizable
				panes.resizable = enabled
				probe := &SplitDragProbe{}
				panes.user = probe
				panes.changed = split_changed
				initial := if vertical { first.h } else { first.w }
				split_test_move(mut app, panes, initial, true, false)
				assert (app.drag == panes) == enabled
				assert panes.value == 500 && probe.changes == 0
				for delta in 1 .. 4 {
					split_test_move(mut app, panes, initial + delta, true, true)
					app.redraw()
					keep := initial + if enabled { delta } else { 0 }
					assert (if vertical { first.h } else { first.w }) == keep
					assert (if vertical { second.y - panes.y } else { second.x - panes.x }) == keep + 1
					divider := panes.split_divider()
					assert app.screen.cells[divider.y * app.width + divider.x].glyph == if vertical {
						if ascii { '-' } else { '─' }
					} else {
						if ascii { '|' } else { '│' }
					}
					assert probe.changes == if enabled { delta } else { 0 }
					assert first.text == 'unsaved draft' && first.cursor == 4 && first.anchor == 1
					assert app.focus == first
				}
				split_test_move(mut app, panes, initial + 3, false, false)
				assert isnil(app.drag)
				assert probe.changes == if enabled { 3 } else { 0 }
				share := panes.value
				mut window := panes.owner_window_ptr()
				app.maximize(mut window)
				app.redraw()
				space := (if vertical { panes.h } else { panes.w }) - 1
				assert panes.value == share
				assert (if vertical { first.h } else { first.w }) == space * share / 1000
			}
		}
	}
}

fn test_split_drag_clamps_outside_the_window_to_pane_minimums() {
	for vertical in [false, true] {
		mut app := new_app()
		mut panes, mut first, mut second := split_test_panes(mut app, vertical)
		panes.resizable = true
		first.min_w, first.min_h = 8, 3
		second.min_w, second.min_h = 9, 4
		initial := if vertical { first.h } else { first.w }
		split_test_move(mut app, panes, initial, true, false)
		split_test_move(mut app, panes, -100, true, true)
		assert app.drag == panes
		assert (if vertical { first.h } else { first.w }) == if vertical { 3 } else { 8 }
		// Wheels and unrelated buttons must not move or release a captured divider.
		share := panes.value
		for event in [
			Event{ kind: .mouse, button: .wheel_down, pressed: true, x: 1000, y: 1000 },
			Event{ kind: .mouse, button: .wheel_down, x: 1000, y: 1000 },
			Event{ kind: .mouse, button: .right, pressed: true, x: 1000, y: 1000 },
			Event{ kind: .mouse, button: .right, x: 1000, y: 1000 },
		] {
			app.dispatch(event)
			assert panes.value == share && app.drag == panes
		}
		// Release applies its final position even without a preceding motion report.
		split_test_move(mut app, panes, 1000, false, false)
		assert isnil(app.drag)
		assert (if vertical { second.h } else { second.w }) == if vertical { 4 } else { 9 }
		assert panes.value > 0 && panes.value < 1000
	}
}

fn test_split_drag_starts_only_on_its_divider_and_preserves_preferred_size_on_click() {
	for vertical in [false, true] {
		mut app := new_app()
		mut panes, first, _ := split_test_panes(mut app, vertical)
		panes.resizable = true
		panes.value = 0
		app.redraw()
		initial := if vertical { first.h } else { first.w }
		split_test_move(mut app, panes, initial, true, false)
		assert app.drag == panes
		split_test_move(mut app, panes, initial, false, false)
		assert panes.value == 0 && isnil(app.drag)
		app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: first.x + 1, y: first.y })
		assert app.drag == first
		app.dispatch(Event{ kind: .mouse, button: .left, x: first.x + 1, y: first.y })
		assert isnil(app.drag) && panes.value == 0
	}
}

fn test_nested_splits_resize_independently_and_ignore_hidden_panes() {
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Nested splits', 63, 23)
	mut outer := split(false, 500)
	mut inner := split(true, 500)
	outer.resizable = true
	inner.resizable = true
	mut hidden := label('Hidden')
	hidden.hidden = true
	mut first := label('Left')
	mut top := label('Top')
	mut bottom := label('Bottom')
	outer.add(mut hidden)
	outer.add(mut first)
	inner.add(mut top)
	inner.add(mut bottom)
	outer.add(mut inner)
	window.add(mut outer)
	app.redraw()
	assert outer.split_divider().x == first.x + first.w
	split_test_move(mut app, inner, top.h, true, false)
	assert app.drag == inner
	split_test_move(mut app, inner, top.h + 2, true, true)
	assert outer.value == 500 && inner.value > 500
	app.dispatch(Event{ kind: .mouse })
	assert isnil(app.drag)
	share := inner.value
	split_test_move(mut app, outer, first.w, true, false)
	assert app.drag == outer
	split_test_move(mut app, outer, first.w + 3, true, true)
	assert outer.value > 500 && inner.value == share
	assert inner.x == first.x + first.w + 1
	split_test_move(mut app, outer, first.w, false, false)
	assert isnil(app.drag)
}

fn test_incomplete_splits_and_decorative_separators_do_not_capture_a_drag() {
	for count in [0, 1] {
		mut app := new_app()
		app.desktop = false
		mut window := app.window('Incomplete split', 40, 12)
		mut panes := split(false, 500)
		panes.resizable = true
		if count == 1 { mut child := label('Only pane'); panes.add(mut child) }
		window.add(mut panes)
		app.redraw()
		assert panes.split_divider().w == 0
		split_test_move(mut app, panes, panes.w / 2, true, false)
		assert isnil(app.drag)
	}
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Separator', 40, 12)
	mut line := separator()
	line.resizable = true
	window.add(mut line)
	app.redraw()
	app.dispatch(Event{ kind: .mouse, button: .left, pressed: true, x: line.x + 1, y: line.y })
	assert isnil(app.drag)
}

fn split_destroy_on_resize(mut c Ctl, mut app App) {
	app.destroy_ctl(mut c)
}

fn test_split_drag_cancels_on_lifecycle_changes_and_callbacks_can_destroy_it() {
	for action in ['disable', 'clear', 'hide', 'detach', 'close', 'focus_out', 'resize', 'modal', 'callback'] {
		mut app := new_app()
		mut panes, first, _ := split_test_panes(mut app, false)
		panes.resizable = true
		split_test_move(mut app, panes, first.w, true, false)
		assert app.drag == panes
		match action {
			'disable' { panes.resizable = false }
			'clear' { panes.clear() }
			'hide' { panes.hidden = true }
			'detach' { panes.detach() }
			'close' { mut window := panes.owner_window_ptr(); app.close(mut window) }
			'focus_out' { app.dispatch(Event{ kind: .focus_out }) }
			'resize' { app.dispatch(Event{ kind: .resize, width: 90, height: 30 }) }
			'modal' { mut dialog := app.window('Modal', 24, 6); dialog.modal = true }
			'callback' { panes.changed = split_destroy_on_resize }
			else {}
		}
		before := panes.value
		split_test_move(mut app, panes, first.w + 2, true, true)
		split_test_move(mut app, panes, first.w, false, false)
		assert isnil(app.drag), action
		if action == 'callback' { assert panes.destroyed } else { assert panes.value == before, action }
	}
}

fn test_split_drag_leaves_insufficient_space_unchanged() {
	for vertical in [false, true] {
		mut app := new_app()
		mut panes, mut first, mut second := split_test_panes(mut app, vertical)
		panes.resizable = true
		first.min_w, first.min_h = 100, 100
		second.min_w, second.min_h = 100, 100
		initial := if vertical { first.h } else { first.w }
		split_test_move(mut app, panes, initial, true, false)
		split_test_move(mut app, panes, 1, true, true)
		split_test_move(mut app, panes, 1, false, false)
		assert panes.value == 500 && isnil(app.drag)
		assert (if vertical { first.h } else { first.w }) == initial
	}
}

fn test_split_drag_respects_minimums_with_more_cells_than_ratio_steps() {
	for vertical in [false, true] {
		mut app := new_app()
		mut panes, mut first, mut second := split_test_panes(mut app, vertical)
		panes.resizable = true
		first.min_w, first.min_h = 9, 9
		second.min_w, second.min_h = 9, 9
		app.dispatch(Event{ kind: .resize, width: if vertical { 40 } else { 1600 }, height: if vertical { 1600 } else { 40 } })
		mut window := panes.owner_window_ptr()
		app.maximize(mut window)
		app.redraw()
		initial := if vertical { first.h } else { first.w }
		split_test_move(mut app, panes, initial, true, false)
		split_test_move(mut app, panes, 2000, true, true)
		assert (if vertical { second.h } else { second.w }) >= 9
		split_test_move(mut app, panes, -100, true, true)
		assert (if vertical { first.h } else { first.w }) >= 9
		split_test_move(mut app, panes, -100, false, false)
		assert isnil(app.drag)
	}
}
