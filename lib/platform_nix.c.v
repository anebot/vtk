@[has_globals]
module vtk

import os
import term.termios

#include <unistd.h>
#include <poll.h>
#include <sys/ioctl.h>

struct C.pollfd {
	fd      int
	events  i16
	revents i16
}

struct C.winsize {
	ws_row    u16
	ws_col    u16
	ws_xpixel u16
	ws_ypixel u16
}

fn C.poll(voidptr, u32, int) int
fn C.ioctl(int, u64, ...voidptr) int

__global active_driver = ?&Driver(none)
__global terminal_signal = int(0)

struct SignalRestore {
	signal  os.Signal
	handler os.SignalHandler = fn (_ os.Signal) {}
}

@[heap]
struct Driver {
mut:
	saved        termios.Termios
	active       bool
	mouse_motion bool
	pointer      MousePointer
	eof          bool
	signals      []SignalRestore
	read_buffer  []u8
}

fn terminal_on_signal(signal os.Signal) { terminal_signal = int(signal) }

fn terminal_on_exit() {
	if mut driver := active_driver { driver.stop() }
}

fn (mut d Driver) start() ! {
	if driver := active_driver {
		if driver.active { return error('another VTK app owns this terminal') }
	}
	if C.isatty(0) == 0 || C.isatty(1) == 0 { return error('vtk needs an interactive terminal') }
	if termios.tcgetattr(0, mut d.saved) != 0 { return error('cannot read terminal attributes') }
	mut raw := d.saved
	raw.c_iflag &= termios.invert(termios.flag(int(C.BRKINT) | int(C.ICRNL) | int(C.INPCK) | int(C.ISTRIP) | int(C.IXON)))
	raw.c_lflag &= termios.invert(termios.flag(int(C.ECHO) | int(C.ICANON) | int(C.IEXTEN) | int(C.ISIG)))
	raw.c_cflag |= termios.flag(C.CS8)
	raw.c_cc[C.VMIN] = 0
	raw.c_cc[C.VTIME] = 0
	if termios.tcsetattr(0, C.TCSAFLUSH, mut raw) != 0 {
		return error('cannot set terminal raw mode')
	}
	d.active = true
	d.eof = false
	active_driver = &d
	terminal_signal = 0
	at_exit(terminal_on_exit) or {}
	for signal in [os.Signal.int, .term, .hup, .quit] {
		previous := os.signal_opt(signal, terminal_on_signal) or { continue }
		d.signals << SignalRestore{signal, previous}
	}
	d.mouse_motion = false
	d.pointer = MousePointer{}
	print('\x1b[?1049h\x1b[?25l\x1b[?1002h\x1b[?1004h\x1b[?1006h\x1b[?2004h\x1b[2J')
	flush_stdout()
}

fn (mut d Driver) stop() {
	if !d.active { return }
	print(d.pointer.restore() + '\x1b[0m\x1b[?2004l\x1b[?1006l\x1b[?1004l\x1b[?1003l\x1b[?1002l\x1b[0 q\x1b[?25h\x1b[?1049l')
	flush_stdout()
	termios.tcsetattr(0, C.TCSAFLUSH, mut d.saved)
	d.active = false
	active_driver = none
	d.read_buffer = []
	for saved in d.signals { os.signal_opt(saved.signal, saved.handler) or {} }
	d.signals.clear()
}

fn (mut d Driver) read(timeout int) string {
	mut p := C.pollfd{ fd: 0, events: i16(C.POLLIN) }
	ready := C.poll(&p, 1, max(0, timeout))
	if terminal_signal != 0 {
		signal := terminal_signal
		terminal_signal = 0
		if signal == int(os.Signal.int) { return '\x03' }
		d.eof = true
		return ''
	}
	if ready <= 0 { return '' }
	if d.read_buffer.len == 0 { d.read_buffer = []u8{len: 16384} }
	n := int(C.read(0, d.read_buffer.data, uint(d.read_buffer.len)))
	if n <= 0 {
		if n == 0 { d.eof = true }
		return ''
	}
	return d.read_buffer[..n].bytestr()
}

fn (d &Driver) size() (int, int) {
	mut ws := C.winsize{}
	if C.ioctl(1, u64(C.TIOCGWINSZ), &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
		return int(ws.ws_col), int(ws.ws_row)
	}
	return 80, 24
}
