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
	chart
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

// ControlContext carries a typed reference for control callbacks.
pub interface ControlContext {}

pub type Callback = fn (mut Ctl, mut App)
pub type KeyCallback = fn (mut Ctl, Event, mut App) bool
pub type ScrollCallback = fn (mut Ctl, int, mut App) bool
pub type CloseCallback = fn (mut Ctl, mut App) bool
pub type CellCallback = fn (&Ctl, int, int) string
pub type PaintCallback = fn (mut Ctl, mut Screen)
pub type OverlayCallback = fn (mut App, mut Screen)
pub type TabReorderCallback = fn (mut Ctl, int, int, mut App)

// Ctl is the shared control model. Positions are zero-based terminal cells;
// editor positions are UTF-8 byte offsets, just as in HTK.
@[heap]
pub struct Ctl {
pub:
	kind          Kind
pub mut:
	link          ?&Ctl
	text          string
	text_align    TextAlign
	padding       Insets
	changed       ?Callback
	reordered     ?TabReorderCallback
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
	data          i64
	value         int
	expanded      bool
	dialog_result int
	blocky        bool
	low           int
	high          int
	byte_limit    int
	row_count     int
	top           int
	left          int
	cursor        int
	anchor        int = -1
	min_w         int
	min_h         int
	max_w         int
	max_h         int
	col           int
	row           int
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
	reorderable   bool
	resizable     bool
	dismissable   bool
	// A custom mousefn keeps receiving motion and the release after it consumes
	// a left press, so drags can continue outside the control.
	mouse_capture bool
	controls      int         = window_default_controls
	cursor_shape  CursorShape = .bar
	edit          &Edit = &Edit{}
	md            Markdown
	vim           Vim
	table         Table
	chart         Chart
mut:
	callback_context ?ControlContext
	parent        ?&Ctl
	kids          []&Ctl
	selected_node ?&Ctl
	default_button ?&Ctl
	popup_owner   ?&Ctl
	menu          ?&Ctl
	modal         bool
	modal_owner   ?&Ctl
	hovered       bool
	desktop_id    int = 1
	x             int
	y             int
	w             int
	h             int
	pw            int
	ph            int
	tab_x         int
	tab_w         int
	wrap_words    bool
	padding_used  Insets
	editor_cache  ?&EditorRowsCache
	intrinsic_w   int
	intrinsic_h   int
	closed        bool
	closing_now   bool
	destroyed     bool
	minimized     bool
	maximized     bool
	always_on_top bool
	saved         Rect
	term          ?&Terminal
	// Only roots (windows and standalone menus) retain the owning app.
	app           ?&App
	modal_parent  ?&Ctl
	window_order  int
	date_value    time.Time
	click_time    i64
	click_count   int
	click_x       int
	click_y       int
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
	return Rect{c.x - c.padding_used.left, c.y - c.padding_used.top,
		c.w + c.padding_used.left + c.padding_used.right,
		c.h + c.padding_used.top + c.padding_used.bottom}
}

pub fn new_ctl(kind Kind) &Ctl {
	return &Ctl{ kind: kind }
}

// Format the control without following its parent, children or owning app.
pub fn (c &Ctl) str() string {
	return 'Ctl{kind: ${c.kind}, text: ${c.text}}'
}

// set_context attaches shared callback state by reference.
pub fn (mut c Ctl) set_context(context ControlContext) {
	c.callback_context = context
}

// context returns the attached state when its type matches T.
@[inline]
pub fn (c &Ctl) context[T]() ?&T {
	context := c.callback_context or { return none }
	if context is T { return context }
	return none
}

fn (c &Ctl) can_adopt(child &Ctl) bool {
	return !c.destroyed && !child.destroyed && child.kind != .window && !child.contains_ctl(c)
}

// Controls are handles. Compare their addresses even inside optional references.
@[inline]
pub fn (a &Ctl) == (b &Ctl) bool {
	return voidptr(a) == voidptr(b)
}

@[inline]
fn same_ctl(a ?&Ctl, b ?&Ctl) bool {
	first := a or { return b == none }
	second := b or { return false }
	return first == second
}

@[inline]
fn same_app(owner ?&App, app &App) bool {
	current := owner or { return false }
	return current == app
}

fn (c &Ctl) contains_ctl(child ?&Ctl) bool {
	mut next := child
	for {
		node := next or { return false }
		if node == c { return true }
		next = node.parent
	}
}

// add reparents a control and rejects cycles rather than corrupting the tree.
pub fn (mut c Ctl) add(mut child Ctl) {
	if !c.can_adopt(&child) { return }
	child.detach()
	if !c.can_adopt(&child) { return }
	child.parent = c
	c.kids << &child
	c.sources_changed()
	c.invalidate()
}

pub fn (mut c Ctl) detach() {
	c.invalidate()
	owner := c.root().app
	if mut app := owner {
		app.sources_dirty = true
		app.release_ctl(&c)
	}
	mut next := c.parent
	for {
		mut ancestor := next or { break }
		if c.contains_ctl(ancestor.selected_node) { ancestor.selected_node = none }
		if c.contains_ctl(ancestor.default_button) { ancestor.default_button = none }
		next = ancestor.parent
	}
	if mut parent := c.parent {
		if same_ctl(parent.menu, &c) { parent.menu = none }
		at := parent.kids.index(&c)
		if at >= 0 { parent.kids.delete(at) }
	}
	if mut term := c.term { term.standalone_window = none }
	c.parent = none
	c.app = none
	if mut app := owner {
		if c.kind == .window {
			at := app.windows.index(&c)
			if at >= 0 { app.windows.delete(at) }
			app.window_layout = WindowLayout{}
		}
		if app.focus == none { app.focus_first(app.top_window()) }
	}
}

// clear detaches children; use App.destroy_ctl when their resources must close.
pub fn (mut c Ctl) clear() {
	for mut child in c.kids.clone() { child.detach() }
	c.selected_node = none
	c.invalidate()
}

pub fn (mut c Ctl) replace(mut child Ctl, mut replacement Ctl) bool {
	if !same_ctl(child.parent, &c) || c.kids.index(&child) < 0 || !c.can_adopt(&replacement) { return false }
	if &child == &replacement { return true }
	replacement.detach()
	at := c.kids.index(&child)
	if at < 0 { return false }
	child.detach()
	if !c.can_adopt(&replacement) || replacement.parent != none { return false }
	replacement.parent = &c
	c.kids.insert(clamp(at, 0, c.kids.len), &replacement)
	c.sources_changed()
	c.invalidate()
	return true
}

pub fn (c &Ctl) owner_window() ?&Ctl {
	mut node := &Ctl(c)
	for node.kind != .window {
		node = node.parent or { return none }
	}
	return node
}

pub fn (mut c Ctl) set_text(text string) {
	cursor := boundary(text, clamp(c.cursor, 0, text.len))
	changed := c.text != text || cursor != c.cursor || (c.anchor >= 0 && c.anchor != c.cursor)
	mut paint_only := c.kind in [.entry, .multiline, .markdown]
	if changed && c.kind == .label {
		old_width, old_height := label_size(c.text)
		new_width, new_height := label_size(text)
		paint_only = old_width == new_width && old_height == new_height
	}
	if cache := c.editor_cache {
		if !text.starts_with(cache.key.text) { c.editor_cache = none }
	}
	c.text = text
	c.cursor = cursor
	c.anchor = -1
	c.edit.reset()
	if !changed { return }
	if paint_only { c.invalidate_paint() } else { c.invalidate() }
}

// root resolves ownership dynamically so entire subtrees can be reparented.
fn (c &Ctl) root() &Ctl {
	mut root := &Ctl(c)
	for { root = root.parent or { return root } }
}

// Detached controls are accessible; roots owned by another app are not.
fn (app &App) can_access(c &Ctl) bool {
	owner := c.root().app or { return true }
	return owner == app
}

// invalidate schedules a redraw without emitting a changed callback.
// Detached controls have no app and can be configured safely.
pub fn (c &Ctl) invalidate() {
	if mut app := c.root().app { app.dirty = true }
}

pub fn (mut c Ctl) fire() {
	mut app := c.root().app or { return }
	if f := c.changed {
		app.dirty = true
		f(mut c, mut app)
	} else if c.kind in [.entry, .multiline, .markdown, .table, .slider, .spin, .progress, .checkbox, .switch, .radio, .date_picker, .tree] {
		c.invalidate_paint()
	} else {
		app.dirty = true
	}
}

pub fn (c &Ctl) visible() bool {
	mut p := &Ctl(c)
	for {
		if p.hidden || p.closed || p.minimized || p.disabled { return false }
		if p.kind == .window && p.app != none && !p.app.on_desktop(p) { return false }
		p = p.parent or { return true }
	}
}

pub struct Notice {
pub mut:
	text   string
mut:
	due    i64
	closed bool
	rect   Rect
}

pub struct Launcher {
pub:
	name  string
	start fn (mut App) = fn (mut _ App) {}
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
	theme            Theme = theme_default()
	rendering        RenderOptions
	overlay          ?OverlayCallback
	desktop          bool = true
	bar_always       bool = true
	bar_top          bool
	bar_clock        bool = true
	start_programs   bool
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
	windows          []&Ctl
	focus            ?&Ctl
	popups           []&Ctl
	notices          []&Notice
	launchers        []Launcher
	screen           Screen
	running          bool = true
	dirty            bool = true
	damage           PaintDamage
	cursor_dirty     bool
	width            int  = 80
	height           int  = 24
	desktop_count    int = 1
	active_desktop   int = 1
	clipboard        string
	hooks            []Hook
	next_hook        int
	driver           Driver
	input            Input
	events           []Event
	event_index      int
	terminals        []&Ctl
	spinners         []&Ctl
	sources_dirty    bool = true
	last_clock       i64
	last_animation   i64
	next_frame       i64
	ctrl_c_active    bool
	started          bool
	quitting         bool
	finishing        bool
	drag             ?&Ctl
	drag_mode        int
	scroll_drag      ?&Ctl
	scroll_total     int
	scroll_view      int
	drag_start       Rect
	drag_x           int
	drag_y           int
	tab_drag_last_x  int
	tab_drag_last_y  int
	title_click      ?&Ctl
	title_click_at   i64
	title_click_x    int
	title_click_y    int
	placement        ?&Ctl
	placement_resize bool
	placement_start  Rect
	window_layout    WindowLayout
	desktop_focus    [4]?&Ctl
	settings_path    string
	bar_offset       int
	next_window_order int
	app_popup        ?&Ctl
	popup_at_bar     bool
	mouse_x          int = -1
	mouse_y          int = -1
	hover            ?&Ctl
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
	for i, hook in app.hooks {
		if hook.id == id { app.hooks.delete(i); return }
	}
}

fn (mut app App) tick() {
	now := time.ticks()
	// Remove or reschedule before calling: callbacks may add/cancel hooks.
	due := if app.hooks.any(it.due <= now) { app.hooks.filter(it.due <= now) } else { []Hook{} }
	for hook in due {
		if !app.hooks.any(it.id == hook.id) { continue }
		app.cancel_hook(hook.id)
		if hook.interval > 0 {
			app.hooks << Hook{hook.id, now + hook.interval, hook.interval, hook.call}
		}
		hook.call(mut app)
	}
	for i := app.notices.len - 1; i >= 0; i-- {
		mut notice := app.notices[i]
		if notice.closed || (notice.due > 0 && now >= notice.due) {
			notice.closed = true
			app.notices.delete(i)
			app.dirty = true
		}
	}
	clock := app.bar_clock_rect()
	if clock.w > 0 {
		minute := time.now().unix_milli() / 60000
		if minute != app.last_clock {
			app.last_clock = minute
			app.invalidate_area(clock)
		}
	}
	period := app.animation_period()
	if now / period != app.last_animation {
		app.last_animation = now / period
		for spinner in app.spinners { app.invalidate_area(app.spinner_rect(spinner)) }
	}
}

fn min(a int, b int) int { return if a < b { a } else { b } }

fn max(a int, b int) int { return if a > b { a } else { b } }

fn abs(a int) int { return if a < 0 { -a } else { a } }
