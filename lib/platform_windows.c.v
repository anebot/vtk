module vtk

import term

#include <windows.h>
#include "@VMODROOT/lib/tty_windows.h"

fn C.FlushConsoleInputBuffer(voidptr) bool
fn C.vtk_console_watch_control(bool) bool
fn C.vtk_console_take_control() int

struct Driver {
mut:
	input        voidptr
	output       voidptr
	input_mode   u32
	output_mode  u32
	active       bool
	mouse_motion bool
	conservative bool
	pointer      MousePointer
	eof          bool
	interrupted  bool
	resumed      bool
	terminals_ready bool
	read_buffer  []u8
}

fn (mut d Driver) start_platform() ! {
	d.input = C.GetStdHandle(C.STD_INPUT_HANDLE)
	d.output = C.GetStdHandle(C.STD_OUTPUT_HANDLE)
	if !C.GetConsoleMode(d.input, &d.input_mode) || !C.GetConsoleMode(d.output, &d.output_mode) {
		return error('vtk needs an interactive console')
	}
	if !C.vtk_console_watch_control(true) { return error('cannot install console control handler') }
	if !C.SetConsoleMode(d.input, u32(C.ENABLE_EXTENDED_FLAGS | C.ENABLE_VIRTUAL_TERMINAL_INPUT)) {
		C.vtk_console_watch_control(false)
		return error('virtual terminal input is unavailable')
	}
	if !C.SetConsoleMode(d.output, d.output_mode | u32(C.ENABLE_PROCESSED_OUTPUT | C.ENABLE_VIRTUAL_TERMINAL_PROCESSING)) {
		C.SetConsoleMode(d.input, d.input_mode)
		C.vtk_console_watch_control(false)
		return error('virtual terminal output is unavailable')
	}
}

fn (mut d Driver) stop_platform() {
	d.output(tty_restore(d.conservative, d.pointer.restore()))
	C.FlushConsoleInputBuffer(d.input)
	C.SetConsoleMode(d.input, d.input_mode)
	C.SetConsoleMode(d.output, d.output_mode)
	C.vtk_console_watch_control(false)
	d.read_buffer = []
}

fn (mut d Driver) read(timeout int, terminals []&Ctl) string {
	// Console mode does not expose resize events or readable pipe events.
	d.terminals_ready = terminals.any(!it.closed && !it.term.exited)
	wait := limit_wait(timeout, if d.terminals_ready { 25 } else { 100 })
	result := C.WaitForSingleObject(d.input, u32(wait))
	control := C.vtk_console_take_control()
	if control & C.VTK_CONSOLE_BREAK != 0 || result == u32(C.WAIT_FAILED) {
		d.eof = true
		return ''
	}
	if control & C.VTK_CONSOLE_INTERRUPT != 0 {
		d.interrupted = true
		return ''
	}
	if result != 0 { return '' }
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

fn (mut d Driver) output(sequence string, _ TtyWriteOptions) {
	if sequence == '' { return }
	print(sequence)
	flush_stdout()
}

fn (d &Driver) output_busy() bool { return false }

fn (mut d Driver) resize_pending() bool { return true }
