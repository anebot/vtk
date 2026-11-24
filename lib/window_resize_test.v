module vtk

import math

fn resize_test_window(mut app App, name string, r Rect) &Ctl {
	mut w := app.window(name, r.w, r.h)
	w.x = r.x
	w.y = r.y
	w.w = r.w
	w.h = r.h
	return w
}

fn test_terminal_resize_preserves_side_tiles_without_rounding_drift() {
	for bar_top in [false, true] {
		mut app := new_app()
		app.width = 101
		app.height = 40
		app.bar_top = bar_top
		mut left := app.window('Left', 30, 10)
		mut right := app.window('Right', 30, 10)
		app.tile_side(mut left, .left)
		app.tile_side(mut right, .right)
		original_left, original_right := left.rect(), right.rect()
		for _ in 0 .. 4 {
			for dimensions in [[137, 53], [99, 37], [101, 40]] {
				app.dispatch(Event{ kind: .resize, width: dimensions[0], height: dimensions[1] })
				app.redraw()
				area := app.work_area()
				assert left.x == 0 && left.x + left.w == right.x
				assert right.x + right.w == area.w
				assert left.y == area.y && right.y == area.y
				assert left.h == area.h && right.h == area.h
			}
			assert left.rect() == original_left && right.rect() == original_right
		}
		// Minimum sizes take precedence while the terminal is too small.
		app.dispatch(Event{ kind: .resize, width: 12, height: 2 })
		app.redraw()
		assert left.w >= 16 && right.w >= 16 && left.h >= 3 && right.h >= 3
		app.dispatch(Event{ kind: .resize, width: 101, height: 40 })
		assert left.rect() == original_left && right.rect() == original_right
	}
}

fn test_tile_grid_uses_remainder_cells_and_keeps_shared_edges_on_resize() {
	mut app := new_app()
	app.width = 101
	app.height = 40
	app.bar_top = true
	for i in 0 .. 6 { app.window('Tile ${i}', 20, 6) }
	app.tile()
	original := app.windows.map(it.rect())
	for dimensions in [[101, 40], [149, 57], [83, 24], [101, 40]] {
		app.dispatch(Event{ kind: .resize, width: dimensions[0], height: dimensions[1] })
		app.redraw()
		area := app.work_area()
		for row in 0 .. 2 {
			for col in 0 .. 3 {
				w := app.windows[row * 3 + col]
				if col == 0 {
					assert w.x == 0
				}
				if col == 2 {
					assert w.x + w.w == area.w
				}
				if col < 2 {
					assert w.x + w.w == app.windows[row * 3 + col + 1].x
				}
				if row == 0 {
					assert w.y == area.y
					assert w.y + w.h == app.windows[3 + col].y
				} else {
					assert w.y + w.h == area.y + area.h
				}
			}
		}
	}
	assert app.windows.map(it.rect()) == original
}

fn test_terminal_resize_detects_manually_arranged_t_junctions() {
	mut app := new_app()
	app.desktop = false
	app.width = 101
	app.height = 30
	left := resize_test_window(mut app, 'Left', Rect{0, 0, 31, 30})
	top := resize_test_window(mut app, 'Top right', Rect{31, 0, 70, 12})
	bottom := resize_test_window(mut app, 'Bottom right', Rect{31, 12, 70, 18})
	app.dispatch(Event{ kind: .resize, width: 137, height: 44 })
	assert left.rect() == Rect{0, 0, 42, 44}
	assert top.rect() == Rect{42, 0, 95, 17}
	assert bottom.rect() == Rect{42, 17, 95, 27}
	app.dispatch(Event{ kind: .resize, width: 101, height: 30 })
	assert left.rect() == Rect{0, 0, 31, 30}
	assert top.rect() == Rect{31, 0, 70, 12}
	assert bottom.rect() == Rect{31, 12, 70, 18}
}

fn test_terminal_resize_keeps_shared_border_cells() {
	mut app := new_app()
	app.desktop = false
	app.width = 101
	app.height = 30
	left := resize_test_window(mut app, 'Left', Rect{0, 0, 51, 30})
	right := resize_test_window(mut app, 'Right', Rect{50, 0, 51, 30})
	for width in [137, 138, 79, 101] {
		app.dispatch(Event{ kind: .resize, width: width, height: 30 })
		assert left.x == 0 && left.x + left.w - 1 == right.x
		assert right.x + right.w == width
	}
	assert left.rect() == Rect{0, 0, 51, 30}
	assert right.rect() == Rect{50, 0, 51, 30}
}

fn test_terminal_resize_moves_shared_edges_to_respect_size_limits() {
	mut app := new_app()
	app.desktop = false
	app.width = 100
	app.height = 30
	mut left := resize_test_window(mut app, 'Left', Rect{0, 0, 50, 30})
	right := resize_test_window(mut app, 'Right', Rect{50, 0, 50, 30})
	left.set_size_limits(50, 3, 60, 0)
	app.dispatch(Event{ kind: .resize, width: 90, height: 30 })
	assert left.rect() == Rect{0, 0, 50, 30}
	assert right.rect() == Rect{50, 0, 40, 30}
	app.dispatch(Event{ kind: .resize, width: 200, height: 30 })
	assert left.rect() == Rect{0, 0, 60, 30}
	assert right.rect() == Rect{60, 0, 140, 30}
	app.dispatch(Event{ kind: .resize, width: 100, height: 30 })
	assert left.rect() == Rect{0, 0, 50, 30}
	assert right.rect() == Rect{50, 0, 50, 30}
}

fn test_terminal_resize_preserves_docked_size_and_proportional_floating_margins() {
	mut app := new_app()
	app.desktop = false
	app.width = 101
	app.height = 30
	mut docked := resize_test_window(mut app, 'Docked', Rect{76, 22, 25, 8})
	floating := resize_test_window(mut app, 'Floating', Rect{5, 5, 20, 5})
	app.dispatch(Event{ kind: .resize, width: 137, height: 44 })
	assert docked.rect() == Rect{112, 36, 25, 8}
	assert floating.rect() == Rect{7, 8, 20, 5}
	// Raising a window changes stacking order, not the saved layout.
	app.raise(mut docked)
	app.dispatch(Event{ kind: .resize, width: 101, height: 30 })
	assert docked.rect() == Rect{76, 22, 25, 8}
	assert floating.rect() == Rect{5, 5, 20, 5}
	// User placement breaks the old attachments before the next resize.
	docked.x = 60
	docked.y = 10
	app.dispatch(Event{ kind: .resize, width: 137, height: 44 })
	assert docked.rect() == Rect{88, 16, 25, 8}
	assert floating.rect() == Rect{7, 8, 20, 5}
}

fn test_terminal_resize_keeps_floating_windows_centered_without_resizing() {
	for desktop in [false, true] {
		for bar_top in [false, true] {
			mut app := new_app()
			app.desktop = desktop
			app.bar_top = bar_top
			app.width = 100
			app.height = 40 + int(desktop)
			area := app.work_area()
			w := resize_test_window(mut app, 'Centered', Rect{40, area.y + 15, 20, 10})
			original := w.rect()
			for _ in 0 .. 4 {
				for dimensions in [[140, 60], [99, 37], [60, 20], [100, 40]] {
					app.dispatch(Event{ kind: .resize, width: dimensions[0],
						height: dimensions[1] + int(desktop) })
					app.redraw()
					current := app.work_area()
					assert w.w == 20 && w.h == 10
					assert math.abs((w.x - current.x) * 2 - (current.w - w.w)) <= 1
					assert math.abs((w.y - current.y) * 2 - (current.h - w.h)) <= 1
				}
				assert w.rect() == original
			}
			// A temporarily tiny terminal must not replace the saved placement.
			app.dispatch(Event{ kind: .resize, width: 12, height: 2 })
			assert w.w == 16 && w.h == 3
			app.dispatch(Event{ kind: .resize, width: 100, height: 40 + int(desktop) })
			assert w.rect() == original
		}
	}
}

fn test_terminal_resize_preserves_floating_margins_on_each_unattached_axis() {
	mut app := new_app()
	app.desktop = false
	app.width = 100
	app.height = 40
	left := resize_test_window(mut app, 'Left', Rect{0, 15, 20, 10})
	top := resize_test_window(mut app, 'Top', Rect{40, 0, 20, 10})
	app.dispatch(Event{ kind: .resize, width: 140, height: 60 })
	assert left.rect() == Rect{0, 25, 20, 10}
	assert top.rect() == Rect{60, 0, 20, 10}
	app.dispatch(Event{ kind: .resize, width: 100, height: 40 })
	assert left.rect() == Rect{0, 15, 20, 10}
	assert top.rect() == Rect{40, 0, 20, 10}
}

fn test_terminal_resize_propagates_size_limits_through_a_chain_of_tiles() {
	mut app := new_app()
	app.desktop = false
	app.width = 100
	app.height = 30
	mut left := resize_test_window(mut app, 'Left', Rect{0, 0, 40, 30})
	mut middle := resize_test_window(mut app, 'Middle', Rect{40, 0, 30, 30})
	mut right := resize_test_window(mut app, 'Right', Rect{70, 0, 30, 30})
	left.set_size_limits(30, 3, 45, 0)
	middle.set_size_limits(25, 3, 40, 0)
	right.set_size_limits(20, 3, 0, 0)
	app.dispatch(Event{ kind: .resize, width: 75, height: 30 })
	assert left.rect() == Rect{0, 0, 30, 30}
	assert middle.rect() == Rect{30, 0, 25, 30}
	assert right.rect() == Rect{55, 0, 20, 30}
	app.dispatch(Event{ kind: .resize, width: 180, height: 30 })
	assert left.rect() == Rect{0, 0, 45, 30}
	assert middle.rect() == Rect{45, 0, 40, 30}
	assert right.rect() == Rect{85, 0, 95, 30}
	app.dispatch(Event{ kind: .resize, width: 100, height: 30 })
	assert left.rect() == Rect{0, 0, 40, 30}
	assert middle.rect() == Rect{40, 0, 30, 30}
	assert right.rect() == Rect{70, 0, 30, 30}
}
