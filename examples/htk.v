// Port of examples/htk.hc: tabs, bounded entry, groups and a notes window.
module main

import vtk

fn confirm_quit(mut app vtk.App) { app.confirm_quit() }

fn second_window(mut app vtk.App) {
	mut window := app.window('Notes', 34, 10)
	mut note := vtk.multiline('The temple\nis clean.\n')
	note.line_numbers = true
	note.wrap = true
	note.scrollbar = true
	window.dismissable = true
	window.add(mut note)
	app.raise(mut window)
	app.set_focus(note)
}

fn access_code_submit(mut code vtk.Ctl, mut app vtk.App) {
	app.notify(if code.text == 'temple' { 'Access code accepted' } else { 'Invalid access code' }, 2000)
}

fn open_notes(mut button vtk.Ctl, mut app vtk.App) {
	if button.link.text == 'temple' {
		second_window(mut app)
	} else {
		app.notify('Invalid access code', 2500)
	}
}

fn demo_start(mut app vtk.App, _ voidptr) {
	mut window := app.window('V TermKit', 46, 16)
	mut body := vtk.box(true)
	mut tabs := vtk.tabs()
	mut general := vtk.box(true)
	mut check := vtk.checkbox('Bless this machine', true)
	general.add(mut check)
	mut code := vtk.entry('', 8)
	code.low = 20
	code.submit = access_code_submit
	mut frame := vtk.group('Access code')
	frame.add(mut code)
	general.add(mut frame)
	mut notes := vtk.button('Open notes')
	notes.link = code
	notes.changed = open_notes
	general.add(mut notes)
	tabs.add_tab('General', mut general)
	mut about := vtk.box(true)
	mut text := vtk.label('An offering,\nrendered in cells.')
	about.add(mut text)
	tabs.add_tab('About', mut about)
	body.add(mut tabs)
	window.add(mut body)
	window.layout(window.rect())
	app.set_focus(code)
}

fn main() {
	mut app := vtk.new_app()
	app.init() or {
		eprintln(err)
		return
	}
	defer { app.fini() }
	if !app.settings_saved() { app.theme = vtk.theme_preset(.teal) }
	app.ctrl_c = .callback
	app.ctrl_c_handler = confirm_quit
	app.register('V TermKit', demo_start, unsafe { nil })
	demo_start(mut app, unsafe { nil })
	app.run() or { eprintln(err) }
	println('bye')
}
