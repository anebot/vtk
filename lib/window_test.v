module vtk

fn test_window_titles_stop_before_controls_and_preserve_the_frame() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('X'.repeat(80), 40, 8)
	app.redraw()
	row := w.y * app.width + w.x
	assert app.screen.cells[row + 29].glyph == 'X'
	assert app.screen.cells[row + 30..row + 39].map(it.glyph).join('') == '[_][□][■]'
	w.controls = window_close
	app.redraw()
	assert app.screen.cells[row + 35].glyph == 'X'
	assert app.screen.cells[row + 36..row + 39].map(it.glyph).join('') == '[■]'
	w.controls = 0
	app.redraw()
	assert app.screen.cells[row + 38].glyph == 'X'
	assert app.screen.cells[row + 39].glyph == '╗'
	w.controls = window_default_controls
	w.set_text('界'.repeat(80))
	app.redraw()
	assert app.screen.cells[row + 28].glyph == '界' && app.screen.cells[row + 29].continuation
	assert app.screen.cells[row + 30].glyph == '['
	w.set_text('e\u0301'.repeat(80))
	app.redraw()
	assert app.screen.cells[row + 29].glyph == 'e\u0301'
	assert app.screen.cells[row + 30].glyph == '['
}

fn test_window_minimum_size_limits_and_resizing() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Tiny', 1, 1)
	assert w.w == 16 && w.h == 3 && w.min_w == 16 && w.min_h == 3
	w.set_size_limits(1, 1, 8, 2)
	assert w.w == 16 && w.h == 3 && w.max_w == 16 && w.max_h == 3
	w.set_size_limits(16, 3, 0, 0)
	w.w = 30
	w.h = 10
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: w.x + w.w - 1, y: w.y + w.h - 1, button: .left, pressed: true })
	app.dispatch(Event{ kind: .mouse, x: 0, y: 0, button: .left, pressed: true, motion: true })
	app.dispatch(Event{ kind: .mouse, x: 0, y: 0, button: .left })
	assert w.w == 16 && w.h == 3
	app.begin_placement(mut w, true)
	for _ in 0 .. 30 {
		app.dispatch(Event{ key: int(Key.left) })
		app.dispatch(Event{ key: int(Key.up) })
	}
	app.dispatch(Event{ key: int(Key.enter) })
	assert w.w == 16 && w.h == 3
	app.width = 12
	app.height = 2
	app.tile()
	assert w.w == 16 && w.h == 3
	app.cascade()
	assert w.w == 16 && w.h == 3
	w.set_size_limits(20, 6, 0, 0)
	app.cascade()
	assert w.w == 20 && w.h == 6
}

fn test_top_bar_reserves_first_row_for_windows_dialogs_and_placement() {
	mut app := new_app()
	app.bar_top = true
	mut w := app.window('Top', 30, 8)
	app.maximize(mut w)
	assert w.y == 1 && w.h == 23
	app.dispatch(Event{ kind: .resize, width: 100, height: 30 })
	app.redraw()
	assert w.y == 1 && w.h == 29
	for side in [TileSide.left, .right, .top, .bottom] {
		app.tile_side(mut w, side)
		assert w.y >= 1 && w.y + w.h == if side == .top { 15 } else { 30 }
	}
	mut second := app.window('Second', 30, 8)
	app.tile()
	assert w.y == 1 && second.y == 1
	app.cascade()
	assert w.y == 1 && second.y == 2
	app.begin_placement(mut w, false)
	app.dispatch(Event{ key: int(Key.up), shift: true })
	assert w.y == 1
	app.redraw()
	assert app.screen.cells[..4].map(it.glyph).join('') == 'Move'
	app.dispatch(Event{ key: int(Key.enter) })
	app.raise(mut w)
	app.redraw()
	app.dispatch(Event{ kind: .mouse, x: w.x + 5, y: w.y, button: .left, pressed: true })
	app.dispatch(Event{ kind: .mouse, x: w.x + 5, y: 0, button: .left, pressed: true, motion: true })
	app.dispatch(Event{ kind: .mouse, button: .left })
	assert w.y == 1
	mut body := label('Dialog body')
	mut dialog := app.dialog('Centered', mut body)
	assert dialog.y == 1 + (29 - dialog.h) / 2
	app.notify('Notice', 0)
	app.redraw()
	assert app.notices[0].rect.y + 3 == 30
	app.bar_always = false
	app.maximize(mut w)
	assert w.y == 0 && w.h == 30
	app.minimize(mut second)
	app.redraw()
	assert w.y == 1 && w.h == 29
}

fn test_terminal_resize_keeps_windows_inside_the_workspace() {
	for bar_top in [false, true] {
		for bar_always in [false, true] {
			mut app := new_app()
			app.width = 100
			app.height = 40
			app.bar_top = bar_top
			app.bar_always = bar_always
			inside := app.window('Inside', 20, 5)
			original := inside.rect()
			mut displaced := app.window('Displaced', 25, 8)
			displaced.x = 70
			displaced.y = 25
			mut oversized := app.window('Oversized', 90, 30)
			mut field := entry('Keep this text', 0)
			oversized.add(mut field)
			app.set_focus(field)
			order := app.windows.clone()
			app.dispatch(Event{ kind: .resize, width: 40, height: 12 })
			area := app.work_area()
			assert inside.rect() == original
			assert oversized.w == 40 && oversized.h == area.h
			for w in app.windows {
				assert w.x >= area.x && w.x + w.w <= area.x + area.w
				assert w.y >= area.y && w.y + w.h <= area.y + area.h
			}
			assert app.windows == order && app.focus == field && field.text == 'Keep this text'
			adjusted := displaced.rect()
			app.raise(mut displaced)
			app.redraw()
			app.dispatch(Event{ kind: .mouse, x: displaced.x + 2, y: displaced.y, button: .left, pressed: true })
			assert app.popups.len == 1 && app.popups[0].link.kids[0].link == displaced
			app.close_popups()
			app.dispatch(Event{ kind: .resize, width: 100, height: 40 })
			assert displaced.rect() == adjusted && inside.rect() == original
		}
	}
}

fn test_terminal_resize_keeps_minimized_hidden_and_restored_windows_reachable() {
	mut app := new_app()
	mut minimized := app.window('Minimized', 25, 8)
	minimized.x = 50
	minimized.y = 15
	app.minimize(mut minimized)
	mut hidden := app.window('Hidden', 30, 10)
	hidden.x = 45
	hidden.y = 12
	hidden.hidden = true
	mut maximized := app.window('Maximized', 25, 8)
	maximized.x = 50
	maximized.y = 15
	app.maximize(mut maximized)
	saved := maximized.saved
	app.dispatch(Event{ kind: .resize, width: 30, height: 10 })
	assert maximized.rect() == Rect{0, 0, 30, 9}
	assert maximized.saved == saved && minimized.minimized && hidden.hidden
	app.raise(mut minimized)
	assert !minimized.minimized && minimized.rect() == Rect{5, 1, 25, 8}
	hidden.hidden = false
	app.raise(mut hidden)
	assert hidden.rect() == Rect{0, 0, 30, 9}
	app.restore(mut maximized)
	assert !maximized.maximized && maximized.rect() == Rect{5, 1, 25, 8}
}

fn test_terminal_resize_preserves_minimum_sizes_and_cancels_stale_placement() {
	mut app := new_app()
	app.bar_top = true
	mut w := app.window('Bounded', 30, 10)
	w.set_size_limits(24, 6, 40, 12)
	app.begin_placement(mut w, false)
	app.dispatch(Event{ key: int(Key.right), shift: true })
	app.drag = w
	app.dispatch(Event{ kind: .resize, width: 12, height: 3 })
	assert isnil(app.placement) && isnil(app.drag) && isnil(app.scroll_drag)
	assert w.rect() == Rect{0, 1, 24, 6}
	app.redraw()
	assert app.screen.cells[app.width..app.width + 4].map(it.glyph).join('') == '╔[=]'
	app.dispatch(Event{ kind: .resize, width: 80, height: 24 })
	app.dispatch(Event{ key: int(Key.escape) })
	assert w.rect() == Rect{0, 1, 24, 6}
}

fn test_new_windows_and_bar_changes_keep_the_whole_frame_in_the_workspace() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		mut w := app.window('Oversized', 100, 40)
		assert w.rect() == Rect{0, if bar_top { 1 } else { 0 }, 80, 23}
		w.x = 10
		w.y = 20
		w.w = 30
		w.h = 4
		app.redraw()
		assert w.y == if bar_top { 20 } else { 19 }
		app.bar_top = !bar_top
		app.redraw()
		assert w.y + w.h <= if app.bar_top { 24 } else { 23 }
		app.bar_always = false
		w.x = 0
		w.y = 0
		w.w = 80
		w.h = 24
		app.redraw()
		assert w.rect() == Rect{0, 0, 80, 24}
		mut second := app.window('Minimized', 20, 5)
		app.minimize(mut second)
		app.redraw()
		assert w.rect() == Rect{0, if app.bar_top { 1 } else { 0 }, 80, 23}
	}
}

fn test_mouse_and_keyboard_moves_keep_the_whole_window_above_or_below_the_bar() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		mut w := app.window('Move', 30, 8)
		app.redraw()
		app.dispatch(Event{ kind: .mouse, x: w.x + 5, y: w.y, button: .left, pressed: true })
		app.dispatch(Event{ kind: .mouse, x: 200, y: 200, button: .left, pressed: true, motion: true })
		assert w.rect() == Rect{50, if bar_top { 16 } else { 15 }, 30, 8}
		app.dispatch(Event{ kind: .mouse, x: -100, y: -100, button: .left, pressed: true, motion: true })
		assert w.rect() == Rect{0, if bar_top { 1 } else { 0 }, 30, 8}
		app.dispatch(Event{ kind: .mouse, button: .left })
		app.begin_placement(mut w, false)
		for _ in 0 .. 30 {
			app.dispatch(Event{ key: int(Key.right), shift: true })
			app.dispatch(Event{ key: int(Key.down), shift: true })
		}
		assert w.rect() == Rect{50, if bar_top { 16 } else { 15 }, 30, 8}
		app.dispatch(Event{ key: int(Key.escape) })
		assert w.rect() == Rect{0, if bar_top { 1 } else { 0 }, 30, 8}
		app.begin_placement(mut w, false)
		app.dispatch(Event{ kind: .mouse, x: 200, y: 200, button: .left, pressed: true })
		assert w.rect() == Rect{50, if bar_top { 16 } else { 15 }, 30, 8}
	}
}

fn test_frame_and_placement_resize_respect_the_bar_and_preserve_the_fixed_edges() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.bar_top = bar_top
		mut w := app.window('Resize', 30, 8)
		w.x = 10
		w.y = 5
		app.redraw()
		app.dispatch(Event{ kind: .mouse, x: 39, y: 12, button: .left, pressed: true })
		app.dispatch(Event{ kind: .mouse, x: 200, y: 200, button: .left, pressed: true, motion: true })
		assert w.rect() == Rect{10, 5, 70, if bar_top { 19 } else { 18 }}
		app.dispatch(Event{ kind: .mouse, button: .left })
		w.layout(Rect{10, 5, 30, 8})
		app.dispatch(Event{ kind: .mouse, x: 10, y: 5, button: .left, pressed: true })
		app.dispatch(Event{ kind: .mouse, x: -100, y: -100, button: .left, pressed: true, motion: true })
		assert w.rect() == Rect{0, if bar_top { 1 } else { 0 }, 40, if bar_top { 12 } else { 13 }}
		app.dispatch(Event{ kind: .mouse, button: .left })
		w.layout(Rect{10, 5, 30, 8})
		app.begin_placement(mut w, true)
		for _ in 0 .. 30 {
			app.dispatch(Event{ key: int(Key.right), shift: true })
			app.dispatch(Event{ key: int(Key.down), shift: true })
		}
		assert w.rect() == Rect{10, 5, 70, if bar_top { 19 } else { 18 }}
		app.dispatch(Event{ key: int(Key.escape) })
		assert w.rect() == Rect{10, 5, 30, 8}
		app.begin_placement(mut w, true)
		app.dispatch(Event{ kind: .mouse, x: 200, y: 200, button: .left, pressed: true })
		assert w.rect() == Rect{10, 5, 70, if bar_top { 19 } else { 18 }}
	}
}

fn test_tiling_and_cascading_keep_minimum_sized_windows_inside_the_workspace() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.height = 10
		app.bar_top = bar_top
		for i in 0 .. 4 {
			mut w := app.window('Window ${i}', 30, 6)
			w.set_size_limits(20, 6, 0, 0)
		}
		for side in [TileSide.left, .right, .top, .bottom] {
			for mut w in app.windows.clone() { app.tile_side(mut w, side) }
			for w in app.windows {
				assert w.y >= int(bar_top) && w.y + w.h <= 9 + int(bar_top)
			}
		}
		app.tile()
		for w in app.windows {
			assert w.y >= int(bar_top) && w.y + w.h <= 9 + int(bar_top)
		}
		app.cascade()
		for w in app.windows {
			assert w.y >= int(bar_top) && w.y + w.h <= 9 + int(bar_top)
		}
	}
}
