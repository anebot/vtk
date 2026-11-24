module vtk

fn (mut app App) draw_tabs(mut c Ctl, fg int, bg int) {
	padding_clip := app.screen.set_clip(c.content_rect())
	defer { app.screen.restore_clip(padding_clip) }
	app.screen.fill(Rect{c.x, c.y, c.w, 1}, ` `, fg, bg)
	app.screen.frame(Rect{c.x, c.y + 1, c.w, c.h - 1}, false, app.theme.dim, bg)
	clip := app.screen.set_clip(Rect{c.x + 1, c.y, max(0, c.w - 2), 2})
	dragging := c.reorderable && app.drag != none && app.drag.kind == .tabpage
		&& same_ctl(app.drag.parent, &c) && c.kids.index(app.drag) == c.value
	for i, page in c.kids {
		if dragging && same_ctl(app.drag, page) { continue }
		app.draw_tab_header(c, page, page.tab_x, i == c.value, fg, bg)
	}
	// Paint the grabbed header last, following the pointer at its grab offset.
	// Its logical slot stays in the layout so neighbouring tabs can reflow live.
	if dragging {
		if page := app.drag {
			x := clamp(app.drag_start.x + app.mouse_x - app.drag_x, c.x + 1, c.x + c.w - page.tab_w - 1)
			app.draw_tab_header(c, page, x, true, fg, bg)
		}
	}
	app.screen.restore_clip(clip)
	for mut page in c.kids {
		if !page.hidden { app.draw_ctl(mut page) }
	}
}

fn (mut app App) draw_tab_header(c &Ctl, page &Ctl, x int, selected bool, fg int, bg int) {
	if page.tab_w < 4 { return }
	t := app.theme
	tab_fg := if selected && !c.disabled { t.accent } else { t.dim }
	attr := if selected { bold } else { 0 }
	app.screen.fill(Rect{x, c.y, page.tab_w, 1}, ` `, tab_fg, bg)
	app.screen.put(x, c.y, `╭`, tab_fg, bg, attr)
	app.screen.aligned_text(x + 2, c.y, page.tab_w - 4, page.text, .left, tab_fg, bg, attr)
	app.screen.put(x + page.tab_w - 1, c.y, `╮`, tab_fg, bg, attr)
	if selected {
		// The open bottom joins the selected tab to its page.
		app.screen.fill(Rect{x + 1, c.y + 1, page.tab_w - 2, 1}, ` `, fg, bg)
		app.screen.put(x, c.y + 1, `╯`, t.dim, bg, 0)
		app.screen.put(x + page.tab_w - 1, c.y + 1, `╰`, t.dim, bg, 0)
	} else {
		app.screen.put(x, c.y + 1, `┴`, t.dim, bg, 0)
		app.screen.put(x + page.tab_w - 1, c.y + 1, `┴`, t.dim, bg, 0)
	}
}

fn (mut c Ctl) drag_tab(page &Ctl, e Event) {
	if e.y < c.y || e.y >= c.y + 2 || e.x <= c.x || e.x >= c.x + c.w - 1 { return }
	from := c.kids.index(page)
	if from < 0 || from != c.value { return }
	mut to := from
	// At a clipped strip edge, advance into the neighbouring offscreen slot.
	if e.x == c.x + 1 && from > 0
		&& c.kids[from - 1].tab_x + c.kids[from - 1].tab_w / 2 <= e.x {
		to--
	} else if e.x == c.x + c.w - 2 && from < c.kids.len - 1
		&& c.kids[from + 1].tab_x + c.kids[from + 1].tab_w / 2 >= e.x {
		to++
	} else {
		for i, target in c.kids {
			if e.x < target.tab_x || e.x >= target.tab_x + target.tab_w { continue }
			// Cross the midpoint before moving, so unequal widths do not make
			// tabs swap back and forth under a stationary pointer.
			if (i > from && e.x >= target.tab_x + target.tab_w / 2)
				|| (i < from && e.x < target.tab_x + target.tab_w / 2) { to = i }
			break
		}
	}
	if to == from { return }
	c.kids.delete(from)
	c.kids.insert(to, page)
	c.value = to
	c.layout(c.rect())
	c.invalidate()
	if mut app := c.root().app {
		if f := c.reordered { f(mut c, from, to, mut app) }
	}
}
