module vtk

// Keep the last user-arranged geometry separately from the applied geometry.
// Reusing it avoids rounding drift and restores windows after a tiny terminal.
struct WindowLayout {
	area Rect
mut:
	applied_area Rect
	windows      []WindowPlacement
}

struct WindowPlacement {
	window       &Ctl
	desktop_id   int
	rect         Rect
	participates bool
	min_w        int
	min_h        int
	max_w        int
	max_h        int
mut:
	applied Rect
}

fn (w &Ctl) joins_window_layout() bool {
	return !w.minimized && !w.hidden && !w.maximized
}

fn (layout &WindowLayout) matches(windows []&Ctl, area Rect) bool {
	if layout.applied_area != area { return false }
	mut count := 0
	for w in windows {
		if w.closed { continue }
		count++
		mut found := false
		for p in layout.windows {
			if p.window != w { continue }
			if p.desktop_id != w.desktop_id || p.applied != w.rect() || p.participates != w.joins_window_layout()
				|| p.min_w != w.min_w || p.min_h != w.min_h
				|| p.max_w != w.max_w || p.max_h != w.max_h {
				return false
			}
			found = true
			break
		}
		if !found { return false }
	}
	return count == layout.windows.len
}

fn (mut app App) resize_windows(old_area Rect) {
	if !app.window_layout.matches(app.windows, old_area) {
		mut placements := []WindowPlacement{}
		for w in app.windows {
			if w.closed { continue }
			placements << WindowPlacement{
				window:       w
				desktop_id:   w.desktop_id
				rect:         w.rect()
				applied:      w.rect()
				participates: w.joins_window_layout()
				min_w:        w.min_w
				min_h:        w.min_h
				max_w:        w.max_w
				max_h:        w.max_h
			}
		}
		app.window_layout = WindowLayout{ area: old_area, windows: placements }
	}
	area := app.work_area()
	for vertical in [false, true] {
		for desktop_id in 1 .. app.desktop_count + 1 {
			app.window_layout.resize_desktop_axis(area, vertical, desktop_id)
		}
	}
	app.fit_windows()
	app.window_layout.applied_area = area
	for mut p in app.window_layout.windows { p.applied = p.window.rect() }
}

fn window_axis(r Rect, vertical bool) (int, int) {
	return if vertical { r.y, r.h } else { r.x, r.w }
}

struct WindowEdgeJoin {
	a       int
	b       int
	overlap int
}

fn (layout &WindowLayout) resize_desktop_axis(area Rect, vertical bool, desktop_id int) {
	origin, size := window_axis(area, vertical)
	old_origin, old_size := window_axis(layout.area, vertical)
	if old_size <= 0 || size <= 0 { return }
	placements := layout.windows.filter(it.participates && it.desktop_id == desktop_id)
	if placements.len == 0 { return }
	n := placements.len * 2 + 1 // Node zero is the workspace origin.
	mut attached := []bool{len: n}
	mut joins := []WindowEdgeJoin{}
	for i, p in placements {
		start, span := window_axis(p.rect, vertical)
		attached[i * 2 + 1] = start == old_origin
		attached[i * 2 + 2] = start + span == old_origin + old_size
	}
	for i, p in placements {
		start, span := window_axis(p.rect, vertical)
		across, across_span := window_axis(p.rect, !vertical)
		for j, q in placements {
			if i == j { continue }
			next, _ := window_axis(q.rect, vertical)
			other, other_span := window_axis(q.rect, !vertical)
			overlap := start + span - next
			// Accept adjacent frames and frames sharing one border cell.
			if overlap !in [0, 1] || across >= other + other_span
				|| other >= across + across_span {
				continue
			}
			a, b := i * 2 + 2, j * 2 + 1
			attached[a] = true
			attached[b] = true
			joins << WindowEdgeJoin{a, b, overlap}
		}
	}
	mut limits := [][]int{len: n, init: []int{len: n, init: window_edge_infinity}}
	mut target := []int{len: n}
	mut active := []bool{len: n}
	for i in 0 .. n { limits[i][i] = 0 }
	for i, p in placements {
		a, b := i * 2 + 1, i * 2 + 2
		start, span := window_axis(p.rect, vertical)
		if !attached[a] && !attached[b] {
			// Preserve the ratio of opposite margins without scaling the window.
			old_gap := old_size - span
			target[a] = if old_gap > 0 {
				int((i64(clamp(start - old_origin, 0, old_gap)) * max(0, size - span)
					+ old_gap / 2) / old_gap)
			} else {
				0
			}
			target[b] = target[a] + span
			continue
		}
		active[a] = true
		active[b] = true
		target[a] = int(i64(start - old_origin) * size / old_size)
		target[b] = int(i64(start + span - old_origin) * size / old_size)
		if !attached[a] { target[a] = target[b] - span }
		if !attached[b] { target[b] = target[a] + span }
		low := if vertical {
			max(minimum_window_height, p.min_h)
		} else {
			max(minimum_window_width, p.min_w)
		}
		high := if vertical { p.max_h } else { p.max_w }
		mut upper := if high > 0 { high } else { size }
		// One anchored edge moves the window without enlarging it.
		if !attached[a] || !attached[b] { upper = min(upper, max(low, span)) }
		window_edge_limit(mut limits, 0, a, 0, size)
		window_edge_limit(mut limits, 0, b, 0, size)
		window_edge_limit(mut limits, a, b, low, upper)
		if start == old_origin { window_edge_limit(mut limits, 0, a, 0, 0) }
		if start + span == old_origin + old_size { window_edge_limit(mut limits, 0, b, size, size) }
	}
	for join in joins { window_edge_limit(mut limits, join.b, join.a, join.overlap, join.overlap) }
	positions := window_edge_positions(mut limits, target, active, attached)
	for i, p in placements {
		a, b := i * 2 + 1, i * 2 + 2
		mut w := p.window
		if vertical {
			w.y = origin + positions[a]
			w.h = positions[b] - positions[a]
		} else {
			w.x = origin + positions[a]
			w.w = positions[b] - positions[a]
		}
	}
}

const window_edge_infinity = 1_000_000_000

// limits[a][b] is the upper bound on position[b] - position[a].
fn window_edge_limit(mut limits [][]int, a int, b int, low int, high int) {
	limits[a][b] = min(limits[a][b], high)
	limits[b][a] = min(limits[b][a], -low)
}

fn window_edge_positions(mut limits [][]int, target []int, active []bool, attached []bool) []int {
	n := limits.len
	// Propagate size limits through all shared edges before choosing positions.
	for k in 0 .. n {
		for a in 0 .. n {
			if limits[a][k] == window_edge_infinity { continue }
			for b in 0 .. n {
				if limits[k][b] == window_edge_infinity { continue }
				limits[a][b] = min(limits[a][b], limits[a][k] + limits[k][b])
				// A negative cycle means the requested bounds conflict.
				// Fall back to fit_window's size limits; the saved layout will
				// recover on a later resize with enough space.
				if a == b && limits[a][b] < 0 { return target }
			}
		}
	}
	mut positions := target.clone()
	// Choose shared/anchored borders first, then the free edges of docked windows.
	for anchored in [true, false] {
		for node in 1 .. n {
			if !active[node] || attached[node] != anchored { continue }
			position := clamp(target[node], -limits[node][0], limits[0][node])
			positions[node] = position
			window_edge_fix(mut limits, 0, node, position)
			window_edge_fix(mut limits, node, 0, -position)
		}
	}
	return positions
}

// Adding one bound to a closed distance matrix needs only one quadratic pass.
fn window_edge_fix(mut limits [][]int, from int, to int, bound int) {
	if bound >= limits[from][to] { return }
	for a in 0 .. limits.len {
		if limits[a][from] == window_edge_infinity { continue }
		for b in 0 .. limits.len {
			if limits[to][b] == window_edge_infinity { continue }
			limits[a][b] = min(limits[a][b], limits[a][from] + bound + limits[to][b])
		}
	}
}
