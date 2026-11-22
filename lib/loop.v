module vtk

import os
import time

pub fn (mut app App) init() ! {
	if app.started { return }
	app.driver.start()!
	app.started = true
	app.width, app.height = app.driver.size()
	app.terminal_focused = true
	app.clear_mouse()
	app.touch_titles = os.getenv('TERMUX_VERSION') != ''
	if app.desktop { app.settings_load() or {} }
	app.fit_windows()
	app.sync_mouse_motion()
	app.screen.resize(app.width, app.height)
	app.dirty = true
}

pub fn (mut app App) fini() {
	app.clear_mouse()
	for mut w in app.windows { app.close_terminals(mut w) }
	app.driver.stop()
	app.started = false
}

pub fn (mut app App) run() ! {
	app.init()!
	defer { app.fini() }
	for app.running { app.step(30) }
}

// step also works headlessly: dispatch events yourself and inspect screen.
pub fn (mut app App) step(timeout_ms int) bool {
	if !app.running { return false }
	if app.started {
		app.sync_mouse_motion()
		width, height := app.driver.size()
		if width != app.width || height != app.height {
			app.dispatch(Event{ kind: .resize, width: width, height: height })
		}
		mut timeout := max(0, timeout_ms)
		for hook in app.hooks { timeout = min(timeout, max(0, int(hook.due - time.ticks()))) }
		bytes := app.driver.read(if app.events.len > 0 { 0 } else { timeout })
		if app.driver.eof {
			app.running = false
			return false
		}
		app.events << app.input.feed(bytes)
		for app.events.len > 0 && app.running {
			e := app.events[0]
			app.events.delete(0)
			app.dispatch(e)
		}
	}
	app.tick()
	if app.dirty {
		app.redraw()
		if app.started {
			print(app.screen.diff())
			flush_stdout()
		}
	}
	if app.windows.filter(!it.closed).len == 0 && app.launchers.len == 0 { app.running = false }
	return app.running
}

pub fn (mut app App) redraw() {
	app.dirty = false
	app.screen.resize(app.width, app.height)
	app.screen.ascii = app.theme.ascii
	app.screen.cursor_x = -1
	app.screen.cursor_y = -1
	app.screen.restore_clip(Rect{0, 0, app.width, app.height})
	app.screen.fill(Rect{0, 0, app.width, app.height}, `▒`, app.theme.desk_fg, app.theme.desk_bg)
	area := app.work_area()
	app.fit_windows()
	for mut w in app.windows {
		if w.closed || w.minimized || w.hidden { continue }
		w.measure()
		w.layout(w.rect())
	}
	app.layout_notices()
	app.layout_popups()
	app.update_hover()
	workspace_clip := app.screen.set_clip(area)
	for mut w in app.windows {
		if w.closed || w.minimized || w.hidden { continue }
		if app.window_shadow {
			for y in max(area.y, w.y + 1) .. min(area.y + area.h, w.y + w.h + 1) {
				for x in max(area.x, w.x + 2) .. min(area.x + area.w, w.x + w.w + 2) {
					at := y * app.width + x
					app.screen.cells[at].fg = gray
					app.screen.cells[at].bg = black
				}
			}
		}
		app.draw_ctl(mut w)
	}
	app.screen.restore_clip(workspace_clip)
	app.draw_notices()
	app.draw_bar()
	app.draw_popups()
	if !isnil(app.placement) {
		app.screen.fill(Rect{0, app.bar_y(), app.width, 1}, ` `, app.theme.bar_fg, app.theme.bar_bg)
		app.screen.text(0, app.bar_y(), (if app.placement_resize { 'Resize' } else { 'Move' }) + ': arrows / Shift+arrows, Enter accepts, Esc cancels', app.theme.bar_fg, app.theme.bar_bg, 0)
	}
	// A cursor is valid only if its cell remains visible in the top window.
	if !area.contains(app.screen.cursor_x, app.screen.cursor_y) || app.popups.len > 0
		|| (!isnil(app.focus) && app.focus.owner_window() != app.top_window()) {
		app.screen.cursor_x = -1
	}
	app.draw_mouse_cursor()
}

pub fn (mut app App) dispatch(e Event) {
	if e.kind == .pointer_shape {
		app.driver.pointer.reply(e.text, time.ticks())
		app.sync_mouse_pointer()
		return
	}
	if e.kind != .mouse { app.title_click = unsafe { nil } }
	if e.kind in [.focus_in, .focus_out] {
		app.terminal_focused = e.kind == .focus_in
		if e.kind == .focus_out {
			app.clear_mouse()
			app.drag = unsafe { nil }
			app.scroll_drag = unsafe { nil }
		}
		app.sync_mouse_pointer()
		return
	}
	if e.kind == .resize {
		app.width = max(1, e.width)
		app.height = max(1, e.height)
		app.drag = unsafe { nil }
		app.scroll_drag = unsafe { nil }
		if !isnil(app.placement) { app.placement_key(Event{ key: int(Key.escape) }) }
		app.fit_windows()
		app.screen.resize(app.width, app.height)
		app.layout_popups()
		app.sync_mouse_pointer()
		app.dirty = true
		return
	}
	app.enforce_modal_input()
	if e.kind == .mouse {
		app.mouse_x = e.x
		app.mouse_y = e.y
		app.update_hover()
		app.mouse(e)
		app.update_hover()
		app.sync_mouse_pointer()
		return
	}
	if e.kind == .paste {
		if !isnil(app.focus) {
			mut c := app.focus
			if c.kind == .terminal {
				c.term.write(e.text)
			} else if c.kind in [.entry, .multiline, .markdown] {
				c.replace_selection(e.text, mut app)
			}
		}
		return
	}
	if !isnil(app.placement) {
		app.placement_key(e)
		return
	}
	if app.popups.len > 0 {
		app.popup_key(e)
		return
	}
	if e.ctrl && lower_key(e.key) == `c` {
		if !isnil(app.focus) && app.focus.kind == .terminal {
			app.focus.term.key(e)
			return
		}
		match app.ctrl_c {
			.quit { app.quit() }
			.ignore {}
			.copy { app.copy_focus() }
			.callback {
				if !app.ctrl_c_active {
					app.ctrl_c_active = true
					if f := app.ctrl_c_handler { f(mut app) }
					app.ctrl_c_active = false
				}
			}
		}
		return
	}
	mut w := app.top_window()
	if !isnil(w) {
		if app.move_key.matches(e) {
			app.begin_placement(mut w, false)
			return
		}
		if app.resize_key.matches(e) {
			app.begin_placement(mut w, true)
			return
		}
	}
	if e.ctrl && e.key == int(Key.tab) {
		app.cycle_window(e.shift)
		return
	}
	if (e.ctrl && e.key == `g`) && !isnil(w) {
		app.window_menu(mut w, w.x + 1, w.y + 1)
		return
	}
	if (e.alt && e.key in [int(`a`), int(Key.f10)]) || (e.ctrl && e.key == `o` && (isnil(app.focus) || app.focus.kind == .terminal)) {
		app.app_menu(0, app.bar_y())
		return
	}
	if e.key == int(Key.tab) && (isnil(app.focus) || app.focus.kind != .terminal || e.shift) {
		if !isnil(app.focus) {
			if f := app.focus.keyfn {
				if f(mut app.focus, e, mut app) { return }
			}
		}
		app.focus_next(e.shift)
		return
	}
	if (e.key == int(Key.f10) || (e.alt && e.key == `m`)) && !isnil(w) {
		for menu in w.kids {
			if menu.kind == .menu {
				app.open_menu(menu, menu.x, menu.y + 1)
				return
			}
		}
	}
	if !isnil(app.focus) && app.focus.visible() {
		mut c := app.focus
		if f := c.keyfn {
			if f(mut c, e, mut app) { return }
		}
		if app.widget_key(mut c, e) {
			app.dirty = true
			return
		}
	}
	if e.ctrl && e.key == `o` {
		app.app_menu(0, app.bar_y())
		return
	}
	if !isnil(w) {
		if f := w.keyfn {
			if f(mut w, e, mut app) { return }
		}
		if e.key == int(Key.escape) && w.dismissable {
			app.close(mut w)
		} else if e.key == int(Key.enter) && !isnil(w.link) {
			w.link.fire(mut app)
		}
	}
}

fn (mut app App) widget_key(mut c Ctl, event Event) bool {
	e := if (app.vim_mode || c.vim.enabled) && !event.ctrl && !event.alt
		&& c.kind in [.radio, .tabs, .table, .tree] && event.key in [int(`j`), int(`k`)] {
		Event{ ...event, key: if event.key == `j` { int(Key.down) } else { int(Key.up) } }
	} else {
		event
	}
	match c.kind {
		.terminal {
			c.term.key(e)
			return true
		}
		.entry, .multiline, .markdown { return c.editor_key(e, mut app) }
		.button, .toolbutton {
			if e.key in [int(Key.enter), int(Key.space)] {
				c.fire(mut app)
				return true
			}
		}
		.checkbox, .switch {
			if e.key in [int(Key.enter), int(Key.space)] {
				c.value = int(c.value == 0)
				c.fire(mut app)
				return true
			}
		}
		.slider, .spin {
			step := if c.kind == .spin { 1 } else { max(1, (c.high - c.low) / 20) }
			if e.key in [int(Key.left), int(Key.down)] {
				c.set_value(c.value - step, mut app)
				return true
			}
			if e.key in [int(Key.right), int(Key.up)] {
				c.set_value(c.value + step, mut app)
				return true
			}
			if e.key == int(Key.home) {
				c.set_value(c.low, mut app)
				return true
			}
			if e.key == int(Key.end) {
				c.set_value(c.high, mut app)
				return true
			}
		}
		.combo {
			if e.key in [int(Key.enter), int(Key.space), int(Key.down)] {
				app.open_menu(&c, c.x, c.y + 1)
				return true
			}
		}
		.radio, .tabs, .table {
			count := if c.kind == .table { c.high } else { c.kids.len }
			if count == 0 { return false }
			step := if e.key == int(Key.page_up) {
				-max(1, c.h - 2)
			} else if e.key == int(Key.page_down) {
				max(1, c.h - 2)
			} else if e.key in [int(Key.left), int(Key.up)] {
				-1
			} else if e.key in [int(Key.right), int(Key.down)] {
				1
			} else {
				0
			}
			if step != 0 || e.key in [int(Key.home), int(Key.end)] {
				c.scroll_hold = false
				c.set_value(clamp(if e.key == int(Key.home) {
					0
				} else if e.key == int(Key.end) {
					count - 1
				} else {
					c.value + step
				}, 0, count - 1), mut app)
				if c.kind == .tabs {
					c.layout(c.rect())
					if !isnil(app.focus) && !app.focus.visible() { app.focus = &c }
				}
				return true
			}
			if e.key == int(Key.enter) {
				if f := c.submit {
					f(mut c, mut app)
					return true
				}
			}
		}
		.tree {
			rows := c.tree_rows()
			if rows.len == 0 { return false }
			mut at := 0
			for i, row in rows {
				if row.node == c.link {
					at = i
					break
				}
			}
			if e.key in [int(Key.up), int(Key.down), int(Key.home), int(Key.end), int(Key.page_up),
				int(Key.page_down)] {
				at = clamp(match e.key {
					int(Key.home) { 0 }
					int(Key.end) { rows.len - 1 }
					int(Key.page_up) { at - max(1, c.h - 2) }
					int(Key.page_down) { at + max(1, c.h - 2) }
					int(Key.up) { at - 1 }
					else { at + 1 }
				}, 0, rows.len - 1)
				c.link = rows[at].node
				c.scroll_hold = false
				c.fire(mut app)
				return true
			}
			if e.key in [int(Key.left), int(Key.right), int(Key.enter)] && !isnil(c.link) {
				if e.key == int(Key.enter) {
					if f := c.submit {
						f(mut c, mut app)
						return true
					}
				}
				c.link.value = if e.key == int(Key.left) {
					0
				} else if e.key == int(Key.right) {
					1
				} else {
					int(c.link.value == 0)
				}
				c.fire(mut app)
				return true
			}
		}
		else {}
	}
	return false
}

pub fn (mut app App) scroll_ctl(mut c Ctl, rows int) bool {
	if f := c.scrollfn {
		if f(mut c, rows, mut app) {
			app.dirty = true
			return true
		}
	}
	mut consumed := false
	match c.kind {
		.scroll {
			if c.kids.len > 0 { consumed = c.scroll_rows(rows, c.kids[0].ph, c.h) }
		}
		.table { consumed = c.scroll_rows(rows, c.high, c.h - 1) }
		.tree { consumed = c.scroll_rows(rows, c.tree_rows().len, c.h) }
		.multiline, .markdown {
			consumed = c.scroll_rows(rows, c.editor_rows().len, c.editor_height())
		}
		else {}
	}
	if consumed { app.dirty = true }
	return consumed
}

fn (mut app App) mouse(e Event) {
	app.dirty = true
	now := app.now()
	last_title := app.title_click
	double_title_click := e.pressed && !e.motion && e.button == .left && !isnil(last_title)
		&& e.x == app.title_click_x && e.y == app.title_click_y && now - app.title_click_at < 400
	if (e.pressed && !e.motion) || (e.button == .left && (e.x != app.title_click_x || e.y != app.title_click_y)) {
		app.title_click = unsafe { nil }
	}
	if double_title_click && app.placement == last_title && !app.placement_resize
		&& last_title.controls & window_maximize != 0 {
		app.placement = unsafe { nil }
	}
	if !isnil(app.placement) {
		if e.pressed && e.button == .left && !e.motion {
			mut w := app.placement
			if app.placement_resize {
				w.resize_window(e.x - w.x + 1, e.y - w.y + 1, app.work_area(), false, false)
			} else {
				w.x = e.x - app.drag_x
				w.y = e.y
				w.fit_window(app.work_area())
			}
			app.placement = unsafe { nil }
		}
		return
	}
	if !isnil(app.scroll_drag) {
		if !e.pressed {
			app.scroll_drag = unsafe { nil }
			return
		}
		mut c := app.scroll_drag
		inset := if c.kind == .table {
			1
		} else if c.kind == .markdown {
			int(c.md.ruler_top)
		} else {
			0
		}
		c.top = clamp((e.y - c.y - inset) * max(0, app.scroll_total - app.scroll_view) / max(1, app.scroll_view - 1), 0, app.scroll_total - app.scroll_view)
		c.scroll_hold = true
		return
	}
	if !isnil(app.drag) {
		mut c := app.drag
		if !e.pressed {
			app.drag = unsafe { nil }
			return
		}
		if c.kind in [.entry, .multiline, .markdown] {
			c.editor_mouse(e, mut app)
			return
		}
		if c.kind == .slider {
			c.set_value(c.low + (e.x - c.x) * (c.high - c.low) / max(1, c.w - 1), mut app)
			return
		}
		if e.motion {
			dx, dy := e.x - app.drag_x, e.y - app.drag_y
			if c.maximized && dx == 0 && dy == 0 { return }
			if app.drag_mode == 0 {
				c.x = app.drag_start.x + dx
				c.y = app.drag_start.y + dy
				c.fit_window(app.work_area())
			} else {
				mut width, mut height := c.w, c.h
				if app.drag_mode & 16 == 0 {
					width = app.drag_start.w + if app.drag_mode & 1 != 0 { -dx } else { dx }
				}
				if app.drag_mode & 8 == 0 {
					height = app.drag_start.h + if app.drag_mode & 2 != 0 { -dy } else { dy }
				}
				was_maximized := c.maximized
				c.maximized = false
				c.resize_window(width, height, app.work_area(), app.drag_mode & 1 != 0, app.drag_mode & 2 != 0)
				if was_maximized && c.rect() == app.drag_start { c.maximized = true }
			}
		}
		return
	}
	if app.popups.len > 0 {
		mut p := app.popups.last()
		if p.rect().contains(e.x, e.y) {
			row := p.top + e.y - p.y - 1
			if row >= 0 && row < p.link.kids.len {
				p.value = row
				if e.pressed && !e.motion && e.button == .left { app.choose_popup() }
			}
		} else if e.pressed && !e.motion {
			app.close_popups()
		}
		return
	}
	if app.bar_mouse(e) { return }
	for mut n in app.notices {
		if n.closed { continue }
		if n.rect.contains(e.x, e.y) {
			if e.pressed && e.button == .left && e.x >= n.rect.x + n.rect.w - 4 { n.closed = true }
			return
		}
	}
	mut w := &Ctl(unsafe { nil })
	for i := app.windows.len - 1; i >= 0; i-- {
		candidate := app.windows[i]
		if !candidate.closed && !candidate.minimized && !candidate.hidden && candidate.rect().contains(e.x, e.y) {
			w = candidate
			break
		}
	}
	if isnil(w) {
		if e.pressed && e.button == .right && app.desktop { app.app_menu(e.x, e.y) }
		return
	}
	mut blocked := app.blocker(w)
	if !isnil(blocked) {
		if e.pressed && !e.motion { app.raise(mut blocked) }
		return
	}
	if e.pressed && !e.motion { app.raise(mut w) }
	if e.y == w.y || e.x == w.x || e.x == w.x + w.w - 1 || e.y == w.y + w.h - 1 {
		if e.button == .right && e.pressed && w.controls & window_menu != 0 {
			app.window_menu(mut w, e.x, e.y)
			return
		}
		if e.button != .left || !e.pressed || e.motion { return }
		if e.y == w.y {
			mut x := w.x + w.w - 4
			if w.controls & window_close != 0 {
				if e.x >= x && e.x < x + 3 {
					app.close(mut w)
					return
				}
				x -= 3
			}
			if w.controls & window_maximize != 0 {
				if e.x >= x && e.x < x + 3 {
					if w.maximized { app.restore(mut w) } else { app.maximize(mut w) }
					return
				}
				x -= 3
			}
			if w.controls & window_minimize != 0 && e.x >= x && e.x < x + 3 {
				app.minimize(mut w)
				return
			}
			if w.controls & window_menu != 0 && e.x > w.x && e.x < w.x + 4 {
				app.window_menu(mut w, w.x, w.y + 1)
				return
			}
			if w.controls & window_maximize != 0 {
				if double_title_click && last_title == w {
					if w.maximized { app.restore(mut w) } else { app.maximize(mut w) }
					return
				}
				app.title_click = w
				app.title_click_at = now
				app.title_click_x = e.x
				app.title_click_y = e.y
			}
		}
		app.drag_start = w.rect()
		app.drag_x = e.x
		app.drag_y = e.y
		app.drag_mode = if e.y == w.y && e.x > w.x && e.x < w.x + w.w - 1 {
			0
		} else {
			4 | int(e.x == w.x) | (int(e.y == w.y) << 1)
		}
		if w.maximized && app.drag_mode == 0 { return }
		if app.drag_mode != 0 {
			if e.x > w.x && e.x < w.x + w.w - 1 {
				app.drag_mode |= 16
			} else if e.y > w.y && e.y < w.y + w.h - 1 {
				app.drag_mode |= 8
			}
		}
		if app.touch_titles && app.drag_mode == 0 {
			app.begin_placement(mut w, false)
			app.drag_x = e.x - w.x
		} else {
			app.drag = w
		}
		return
	}
	for menu in w.kids {
		if menu.kind == .menu && menu.rect().contains(e.x, e.y) && e.pressed && !e.motion {
			app.open_menu(menu, menu.x, menu.y + 1)
			return
		}
	}
	mut c := w.hit(e.x, e.y)
	if isnil(c) || !c.visible() { return }
	if e.button == .right && e.pressed {
		mut p := c
		for !isnil(p) {
			if !isnil(p.menu) {
				app.open_menu(p.menu, e.x, e.y)
				return
			}
			p = p.parent
		}
	}
	if f := c.mousefn {
		if f(mut c, e, mut app) { return }
	}
	if e.button in [.wheel_up, .wheel_down] {
		mut p := c
		for !isnil(p) {
			if app.scroll_ctl(mut p, if e.button == .wheel_up { -1 } else { 1 }) { return }
			p = p.parent
		}
		return
	}
	if e.button != .left || !e.pressed || e.motion { return }
	app.set_focus(c)
	if c.scrollbar && e.x == c.x + c.w - 1 {
		total, view := c.scroll_dimensions()
		if view > 0 {
			app.scroll_drag = c
			app.scroll_total = total
			app.scroll_view = view
			c.top = clamp((e.y - c.y) * max(0, total - view) / max(1, view - 1), 0, total - view)
			c.scroll_hold = true
			return
		}
	}
	match c.kind {
		.button, .toolbutton { c.fire(mut app) }
		.checkbox, .switch {
			c.value = int(c.value == 0)
			c.fire(mut app)
		}
		.entry, .multiline, .markdown {
			c.editor_mouse(e, mut app)
			app.drag = c
		}
		.slider {
			c.set_value(c.low + (e.x - c.x) * (c.high - c.low) / max(1, c.w - 1), mut app)
			app.drag = c
		}
		.spin { c.set_value(c.value + if e.x < c.x + c.w / 2 { -1 } else { 1 }, mut app) }
		.combo { app.open_menu(c, c.x, c.y + 1) }
		.radio { c.set_value(clamp(e.y - c.y, 0, c.kids.len - 1), mut app) }
		.tabs {
			if e.y >= c.y + 2 { return }
			for i, page in c.kids {
				if e.x >= page.tab_x && e.x < page.tab_x + page.tab_w {
					c.value = i
					c.fire(mut app)
					break
				}
			}
		}
		.table {
			if e.y > c.y && c.high > 0 {
				c.scroll_hold = false
				c.set_value(clamp(c.top + e.y - c.y - 1, 0, c.high - 1), mut app)
			}
		}
		.tree {
			rows := c.tree_rows()
			at := c.top + e.y - c.y
			if at >= 0 && at < rows.len {
				c.link = rows[at].node
				c.link.value = int(c.link.value == 0)
				c.scroll_hold = false
				c.fire(mut app)
			}
		}
		else {}
	}
}

fn (mut app App) placement_key(e Event) {
	mut w := app.placement
	if e.key == int(Key.escape) {
		w.x = app.placement_start.x
		w.y = app.placement_start.y
		w.w = app.placement_start.w
		w.h = app.placement_start.h
		app.placement = unsafe { nil }
		w.fit_window(app.work_area())
	} else if e.key == int(Key.enter) {
		app.placement = unsafe { nil }
	} else {
		step := if e.shift { 5 } else { 1 }
		dx := if e.key == int(Key.left) {
			-step
		} else if e.key == int(Key.right) {
			step
		} else {
			0
		}
		dy := if e.key == int(Key.up) {
			-step
		} else if e.key == int(Key.down) {
			step
		} else {
			0
		}
		if app.placement_resize {
			w.resize_window(w.w + dx, w.h + dy, app.work_area(), false, false)
		} else {
			w.x += dx
			w.y += dy
			w.fit_window(app.work_area())
		}
	}
	app.dirty = true
}

fn (mut app App) cycle_window(back bool) {
	windows := app.windows.filter(!it.closed && !it.minimized && isnil(app.blocker(it)))
	if windows.len < 2 { return }
	mut next := if back { windows[windows.len - 2] } else { windows[0] }
	app.raise(mut next)
}
