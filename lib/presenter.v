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

const tty_setup = '\x1b[?1049h\x1b[?25l\x1b[?1002h\x1b[?1004h\x1b[?1006h\x1b[?2004h\x1b[2J'

fn tty_restore(conservative bool) string {
	shape := if conservative { '' } else { '\x1b[0 q' }
	return '\x1b[0m\x1b[?2004l\x1b[?1006l\x1b[?1004l\x1b[?1003l\x1b[?1002l' + shape + '\x1b[?25h\x1b[?1049l'
}
