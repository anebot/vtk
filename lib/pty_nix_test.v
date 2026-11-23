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
