module vtk

import os
import time

pub fn (mut app App) register(name string, start fn (mut App, voidptr), data voidptr) {
	app.launchers << Launcher{name, start, data}
}

pub fn (mut app App) notify(text string, timeout_ms int) &Notice {
	mut notice := &Notice{
		text: text
		due:  if timeout_ms > 0 {
			time.ticks() + timeout_ms
		} else {
			0
		}
	}
	app.notices.insert(0, notice)
	app.dirty = true
	return notice
}

pub fn (mut app App) notice_close(mut notice Notice) {
	notice.closed = true
	app.dirty = true
}

fn (app &App) bar_height() int {
	return int((app.desktop && app.bar_always) || app.windows.any(it.minimized && !it.closed))
}

fn (app &App) bar_y() int { return if app.bar_top { 0 } else { app.height - 1 } }

fn (app &App) work_area() Rect {
	return Rect{0, if app.bar_top { app.bar_height() } else { 0 }, app.width, max(0, app.height - app.bar_height())}
}

fn (app &App) bar_buttons_rect() Rect {
	x := if app.desktop { 6 } else { 0 }
	clock_width := if app.bar_clock && app.desktop { 6 } else { 0 }
	return Rect{x, app.bar_y(), max(0, app.width - x - clock_width), 1}
}

fn (mut app App) draw_bar() {
	if app.bar_height() == 0 { return }
	t := app.theme
	y := app.bar_y()
	app.screen.fill(Rect{0, y, app.width, 1}, ` `, t.bar_fg, t.bar_bg)
	if app.desktop { app.screen.text(0, y, '[App]', t.bar_fg, t.bar_bg, bold) }
	buttons := app.bar_buttons_rect()
	mut x := buttons.x - app.bar_offset
	old := app.screen.set_clip(buttons)
	for w in app.windows {
		if w.closed || (!app.desktop && !w.minimized) { continue }
		text := '[= ${w.text}] '
		app.screen.text(x, y, text, if w == app.top_window() { t.sel_fg } else { t.bar_fg }, if w == app.top_window() {
			t.sel_bg
		} else {
			t.bar_bg
		}, 0)
		x += text_width(text)
	}
	app.screen.restore_clip(old)
	if app.bar_clock && app.desktop {
		app.screen.text(max(0, app.width - 5), y, time.now().hhmm(), t.bar_fg, t.bar_bg, 0)
	}
}

fn (mut app App) layout_notices() {
	area := app.work_area()
	mut y := area.y + area.h - 3
	for mut notice in app.notices {
		if notice.closed { continue }
		w := min(max(20, text_width(notice.text) + 7), max(1, app.width - 2))
		notice.rect = Rect{max(0, app.width - w - 1), y, w, 3}
		y -= 4
	}
}

fn (mut app App) draw_notices() {
	t := app.theme
	for notice in app.notices {
		if notice.closed { continue }
		y, w := notice.rect.y, notice.rect.w
		if y >= 0 {
			app.screen.fill(notice.rect, ` `, t.fg, t.bg)
			app.screen.frame(notice.rect, false, t.frame, t.bg)
			old := app.screen.set_clip(Rect{notice.rect.x + 2, y + 1, max(0, w - 7), 1})
			app.screen.text(notice.rect.x + 2, y + 1, notice.text, t.fg, t.bg, 0)
			app.screen.restore_clip(old)
			app.screen.text(notice.rect.x + w - 4, y + 1, '[x]', t.btn_bg, t.bg, 0)
		}
	}
}

fn launcher_action(mut c Ctl, mut app App) {
	if c.data >= 0 && c.data < app.launchers.len {
		launcher := app.launchers[int(c.data)]
		launcher.start(mut app, launcher.data)
	}
}

fn desktop_action(mut c Ctl, mut app App) {
	match c.data {
		1 { app.settings_dialog() }
		2 { app.quit() }
		3 {
			app.terminal_window() or {
				app.notify(err.msg(), 3000)
				return
			}
		}
		else {}
	}
}

pub fn (mut app App) app_menu(x int, y int) {
	if !app.desktop || !isnil(app.blocker(unsafe { nil })) { return }
	anchored := x == 0 && y == app.bar_y() && app.bar_height() > 0
	if anchored && !isnil(app.app_popup) {
		app.close_popups()
		return
	}
	if anchored && (app.height < 4 || app.width < 5) { return }
	mut menu := context_menu()
	for i, launcher in app.launchers {
		mut item := menu.menu_item(launcher.name, launcher_action)
		item.data = i
	}
	if app.launchers.len > 0 { menu.menu_separator() }
	mut terminal_item := menu.menu_item('Terminal', desktop_action)
	terminal_item.data = 3
	mut settings := menu.menu_item('Settings...', desktop_action)
	settings.data = 1
	mut quit := menu.menu_item('Quit', desktop_action)
	quit.data = 2
	app.open_menu(menu, x, y)
	if anchored && app.popups.len > 0 {
		app.app_popup = app.popups[0]
		app.popup_at_bar = true
		app.layout_popups()
	}
}

fn (mut app App) bar_mouse(e Event) bool {
	if app.bar_height() == 0 || e.y != app.bar_y() { return false }
	if !isnil(app.blocker(unsafe { nil })) { return true }
	if e.button in [.wheel_up, .wheel_down] {
		app.bar_offset = max(0, app.bar_offset + if e.button == .wheel_up { -3 } else { 3 })
		return true
	}
	if !e.pressed || e.motion { return true }
	if app.desktop && e.x < 5 {
		app.app_menu(0, e.y)
		return true
	}
	buttons := app.bar_buttons_rect()
	if !buttons.contains(e.x, e.y) { return true }
	mut x := buttons.x - app.bar_offset
	for mut w in app.windows.clone() {
		if w.closed || (!app.desktop && !w.minimized) { continue }
		width := text_width(w.text) + 5
		if e.x >= x && e.x < x + width {
			if e.button == .right || (e.button == .left && e.x == x + 1) {
				app.window_menu(mut w, e.x, e.y)
			} else {
				app.raise(mut w)
			}
			return true
		}
		x += width
	}
	return true
}

pub fn (mut app App) settings_file(path string) { app.settings_path = path }

fn (app &App) settings_filename() string {
	return if app.settings_path != '' {
		app.settings_path
	} else {
		os.join_path(os.home_dir(), 'vtk.ini')
	}
}

pub fn (mut app App) settings_load() ! {
	text := os.read_file(app.settings_filename())!
	mut move, mut resize := app.move_key, app.resize_key
	mut in_section := false
	mut theme_fields := map[string]bool{}
	for line in text.split_into_lines() {
		trim := line.trim_space()
		if trim.starts_with('[') {
			in_section = trim == '[vtk]'
			continue
		}
		if !in_section || trim.starts_with('#') || trim.starts_with(';') { continue }
		parts := trim.split_nth('=', 2)
		if parts.len != 2 { continue }
		key, value := parts[0].trim_space(), parts[1].trim_space()
		match key {
			'move_key' { move = parse_binding(value) or { move } }
			'resize_key' { resize = parse_binding(value) or { resize } }
			'bar_always' { app.bar_always = value == '1' }
			'bar_top' { app.bar_top = value == '1' }
			'bar_clock' { app.bar_clock = value == '1' }
			'window_shadow' { app.window_shadow = value == '1' }
			'dim_inactive' { app.dim_inactive = value == '1' }
			'title_gradient' { app.title_gradient = value == '1' }
			'mouse_cursor' { app.set_mouse_cursor(MouseCursor{ ...app.mouse_cursor, enabled: value == '1' }) }
			'vim_mode' { app.vim_set(value == '1') }
			'ascii' { app.theme.ascii = value == '1' }
			else {
				app.load_theme_field(key, value.int())
				theme_fields[key] = true
			}
		}
	}
	// Older files have only a title foreground and a focus background. Fill in
	// their missing partners without replacing the saved palette or custom colors.
	if theme_fields['title'] && !theme_fields['title_bg'] {
		app.theme.title_bg = if app.theme.title == black { white } else if app.theme.bg == black { blue } else { black }
	}
	if theme_fields['focus_bg'] && !theme_fields['focus_fg'] {
		t := app.theme
		app.theme.focus_fg = if t.focus_bg == t.field_bg { t.field_fg }
			else if t.focus_bg == t.sel_bg { t.sel_fg }
			else if t.focus_bg == t.tool_bg { t.tool_fg }
			else if t.focus_bg == t.bg { t.fg }
			else { t.btn_fg }
	}
	app.set_keys(move, resize)
	app.dirty = true
}

fn (mut app App) load_theme_field(name string, value int) {
	$for field in Theme.fields {
		$if field.typ is int {
			if name == field.name { app.theme.$(field.name) = value }
		}
	}
}

pub fn (app &App) settings_saved() bool { return os.exists(app.settings_filename()) }

pub fn (app &App) settings_save() ! {
	mut lines := ['[vtk]', 'move_key = ${app.move_key}', 'resize_key = ${app.resize_key}',
		'bar_always = ${int(app.bar_always)}', 'bar_top = ${int(app.bar_top)}',
		'bar_clock = ${int(app.bar_clock)}', 'window_shadow = ${int(app.window_shadow)}',
		'dim_inactive = ${int(app.dim_inactive)}', 'mouse_cursor = ${int(app.mouse_cursor.enabled)}',
		'title_gradient = ${int(app.title_gradient)}',
		'vim_mode = ${int(app.vim_mode)}', 'ascii = ${int(app.theme.ascii)}']
	$for field in Theme.fields {
		$if field.typ is int {
			value := app.theme.$(field.name)
			lines << '${field.name} = ${value}'
		}
	}
	os.write_file(app.settings_filename(), lines.join('\n') + '\n')!
}

pub fn (mut app App) settings_reset() ! {
	app.theme = theme_default()
	app.bar_always = true
	app.bar_top = false
	app.bar_clock = true
	app.window_shadow = true
	app.dim_inactive = true
	app.title_gradient = false
	app.set_mouse_cursor(MouseCursor{ ...app.mouse_cursor, enabled: false })
	app.move_key = Binding{ key: int(Key.f7), alt: true }
	app.resize_key = Binding{ key: int(Key.f8), alt: true }
	app.vim_set(false)
	if app.settings_saved() { os.rm(app.settings_filename())! }
	app.dirty = true
}

@[heap]
struct Settings {
mut:
	palette      Theme
	theme        &Ctl = unsafe { nil }
	desktop      &Ctl = unsafe { nil }
	bar          &Ctl = unsafe { nil }
	bar_top      &Ctl = unsafe { nil }
	clock        &Ctl = unsafe { nil }
	shadow       &Ctl = unsafe { nil }
	dim          &Ctl = unsafe { nil }
	gradient     &Ctl = unsafe { nil }
	mouse_cursor &Ctl = unsafe { nil }
	vim          &Ctl = unsafe { nil }
	move         &Ctl = unsafe { nil }
	resize       &Ctl = unsafe { nil }
}

fn (mut s Settings) update_desktop_color() {
	s.desktop.set_text('#${color_as_rgb(s.palette.desk_bg):06x}...')
}

fn settings_theme_changed(mut c Ctl, mut app App) {
	mut s := unsafe { &Settings(c.user) }
	s.palette = theme_preset(unsafe { Preset(clamp(c.value, 0, 6)) })
	s.update_desktop_color()
	app.dirty = true
}

fn settings_desktop_color(mut c Ctl, mut app App) {
	mut s := unsafe { &Settings(c.user) }
	if rgb := app.color_pick(c.owner_window(), 'Desktop background', color_as_rgb(s.palette.desk_bg)) {
		s.palette.desk_bg = 0x1000000 | rgb
		s.update_desktop_color()
		app.dirty = true
	}
}

fn settings_apply(mut c Ctl, mut app App) {
	mut s := unsafe { &Settings(c.user) }
	if c.data == 2 {
		app.settings_reset() or { app.notify(err.msg(), 2500) }
		s.palette = app.theme
		s.update_desktop_color()
		s.theme.value = 0
		s.bar.value = int(app.bar_always)
		s.bar_top.value = int(app.bar_top)
		s.clock.value = int(app.bar_clock)
		s.shadow.value = int(app.window_shadow)
		s.dim.value = int(app.dim_inactive)
		s.gradient.value = int(app.title_gradient)
		s.mouse_cursor.value = int(app.mouse_cursor.enabled)
		s.vim.value = int(app.vim_mode)
		s.move.set_text(app.move_key.str())
		s.resize.set_text(app.resize_key.str())
		return
	}
	move := parse_binding(s.move.text) or {
		app.notify(err.msg(), 2500)
		return
	}
	resize := parse_binding(s.resize.text) or {
		app.notify(err.msg(), 2500)
		return
	}
	if !app.set_keys(move, resize) {
		app.notify('Move and Resize shortcuts must differ', 2500)
		return
	}
	app.theme = s.palette
	app.bar_always = s.bar.value != 0
	app.bar_top = s.bar_top.value != 0
	app.bar_clock = s.clock.value != 0
	app.window_shadow = s.shadow.value != 0
	app.dim_inactive = s.dim.value != 0
	app.title_gradient = s.gradient.value != 0
	app.set_mouse_cursor(MouseCursor{ ...app.mouse_cursor, enabled: s.mouse_cursor.value != 0 })
	app.vim_set(s.vim.value != 0)
	if c.data == 1 {
		app.settings_save() or {
			app.notify(err.msg(), 2500)
			return
		}
	}
	app.dirty = true
}

pub fn (mut app App) settings_dialog() {
	mut s := &Settings{ palette: app.theme }
	mut body := box(true)
	mut spacer := label('')
	body.add(mut spacer)
	s.theme = combo()
	s.theme.text_align = .center
	for name in ['Borland', 'Light Borland', 'Dark', 'Light', 'Teal', 'Modern', 'Serial'] {
		s.theme.add_item(name)
	}
	s.theme.value = 0
	for i in 0 .. 7 {
		preset := theme_preset(unsafe { Preset(i) })
		if Theme{ ...app.theme, desk_bg: preset.desk_bg } == preset { s.theme.value = i }
	}
	s.theme.user = s
	s.theme.changed = settings_theme_changed
	mut theme_row := box(false)
	mut theme_label := label('Theme:')
	theme_row.add(mut theme_label)
	s.theme.expand = true
	theme_row.add(mut s.theme)
	body.add(mut theme_row)
	mut desktop_row := box(false)
	mut desktop_label := label('Desktop background:')
	desktop_row.add(mut desktop_label)
	s.desktop = button('')
	s.desktop.user = s
	s.desktop.changed = settings_desktop_color
	s.update_desktop_color()
	desktop_row.add(mut s.desktop)
	body.add(mut desktop_row)
	s.bar = checkbox('Always show window bar', app.bar_always)
	s.bar_top = checkbox('Window bar at top', app.bar_top)
	s.clock = checkbox('Clock', app.bar_clock)
	s.shadow = checkbox('Window shadows', app.window_shadow)
	s.dim = checkbox('Dim inactive windows', app.dim_inactive)
	s.gradient = checkbox('Gradient window titles', app.title_gradient)
	s.mouse_cursor = checkbox('Block mouse cursor', app.mouse_cursor.enabled)
	s.vim = checkbox('Vim mode', app.vim_mode)
	s.move = entry(app.move_key.str(), 0)
	s.move.expand = false
	s.move.col = 1
	s.resize = entry(app.resize_key.str(), 0)
	s.resize.expand = false
	s.resize.col = 1
	s.resize.row = 1
	mut controls := [s.bar, s.bar_top, s.clock, s.shadow, s.dim, s.gradient, s.mouse_cursor, s.vim]
	for mut ctl in controls { body.add(mut ctl) }
	mut shortcuts := grid()
	mut move_label := label('Move shortcut')
	shortcuts.add(mut move_label)
	shortcuts.add(mut s.move)
	mut resize_label := label('Resize shortcut')
	resize_label.row = 1
	shortcuts.add(mut resize_label)
	shortcuts.add(mut s.resize)
	body.add(mut shortcuts)
	mut row := button_bar()
	for i, text in ['Apply', 'Save', 'Reset'] {
		mut b := button(text)
		b.data = i
		b.user = s
		b.changed = settings_apply
		row.add(mut b)
	}
	mut close := dialog_button('Close', false)
	row.add(mut close)
	body.add(mut row)
	mut w := app.dialog('Settings', mut body)
	app.modal_for(mut w, unsafe { nil })
	app.destroy_ctl(mut w)
}
