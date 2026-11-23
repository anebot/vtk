module vtk

fn tabs_mouse_click(mut app App, x int, y int) {
	app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
	app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left })
}

fn test_tabs_join_the_selected_header_to_its_page_in_unicode_and_ascii() {
	for ascii in [false, true] {
		mut app := new_app()
		app.screen.resize(42, 6)
		app.screen.ascii = ascii
		mut pages := tabs()
		for title in ['Details', 'Conversation', 'Diff'] {
			mut content := label(title + ' page')
			pages.add_tab(title, mut content)
		}
		pages.measure()
		assert pages.pw >= 40 && pages.ph == 4
		for selected in 0 .. 3 {
			pages.value = selected
			pages.layout(Rect{0, 0, 42, 6})
			app.screen.fill(pages.rect(), ` `, app.theme.fg, app.theme.bg)
			app.draw_ctl(mut pages)
			rows := app.screen.snapshot().split('\n')
			assert rows[0].trim_right(' ') == if ascii {
				'  + Details + + Conversation + + Diff +'
			} else {
				'  ╭ Details ╮ ╭ Conversation ╮ ╭ Diff ╮'
			}
			for i, page in pages.kids {
				bottom := app.screen.cells[42 + page.tab_x..42 + page.tab_x + page.tab_w].map(it.glyph).join('')
				assert bottom == if i == selected {
					(if ascii { '+' } else { '╯' }) + ' '.repeat(page.tab_w - 2) + (if ascii { '+' } else { '╰' })
				} else {
					(if ascii { '+' } else { '┴' }) + (if ascii { '-' } else { '─' }).repeat(page.tab_w - 2) + (if ascii { '+' } else { '┴' })
				}
			}
			assert rows[2].contains(pages.kids[selected].text + ' page')
			assert app.screen.cells[42].glyph == if ascii { '+' } else { '┌' }
			assert app.screen.cells[83].glyph == if ascii { '+' } else { '┐' }
		}
	}
}

fn test_tabs_keep_the_page_background_when_focused_and_preserve_the_frame_when_narrow() {
	for i in 0 .. theme_names.len {
		mut app := new_app()
		app.theme = theme_preset(unsafe { Preset(i) })
		app.screen.resize(20, 6)
		app.screen.ascii = app.theme.ascii
		mut pages := tabs()
		for title in ['Details', 'Conversation', 'Diff 界e\u0301'] {
			mut content := label('Page')
			pages.add_tab(title, mut content)
		}
		for selected in 0 .. 3 {
			pages.value = selected
			pages.layout(Rect{0, 0, 20, 6})
			page := pages.kids[selected]
			assert page.tab_x >= 1 && page.tab_x + page.tab_w <= 19
			for focused in [false, true] {
				app.focus = if focused { pages } else { unsafe { nil } }
				app.draw_ctl(mut pages)
				cell := app.screen.cells[page.tab_x + 2]
				assert cell.fg == app.theme.accent && cell.bg == app.theme.bg
				for header_cell in app.screen.cells[page.tab_x..page.tab_x + page.tab_w] {
					assert header_cell.bg == app.theme.bg
				}
				assert cell.attr & bold != 0
				assert app.screen.cells[20].glyph == if app.theme.ascii { '+' } else { '┌' }
				assert app.screen.cells[39].glyph == if app.theme.ascii { '+' } else { '┐' }
			}
		}
	}
}

fn test_tab_mouse_targets_include_both_header_rows_and_exclude_the_page_frame() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Tabs', 50, 10)
	mut pages := tabs()
	for title in ['Details', 'Conversation', 'Diff'] {
		mut content := label(title)
		pages.add_tab(title, mut content)
	}
	w.add(mut pages)
	app.redraw()
	for row in 0 .. 2 {
		tabs_mouse_click(mut app, pages.kids[1].tab_x + 2, pages.y + row)
		app.redraw()
		assert pages.value == 1 && pages.kids[1].visible() && app.focus == pages
		tabs_mouse_click(mut app, pages.kids[2].tab_x + 2, pages.y + row)
		app.redraw()
		assert pages.value == 2 && pages.kids[2].visible()
	}
	tabs_mouse_click(mut app, pages.kids[0].tab_x + 2, pages.y + pages.h - 1)
	app.redraw()
	assert pages.value == 2
	app.dispatch(Event{ key: int(Key.left) })
	app.redraw()
	assert pages.value == 1 && pages.kids[1].visible()
}

@[heap]
struct TabReorderProbe {
mut:
	changes int
	moves   [][]int
}

fn tabs_changed(mut c Ctl, mut _ App) {
	mut probe := unsafe { &TabReorderProbe(c.user) }
	probe.changes++
}

fn tabs_reordered(mut c Ctl, from int, to int, mut _ App) {
	mut probe := unsafe { &TabReorderProbe(c.user) }
	probe.moves << [from, to]
	assert c.value == to
	assert c.kids[to].visible()
}

fn tabs_drag(mut app App, pages &Ctl, from int, to int, row int) {
	x := pages.kids[from].tab_x + 2
	y := pages.y + row
	target := pages.kids[to].tab_x + pages.kids[to].tab_w / 2 + if to < from { -1 } else { 0 }
	app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
	app.dispatch(Event{ kind: .mouse, x: target, y: y, button: .left, pressed: true, motion: true })
	app.dispatch(Event{ kind: .mouse, x: target, y: y, button: .left })
	app.redraw()
}

fn test_tabs_only_reorder_when_enabled_and_preserve_the_page_and_callback_contract() {
	for enabled in [false, true] {
		for row in 0 .. 2 {
			mut app := new_app()
			app.desktop = false
			mut w := app.window('Tabs', 70, 12)
			mut pages := tabs()
			assert !pages.reorderable
			pages.reorderable = enabled
			probe := &TabReorderProbe{}
			pages.user = probe
			pages.changed = tabs_changed
			pages.reordered = tabs_reordered
			mut draft := entry('unsaved draft', 0)
			draft.cursor = 4
			first := pages.add_tab('First', mut draft)
			for title in ['A much longer second tab', 'Last'] {
				mut content := label(title)
				pages.add_tab(title, mut content)
			}
			w.add(mut pages)
			app.redraw()
			tabs_drag(mut app, pages, 0, 2, row)
			assert pages.kids.map(it.text) == if enabled { ['A much longer second tab', 'Last', 'First'] } else { ['First', 'A much longer second tab', 'Last'] }
			assert pages.kids[pages.value] == first && first.visible()
			assert first.kids[0] == draft && draft.text == 'unsaved draft' && draft.cursor == 4
			assert app.focus == pages && isnil(app.drag)
			assert probe.changes == 1
			assert probe.moves == if enabled { [[0, 2]] } else { [][]int{} }
			if enabled {
				tabs_drag(mut app, pages, 2, 0, row)
				assert pages.kids.map(it.text) == ['First', 'A much longer second tab', 'Last']
				assert probe.moves == [[0, 2], [2, 0]]
				app.dispatch(Event{ key: int(Key.right) })
				app.redraw()
				assert pages.value == 1 && pages.kids[1].visible()
			}
		}
	}
}

fn test_tab_drag_captures_the_mouse_and_ignores_wheels_other_buttons_and_outside_targets() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Tabs', 70, 12)
	mut pages := tabs()
	pages.reorderable = true
	for title in ['One', 'A much longer second tab', 'Three'] {
		mut content := label(title)
		pages.add_tab(title, mut content)
	}
	w.add(mut pages)
	app.redraw()
	x, y := pages.kids[0].tab_x + 2, pages.y
	app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
	assert app.drag == pages.kids[0]
	for event in [
		Event{ kind: .mouse, x: pages.kids[2].tab_x + 3, y: y, button: .right, pressed: true },
		Event{ kind: .mouse, x: pages.kids[2].tab_x + 3, y: y, button: .wheel_down, pressed: true },
		Event{ kind: .mouse, x: pages.kids[2].tab_x + 3, y: y, button: .wheel_down },
		Event{ kind: .mouse, x: pages.kids[2].tab_x + 3, y: y + 3, button: .left, pressed: true, motion: true },
		Event{ kind: .mouse, x: w.x + w.w + 1, y: y, button: .left, pressed: true, motion: true },
	] {
		app.dispatch(event)
		assert pages.kids.map(it.text) == ['One', 'A much longer second tab', 'Three']
		assert app.drag == pages.kids[0]
	}
	// Releasing over a target works even if the terminal omitted its last motion.
	target := pages.kids[1].tab_x + pages.kids[1].tab_w - 2
	app.dispatch(Event{ kind: .mouse, x: target, y: y, button: .left })
	assert isnil(app.drag)
	assert pages.kids.map(it.text) == ['A much longer second tab', 'One', 'Three']
	app.redraw()
	// A stationary pointer must not move the tab back after the headers reflow.
	app.dispatch(Event{ kind: .mouse, x: pages.kids[1].tab_x + 2, y: y, button: .left, pressed: true })
	target_left := pages.kids[0].tab_x + pages.kids[0].tab_w / 2 - 1
	for _ in 0 .. 3 {
		app.dispatch(Event{ kind: .mouse, x: target_left, y: y, button: .left, pressed: true, motion: true })
		assert pages.kids[0].text == 'One'
	}
	app.dispatch(Event{ kind: .mouse, x: target_left, y: y + 3, button: .left })
	assert isnil(app.drag)
}

fn test_tab_drag_is_cancelled_when_disabled_or_its_page_is_no_longer_available() {
	for action in ['disable', 'close', 'detach', 'focus_out', 'resize', 'select_other', 'modal'] {
		mut app := new_app()
		app.desktop = false
		mut w := app.window('Tabs', 60, 12)
		mut pages := tabs()
		pages.reorderable = true
		for title in ['One', 'Two', 'Three'] {
			mut content := label(title)
			pages.add_tab(title, mut content)
		}
		w.add(mut pages)
		app.redraw()
		mut page := pages.kids[0]
		x, y := pages.kids[2].tab_x + 4, pages.y
		app.dispatch(Event{ kind: .mouse, x: page.tab_x + 2, y: y, button: .left, pressed: true })
		assert app.drag == page
		match action {
			'disable' { pages.reorderable = false }
			'close' { app.close(mut w) }
			'detach' { page.detach() }
			'focus_out' { app.dispatch(Event{ kind: .focus_out }) }
			'resize' { app.dispatch(Event{ kind: .resize, width: 90, height: 30 }) }
			'select_other' { pages.set_value(1) }
			'modal' { mut dialog := app.window('Modal', 24, 6); dialog.modal = true; dialog.modal_owner = w }
			else {}
		}
		before := pages.kids.clone()
		app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true, motion: true })
		app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left })
		assert isnil(app.drag), action
		assert pages.kids == before, action
	}
}

fn test_dragged_header_follows_each_mouse_move_and_tabs_reflow_before_release() {
	for ascii in [false, true] {
		mut app := new_app()
		app.desktop = false
		app.theme.ascii = ascii
		app.screen.ascii = ascii
		mut w := app.window('Tabs', 70, 12)
		mut pages := tabs()
		pages.reorderable = true
		for title in ['First 界e\u0301', 'A much longer second tab', 'Last'] {
			mut content := label(title + ' page')
			pages.add_tab(title, mut content)
		}
		w.add(mut pages)
		app.redraw()
		page := pages.kids[0]
		x, y := page.tab_x + 3, pages.y
		original_x := page.tab_x
		app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
		for dx in [1, 2, 4, 7] {
			app.dispatch(Event{ kind: .mouse, x: x + dx, y: y, button: .left, pressed: true, motion: true })
			app.redraw()
			assert pages.value == 0 && page.tab_x == original_x
			assert app.screen.cells[y * app.width + original_x + dx].glyph == if ascii { '+' } else { '╭' }, 'ascii=${ascii}, dx=${dx}\n${app.screen.snapshot()}'
			assert app.screen.cells[(y + 1) * app.width + original_x + dx].glyph == if ascii { '+' } else { '╯' }
		}
		target := pages.kids[1].tab_x + pages.kids[1].tab_w / 2
		app.dispatch(Event{ kind: .mouse, x: target, y: y, button: .left, pressed: true, motion: true })
		app.redraw()
		assert pages.value == 1 && pages.kids[1] == page
		assert app.drag == page && page.visible()
		assert app.screen.cells[y * app.width + target - 3].glyph == if ascii { '+' } else { '╭' }
		app.dispatch(Event{ kind: .mouse, x: target, y: y, button: .left })
		app.redraw()
		assert isnil(app.drag)
		assert app.screen.cells[y * app.width + page.tab_x].glyph == if ascii { '+' } else { '╭' }
		// A release without a button identity also ends the capture.
		app.dispatch(Event{ kind: .mouse, x: page.tab_x + 2, y: y, button: .left, pressed: true })
		assert app.drag == page
		app.dispatch(Event{ kind: .mouse, x: page.tab_x + 2, y: y })
		assert isnil(app.drag)
	}
}

fn tabs_destroy_on_reorder(mut c Ctl, _ int, _ int, mut app App) {
	app.destroy_ctl(mut c)
}

fn test_tab_drag_at_clipped_edges_reaches_tabs_beyond_a_narrow_strip() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Tabs', 24, 9)
	mut pages := tabs()
	pages.reorderable = true
	for title in ['First long tab 界', 'Second long tab 界', 'Third long tab 界'] {
		mut content := label(title)
		pages.add_tab(title, mut content)
	}
	w.add(mut pages)
	app.redraw()
	first := pages.kids[0]
	x, y := first.tab_x + 2, pages.y
	app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left, pressed: true })
	for expected in [1, 2] {
		app.dispatch(Event{ kind: .mouse, x: pages.x + pages.w - 3, y: y, button: .left, pressed: true, motion: true })
		app.dispatch(Event{ kind: .mouse, x: pages.x + pages.w - 2, y: y, button: .left, pressed: true, motion: true })
		app.redraw()
		assert pages.value == expected && pages.kids[expected] == first
	}
	for expected in [1, 0] {
		app.dispatch(Event{ kind: .mouse, x: pages.x + 2, y: y, button: .left, pressed: true, motion: true })
		app.dispatch(Event{ kind: .mouse, x: pages.x + 1, y: y, button: .left, pressed: true, motion: true })
		app.redraw()
		assert pages.value == expected && pages.kids[expected] == first
	}
	app.dispatch(Event{ kind: .mouse, x: x, y: y, button: .left })
	assert pages.value == 0 && isnil(app.drag)
}

fn test_reorder_callback_can_destroy_the_tab_control_during_a_drag() {
	mut app := new_app()
	app.desktop = false
	mut w := app.window('Tabs', 60, 12)
	mut pages := tabs()
	pages.reorderable = true
	pages.reordered = tabs_destroy_on_reorder
	for title in ['One', 'Two'] {
		mut content := label(title)
		pages.add_tab(title, mut content)
	}
	w.add(mut pages)
	app.redraw()
	tabs_drag(mut app, pages, 0, 1, 0)
	assert pages.destroyed && isnil(app.drag)
}
