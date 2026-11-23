module vtk

import os

#flag windows -D_WIN32_WINNT=0x0A00
#include <windows.h>

@[typedef]
struct C.STARTUPINFOW {
mut:
	cb u32
}

@[typedef]
struct C.STARTUPINFOEXW {
mut:
	StartupInfo     C.STARTUPINFOW
	lpAttributeList voidptr
}

@[typedef]
struct C.PROCESS_INFORMATION {
	hProcess    voidptr
	hThread     voidptr
	dwProcessId u32
	dwThreadId  u32
}

fn C.CreatePseudoConsole(C.COORD, voidptr, voidptr, u32, &voidptr) int
fn C.ResizePseudoConsole(voidptr, C.COORD) int
fn C.ClosePseudoConsole(voidptr)
fn C.InitializeProcThreadAttributeList(voidptr, u32, u32, &u64) bool
fn C.UpdateProcThreadAttribute(voidptr, u32, u64, voidptr, u64, voidptr, voidptr) bool
fn C.DeleteProcThreadAttributeList(voidptr)

struct Pty {
mut:
	console voidptr
	input   voidptr
	output  voidptr
	process voidptr
	active  bool
	read_buffer []u8
}

fn spawn_pty(cols int, rows int, directory string) !Pty {
	mut in_read, mut in_write, mut out_read, mut out_write := voidptr(0), voidptr(0), voidptr(0), voidptr(0)
	if !C.CreatePipe(&in_read, &in_write, 0, 0) { return error('cannot create ConPTY input pipe') }
	if !C.CreatePipe(&out_read, &out_write, 0, 0) {
		C.CloseHandle(in_read)
		C.CloseHandle(in_write)
		return error('cannot create ConPTY output pipe')
	}
	mut console := voidptr(0)
	result := C.CreatePseudoConsole(C.COORD{ X: i16(cols), Y: i16(rows) }, in_read, out_write, 0, &console)
	C.CloseHandle(in_read)
	C.CloseHandle(out_write)
	if result != 0 {
		C.CloseHandle(in_write)
		C.CloseHandle(out_read)
		return error('CreatePseudoConsole failed')
	}
	mut p := Pty{ console: console, input: in_write, output: out_read, active: true }
	mut size := u64(0)
	C.InitializeProcThreadAttributeList(0, 1, 0, &size)
	mut attributes := []u8{len: int(size)}
	if !C.InitializeProcThreadAttributeList(attributes.data, 1, 0, &size) {
		p.close()
		return error('cannot initialize ConPTY attributes')
	}
	defer { C.DeleteProcThreadAttributeList(attributes.data) }
	if !C.UpdateProcThreadAttribute(attributes.data, 0, 0x20016, console, u64(sizeof(voidptr)), 0, 0) {
		p.close()
		return error('cannot attach ConPTY')
	}
	mut startup := C.STARTUPINFOEXW{ lpAttributeList: attributes.data }
	startup.StartupInfo.cb = u32(sizeof(C.STARTUPINFOEXW))
	mut info := C.PROCESS_INFORMATION{}
	shell := if os.getenv('COMSPEC') != '' { os.getenv('COMSPEC') } else { 'cmd.exe' }
	working_directory := if directory == '' { &u16(unsafe { nil }) } else { directory.to_wide() }
	if !C.CreateProcessW(0, shell.to_wide(), 0, 0, false, 0x80000, 0, working_directory, &startup, &info) {
		p.close()
		return error('cannot start ConPTY shell')
	}
	p.process = info.hProcess
	C.CloseHandle(info.hThread)
	return p
}

fn (mut p Pty) resize(cols int, rows int) {
	if p.active { C.ResizePseudoConsole(p.console, C.COORD{ X: i16(cols), Y: i16(rows) }) }
}

fn (mut p Pty) read(capacity int) string {
	if !p.active { return '' }
	mut available := u32(0)
	if !C.PeekNamedPipe(p.output, 0, 0, 0, &available, 0) || available == 0 { return '' }
	size := min(int(available), max(1, capacity))
	if p.read_buffer.len < size { p.read_buffer = []u8{len: size} }
	mut n := u32(0)
	if !C.ReadFile(p.output, p.read_buffer.data, u32(size), &n, 0) { return '' }
	return p.read_buffer[..int(n)].bytestr()
}

fn (mut p Pty) write(text string) int {
	if !p.active { return 0 }
	mut n := u32(0)
	C.WriteFile(p.input, text.str, u32(text.len), &n, 0)
	return int(n)
}

fn (mut p Pty) alive() bool { return p.active && C.WaitForSingleObject(p.process, 0) != 0 }

fn (mut p Pty) close() {
	if !p.active { return }
	if !isnil(p.process) {
		if p.alive() { C.TerminateProcess(p.process, 0) }
		C.CloseHandle(p.process)
	}
	C.CloseHandle(p.input)
	C.CloseHandle(p.output)
	C.ClosePseudoConsole(p.console)
	p.active = false
	p.read_buffer = []
}
