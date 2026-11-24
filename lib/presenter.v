@[has_globals]
module vtk

// RenderBackend selects the presenter. All presenters share the same layout,
// drawing code and cell buffer.
pub enum RenderBackend {
	ansi
	conservative
	memory
}

// RenderOptions can be configured before App.init or App.run. The slow
// terminal profile reduces background animation, mouse traffic and frame rate.
@[params]
pub struct RenderOptions {
pub:
	backend       RenderBackend
	slow_terminal bool
}

fn (app &App) needs_frame() bool { return app.dirty || app.damage.count > 0 || app.cursor_dirty }

fn (app &App) animation_period() i64 {
	return if app.rendering.slow_terminal { 500 } else { 125 }
}

const tty_mouse_drag = '\x1b[?1002h'
const tty_mouse_all = '\x1b[?1003h'
const tty_mouse_drag_off = '\x1b[?1002l'
const tty_mouse_all_off = '\x1b[?1003l'
const tty_setup = '\x1b[?1049h\x1b[?25l\x1b[?1006h\x1b[?1004h\x1b[?2004h\x1b[2J' + tty_mouse_drag

fn tty_restore(conservative bool, pointer string) string {
	shape := if conservative { '' } else { '\x1b[0 q' }
	// Stop reports before changing their encoding or returning to the normal screen.
	return tty_mouse_all_off + tty_mouse_drag_off + '\x1b[?1004l\x1b[?2004l\x1b[?1006l' +
		'\x1b[0m' + shape + '\x1b[?1049l\x1b[?25h' + pointer
}

@[params]
struct TtyWriteOptions {
	discard_on_stop bool
}

__global (
	active_driver = ?&Driver(none)
	tty_exit_registered bool
)

fn terminal_on_exit() {
	if mut driver := active_driver { driver.stop() }
}

fn (mut d Driver) start() ! {
	if active_driver != none { return error('another VTK app owns this terminal') }
	if !tty_exit_registered {
		at_exit(terminal_on_exit)!
		tty_exit_registered = true
	}
	d.start_platform()!
	d.active = true
	d.eof = false
	d.interrupted = false
	d.resumed = false
	d.mouse_motion = false
	d.pointer = MousePointer{}
	active_driver = &d
	d.output(tty_setup, discard_on_stop: true)
}

fn (mut d Driver) stop() {
	if !d.active { return }
	d.stop_platform()
	d.active = false
	active_driver = none
}
