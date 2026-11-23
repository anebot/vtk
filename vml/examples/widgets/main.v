module main

import time
import vtk

fn today() time.Time { return time.now() }

fn table_cell(_ &vtk.Ctl, row int, col int) string {
	number := row + 1
	return if col == 0 { number.str() } else { (number * number).str() }
}

fn paint_gradient(mut canvas vtk.Ctl, mut screen vtk.Screen) {
	level := canvas.link or { return }
	bounds := canvas.rect()
	x_span := if bounds.w > 1 { bounds.w - 1 } else { 1 }
	y_span := if bounds.h > 1 { bounds.h - 1 } else { 1 }
	for y in 0 .. bounds.h {
		for x in 0 .. bounds.w {
			color := vtk.color_rgb(x * 255 / x_span, y * 255 / y_span, level.value * 255 / 100)
			screen.put(bounds.x + x, bounds.y + y, ` `, color, color, 0)
		}
	}
}

fn main() {
	mut app := vtk.new_app()
	build_ui(mut app)
	app.run() or { eprintln(err) }
}
