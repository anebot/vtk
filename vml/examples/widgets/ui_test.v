module main

import time
import vtk

fn test_widget_gallery_links_values_and_reports_selections() {
	mut app := vtk.new_app()
	defer { app.fini() }
	window := build_ui(mut app)
	body := window.children()[0].children()
	mut tabs := body[0]
	pages := tabs.children()
	controls := pages[0].children()[0].children()
	toggle := controls[0].children()[0]
	grid := controls[1].children()
	mut level := grid[1]
	mut amount := grid[3]
	progress := controls[3]
	activity := controls[4]
	data := pages[1].children()[0].children()
	tree := data[0]
	mut table := data[1]
	calendar_page := pages[2].children()[0].children()
	mut next_week := calendar_page[0].children()[0]
	mut calendar := calendar_page[1]
	mut scroll := pages[3].children()[0]
	canvas := scroll.children()[0].children()[1]
	status := body[1]
	assert level.value == 40 && amount.value == 40 && progress.value == 40
	app.set_focus(level)
	app.dispatch(vtk.Event{ key: int(vtk.Key.end) })
	assert level.value == 100 && amount.value == 100 && progress.value == 100
	amount.set_value(25)
	assert level.value == 25 && progress.value == 25
	assert status.text.starts_with('Level: 25%')
	app.set_focus(toggle)
	app.dispatch(vtk.Event{ key: int(vtk.Key.space) })
	assert level.disabled && amount.disabled && progress.disabled && canvas.disabled
	assert activity.hidden && status.text == 'Controls disabled'
	app.dispatch(vtk.Event{ key: int(vtk.Key.space) })
	assert !level.disabled && !activity.hidden
	tabs.set_value(1)
	app.layout()
	app.set_focus(tree)
	app.dispatch(vtk.Event{ key: int(vtk.Key.down) })
	assert status.text == 'Tree: Controls'
	app.set_focus(table)
	app.dispatch(vtk.Event{ key: int(vtk.Key.end) })
	assert table.value == 99 && status.text == 'Table: 100 squared is 10000'
	tabs.set_value(2)
	app.layout()
	calendar.set_date(time.Time{ year: 2020, month: 2, day: 29 })
	assert status.text == 'Selected date: 2020-02-29'
	next_week.fire()
	assert calendar.text == '2020-03-07' && status.text == 'Selected date: 2020-03-07'
	assert app.focused_ctl() == ?&vtk.Ctl(calendar)
	tabs.set_value(3)
	app.redraw()
	assert app.scroll_ctl(mut scroll, 3) && scroll.top == 3
	app.redraw()
	bounds := canvas.rect()
	app.dispatch(vtk.Event{ kind: .mouse, x: bounds.x + bounds.w - 1, y: scroll.rect().y + 1,
		button: .left, pressed: true })
	assert level.value == 100 && amount.value == 100 && progress.value == 100
	tabs.set_value(4)
	app.redraw()
	assert app.snapshot().contains('Quarterly sales')
	assert app.snapshot().contains('Q4')
}
