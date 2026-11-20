module vtk

import time

fn test_pty_shell_output_and_cleanup() {
	mut pty := spawn_pty(40, 8) or { panic(err) }
	defer { pty.close() }
	assert pty.write("printf 'vtk-pty-ok\\n'; exit\r") > 0
	mut output := ''
	deadline := time.ticks() + 3000
	for time.ticks() < deadline {
		output += pty.read(4096)
		if !pty.alive() {
			output += pty.read(4096)
			break
		}
		time.sleep(5 * time.millisecond)
	}
	assert output.contains('vtk-pty-ok')
	assert !pty.alive()
	pty.close()
	assert pty.fd == -1
}
