module vtk

import os

#include <stdlib.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <signal.h>

fn C.posix_openpt(int) int
fn C.grantpt(int) int
fn C.unlockpt(int) int
fn C.ptsname(int) &char
fn C.fork() int
fn C.setsid() int
fn C.execv(&char, &&char) int

struct Pty {
mut:
	fd     int = -1
	pid    int = -1
	reaped bool
}

fn spawn_pty(cols int, rows int) !Pty {
	master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
	if master < 0 { return error('posix_openpt failed') }
	if C.grantpt(master) != 0 || C.unlockpt(master) != 0 {
		C.close(master)
		return error('cannot unlock PTY')
	}
	slave := C.open(C.ptsname(master), C.O_RDWR | C.O_NOCTTY, 0)
	if slave < 0 {
		C.close(master)
		return error('cannot open PTY slave')
	}
	path := if os.getenv('SHELL') != '' { os.getenv('SHELL') } else { '/bin/sh' }
	argv := [path.str, &u8(unsafe { nil })]
	pid := C.fork()
	if pid < 0 {
		C.close(master)
		C.close(slave)
		return error('cannot fork shell')
	}
	if pid == 0 {
		C.close(master)
		C.setsid()
		C.ioctl(slave, u64(C.TIOCSCTTY), 0)
		C.dup2(slave, 0)
		C.dup2(slave, 1)
		C.dup2(slave, 2)
		if slave > 2 { C.close(slave) }
		unsafe { C.setenv(c'TERM', c'xterm-256color', 1) }
		C.execv(&char(path.str), &&char(argv.data))
		C._exit(127)
	}
	C.close(slave)
	C.fcntl(master, C.F_SETFL, C.fcntl(master, C.F_GETFL, 0) | C.O_NONBLOCK)
	C.fcntl(master, C.F_SETFD, C.FD_CLOEXEC)
	mut p := Pty{ fd: master, pid: pid }
	p.resize(cols, rows)
	return p
}

fn (mut p Pty) resize(cols int, rows int) {
	if p.fd < 0 { return }
	mut ws := C.winsize{ ws_row: u16(rows), ws_col: u16(cols) }
	C.ioctl(p.fd, u64(C.TIOCSWINSZ), &ws)
}

fn (mut p Pty) read(capacity int) string {
	if p.fd < 0 { return '' }
	mut bytes := []u8{len: max(1, capacity)}
	n := int(C.read(p.fd, bytes.data, uint(bytes.len)))
	return if n > 0 { bytes[..n].bytestr() } else { '' }
}

fn (mut p Pty) write(text string) int {
	if p.fd < 0 { return 0 }
	return max(0, int(C.write(p.fd, text.str, text.len)))
}

fn (mut p Pty) alive() bool {
	if p.fd < 0 || p.reaped { return false }
	mut status := 0
	result := C.waitpid(p.pid, &status, C.WNOHANG)
	if result == p.pid || result < 0 {
		p.reaped = true
		return false
	}
	return true
}

fn (mut p Pty) close() {
	if p.fd < 0 { return }
	if p.alive() {
		C.kill(p.pid, C.SIGHUP)
		// Never wait indefinitely for a child which ignores SIGHUP.
		if p.alive() {
			C.kill(p.pid, C.SIGKILL)
			mut status := 0
			C.waitpid(p.pid, &status, 0)
			p.reaped = true
		}
	}
	C.close(p.fd)
	p.fd = -1
}
