module vtk

fn ctl_option(c &Ctl) ?&Ctl {
	if isnil(c) { return none }
	return unsafe { c }
}

pub fn (app &App) top_window() ?&Ctl { return ctl_option(app.top_window_ptr()) }
pub fn (app &App) focused_ctl() ?&Ctl { return ctl_option(app.focus) }
pub fn (app &App) window_list() []&Ctl { return app.windows.clone() }
pub fn (app &App) is_running() bool { return app.running }
pub fn (app &App) size() (int, int) { return app.width, app.height }
pub fn (app &App) get_desktop_count() int { return app.desktop_count }
pub fn (app &App) get_active_desktop() int { return app.active_desktop }
pub fn (app &App) snapshot() string { return app.screen.snapshot() }
pub fn (mut app App) invalidate() { app.dirty = true }

pub fn (c &Ctl) owner_window() ?&Ctl { return ctl_option(c.owner_window_ptr()) }
pub fn (c &Ctl) parent_ctl() ?&Ctl { return ctl_option(c.parent) }
pub fn (c &Ctl) children() []&Ctl { return c.kids.clone() }
pub fn (c &Ctl) context_menu() ?&Ctl { return ctl_option(c.menu) }
pub fn (c &Ctl) tree_selection() ?&Ctl { return ctl_option(c.selected_node) }
pub fn (c &Ctl) get_default_button() ?&Ctl { return ctl_option(c.default_button) }
pub fn (c &Ctl) get_modal_owner() ?&Ctl { return ctl_option(c.modal_owner) }
pub fn (c &Ctl) hit(x int, y int) ?&Ctl { return ctl_option(c.hit_ptr(x, y)) }
pub fn (c &Ctl) is_hovered() bool { return c.hovered }
pub fn (c &Ctl) is_closed() bool { return c.closed }
pub fn (c &Ctl) is_minimized() bool { return c.minimized }
pub fn (c &Ctl) is_maximized() bool { return c.maximized }
pub fn (c &Ctl) is_always_on_top() bool { return c.always_on_top }
pub fn (c &Ctl) is_modal() bool { return c.modal }
pub fn (c &Ctl) get_desktop_id() int { return c.desktop_id }
pub fn (c &Ctl) preferred_size() (int, int) { return c.pw, c.ph }

pub fn (c &Ctl) terminal_state() ?&Terminal {
	if isnil(c.term) { return none }
	return c.term
}

pub fn (n &Notice) is_closed() bool { return n.closed }
pub fn (n &Notice) bounds() Rect { return n.rect }
pub fn (s &Screen) size() (int, int) { return s.width, s.height }
pub fn (s &Screen) cell_snapshot() []Cell { return s.cells.clone() }
pub fn (t &Terminal) size() (int, int) { return t.cols, t.rows }
pub fn (t &Terminal) cell_snapshot() []Cell { return t.cells.clone() }
pub fn (t &Terminal) cursor() (int, int, bool) { return t.cx, t.cy, t.cursor_hidden }
pub fn (t &Terminal) has_exited() bool { return t.exited }
pub fn (edit &Edit) undo_changes() []Change { return edit.undo.clone() }
pub fn (edit &Edit) redo_changes() []Change { return edit.redo.clone() }
pub fn (edit &Edit) revision_number() u64 { return edit.revision }
