module vtk

// Match the visible panes used by layout without allocating a child array on
// every mouse report. Standalone separators have no panes to resize.
fn (c &Ctl) split_panes() ?(&Ctl, &Ctl) {
	mut first := ?&Ctl(none)
	for child in c.kids {
		if child.hidden || child.kind == .menu { continue }
		if previous := first { return previous, child }
		first = child
	}
	return none
}

fn (c &Ctl) split_divider() Rect {
	first, _ := c.split_panes() or { return Rect{} }
	bounds := first.rect()
	return if c.vertical {
		Rect{c.x, bounds.y + bounds.h, c.w, 1}
	} else {
		Rect{bounds.x + bounds.w, c.y, 1, c.h}
	}
}

fn (mut c Ctl) resize_split(e Event) {
	first, second := c.split_panes() or { return }
	space := (if c.vertical { c.h } else { c.w }) - 1
	low := max(if c.vertical { first.min_h } else { first.min_w },
		padded_extent(1, if c.vertical { first.padding.top } else { first.padding.left }, if c.vertical { first.padding.bottom } else { first.padding.right }))
	high := space - max(if c.vertical { second.min_h } else { second.min_w },
		padded_extent(1, if c.vertical { second.padding.top } else { second.padding.left }, if c.vertical { second.padding.bottom } else { second.padding.right }))
	if low > high { return }
	keep := clamp(if c.vertical { e.y - c.y } else { e.x - c.x }, low, high)
	if keep == (if c.vertical { first.rect().h } else { first.rect().w }) { return }
	// Convert cells to the existing thousandths ratio. Constrain the ratio
	// itself too, so rounding in large splits respects both pane minimums.
	min_share := max(1, (low * 1000 + space - 1) / space)
	max_share := min(999, ((high + 1) * 1000 - 1) / space)
	if min_share > max_share { return }
	share := clamp((keep * 1000 + space - 1) / space, min_share, max_share)
	if share == c.value { return }
	c.value = share
	c.layout(c.rect())
	c.fire()
}
