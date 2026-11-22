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
