module desktop

import vtk
import vtk.app.programs.calc
import vtk.app.programs.clock
import vtk.app.programs.files
import vtk.app.programs.paint
import vtk.app.programs.slides
import vtk.app.programs.word
import vtk.app.spread

fn open_clock(mut app vtk.App) {
	windows := app.window_list()
	for i, window in windows {
		if window.text == 'VTK Clock' && !window.is_closed() {
			mut existing := windows[i]
			app.raise(mut existing)
			return
		}
	}
	clock.launch(mut app)
}

fn launch_clock(mut app vtk.App) {
	open_clock(mut app)
}

fn clock_clicked(event vtk.Event, mut app vtk.App) {
	if event.button == .left {
		open_clock(mut app)
	}
}

pub fn register(mut app vtk.App) {
	app.clock_clicked = clock_clicked
	app.register('Word', word.launch)
	app.register('Slides', slides.launch)
	app.register('Spread', spread.launch)
	app.register('Paint', paint.launch)
	app.register('Calc', calc.launch)
	app.register('Clock', launch_clock)
	app.register('Files', files.launch)
}
