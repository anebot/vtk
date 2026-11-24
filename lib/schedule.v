module vtk

import time

fn (c &Ctl) sources_changed() {
	if mut app := c.root().app { app.sources_dirty = true }
}

fn (mut app App) update_sources() {
	if !app.sources_dirty { return }
	app.sources_dirty = false
	app.terminals, app.spinners = [], []
	for window in app.windows { app.collect_sources(window) }
}

fn (mut app App) collect_sources(c &Ctl) {
	if c.closed { return }
	if term := c.term {
		if !term.exited { app.terminals << c }
	}
	if c.kind == .spinner { app.spinners << c }
	for child in c.kids { app.collect_sources(child) }
}

fn (app &App) wait_time(max_wait int) int {
	now := time.ticks()
	mut wait := max_wait
	if app.event_index < app.events.len { return 0 }
	if app.needs_frame() && !app.driver.output_busy() {
		wait = limit_wait(wait, app.next_frame - now)
	}
	for hook in app.hooks { wait = limit_wait(wait, hook.due - now) }
	for notice in app.notices {
		if notice.due > 0 { wait = limit_wait(wait, notice.due - now) }
	}
	if app.bar_clock && app.bar_clock_rect().w > 0 {
		wait = limit_wait(wait, 60000 - time.now().unix_milli() % 60000)
	}
	for spinner in app.spinners {
		if app.spinner_rect(spinner).w > 0 {
			period := app.animation_period()
			wait = limit_wait(wait, period - now % period)
			break
		}
	}
	if app.input.buffer == '\x1b' {
		wait = limit_wait(wait, app.input.escape_at + 30 - now)
	}
	if !app.driver.active {
		// Memory run can receive timers but has no terminal input to wait on.
		return limit_wait(wait, 50)
	}
	return wait
}

fn limit_wait(current int, delay i64) int {
	ms := int(if delay > 0x7fffffff {
		i64(0x7fffffff)
	} else if delay < 0 {
		i64(0)
	} else {
		delay
	})
	return if current < 0 { ms } else { min(current, ms) }
}
