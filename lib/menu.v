module vtk

pub fn context_menu() &Ctl { return new_ctl(.menu) }

// set_menu attaches a context menu so its items inherit the control's app.
pub fn (mut c Ctl) set_menu(mut menu Ctl) {
	if menu.kind != .menu || c.menu == &menu || !c.can_adopt(&menu) { return }
	if !isnil(c.menu) { c.menu.detach() }
	menu.detach()
	if !c.can_adopt(&menu) { return }
	// A context menu inherits ownership without becoming a choice or tab.
	menu.parent = &c
	c.menu = &menu
	c.invalidate()
}

pub fn (mut c Ctl) add_menu(title string) &Ctl {
	mut menu := &Ctl{ kind: .menu, text: title }
	c.add(mut menu)
	return menu
}

pub fn (mut c Ctl) menu_item(title string, action Callback) &Ctl {
	mut item := &Ctl{ kind: .menuitem, text: title, changed: action }
	c.add(mut item)
	return item
}

pub fn (mut c Ctl) menu_separator() {
	mut sep := separator()
	c.add(mut sep)
}

pub fn (mut app App) open_menu(owner &Ctl, x int, y int) {
	w := owner.owner_window_ptr()
	if !isnil(w) && (w.app != &app || !isnil(app.blocker(w))) { return }
	app.close_popups()
	app.push_menu(owner, x, y)
}

fn (mut app App) push_menu(owner &Ctl, x int, y int) {
	if owner.kids.len == 0 { return }
	mut root := owner.root()
	if root.kind == .window && root.app != &app { return }
	if !isnil(root.app) && root.app != &app { root.app.clear_hover_within(root) }
	root.app = app
	mut width := 8
	for item in owner.kids { width = max(width, text_width(item.text) + 4) }
	w := min(app.width, width)
	h := min(app.height, owner.kids.len + 2)
	mut p := &Ctl{
		kind:  .popup
		app:   app
		popup_owner: owner
		x:     clamp(x, 0, app.width - w)
		y:     clamp(y, 0, app.height - h)
		w:     w
		h:     h
		value: if owner.kind == .combo {
			max(0, owner.value)
		} else {
			0
		}
	}
	for p.value < owner.kids.len - 1 && owner.kids[p.value].kind == .separator { p.value++ }
	app.popups << p
	app.layout_popups()
	app.dirty = true
}

pub fn (mut app App) close_popups() {
	app.popups = []
	app.app_popup = unsafe { nil }
	app.popup_at_bar = false
	app.dirty = true
}

fn (mut app App) layout_popups() {
	if app.popups.any(!app.can_access(it.popup_owner)) {
		app.close_popups()
		return
	}
	anchored := app.popup_at_bar
	if anchored && ((!isnil(app.app_popup) && !app.desktop) || app.bar_height() == 0 || app.height < 4 || app.width < 7) {
		app.close_popups()
		return
	}
	area := app.work_area()
	if area.h < 3 {
		app.close_popups()
		return
	}
	height := area.h
	for i, mut p in app.popups {
		mut width := 8
		for item in p.popup_owner.kids { width = max(width, text_width(item.text) + 4) }
		p.w = min(app.width, width)
		p.h = min(height, p.popup_owner.kids.len + 2)
		if i == 0 && anchored {
			if !isnil(app.app_popup) { p.x = 0 }
			p.y = if app.bar_top { area.y } else { area.y + height - p.h }
		} else if i > 0 {
			parent := app.popups[i - 1]
			p.x = if parent.x + parent.w - 1 + p.w <= app.width {
				parent.x + parent.w - 1
			} else {
				parent.x - p.w + 1
			}
			p.y = parent.y + parent.value - parent.top
		}
		p.x = clamp(p.x, 0, app.width - p.w)
		p.y = clamp(p.y, area.y, area.y + height - p.h)
		view := max(1, p.h - 2)
		p.value = clamp(p.value, 0, p.popup_owner.kids.len - 1)
		p.top = clamp(p.top, 0, p.popup_owner.kids.len - view)
		p.scroll_into_view(p.value, view)
	}
}

fn (mut app App) choose_popup() {
	if app.popups.len == 0 { return }
	p := app.popups.last()
	if p.value < 0 || p.value >= p.popup_owner.kids.len { return }
	mut item := p.popup_owner.kids[p.value]
	if item.disabled || item.kind == .separator { return }
	if item.kind == .menu {
		app.push_menu(item, p.x + p.w - 1, p.y + p.value)
		return
	}
	mut owner := p.popup_owner
	app.close_popups()
	if owner.kind == .combo {
		owner.value = p.value
		owner.fire()
	} else {
		item.fire()
	}
}

fn (mut app App) popup_key(e Event) {
	mut p := app.popups.last()
	if e.key in [int(Key.escape), int(Key.left), int(`h`)] && app.popups.len > 1 {
		app.popups.delete_last()
		app.dirty = true
		return
	}
	if e.key in [int(Key.up), int(`k`), int(Key.down), int(`j`)] {
		step := if e.key in [int(Key.up), int(`k`)] { -1 } else { 1 }
		mut at := p.value + step
		for at >= 0 && at < p.popup_owner.kids.len {
			if p.popup_owner.kids[at].kind != .separator {
				p.value = at
				break
			}
			at += step
		}
		p.scroll_into_view(p.value, p.h - 2)
	} else if e.key in [int(Key.enter), int(Key.space)] {
		app.choose_popup()
	} else if e.key in [int(Key.right), int(`l`)] && p.value < p.popup_owner.kids.len && p.popup_owner.kids[p.value].kind == .menu {
		app.choose_popup()
	} else if e.key in [int(Key.left), int(Key.right), int(`h`), int(`l`)] && !isnil(p.popup_owner.parent) && p.popup_owner.parent.kind == .window {
		menus := p.popup_owner.parent.kids.filter(it.kind == .menu)
		for i, menu in menus {
			if menu == p.popup_owner {
				next := menus[(i + (if e.key in [int(Key.left), int(`h`)] {
					menus.len - 1
				} else {
					1
				})) % menus.len]
				app.open_menu(next, next.x, next.y + 1)
				break
			}
		}
	} else if e.key == int(Key.escape) {
		app.close_popups()
	}
	app.dirty = true
}

fn (mut app App) draw_popups() {
	t := app.theme
	for p in app.popups {
		app.screen.fill(p.rect(), ` `, t.fg, t.bg)
		app.screen.frame(p.rect(), false, t.frame, t.bg)
		old := app.screen.set_clip(Rect{p.x + 1, p.y + 1, p.w - 2, p.h - 2})
		for i := p.top; i < p.popup_owner.kids.len && i < p.top + p.h - 2; i++ {
			item := p.popup_owner.kids[i]
			y := p.y + 1 + i - p.top
			fg := if item.disabled {
				t.dim
			} else if i == p.value {
				t.sel_fg
			} else {
				t.fg
			}
			bg := if i == p.value && !item.disabled { t.sel_bg } else { t.bg }
			app.screen.fill(Rect{p.x + 1, y, p.w - 2, 1}, if item.kind == .separator {
				`─`
			} else {
				` `
			}, fg, bg)
			if item.kind != .separator {
				if p.popup_owner.kind == .combo {
					app.screen.aligned_text(p.x + 2, y, p.w - 4, item.text, p.popup_owner.text_align, fg, bg, 0)
				} else {
					app.screen.text(p.x + 2, y, item.text, fg, bg, 0)
				}
				if item.kind == .menu { app.screen.text(p.x + p.w - 2, y, '▸', fg, bg, 0) }
			}
		}
		app.screen.restore_clip(old)
	}
}

fn window_desktop_action(mut item Ctl, mut app App) {
	mut w := item.link or { return }
	app.move_window_to_desktop(mut w, int(item.data))
}

fn window_menu_action(mut item Ctl, mut app App) {
	mut w := item.link or { return }
	match item.data {
		1 { app.minimize(mut w) }
		2 {
			if w.maximized { app.restore(mut w) } else { app.maximize(mut w) }
		}
		3 { app.begin_placement(mut w, false) }
		4 { app.begin_placement(mut w, true) }
		5 { app.always_on_top(mut w, !w.always_on_top) }
		6 { app.close(mut w) }
		7 { app.tile_side(mut w, .left) }
		8 { app.tile_side(mut w, .right) }
		9 { app.tile_side(mut w, .top) }
		10 { app.tile_side(mut w, .bottom) }
		else {}
	}
}

pub fn (mut app App) window_menu(mut w Ctl, x int, y int) {
	if !app.can_manage(&w) || !app.on_desktop(&w) || w.hidden || w.closed || w.disabled || !isnil(app.blocker(&w)) { return }
	mut menu := context_menu()
	names := ['Minimize', if w.maximized { 'Restore' } else { 'Maximize' }, 'Move', 'Resize',
		(if w.always_on_top { '[x] ' } else { '[ ] ' }) + 'Always on top', 'Close']
	for i, name in names {
		mut item := menu.menu_item(name, window_menu_action)
		item.link = &w
		item.data = i64(i + 1)
	}
	mut tile := menu.add_menu('Tile')
	for i, name in ['Left', 'Right', 'Top', 'Bottom'] {
		mut item := tile.menu_item(name, window_menu_action)
		item.link = &w
		item.data = i64(i + 7)
	}
	if app.desktop_count > 1 {
		mut desktops := menu.add_menu('Move to desktop')
		desktops.disabled = w.modal
		for desktop_id in 1 .. app.desktop_count + 1 {
			mut item := desktops.menu_item('Desktop ${desktop_id}', window_desktop_action)
			item.link = &w
			item.data = desktop_id
			item.disabled = desktop_id == w.desktop_id
		}
	}
	app.open_menu(menu, x, y)
	if y == app.bar_y() && app.bar_height() > 0 && app.popups.len > 0 {
		app.popup_at_bar = true
		app.layout_popups()
	}
}
