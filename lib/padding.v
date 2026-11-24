module vtk

import math { max }

// Insets are terminal cells: columns horizontally and rows vertically.
pub struct Insets {
pub mut:
	left int
	right int
	top int
	bottom int
}

fn padded_extent(size int, before int, after int) int {
	total := i64(max(0, size)) + max(0, before) + max(0, after)
	return if total > 0x7fffffff { 0x7fffffff } else { int(total) }
}

// Clamp each side to the available allocation, including when padding consumes
// the entire widget. Negative insets act as zero.
pub fn (r Rect) inset(p Insets) Rect {
	w, h := max(0, r.w), max(0, r.h)
	left, top := clamp(p.left, 0, w), clamp(p.top, 0, h)
	right, bottom := clamp(p.right, 0, w - left), clamp(p.bottom, 0, h - top)
	return Rect{r.x + left, r.y + top, w - left - right, h - top - bottom}
}

pub fn (mut c Ctl) set_padding(padding Insets) bool {
	if c.destroyed { return false }
	c.padding = padding
	c.invalidate()
	return true
}

// rect() is the allocation; content_rect() is the inset drawing/input area.
// Window padding belongs to the client area, leaving its frame and menu intact.
pub fn (c &Ctl) content_rect() Rect {
	if c.kind == .window {
		menus := int(c.kids.any(it.kind == .menu && !it.hidden))
		return Rect{c.x + 1, c.y + 1 + menus, max(0, c.w - 2), max(0, c.h - 2 - menus)}.inset(c.padding)
	}
	return Rect{c.x, c.y, c.w, c.h}
}

fn (mut c Ctl) layout_bounds(r Rect) {
	outer := Rect{r.x, r.y, max(0, r.w), max(0, r.h)}
	inner := if c.kind == .window { outer } else { outer.inset(c.padding) }
	c.padding_used = Insets{left: inner.x - outer.x, top: inner.y - outer.y,
		right: outer.w - (inner.x - outer.x) - inner.w,
		bottom: outer.h - (inner.y - outer.y) - inner.h}
	c.x, c.y, c.w, c.h = inner.x, inner.y, inner.w, inner.h
}

// Fill the whole allocation with the widget's own background before restricting
// painting to its inset area. Callers restore their incoming screen clip.
fn (mut app App) fill_ctl(c &Ctl, fg int, bg int) {
	app.screen.fill(c.rect(), ` `, fg, bg)
	app.screen.set_clip(c.content_rect())
}
