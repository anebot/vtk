module vtk

import math { max, min }
import os
import time

pub fn (mut app App) init() ! {
	if app.started { return }
	$if vtk_snapshot ? {
		app.rendering = RenderOptions{...app.rendering, backend: .memory}
	}
	if app.rendering == RenderOptions{} {
		app.rendering = RenderOptions{
			backend: if os.getenv('VTK_RENDERER') == 'conservative' { .conservative } else { .ansi }
			slow_terminal: os.getenv('VTK_SLOW_TERMINAL') == '1'
		}
	}
	if app.rendering.backend != .memory {
		app.driver.conservative = app.rendering.backend == .conservative
		app.driver.start()!
		app.width, app.height = app.driver.size()
	}
	app.started = true
	app.terminal_focused = true
	app.clear_mouse()
	app.touch_titles = os.getenv('TERMUX_VERSION') != ''
	if app.driver.active && app.desktop { app.settings_load() or {} }
	app.fit_windows()
	app.sync_mouse_motion()
	app.screen.resize(app.width, app.height)
	app.dirty = true
}

pub fn (mut app App) fini() {
	if app.finishing { return }
	app.finishing = true
	defer { app.finishing = false }
	app.running = false
	app.clear_mouse()
	for app.windows.len > 0 {
		mut w := app.windows.pop()
		app.dispose_ctl(mut w)
	}
	app.windows = []
	app.clear_desktop_input()
	app.focus = none
	app.desktop_focus = [4]?&Ctl{}
	app.hooks = []
	app.terminals, app.spinners = [], []
	app.events = []
	for mut notice in app.notices { notice.closed = true }
	app.notices = []
	app.launchers = []
	app.window_layout = WindowLayout{}
	app.screen = Screen{}
	app.input = Input{}
	app.clipboard = ''
	app.clock_clicked = none
	app.ctrl_c_handler = none
	app.driver.stop()
	app.started = false
}

pub fn (mut app App) run() ! {
	app.init()!
	defer { app.fini() }
	$if vtk_snapshot ? {
		if app.running { app.print_snapshot() }
	} $else {
		for app.running { app.advance(-1) }
	}
}

fn (mut app App) print_snapshot() {
	app.redraw()
	println(app.snapshot())
	app.running = false
}

// step releases the terminal when the loop stops. Call fini to dispose of the app.
// Headless callers can dispatch events themselves and inspect the screen.
pub fn (mut app App) step(timeout_ms int) bool {
	if app.advance(max(0, timeout_ms)) { return true }
	app.driver.stop()
	return false
}

fn (mut app App) advance(timeout_ms int) bool {
	if !app.running { return false }
	app.update_sources()
	wait := app.wait_time(timeout_ms)
	if app.driver.active {
		app.sync_mouse_motion()
		bytes := if app.driver.eof { '' } else { app.driver.read(wait, app.terminals) }
		if app.driver.eof {
			app.running = false
			return false
		}
		if app.driver.resumed {
			app.driver.resumed = false
			app.input = Input{}
			app.events.clear()
			app.event_index = 0
			app.dispatch(Event{kind: .focus_out})
			app.terminal_focused = true
			app.screen.invalidate()
			app.next_frame = 0
			app.dirty = true
			app.sync_mouse_motion()
		}
		if app.driver.resize_pending() {
			width, height := app.driver.size()
			if width != app.width || height != app.height {
				app.dispatch(Event{kind: .resize, width: width, height: height})
			}
		}
		if bytes != '' || app.input.buffer == '\x1b' {
			app.events << app.input.feed(bytes)
		}
		if app.driver.interrupted {
			// An OS interrupt is independent of a partially received escape or paste.
			app.driver.interrupted = false
			app.events << Event{key: `c`, ctrl: true}
		}
		// Process the queue by index instead of copying it on every event.
		// A callback may enter a modal loop, which can consume the remaining events.
		for app.event_index < app.events.len && app.running {
			e := app.events[app.event_index]
			app.events[app.event_index] = Event{}
			app.event_index++
			app.dispatch(e)
		}
		app.event_index = 0
		app.events.clear()
	} else if wait > 0 {
		time.sleep(wait * time.millisecond)
	}
	app.update_sources()
	app.tick()
	app.update_sources()
	if !app.driver.active || app.driver.terminals_ready {
		// Retain the list if an exit callback rebuilds app.terminals in a nested step.
		terminals := app.terminals
		for i in 0 .. terminals.len {
			mut control := terminals[i]
			app.pump_terminal(mut control)
		}
	}
	if app.windows.any(it.closed) {
		for mut w in app.windows.filter(it.closed) { app.dispose_ctl(mut w) }
	}
	app.update_sources()
	if !app.windows.any(!it.closed) && app.launchers.len == 0 { app.running = false }
	if !app.running && app.driver.active { return false }
	if app.needs_frame() && (!app.driver.active || (!app.driver.output_busy() && time.ticks() >= app.next_frame)) {
		if app.dirty || app.damage.count > 0 { app.repaint() }
		app.cursor_dirty = false
		if app.driver.active {
			app.driver.output(app.screen.present(app.rendering), discard_on_stop: true)
			if app.rendering.slow_terminal { app.next_frame = time.ticks() + 80 }
		}
	}
	return app.running
}

pub fn (mut app App) layout() {
	app.fit_windows()
	for mut w in app.windows {
		if !app.on_desktop(w) || w.closed || w.minimized || w.hidden { continue }
		w.measure()
		w.layout(w.rect())
	}
	app.dirty = true
}

// redraw synchronously recomputes geometry and the whole screen snapshot.
pub fn (mut app App) redraw() {
	app.dirty = true
	app.repaint()
}

fn (mut app App) repaint() {
	app.screen.resize(app.width, app.height)
	app.screen.ascii = app.theme.ascii || app.rendering.slow_terminal
	size := Rect{0, 0, app.width, app.height}
	damage := app.damage
	app.damage.count = 0
	if app.dirty {
		app.screen.cursor_x, app.screen.cursor_y = -1, -1
		app.layout()
		app.dirty = false
		app.layout_notices()
		app.layout_popups()
		app.update_hover()
		app.paint_band(size)
	} else {
		for i in 0 .. damage.count { app.paint_band(damage.bands[i]) }
	}
}

fn (mut app App) paint_band(band Rect) {
	app.screen.restore_clip(Rect{0, 0, app.width, app.height})
	app.screen.paint_y, app.screen.paint_end = band.y, band.y + band.h
	defer { app.screen.paint_y, app.screen.paint_end = 0, app.height }
	app.screen.fill(band, `▒`, app.theme.desk_fg, app.theme.desk_bg)
	area := app.work_area()
	workspace_clip := app.screen.set_clip(area)
	for i, mut w in app.windows {
		if !app.paints_window(w) { continue }
		if app.window_shadow {
			for y in max(band.y, max(area.y, w.y + 1)) .. min(band.y + band.h, min(area.y + area.h, w.y + w.h + 1)) {
				for x in max(area.x, w.x + 2) .. min(area.x + area.w, w.x + w.w + 2) {
					at := y * app.width + x
					app.screen.cells[at].fg = gray
					app.screen.cells[at].bg = black
				}
			}
		}
		visible := w.rect().intersection(area).intersection(band)
		if visible.h > 0 && visible.w > 0 && !app.covered_by_window(i + 1, visible) {
			app.draw_ctl(mut w)
		}
	}
	app.screen.restore_clip(workspace_clip)
	app.draw_notices()
	if band.contains(0, app.bar_y()) { app.draw_bar() }
	app.draw_popups()
	if paint := app.overlay { paint(mut app, mut app.screen) }
	if app.placement != none && band.contains(0, app.bar_y()) {
		app.screen.fill(Rect{0, app.bar_y(), app.width, 1}, ` `, app.theme.bar_fg, app.theme.bar_bg)
		app.screen.text(0, app.bar_y(), (if app.placement_resize { 'Resize' } else { 'Move' }) + ': arrows / Shift+arrows, Enter accepts, Esc cancels', app.theme.bar_fg, app.theme.bar_bg, 0)
	}
	// A cursor is valid only if its cell remains visible in the top window.
	if !area.contains(app.screen.cursor_x, app.screen.cursor_y) || app.popups.len > 0
		|| (app.focus != none && !same_ctl(app.focus.owner_window(), app.top_window())) {
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
	if e.kind != .mouse { app.title_click = none }
	if e.kind in [.focus_in, .focus_out] {
		app.terminal_focused = e.kind == .focus_in
		if e.kind == .focus_out {
			app.clear_mouse()
			app.drag = none
			app.scroll_drag = none
		}
		app.sync_mouse_pointer()
		return
	}
	if e.kind == .resize {
		if app.placement != none { app.placement_key(Event{ key: int(Key.escape) }) }
		old_area := app.work_area()
		app.width = max(1, e.width)
		app.height = max(1, e.height)
		app.drag = none
		app.scroll_drag = none
		app.resize_windows(old_area)
		app.screen.resize(app.width, app.height)
		app.layout_popups()
		app.sync_mouse_pointer()
		app.dirty = true
		return
	}
	app.enforce_modal_input()
	if e.kind == .mouse {
		if app.mouse_cursor.enabled && (e.x != app.mouse_x || e.y != app.mouse_y) {
			app.invalidate_area(Rect{app.mouse_x, app.mouse_y, 1, 1})
			app.invalidate_area(Rect{e.x, e.y, 1, 1})
		}
		app.mouse_x = e.x
		app.mouse_y = e.y
		app.update_hover()
		app.mouse(e)
		app.update_hover()
		app.sync_mouse_pointer()
		return
	}
	if e.kind == .paste {
		if mut c := app.focus {
			if f := c.keyfn {
				if f(mut c, e, mut app) {
					app.dirty = true
					return
				}
			}
			if c.kind == .terminal {
				if mut term := c.term { term.write(e.text) }
			} else if c.kind == .table && c.table.pasteable {
				c.table_paste(e.text) or { app.notify(err.msg(), 3000) }
			} else if c.kind in [.entry, .multiline, .markdown] {
				c.replace_selection(e.text)
			}
		}
		return
	}
	if app.placement != none {
		app.placement_key(e)
		return
	}
	if app.popups.len > 0 {
		app.popup_key(e)
		return
	}
	if e.ctrl && lower_key(e.key) == `c` {
		if app.focus != none && app.focus.kind == .terminal {
			if mut term := app.focus.term { term.key(e) }
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
	window := app.top_window()
	if mut w := window {
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
	if e.ctrl && e.key == `g` {
		if mut w := window {
			app.window_menu(mut w, w.x + 1, w.y + 1)
			return
		}
	}
	terminal_has_focus := app.focus != none && app.focus.kind == .terminal
	if (e.alt && e.key in [int(`a`), int(`s`), int(Key.f10)]) || (e.ctrl && e.key == `o` && (app.focus == none || terminal_has_focus)) {
		app.app_menu(0, app.bar_y())
		return
	}
	if e.key == int(Key.tab) && (!terminal_has_focus || e.shift) {
		if mut focus := app.focus {
			if f := focus.keyfn {
				if f(mut focus, e, mut app) { return }
			}
		}
		if app.focus != none && app.focus.kind == .table && app.focus.table_key(e, mut app) { return }
		app.focus_next(e.shift)
		return
	}
	if (e.key == int(Key.f10) || (e.alt && e.key == `m`)) && window != none {
		w := window
		for menu in w.kids {
			if menu.kind == .menu {
				app.open_menu(menu, menu.x, menu.y + 1)
				return
			}
		}
	}
	if mut c := app.focus {
		if c.visible() {
			if f := c.keyfn {
				if f(mut c, e, mut app) { return }
			}
			if app.widget_key(mut c, e) {
				if c.kind in [.entry, .multiline, .markdown, .table, .terminal] {
					c.invalidate_paint()
				} else {
					app.dirty = true
				}
				return
			}
		}
	}
	if e.ctrl && e.key == `o` {
		app.app_menu(0, app.bar_y())
		return
	}
	if mut w := window {
		if f := w.keyfn {
			if f(mut w, e, mut app) { return }
		}
		if e.key == int(Key.escape) && w.dismissable {
			app.close(mut w)
		} else if e.key == int(Key.enter) && w.default_button != none {
			w.default_button.fire()
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
			if mut term := c.term { term.key(e) }
			return true
		}
		.date_picker { return c.date_picker_key(e, mut app) }
		.entry, .multiline, .markdown { return c.editor_key(e, mut app) }
		.button, .toolbutton {
			if e.key in [int(Key.enter), int(Key.space)] {
				c.fire()
				return true
			}
		}
		.checkbox, .switch {
			if e.key in [int(Key.enter), int(Key.space)] {
				c.value = int(c.value == 0)
				c.fire()
				return true
			}
		}
		.slider, .spin {
			step := if c.kind == .spin { 1 } else { max(1, (c.high - c.low) / 20) }
			if e.key in [int(Key.left), int(Key.down)] {
				c.set_value(c.value - step)
				return true
			}
			if e.key in [int(Key.right), int(Key.up)] {
				c.set_value(c.value + step)
				return true
			}
			if e.key == int(Key.home) {
				c.set_value(c.low)
				return true
			}
			if e.key == int(Key.end) {
				c.set_value(c.high)
				return true
			}
		}
		.combo {
			if e.key in [int(Key.enter), int(Key.space), int(Key.down)] {
				app.open_menu(&c, c.x, c.y + 1)
				return true
			}
		}
		.table { return c.table_key(e, mut app) }
		.radio, .tabs {
			count := c.kids.len
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
				}, 0, count - 1))
				if c.kind == .tabs {
					c.layout(c.rect())
					if app.focus != none && !app.focus.visible() { app.focus = &c }
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
				if same_ctl(c.selected_node, row.node) {
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
				c.selected_node = rows[at].node
				c.scroll_hold = false
				c.fire()
				return true
			}
			if e.key in [int(Key.left), int(Key.right), int(Key.enter)] && c.selected_node != none {
				if e.key == int(Key.enter) {
					if f := c.submit {
						f(mut c, mut app)
						return true
					}
				}
				c.selected_node.expanded = if e.key == int(Key.enter) {
					!c.selected_node.expanded
				} else { e.key == int(Key.right) }
				c.fire()
				return true
			}
		}
		else {}
	}
	return false
}

pub fn (mut app App) scroll_ctl(mut c Ctl, rows int) bool {
	if !app.can_access(&c) { return false }
	if f := c.scrollfn {
		if f(mut c, rows, mut app) {
			app.dirty = true
			return true
		}
	}
	if c.kind !in [.scroll, .table, .tree, .multiline, .markdown] || (c.kind == .scroll && c.kids.len == 0) {
		return false
	}
	total, viewport := c.scroll_dimensions()
	return c.scroll_rows(rows, total, viewport)
}

fn (mut app App) mouse(e Event) {
	passive := e.motion && !e.pressed && e.button == .none && app.drag == none
		&& app.scroll_drag == none
	if e.button.is_wheel() {
		if !e.pressed { return }
		// Wheel reports are not left-button drag/motion events. Retain capture
		// and selection while scrolling text; leave a dragged thumb stationary.
		if app.scroll_drag != none { return }
		if mut target := app.drag {
			if target.kind == .terminal {
				if mut term := target.term { term.mouse(e, e.x - target.x, e.y - target.y) }
				return
			}
			if target.kind in [.entry, .multiline, .markdown] && e.button in [.wheel_up, .wheel_down] {
				app.scroll_ctl(mut target, if e.button == .wheel_up { -1 } else { 1 })
			}
			return
		}
	}
	now := app.now()
	last_title := app.title_click
	double_title_click := e.pressed && !e.motion && e.button == .left && last_title != none
		&& e.x == app.title_click_x && e.y == app.title_click_y && now - app.title_click_at < 400
	if (e.pressed && !e.motion) || (e.button == .left && (e.x != app.title_click_x || e.y != app.title_click_y)) {
		app.title_click = none
	}
	if double_title_click && last_title != none && same_ctl(app.placement, last_title) && !app.placement_resize
		&& last_title.controls & window_maximize != 0 {
		app.placement = none
	}
	if mut w := app.placement {
		if e.pressed && e.button == .left && !e.motion {
			if app.placement_resize {
				w.resize_window(e.x - w.x + 1, e.y - w.y + 1, app.work_area(), false, false)
			} else {
				w.x = e.x - app.drag_x
				w.y = e.y
				w.fit_window(app.work_area())
			}
			app.placement = none
			app.dirty = true
		}
		return
	}
	if mut c := app.scroll_drag {
		if !e.pressed {
			app.scroll_drag = none
			return
		}
		inset := if c.kind == .table {
			1
		} else if c.kind == .markdown {
			int(c.md.ruler_top)
		} else {
			0
		}
		top := clamp((e.y - c.y - inset) * max(0, app.scroll_total - app.scroll_view) / max(1, app.scroll_view - 1), 0, app.scroll_total - app.scroll_view)
		c.scroll_rows(top - c.top, app.scroll_total, app.scroll_view)
		return
	}
	if mut c := app.drag {
		if c.kind == .terminal {
			mut term := c.term or { return }
			if e.button != term.mouse_button && e.button != .none { return }
			event := if e.button == .none && !e.motion { Event{ ...e, button: term.mouse_button } } else { e }
			term.mouse(event, e.x - c.x, e.y - c.y)
			if !e.pressed && !e.motion { app.drag = none }
			return
		}
		if c.kind == .table {
			c.table_drag(e, mut app)
			c.invalidate_paint()
			return
		}
		if c.kind == .split {
			if e.button == .none && !e.pressed { app.drag = none; return }
			if e.button != .left { return }
			if !e.pressed { app.drag = none }
			if !c.resizable || app.popups.len > 0 || c.split_divider().w == 0 {
				app.drag = none
				return
			}
			c.resize_split(e)
			return
		}
		if c.kind == .tabpage {
			if e.button == .none && !e.pressed { app.drag = none; return }
			if e.button != .left { return }
			if !e.pressed { app.drag = none }
			mut strip := c.parent or {
				app.drag = none
				return
			}
			if !strip.reorderable || strip.kind != .tabs
				|| strip.kids.index(c) != strip.value || app.popups.len > 0 {
				app.drag = none
				return
			}
			if e.x != app.tab_drag_last_x || e.y != app.tab_drag_last_y {
				app.tab_drag_last_x, app.tab_drag_last_y = e.x, e.y
				strip.drag_tab(c, e)
			}
			return
		}
		if c.mouse_capture {
			if f := c.mousefn { f(mut c, e, mut app) }
			if !e.pressed { app.drag = none }
			c.invalidate_paint()
			return
		}
		if !e.pressed {
			app.drag = none
			return
		}
		if c.kind in [.entry, .multiline, .markdown] {
			c.editor_mouse(e, mut app)
			return
		}
		if c.kind == .slider {
			c.set_value(c.low + (e.x - c.x) * (c.high - c.low) / max(1, c.w - 1))
			return
		}
		if e.motion {
			old := c.rect()
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
			app.window_geometry_changed(mut c, old)
		}
		return
	}
	if app.popups.len > 0 {
		// The release belongs to the press that opened or chose an item; it must
		// not re-target or close the popups it just opened.
		if !e.pressed && e.button == .left { return }
		mut at := app.popups.len - 1
		for at >= 0 && !app.popups[at].rect().contains(e.x, e.y) {
			at--
		}
		if at < 0 {
			if e.pressed && !e.motion { app.popup_outside_press(e) }
			return
		}
		// Moving over a parent must not drop the submenu the pointer is heading
		// for; only a press switches branches.
		if e.motion && at < app.popups.len - 1 { return }
		// A press on a parent menu switches branches; only the popups below it
		// close, so sibling submenus stay one click away.
		for i := at + 1; i < app.popups.len; i++ {
			app.invalidate_area(app.popups[i].rect())
		}
		if at + 1 < app.popups.len { app.popups = app.popups[..at + 1] }
		mut p := app.popups[at]
		owner := p.popup_owner or { return }
		row := p.top + e.y - p.y - 1
		if row >= 0 && row < owner.kids.len {
			if p.value != row {
				p.value = row
				app.invalidate_area(p.rect())
			}
			if e.pressed && !e.motion && e.button == .left { app.choose_popup() }
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
	mut target := ?&Ctl(none)
	for i := app.windows.len - 1; i >= 0; i-- {
		candidate := app.windows[i]
		if app.on_desktop(candidate) && !candidate.closed && !candidate.minimized && !candidate.hidden && candidate.rect().contains(e.x, e.y) {
			target = candidate
			break
		}
	}
	mut w := target or {
		if e.pressed && e.button == .right && app.desktop { app.app_menu(e.x, e.y) }
		return
	}
	if mut blocked := app.blocker(w) {
		if e.pressed && !e.motion { app.raise(mut blocked) }
		return
	}
	if e.pressed && !e.motion && !same_ctl(app.top_window(), w) { app.raise(mut w) }
	if e.y == w.y || e.x == w.x || e.x == w.x + w.w - 1 || e.y == w.y + w.h - 1 {
		if e.button == .right && e.pressed && w.controls & window_menu != 0 {
			app.window_menu(mut w, e.x, e.y)
			return
		}
		if e.button != .left || !e.pressed || e.motion { return }
		if e.y == w.y {
			title := app.window_title_layout(w)
			if title.close >= 0 && e.x >= title.close && e.x < title.close + 3 {
				app.close(mut w)
				return
			}
			if title.maximize >= 0 && e.x >= title.maximize && e.x < title.maximize + 3 {
				if w.maximized { app.restore(mut w) } else { app.maximize(mut w) }
				return
			}
			if title.minimize >= 0 && e.x >= title.minimize && e.x < title.minimize + 3 {
				app.minimize(mut w)
				return
			}
			if title.menu >= 0 && e.x >= title.menu && e.x < title.menu + 3 {
				app.window_menu(mut w, title.menu - 1, w.y + 1)
				return
			}
			if w.controls & window_maximize != 0 {
				if double_title_click && same_ctl(last_title, w) {
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
	mut c := w.hit(e.x, e.y) or { return }
	if !c.visible() { return }
	if c.kind == .terminal && c.term != none && c.term.mouse_mode != 0 && c.content_rect().contains(e.x, e.y) {
		mut term := c.term or { return }
		if e.pressed && !e.motion && e.button == .left { app.set_focus(c) }
		term.mouse(e, e.x - c.x, e.y - c.y)
		if e.pressed && !e.motion && !e.button.is_wheel() && e.button != .none && term.mouse_mode != 9 {
			term.mouse_button = e.button
			app.drag = c
		}
		return
	}
	if e.button == .right && e.pressed {
		mut p := c
		for {
			if p.menu != none {
				app.open_menu(p.menu, e.x, e.y)
				return
			}
			p = p.parent or { break }
		}
	}
	if f := c.mousefn {
		if f(mut c, e, mut app) {
			// Handled callbacks can mutate public fields and other controls.
			if c.mouse_capture && e.pressed && !e.motion && e.button == .left { app.drag = c }
			app.dirty = true
			return
		}
	}
	if passive { return }
	if !e.button.is_wheel() && !c.content_rect().contains(e.x, e.y)
		&& c.kind !in [.button, .toolbutton, .checkbox, .switch] {
		if e.button == .left && e.pressed && !e.motion { app.set_focus(c) }
		return
	}
	if c.kind == .table && c.table_mouse(e, mut app) { return }
	if e.button.is_wheel() {
		// Horizontal trackpad noise must never reverse a vertical scroll.
		if e.button in [.wheel_left, .wheel_right] { return }
		mut p := c
		for {
			if app.scroll_ctl(mut p, if e.button == .wheel_up { -1 } else { 1 }) { return }
			p = p.parent or { break }
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
			top := clamp((e.y - c.y) * max(0, total - view) / max(1, view - 1), 0, total - view)
			c.scroll_rows(top - c.top, total, view)
			return
		}
	}
	match c.kind {
		.split {
			if c.resizable && c.split_divider().contains(e.x, e.y) { app.drag = c }
		}
		.date_picker { c.date_picker_mouse(e) }
		.button, .toolbutton { c.fire() }
		.checkbox, .switch {
			c.value = int(c.value == 0)
			c.fire()
		}
		.entry, .multiline, .markdown {
			c.editor_mouse(e, mut app)
			app.drag = c
		}
		.slider {
			c.set_value(c.low + (e.x - c.x) * (c.high - c.low) / max(1, c.w - 1))
			app.drag = c
		}
		.spin { c.set_value(c.value + if e.x < c.x + c.w / 2 { -1 } else { 1 }) }
		.combo { app.open_menu(c, c.x, c.y + 1) }
		.radio { c.set_value(clamp(e.y - c.y, 0, c.kids.len - 1)) }
		.tabs {
			if e.y >= c.y + 2 { return }
			for i, page in c.kids {
				if e.x >= page.tab_x && e.x < page.tab_x + page.tab_w {
					c.value = i
					if c.reorderable {
						c.layout(c.rect())
						app.drag = page
						app.drag_start = Rect{page.tab_x, c.y, page.tab_w, 2}
						app.drag_x = e.x
						app.drag_y = e.y
						app.tab_drag_last_x, app.tab_drag_last_y = e.x, e.y
					}
					c.fire()
					break
				}
			}
		}
		.tree {
			rows := c.tree_rows()
			at := c.top + e.y - c.y
			if at >= 0 && at < rows.len {
				mut node := rows[at].node
				c.selected_node = node
				node.expanded = !node.expanded
				c.scroll_hold = false
				c.fire()
			}
		}
		else {}
	}
}

fn (mut app App) placement_key(e Event) {
	mut w := app.placement or { return }
	if e.key == int(Key.escape) {
		w.x = app.placement_start.x
		w.y = app.placement_start.y
		w.w = app.placement_start.w
		w.h = app.placement_start.h
		app.placement = none
		w.fit_window(app.work_area())
	} else if e.key == int(Key.enter) {
		app.placement = none
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
	windows := app.windows.filter(it.desktop_id == app.active_desktop && !it.closed && !it.minimized && !it.hidden && app.blocker(it) == none)
	if windows.len < 2 { return }
	mut next := if back { windows[windows.len - 2] } else { windows[0] }
	app.raise(mut next)
}
