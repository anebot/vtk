module desktop

import vtk
import vtk.app.programs.calc
import vtk.app.programs.clock
import vtk.app.programs.files
import vtk.app.programs.paint
import vtk.app.programs.slides
import vtk.app.programs.word
import vtk.app.spread

fn clock_clicked(event vtk.Event, mut app vtk.App) {
	if event.button == .left {
		clock.open_or_raise(mut app)
	}
}

pub fn register(mut app vtk.App) {
	app.clock_clicked = clock_clicked
	app.register('Word', word.launch)
	app.register('Slides', slides.launch)
	app.register('Spread', spread.launch)
	app.register('Paint', paint.launch)
	app.register('Calc', calc.launch)
	app.register('Clock', clock.open_or_raise)
	app.register('Files', files.launch)
}
