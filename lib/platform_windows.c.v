module vtk

import term

#include <windows.h>

struct Driver {
mut:
	input        voidptr
	output       voidptr
	input_mode   u32
	output_mode  u32
	active       bool
	mouse_motion bool
	pointer      MousePointer
	eof          bool
	read_buffer  []u8
}

fn (mut d Driver) start() ! {
	d.input = C.GetStdHandle(C.STD_INPUT_HANDLE)
	d.output = C.GetStdHandle(C.STD_OUTPUT_HANDLE)
	if !C.GetConsoleMode(d.input, &d.input_mode) || !C.GetConsoleMode(d.output, &d.output_mode) {
		return error('vtk needs an interactive console')
	}
	if !C.SetConsoleMode(d.input, u32(0x0200)) {
		return error('virtual terminal input is unavailable')
	}
	if !C.SetConsoleMode(d.output, d.output_mode | u32(0x0004)) {
		C.SetConsoleMode(d.input, d.input_mode)
		return error('virtual terminal output is unavailable')
	}
	d.active = true
	d.mouse_motion = false
	d.pointer = MousePointer{}
	print('\x1b[?1049h\x1b[?25l\x1b[?1002h\x1b[?1004h\x1b[?1006h\x1b[?2004h\x1b[2J')
	flush_stdout()
}

fn (mut d Driver) stop() {
	if !d.active { return }
	print(d.pointer.restore() + '\x1b[0m\x1b[?2004l\x1b[?1006l\x1b[?1004l\x1b[?1003l\x1b[?1002l\x1b[0 q\x1b[?25h\x1b[?1049l')
	flush_stdout()
	C.SetConsoleMode(d.input, d.input_mode)
	C.SetConsoleMode(d.output, d.output_mode)
	d.active = false
	d.read_buffer = []
}

fn (mut d Driver) read(timeout int) string {
	if C.WaitForSingleObject(d.input, u32(max(0, timeout))) != 0 { return '' }
	if d.read_buffer.len == 0 { d.read_buffer = []u8{len: 16384} }
	mut n := u32(0)
	if !C.ReadFile(d.input, d.read_buffer.data, u32(d.read_buffer.len), &n, unsafe { nil }) {
		d.eof = true
		return ''
	}
	return d.read_buffer[..int(n)].bytestr()
}

fn (d &Driver) size() (int, int) {
	return term.get_terminal_size()
}
