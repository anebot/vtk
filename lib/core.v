module vtk

import time

pub enum Kind {
	window
	box
	grid
	label
	button
	entry
	checkbox
	slider
	progress
	separator
	canvas
	menu
	menuitem
	combo
	radio
	spin
	multiline
	group
	tabs
	tabpage
	toolbar
	status
	split
	scroll
	table
	tree
	treenode
	item
	popup
	terminal
	switch
	spinner
	toolbutton
	flow
	markdown
	date_picker
}

pub enum CtrlC {
	quit
	ignore
	copy
	callback
}

pub enum CursorShape {
	default_shape
	block
	bar
}

pub enum TextSyntax {
	plain
	diff
}

pub enum TextAlign {
	left
	center
	right
}

pub const window_menu = 1
pub const window_minimize = 2
pub const window_maximize = 4
pub const window_close = 8
pub const window_default_controls = 15

pub type Callback = fn (mut Ctl, mut App)
pub type KeyCallback = fn (mut Ctl, Event, mut App) bool
pub type ScrollCallback = fn (mut Ctl, int, mut App) bool
pub type CloseCallback = fn (mut Ctl, mut App) bool
pub type CellCallback = fn (&Ctl, int, int) string
pub type PaintCallback = fn (mut Ctl, mut Screen)

// Ctl is the shared control model. Positions are zero-based terminal cells;
// editor positions are UTF-8 byte offsets, just as in HTK.
@[heap]
pub struct Ctl {
pub mut:
	kind          Kind
	parent        &Ctl = unsafe { nil }
	kids          []&Ctl
	link          &Ctl = unsafe { nil }
	selected_node &Ctl = unsafe { nil }
	default_button &Ctl = unsafe { nil }
	popup_owner   &Ctl = unsafe { nil }
	menu          &Ctl = unsafe { nil }
	modal         bool
	modal_owner   &Ctl = unsafe { nil }
	text          string
	text_align    TextAlign
	changed       ?Callback
	submit        ?Callback
	keyfn         ?KeyCallback
	scrollfn      ?ScrollCallback
	closing       ?CloseCallback
	destroy       ?Callback
	cellfn        ?CellCallback
	paint         ?PaintCallback
	mousefn       ?KeyCallback
	mouse_enter   ?Callback
	mouse_leave   ?Callback
	hovered       bool
	user          voidptr
	data          i64
	value         int
	expanded      bool
	dialog_result int
	blocky        bool
	desktop_id    int = 1
	low           int
	high          int
	byte_limit    int
	row_count     int
	top           int
	left          int
	cursor        int
	anchor        int = -1
	x             int
	y             int
	w             int
	h             int
	pw            int
	ph            int
	min_w         int
	min_h         int
	max_w         int
	max_h         int
	col           int
	row           int
	tab_x         int
	tab_w         int
	vertical      bool
	right         bool
	bottom        bool
	expand        bool
	focusable     bool
	disabled      bool
	hidden        bool
	secret        bool
	line_numbers  bool
	wrap          bool
	syntax        TextSyntax
	scrollbar     bool
	scroll_hold   bool
	readonly      bool
	closed        bool
	minimized     bool
	maximized     bool
	always_on_top bool
	dismissable   bool
	controls      int         = window_default_controls
	cursor_shape  CursorShape = .bar
	saved         Rect
	edit          &Edit = &Edit{}
	md            Markdown
	vim           Vim
	term          &Terminal = unsafe { nil }
mut:
	// Only roots (windows and standalone menus) retain the owning app.
	app           &App = unsafe { nil }
	modal_parent  &Ctl = unsafe { nil }
	window_order  int
	date_value    time.Time
}

pub struct Rect {
pub mut:
	x int
	y int
	w int
	h int
}

pub fn (r Rect) contains(x int, y int) bool {
	return r.w > 0 && r.h > 0 && x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

pub fn (c &Ctl) rect() Rect {
	return Rect{c.x, c.y, c.w, c.h}
}

pub fn new_ctl(kind Kind) &Ctl {
	return &Ctl{ kind: kind }
}

fn (c &Ctl) can_adopt(child &Ctl) bool {
	mut ancestor := unsafe { c }
	for !isnil(ancestor) {
		if ancestor == child { return false }
		ancestor = ancestor.parent
	}
	return true
}

// add reparents a control and rejects cycles rather than corrupting the tree.
pub fn (mut c Ctl) add(mut child Ctl) {
	if !c.can_adopt(&child) { return }
	child.detach()
	child.parent = c
	c.kids << &child
	c.invalidate()
}

pub fn (mut c Ctl) detach() {
	c.invalidate()
	mut app := c.root().app
	if !isnil(app) { app.clear_hover_within(&c) }
	if !isnil(c.parent) {
		if c.parent.menu == &c { c.parent.menu = unsafe { nil } }
		for i, child in c.parent.kids {
			if child == &c {
				c.parent.kids.delete(i)
				break
			}
		}
	}
	c.parent = unsafe { nil }
	c.app = unsafe { nil }
}

pub fn (c &Ctl) owner_window() &Ctl {
	mut p := unsafe { c }
	for !isnil(p) && p.kind != .window { p = p.parent }
	return p
}

pub fn (mut c Ctl) set_text(text string) {
	c.text = text
	c.cursor = boundary(text, clamp(c.cursor, 0, text.len))
	c.anchor = -1
	c.edit.reset()
	c.invalidate()
}

// root resolves ownership dynamically so entire subtrees can be reparented.
fn (c &Ctl) root() &Ctl {
	mut root := unsafe { c }
	for !isnil(root.parent) { root = root.parent }
	return root
}

// Detached controls and nil dialog owners are allowed; foreign roots are not.
fn (app &App) can_access(c &Ctl) bool {
	if isnil(c) { return true }
	owner := c.root().app
	return isnil(owner) || owner == app
}

// invalidate schedules a redraw without emitting a changed callback.
// Detached controls have no app and can be configured safely.
pub fn (c &Ctl) invalidate() {
	mut app := c.root().app
	if !isnil(app) { app.dirty = true }
}

pub fn (mut c Ctl) fire() {
	mut app := c.root().app
	if isnil(app) { return }
	app.dirty = true
	if f := c.changed { f(mut c, mut app) }
}

pub fn (c &Ctl) visible() bool {
	mut p := unsafe { c }
	for !isnil(p) {
		if p.hidden || p.closed || p.minimized || p.disabled { return false }
		if p.kind == .window && !isnil(p.app) && !p.app.on_desktop(p) { return false }
		p = p.parent
	}
	return true
}

pub struct Notice {
pub mut:
	text   string
	due    i64
	closed bool
	rect   Rect
}

pub struct Launcher {
pub:
	name  string
	start fn (mut App, voidptr) = fn (mut app App, data voidptr) {}
	data  voidptr
}

struct Hook {
mut:
	id       int
	due      i64
	interval int
	call     fn (mut App) = fn (mut app App) {}
}

// App owns the desktop and event loop. Separate Apps can be used headlessly;
// only one may own a physical terminal at a time.
@[heap]
pub struct App {
pub mut:
	windows          []&Ctl
	focus            &Ctl = unsafe { nil }
	popups           []&Ctl
	notices          []&Notice
	launchers        []Launcher
	theme            Theme = theme_default()
	screen           Screen
	running          bool = true
	dirty            bool = true
	width            int  = 80
	height           int  = 24
	desktop          bool = true
	desktop_count    int = 1
	active_desktop   int = 1
	bar_always       bool = true
	bar_top          bool
	bar_clock        bool = true
	clock_clicked    ?fn (Event, mut App)
	window_shadow    bool = true
	dim_inactive     bool = true
	title_gradient   bool
	macos_buttons    bool
	vim_mode         bool
	touch_titles     bool
	ctrl_c           CtrlC
	ctrl_c_handler   ?fn (mut App)
	native_clipboard bool
	mouse_motion     bool = true
	mouse_cursor     MouseCursor
	move_key         Binding = Binding{ key: int(Key.f7), alt: true }
	resize_key       Binding = Binding{ key: int(Key.f8), alt: true }
mut:
	clipboard        string
	hooks            []Hook
	next_hook        int
	driver           Driver
	input            Input
	events           []Event
	last_clock       i64
	last_animation   i64
	ctrl_c_active    bool
	started          bool
	drag             &Ctl = unsafe { nil }
	drag_mode        int
	scroll_drag      &Ctl = unsafe { nil }
	scroll_total     int
	scroll_view      int
	drag_start       Rect
	drag_x           int
	drag_y           int
	title_click      &Ctl = unsafe { nil }
	title_click_at   i64
	title_click_x    int
	title_click_y    int
	placement        &Ctl = unsafe { nil }
	placement_resize bool
	placement_start  Rect
	window_layout    WindowLayout
	desktop_focus    [4]&Ctl
	settings_path    string
	bar_offset       int
	next_window_order int
	app_popup        &Ctl = unsafe { nil }
	popup_at_bar     bool
	mouse_x          int = -1
	mouse_y          int = -1
	hover            &Ctl = unsafe { nil }
	updating_hover   bool
	terminal_focused bool = true
}

pub fn new_app() &App {
	return &App{}
}

pub fn clamp(n int, low int, high int) int {
	return max(low, min(n, max(low, high)))
}

pub fn (mut app App) after(ms int, call fn (mut App)) int {
	return app.add_hook(ms, 0, call)
}

pub fn (mut app App) every(ms int, call fn (mut App)) int {
	return app.add_hook(max(1, ms), max(1, ms), call)
}

fn (mut app App) add_hook(ms int, interval int, call fn (mut App)) int {
	app.next_hook++
	app.hooks << Hook{app.next_hook, time.ticks() + max(0, ms), interval, call}
	return app.next_hook
}

pub fn (mut app App) cancel_hook(id int) {
	app.hooks = app.hooks.filter(it.id != id)
}

fn (mut app App) tick() {
	now := time.ticks()
	// Remove or reschedule before calling: callbacks may add/cancel hooks.
	due := app.hooks.filter(it.due <= now)
	for hook in due {
		if !app.hooks.any(it.id == hook.id) { continue }
		app.cancel_hook(hook.id)
		if hook.interval > 0 {
			app.hooks << Hook{hook.id, now + hook.interval, hook.interval, hook.call}
		}
		hook.call(mut app)
	}
	for mut notice in app.notices {
		if notice.due > 0 && now >= notice.due {
			notice.closed = true
			app.dirty = true
		}
	}
	app.notices = app.notices.filter(!it.closed)
	if app.bar_clock && now / 60000 != app.last_clock {
		app.last_clock = now / 60000
		app.dirty = true
	}
	if now / 125 != app.last_animation {
		app.last_animation = now / 125
		for w in app.windows {
			if app.on_desktop(w) && has_spinner(w) {
				app.dirty = true
				break
			}
		}
	}
	for mut w in app.windows { app.pump_terminals(mut w) }
}

fn min(a int, b int) int { return if a < b { a } else { b } }

fn max(a int, b int) int { return if a > b { a } else { b } }

fn abs(a int) int { return if a < 0 { -a } else { a } }

fn has_spinner(c &Ctl) bool {
	if c.hidden || c.closed || c.minimized { return false }
	if c.kind == .spinner { return true }
	for child in c.kids { if has_spinner(child) { return true } }
	return false
}
