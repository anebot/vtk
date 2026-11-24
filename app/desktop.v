// VTK Desktop: a small Start menu shell for the bundled applications.
module main

import os
import vtk

fn project_root() string {
	mut starts := [os.getwd()]
	exe := os.executable()
	if exe != '' {
		starts << os.dir(exe)
	}
	for start in starts {
		mut directory := start
		for {
			if os.exists(os.join_path(directory, 'v.mod'))
				&& os.is_dir(os.join_path(directory, 'app')) {
				return directory
			}
			parent := os.dir(directory)
			if parent == directory {
				break
			}
			directory = parent
		}
	}
	return os.getwd()
}

fn launch_source(mut app vtk.App, title string, binary string, source string) {
	root := project_root()
	mut window := app.terminal_window(directory: root, title: title) or {
		app.notify(err.msg(), 3000)
		return
	}
	app.maximize(mut window)
	binary_path := os.join_path(root, 'build', binary)
	command := if os.exists(binary_path) {
		os.quoted_path(binary_path)
	} else {
		'v run ' + os.quoted_path(os.join_path(root, source))
	}
	children := window.children()
	if children.len > 0 {
		if mut term := children[0].terminal_state() {
			term.write(command + '\n')
		}
	}
}

fn launch_word(mut app vtk.App, _ voidptr) {
	launch_source(mut app, 'Word', 'word', 'app/word.v')
}

fn launch_slides(mut app vtk.App, _ voidptr) {
	launch_source(mut app, 'Slides', 'slides', 'app/slides.v')
}

fn launch_spread(mut app vtk.App, _ voidptr) {
	launch_source(mut app, 'Spread', 'spreadsheet', 'app/spread.v')
}

fn launch_paint(mut app vtk.App, _ voidptr) {
	launch_source(mut app, 'Paint', 'paint', 'app/paint.v')
}

fn main() {
	mut app := vtk.new_app()
	app.start_programs = true
	app.ctrl_c = .quit
	snapshot := '--snapshot' in os.args
	if snapshot {
		app.dispatch(vtk.Event{ kind: .resize, width: 100, height: 30 })
	} else {
		app.init() or {
			eprintln(err)
			return
		}
	}
	defer { app.fini() }
	app.register('Word', launch_word, unsafe { nil })
	app.register('Slides', launch_slides, unsafe { nil })
	app.register('Spread', launch_spread, unsafe { nil })
	app.register('Paint', launch_paint, unsafe { nil })
	if snapshot {
		_, height := app.size()
		app.app_menu(0, height - 1)
		app.dispatch(vtk.Event{ key: int(vtk.Key.right) })
		app.redraw()
		println(app.snapshot())
		return
	}
	app.notify('Click Start or press Alt-S. Programs lists Word, Slides, Spread, Paint and Terminal.', 6000)
	app.run() or { eprintln(err) }
}
