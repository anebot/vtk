@[has_globals]
module vtk

import os
import term.termios
import time

#include <unistd.h>
#include <poll.h>
#include <fcntl.h>
#include "@VMODROOT/lib/tty_signal.h"
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
fn C.ttyname(int) &char
fn C.vtk_tty_set_wake(int)
fn C.vtk_tty_record_signal(int)
fn C.vtk_tty_take_signal() int

__global active_driver = ?&Driver(none)

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
	conservative bool
	pointer      MousePointer
	eof          bool
	signals      []SignalRestore
	read_buffer  []u8
	wake         [2]i32 = [-1, -1]!
	polls        []C.pollfd
	write_fd     int = -1
	output_queue string
	output_at    int
	resized      bool
	terminals_ready bool
	terminal_check_at i64
}

fn terminal_on_signal(signal os.Signal) { C.vtk_tty_record_signal(int(signal)) }

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
	C.vtk_tty_take_signal()
	at_exit(terminal_on_exit) or {}
	d.open_wake_pipe()
	for signal in [os.Signal.int, .term, .hup, .quit, .winch] {
		previous := os.signal_opt(signal, terminal_on_signal) or {
			if signal == .winch { d.close_wake_pipe() }
			continue
		}
		d.signals << SignalRestore{signal, previous}
	}
	// Open the tty independently so changing its file flags does not change
	// stdin, stdout or the caller's file descriptions.
	name := C.ttyname(1)
	if !isnil(name) {
		d.write_fd = C.open(name, C.O_WRONLY | C.O_NOCTTY | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	}
	d.mouse_motion = false
	d.pointer = MousePointer{}
	d.output(tty_setup)
}

fn (mut d Driver) stop() {
	if !d.active { return }
	d.output(d.pointer.restore() + tty_restore(d.conservative))
	if d.write_fd >= 0 {
		if d.output_busy() {
			mut p := C.pollfd{fd: d.write_fd, events: i16(C.POLLOUT)}
			if C.poll(&p, 1, 250) > 0 { d.flush_output() }
		}
		C.close(d.write_fd)
		d.write_fd = -1
		d.output_queue, d.output_at = '', 0
	}
	termios.tcsetattr(0, C.TCSANOW, mut d.saved)
	d.active = false
	active_driver = none
	d.read_buffer = []
	for saved in d.signals { os.signal_opt(saved.signal, saved.handler) or {} }
	d.signals.clear()
	d.close_wake_pipe()
	d.polls = []
}

fn (mut d Driver) read(timeout int, terminals []&Ctl) string {
	d.polls.clear()
	d.polls << C.pollfd{fd: 0, events: i16(C.POLLIN)}
	d.polls << C.pollfd{fd: d.wake[0], events: i16(C.POLLIN)}
	d.polls << C.pollfd{fd: if d.output_busy() { d.write_fd } else { -1 }, events: i16(C.POLLOUT)}
	d.terminals_ready = false
	mut wait := if d.wake[0] < 0 { limit_wait(timeout, 100) } else { timeout }
	mut has_terminals := false
	for c in terminals {
		if c.closed || c.term.pty.fd < 0 { continue }
		has_terminals = true
		if c.term.pty.drained { continue }
		flags := C.POLLIN | if c.term.pending != '' { C.POLLOUT } else { 0 }
		d.polls << C.pollfd{fd: c.term.pty.fd, events: i16(flags)}
	}
	// The shell can exit without a hangup if another process holds the slave open.
	if has_terminals { wait = limit_wait(wait, d.terminal_check_at - time.ticks()) }
	C.poll(d.polls.data, u32(d.polls.len), wait)
	if has_terminals {
		now := time.ticks()
		if now >= d.terminal_check_at {
			d.terminal_check_at = now + 100
			d.terminals_ready = true
		}
	}
	if d.polls[1].revents != 0 {
		mut signals := [32]u8{}
		C.read(d.wake[0], &signals[0], signals.len)
		d.resized = true
	}
	signal := C.vtk_tty_take_signal()
	if signal != 0 {
		if signal == int(os.Signal.int) { return '\x03' }
		d.eof = true
		return ''
	}
	if d.polls[2].revents != 0 { d.flush_output() }
	for p in d.polls[3..] {
		if p.revents != 0 { d.terminals_ready = true; break }
	}
	if d.polls[0].revents == 0 { return '' }
	if d.read_buffer.len == 0 { d.read_buffer = []u8{len: 16384} }
	n := int(C.read(0, d.read_buffer.data, uint(d.read_buffer.len)))
	if n <= 0 {
		if n == 0 { d.eof = true }
		return ''
	}
	return d.read_buffer[..n].bytestr()
}

fn (mut d Driver) open_wake_pipe() {
	if C.pipe(&d.wake[0]) != 0 { return }
	for fd in d.wake {
		if C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) < 0 || C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) < 0 {
			d.close_wake_pipe()
			return
		}
	}
	C.vtk_tty_set_wake(d.wake[1])
}

fn (mut d Driver) close_wake_pipe() {
	C.vtk_tty_set_wake(-1)
	for fd in d.wake {
		if fd >= 0 { C.close(fd) }
	}
	d.wake = [-1, -1]!
}

fn (mut d Driver) resize_pending() bool {
	pending := d.resized || d.wake[0] < 0
	d.resized = false
	return pending
}

fn (d &Driver) size() (int, int) {
	mut ws := C.winsize{}
	if C.ioctl(1, u64(C.TIOCGWINSZ), &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
		return int(ws.ws_col), int(ws.ws_row)
	}
	return 80, 24
}

fn (d &Driver) output_busy() bool { return d.output_queue != '' }

fn (mut d Driver) output(sequence string) {
	if sequence == '' { return }
	if d.write_fd < 0 {
		print(sequence)
		flush_stdout()
		return
	}
	d.output_queue = if d.output_busy() { d.output_queue[d.output_at..] + sequence } else { sequence }
	d.output_at = 0
	d.flush_output()
}

fn (mut d Driver) flush_output() {
	for d.output_busy() {
		remaining := d.output_queue.len - d.output_at
		count := unsafe { int(C.write(d.write_fd, d.output_queue.str + d.output_at, uint(remaining))) }
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 && (C.errno == C.EAGAIN || C.errno == C.EWOULDBLOCK) { return }
		if count == remaining || count <= 0 {
			d.output_queue, d.output_at = '', 0
			if count <= 0 { d.eof = true }
		} else {
			d.output_at += count
		}
	}
}
