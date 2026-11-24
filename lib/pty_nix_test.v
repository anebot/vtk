module vtk

import io.util
import os
import time

fn test_pty_shell_output_and_cleanup() {
	mut pty := spawn_pty(40, 8, '') or { panic(err) }
	defer { pty.close() }
	assert pty.write("printf 'vtk-pty-ok\\n'; exit\r") > 0
	output := terminal_test_output(mut pty)
	assert output.split_into_lines().contains('vtk-pty-ok')
	assert !pty.alive()
	pty.close()
	assert pty.fd == -1
}

fn test_terminal_mouse_reports_reach_the_pty_child() ! {
	directory := util.temp_dir(pattern: 'vtk-mouse-')!
	defer { os.rmdir_all(directory) or {} }
	shell := os.join_path(directory, 'mouse-shell')
	os.write_file(shell, '#!/bin/sh\nstty raw -echo\nprintf "\\033[?1000;1006h"\ndd bs=1 count=28 2>/dev/null | od -An -tx1 | tr -d " \\n"\n')!
	os.chmod(shell, 0o755)!
	previous_shell := os.getenv_opt('SHELL')
	os.setenv('SHELL', shell, true)
	defer {
		if value := previous_shell { os.setenv('SHELL', value, true) } else { os.unsetenv('SHELL') }
	}
	mut app := new_app()
	app.desktop = false
	mut window := app.window('Terminal', 24, 10)
	mut c := terminal(10, 3)!
	defer { c.term.close() }
	window.add(mut c)
	app.redraw()
	deadline := time.ticks() + 3000
	for c.term.mouse_mode == 0 && time.ticks() < deadline {
		app.pump_terminal(mut c)
		time.sleep(5 * time.millisecond)
	}
	assert c.term.mouse_mode == 1000 && c.term.mouse_sgr
	app.dispatch(Event{kind: .mouse, x: c.x, y: c.y, button: .left, pressed: true})
	app.dispatch(Event{kind: .mouse, x: c.x, y: c.y, button: .left})
	app.dispatch(Event{kind: .mouse, x: c.x, y: c.y, button: .wheel_down, pressed: true})
	assert terminal_test_output(mut c.term.pty) == '1b5b3c303b313b314d1b5b3c303b313b316d1b5b3c36353b313b314d'
}

fn test_pty_reads_reuse_storage_and_return_independent_strings() {
	mut pipe := [2]i32{}
	assert C.pipe(&pipe[0]) == 0
	defer { C.close(pipe[1]) }
	mut pty := Pty{fd: pipe[0], reaped: true}
	defer { pty.close() }
	assert C.write(pipe[1], c'abcd', 4) == 4
	first := pty.read(4)
	storage := pty.read_buffer.data
	assert C.write(pipe[1], c'efgh', 4) == 4
	assert pty.read(4) == 'efgh' && pty.read_buffer.data == storage
	assert first == 'abcd'
	assert C.write(pipe[1], c'12345678', 8) == 8
	assert pty.read(8) == '12345678' && pty.read_buffer.len == 8 && first == 'abcd'
	pty.close()
	assert pty.fd == -1 && pty.read_buffer.cap == 0
}

fn terminal_test_output(mut pty Pty) string {
	mut output := ''
	deadline := time.ticks() + 3000
	for time.ticks() < deadline {
		output += pty.read(4096)
		if !pty.alive() {
			output += pty.read(4096)
			return output
		}
		time.sleep(5 * time.millisecond)
	}
	assert false, 'shell did not exit: ${output}'
	return output
}

fn test_terminal_options_start_shells_in_independent_directories() ! {
	directory := util.temp_dir(pattern: 'vtk-terminal-')!
	defer { os.rmdir_all(directory) or {} }
	worktree := os.join_path(directory, "topic ' with spaces 界")
	os.mkdir(worktree)!
	shell := os.join_path(directory, 'test shell')
	os.write_file(shell, '#!/bin/sh\nprintf "VTK-CWD:"\npwd -P\n')!
	os.chmod(shell, 0o755)!
	previous_shell := os.getenv_opt('SHELL')
	os.setenv('SHELL', shell, true)
	defer {
		if value := previous_shell { os.setenv('SHELL', value, true) } else { os.unsetenv('SHELL') }
	}
	cwd := os.getwd()
	mut app := new_app()
	mut first := app.terminal_window(directory: worktree, title: 'Shell: topic')!
	defer { app.close(mut first) }
	mut second := app.terminal_window(directory: directory, title: 'Shell: main')!
	defer { app.close(mut second) }
	assert first.text == 'Shell: topic' && second.text == 'Shell: main'
	assert os.getwd() == cwd
	assert terminal_test_output(mut first.kids[0].term.pty).trim_space() == 'VTK-CWD:${os.real_path(worktree)}'
	assert terminal_test_output(mut second.kids[0].term.pty).trim_space() == 'VTK-CWD:${os.real_path(directory)}'
	mut inherited := app.terminal_window()!
	defer { app.close(mut inherited) }
	assert inherited.text == 'Terminal'
	assert terminal_test_output(mut inherited.kids[0].term.pty).trim_space() == 'VTK-CWD:${os.real_path(cwd)}'
	mut embedded := terminal(40, 8, directory: '.')!
	defer { embedded.term.close() }
	assert terminal_test_output(mut embedded.term.pty).trim_space() == 'VTK-CWD:${os.real_path(cwd)}'
	assert app.close(mut first)
	assert first.kids[0].term.pty.fd == -1
	assert os.getwd() == cwd
}

fn test_terminal_startup_errors_leave_no_window_or_changed_directory() ! {
	directory := util.temp_dir(pattern: 'vtk-terminal-errors-')!
	defer { os.rmdir_all(directory) or {} }
	file := os.join_path(directory, 'file')
	os.write_file(file, '')!
	cwd := os.getwd()
	mut app := new_app()
	for invalid in [os.join_path(directory, 'missing'), file, directory + '\x00suffix'] {
		if _ := app.terminal_window(directory: invalid) {
			assert false, 'invalid directory was accepted: ${invalid}'
		}
		assert app.windows.len == 0 && isnil(app.focus)
		assert os.getwd() == cwd
	}
	previous_shell := os.getenv_opt('SHELL')
	os.setenv('SHELL', os.join_path(directory, 'missing-shell'), true)
	defer {
		if value := previous_shell { os.setenv('SHELL', value, true) } else { os.unsetenv('SHELL') }
	}
	if _ := app.terminal_window(directory: directory) { assert false, 'missing shell was accepted' }
	assert app.windows.len == 0 && isnil(app.focus)
	assert os.getwd() == cwd
}

fn test_window_lifecycle_paths_close_live_terminal_processes() {
	previous_shell := os.getenv_opt('SHELL')
	os.setenv('SHELL', '/bin/sh', true)
	defer {
		if value := previous_shell { os.setenv('SHELL', value, true) } else { os.unsetenv('SHELL') }
	}
	actions := [
		fn (mut app App, mut w Ctl) { assert app.close(mut w) },
		fn (mut app App, mut w Ctl) { app.destroy_ctl(mut w) },
		fn (mut app App, mut _ Ctl) { app.quit() },
		fn (mut app App, mut _ Ctl) { app.fini() },
	]
	for action in actions {
		mut app := new_app()
		mut w := app.window('Shell', 30, 8)
		mut control := terminal(10, 2, TerminalOptions{}) or { panic(err) }
		defer { control.term.close() }
		w.add(mut control)
		assert control.term.pty.alive()
		action(mut app, mut w)
		assert control.term.has_exited() && control.term.pty.fd == -1 && !control.term.pty.alive()
		app.fini()
	}
}
