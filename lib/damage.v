module vtk

fn (r Rect) intersection(q Rect) Rect {
	x, y := max(r.x, q.x), max(r.y, q.y)
	return Rect{x, y, max(0, min(r.x + r.w, q.x + q.w) - x), max(0, min(r.y + r.h, q.y + q.h) - y)}
}

fn (s &Screen) paints(r Rect) bool {
	return r.w > 0 && r.h > 0 && r.y < s.paint_end && r.y + r.h > s.paint_y
}

// Most frames affect only a few rows. Use fixed storage and merge overlapping
// bands. If they fragment, a wider repaint is cheaper than more bookkeeping.
struct PaintDamage {
mut:
	bands [8]Rect
	count int
}

fn (mut d PaintDamage) add(rect Rect) {
	mut band := rect
	mut i := 0
	for i < d.count {
		other := d.bands[i]
		if band.y > other.y + other.h || other.y > band.y + band.h {
			i++
			continue
		}
		band = join_bands(band, other)
		d.count--
		d.bands[i] = d.bands[d.count]
		i = 0
	}
	if d.count == d.bands.len {
		for j in 0 .. d.count { band = join_bands(band, d.bands[j]) }
		d.count = 0
	}
	d.bands[d.count] = band
	d.count++
}

fn join_bands(a Rect, b Rect) Rect {
	y := min(a.y, b.y)
	return Rect{0, y, a.w, max(a.y + a.h, b.y + b.h) - y}
}

// invalidate_area repaints an area whose layout is unchanged. The compositor
// recomposes affected rows to preserve wide glyphs at layer boundaries.
pub fn (mut app App) invalidate_area(rect Rect) {
	r := rect.intersection(Rect{0, 0, app.width, app.height})
	if r.w > 0 && r.h > 0 { app.damage.add(Rect{0, r.y, app.width, r.h}) }
}

// invalidate_paint redraws a control whose preferred size and layout are unchanged.
pub fn (c &Ctl) invalidate_paint() {
	mut app := c.root().app
	if isnil(app) || !c.is_drawable() { return }
	if app.screen.cells.len == 0 {
		app.dirty = true
		return
	}
	r := app.visible_paint_rect(c)
	if r.w == 0 || r.h == 0 { return }
	w := c.owner_window_ptr()
	if !isnil(w) && app.covered_by_window(app.windows.index(w) + 1, r) { return }
	app.invalidate_area(r)
}

fn (c &Ctl) is_drawable() bool {
	mut p := unsafe { c }
	for !isnil(p) {
		if p.hidden || p.closed || p.minimized { return false }
		if p.kind == .window && !isnil(p.app) && !p.app.on_desktop(p) { return false }
		p = p.parent
	}
	return true
}

fn (app &App) paints_window(w &Ctl) bool {
	return app.on_desktop(w) && !w.closed && !w.minimized && !w.hidden
}

fn (app &App) covered_by_window(first int, visible Rect) bool {
	mut overlapping := 0
	for i in first .. app.windows.len {
		w := app.windows[i]
		if !app.paints_window(w) { continue }
		intersection := w.rect().intersection(visible)
		if intersection == visible { return true }
		if intersection.w > 0 && intersection.h > 0 { overlapping++ }
	}
	if overlapping < 2 { return false }
	// Multiple higher windows can cover a lower window together. Walk their
	// horizontal intervals without allocating an occlusion mask.
	for y in visible.y .. visible.y + visible.h {
		mut left := visible.x
		for left < visible.x + visible.w {
			mut right := left
			for i in first .. app.windows.len {
				w := app.windows[i]
				if app.paints_window(w) && w.rect().contains(left, y) {
					right = max(right, w.x + w.w)
				}
			}
			if left == right { return false }
			left = right
		}
	}
	return true
}

fn (app &App) spinner_rect(spinner &Ctl) Rect {
	if !spinner.is_drawable() { return Rect{} }
	r := spinner.content_rect()
	w := spinner.owner_window_ptr()
	cell := Rect{r.x, r.y, 1, 1}
	if r.w <= 0 || r.h <= 0 || isnil(w) || !app.visible_paint_rect(spinner).contains(r.x, r.y)
		|| app.covered_by_window(app.windows.index(w) + 1, cell) {
		return Rect{}
	}
	return cell
}

fn (app &App) visible_paint_rect(c &Ctl) Rect {
	mut rect := c.rect().intersection(app.work_area())
	mut p := c.parent
	for !isnil(p) && rect.w > 0 && rect.h > 0 {
		rect = rect.intersection(p.content_rect())
		if p.kind == .scroll && p.scrollbar {
			rect = rect.intersection(Rect{p.x, p.y, max(0, p.w - 1), p.h})
		}
		p = p.parent
	}
	return rect
}

fn (mut app App) window_geometry_changed(mut w Ctl, old Rect) {
	if old == w.rect() || !app.paints_window(w) { return }
	// A resize changes widget positions and available space. A move reuses their
	// preferred sizes but still has to apply the new absolute coordinates.
	if old.w != w.w || old.h != w.h { w.measure() }
	w.layout(w.rect())
	shadow := int(app.window_shadow)
	app.invalidate_area(Rect{old.x, old.y, old.w + 2 * shadow, old.h + shadow})
	app.invalidate_area(Rect{w.x, w.y, w.w + 2 * shadow, w.h + shadow})
	app.update_hover()
}
