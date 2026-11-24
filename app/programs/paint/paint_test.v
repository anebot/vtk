module paint

import vtk

fn test_paint_windows_follow_desktop_cascade() {
	mut app := vtk.new_app()
	defer { app.fini() }
	app.dispatch(vtk.Event{kind: .resize, width: 120, height: 40})
	first := new_drawing(mut app)
	second := new_drawing(mut app)
	assert second.window.rect().y > first.window.rect().y
}

fn test_undo_redo_preserve_points_and_new_stroke_discards_redo() {
	mut app := vtk.new_app()
	defer { app.fini() }
	app.dispatch(vtk.Event{kind: .resize, width: 100, height: 30})
	drawing := new_drawing(mut app)
	app.redraw()
	bounds := drawing.canvas.rect()
	x, y := bounds.x + 1, bounds.y + 1
	app.dispatch(vtk.Event{kind: .mouse, x: x, y: y, button: .left, pressed: true})
	app.dispatch(vtk.Event{kind: .mouse, x: x + 2, y: y, button: .left, pressed: true, motion: true})
	app.dispatch(vtk.Event{kind: .mouse, x: x + 2, y: y, button: .left})
	assert drawing.strokes.len == 1
	assert drawing.strokes[0].points == [Point{1, 1}, Point{3, 1}]
	undo := vtk.Event{key: int(`z`), ctrl: true}
	redo := vtk.Event{key: int(`y`), ctrl: true}
	app.dispatch(undo)
	assert drawing.strokes.len == 0
	app.dispatch(redo)
	assert drawing.strokes.len == 1
	assert drawing.strokes[0].points == [Point{1, 1}, Point{3, 1}]
	app.dispatch(vtk.Event{kind: .mouse, x: x, y: y + 1, button: .left, pressed: true})
	app.dispatch(undo)
	app.dispatch(vtk.Event{kind: .mouse, x: x + 1, y: y + 1, button: .left, pressed: true,
		motion: true})
	app.dispatch(vtk.Event{kind: .mouse, x: x + 1, y: y + 1, button: .left})
	app.dispatch(redo)
	assert drawing.strokes.len == 2
	assert drawing.strokes[0].points == [Point{1, 1}, Point{3, 1}]
	assert drawing.strokes[1].points == [Point{2, 2}]
}
