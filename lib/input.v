module vtk

import encoding.utf8
import time

// Special keys are above the Unicode range so typing Ć cannot mean Up.
pub enum Key {
	tab       = 9
	enter     = 10
	escape    = 27
	space     = 32
	backspace = 127
	up        = 1114112
	down
	left
	right
	home
	end
	page_up
	page_down
	insert
	delete
	f1
	f2
	f3
	f4
	f5
	f6
	f7
	f8
	f9
	f10
	f11
	f12
}

pub enum EventKind {
	key
	mouse
	paste
	resize
	focus_in
	focus_out
	pointer_shape
}

pub enum MouseButton {
	none
	left
	middle
	right
	wheel_up
	wheel_down
	wheel_left
	wheel_right
}

fn (button MouseButton) is_wheel() bool {
	return button in [.wheel_up, .wheel_down, .wheel_left, .wheel_right]
}

pub struct Event {
pub:
	kind    EventKind
	key     int
	text    string
	ctrl    bool
	alt     bool
	shift   bool
	x       int
	y       int
	button  MouseButton
	pressed bool
	motion  bool
	width   int
	height  int
}

pub struct Binding {
pub:
	key   int
	ctrl  bool
	alt   bool
	shift bool
}

fn lower_key(key int) int { return if key >= `A` && key <= `Z` { key + 32 } else { key } }

pub fn (b Binding) matches(e Event) bool {
	return b.key != 0 && lower_key(e.key) == b.key && b.ctrl == e.ctrl && b.alt == e.alt && b.shift == e.shift
}

const named_keys = {
	'SPACE':     int(Key.space)
	'TAB':       int(Key.tab)
	'ENTER':     int(Key.enter)
	'ESCAPE':    int(Key.escape)
	'BACKSPACE': int(Key.backspace)
	'UP':        int(Key.up)
	'DOWN':      int(Key.down)
	'LEFT':      int(Key.left)
	'RIGHT':     int(Key.right)
	'HOME':      int(Key.home)
	'END':       int(Key.end)
	'PAGEUP':    int(Key.page_up)
	'PAGEDOWN':  int(Key.page_down)
	'INSERT':    int(Key.insert)
	'DELETE':    int(Key.delete)
	'PLUS':      int(`+`)
	'HASH':      int(`#`)
	'SEMICOLON': int(`;`)
}

pub fn parse_binding(text string) !Binding {
	s := text.to_upper().replace(' ', '').replace('\t', '')
	if s == 'NONE' { return Binding{} }
	parts := s.split('+')
	mut ctrl, mut alt, mut shift := false, false, false
	for part in parts[..max(0, parts.len - 1)] {
		match part {
			'CTRL' {
				if ctrl { return error('duplicate modifier') }
				ctrl = true
			}
			'ALT' {
				if alt { return error('duplicate modifier') }
				alt = true
			}
			'SHIFT' {
				if shift { return error('duplicate modifier') }
				shift = true
			}
			else { return error('unknown modifier: ${part}') }
		}
	}
	name := parts.last()
	mut key := named_keys[name] or { 0 }
	if name.len == 1 && name[0] >= 33 && name[0] <= 126 { key = lower_key(int(name[0])) }
	if name.starts_with('F') && name.len > 1 {
		n := name[1..].int()
		if n >= 1 && n <= 12 && name == 'F${n}' { key = int(Key.f1) + n - 1 }
	}
	if key == 0 { return error('invalid key: ${name}') }
	return Binding{key, ctrl, alt, shift}
}

pub fn (b Binding) str() string {
	if b.key == 0 { return 'None' }
	mut name := ''
	for n, key in named_keys {
		if key == b.key {
			name = n
			break
		}
	}
	if b.key >= int(Key.f1) && b.key <= int(Key.f12) { name = 'F${b.key - int(Key.f1) + 1}' }
	if name == '' { name = rune(b.key).str() }
	return (if b.ctrl { 'Ctrl+' } else { '' }) + (if b.alt { 'Alt+' } else { '' }) + (if b.shift {
		'Shift+'
	} else {
		''
	}) + name
}

pub fn (mut app App) set_keys(move Binding, resize Binding) bool {
	if move.key != 0 && move == resize { return false }
	app.move_key = move
	app.resize_key = resize
	return true
}

// Input retains incomplete escape/UTF-8 sequences between reads. A lone
// Escape is emitted after a short timeout; bracketed paste is one event.
pub struct Input {
mut:
	buffer      string
	escape_at   i64
	pasting     bool
	paste       string
	osc_discard bool
}

pub fn (mut input Input) feed(bytes string) []Event {
	input.buffer += bytes
	mut events := []Event{}
	for input.buffer.len > 0 {
		b := input.buffer
		if input.pasting {
			end := b.index('\x1b[201~') or { -1 }
			if end < 0 { break }
			events << Event{ kind: .paste, text: b[..end] }
			input.buffer = b[end + 6..]
			input.pasting = false
			continue
		}
		if b.starts_with('\x1b[200~') {
			input.pasting = true
			input.buffer = b[6..]
			continue
		}
		if b[0] == 27 {
			if input.escape_at == 0 { input.escape_at = time.ticks() }
			if b.len == 1 {
				if time.ticks() - input.escape_at < 30 { break }
				events << Event{ key: int(Key.escape) }
				input.buffer = ''
				input.escape_at = 0
				continue
			}
			if b[1] == `]` {
				// Terminal replies are control strings, never keyboard input.
				mut end := 2
				mut terminator := 0
				mut aborted := false
				for end < b.len {
					if b[end] == 7 || b[end] in [u8(0x18), 0x1a] {
						terminator = 1
						aborted = b[end] != 7
						break
					}
					if b[end] == 27 {
						if end + 1 == b.len { break }
						if b[end + 1] == `\\` {
							terminator = 2
						} else {
							aborted = true
						}
						break
					}
					end++
				}
				if terminator == 0 && !aborted {
					if b.len > 256 {
						input.osc_discard = true
						input.buffer = '\x1b]' + if b.ends_with('\x1b') { '\x1b' } else { '' }
					}
					break
				}
				if !aborted && !input.osc_discard && end <= 256 {
					payload := b[2..end]
					if payload.starts_with('22;') {
						events << Event{ kind: .pointer_shape, text: payload[3..] }
					}
				}
				input.osc_discard = false
				input.buffer = b[end + terminator..]
				input.escape_at = 0
				continue
			}
			if b[1] == `[` || b[1] == `O` {
				mut end := 2
				for end < b.len && (b[end] < 0x40 || b[end] > 0x7e) { end++ }
				if end >= b.len { break }
				seq := b[2..end + 1]
				if seq.starts_with('<') {
					parts := seq[1..seq.len - 1].split(';')
					if parts.len == 3 {
						code := parts[0].int()
						mouse_button := if code & 64 != 0 {
							match code & 3 {
								0 { MouseButton.wheel_up }
								1 { MouseButton.wheel_down }
								2 { MouseButton.wheel_left }
								else { MouseButton.wheel_right }
							}
						} else {
							match code & 3 {
								0 { MouseButton.left }
								1 { MouseButton.middle }
								2 { MouseButton.right }
								else { MouseButton.none }
							}
						}
						events << Event{ kind: .mouse, x: max(0, parts[1].int() - 1), y: max(0, parts[2].int() - 1), button: mouse_button, pressed: seq.ends_with('M') && mouse_button != .none, motion: code & 32 != 0, shift: code & 4 != 0, alt: code & 8 != 0, ctrl: code & 16 != 0 }
					}
				} else {
					if event := parse_escape(seq) { events << event }
				}
				input.buffer = b[end + 1..]
				input.escape_at = 0
				continue
			}
			r, n := utf8.decode_rune_at(b, 1)
			if n < 1 || b.len < 1 + utf8_char_len(b[1]) { break }
			events << Event{ key: int(r), alt: true }
			input.buffer = b[1 + n..]
			input.escape_at = 0
			continue
		}
		if b[0] >= 0x80 && b.len < utf8_char_len(b[0]) { break }
		r, n := utf8.decode_rune_at(b, 0)
		key := if r == 13 {
			int(Key.enter)
		} else if r == 8 {
			int(Key.backspace)
		} else if r > 0 && r < 27 && r !in [8, 9, 10, 13] {
			int(r) + 96
		} else {
			int(r)
		}
		events << Event{ key: key, ctrl: r > 0 && r < 27 && r !in [8, 9, 10, 13] }
		input.buffer = b[max(1, n)..]
	}
	return events
}

fn utf8_char_len(b u8) int {
	return if b < 0x80 {
		1
	} else if b < 0xe0 {
		2
	} else if b < 0xf0 {
		3
	} else {
		4
	}
}

fn parse_escape(seq string) ?Event {
	if seq == 'I' { return Event{ kind: .focus_in } }
	if seq == 'O' { return Event{ kind: .focus_out } }
	if seq == 'Z' { return Event{ key: int(Key.tab), shift: true } }
	last := seq[seq.len - 1]
	parts := seq[..seq.len - 1].split(';')
	mods := if parts.len > 1 { max(0, parts[1].int() - 1) } else { 0 }
	mut key := match last {
		`A` { int(Key.up) }
		`B` { int(Key.down) }
		`C` { int(Key.right) }
		`D` { int(Key.left) }
		`H` { int(Key.home) }
		`F` { int(Key.end) }
		`P` { int(Key.f1) }
		`Q` { int(Key.f2) }
		`R` { int(Key.f3) }
		`S` { int(Key.f4) }
		else { 0 }
	}
	if last == `~` {
		key = match parts[0].int() {
			1, 7 { int(Key.home) }
			2 { int(Key.insert) }
			3 { int(Key.delete) }
			4, 8 { int(Key.end) }
			5 { int(Key.page_up) }
			6 { int(Key.page_down) }
			11 { int(Key.f1) }
			12 { int(Key.f2) }
			13 { int(Key.f3) }
			14 { int(Key.f4) }
			15 { int(Key.f5) }
			17 { int(Key.f6) }
			18 { int(Key.f7) }
			19 { int(Key.f8) }
			20 { int(Key.f9) }
			21 { int(Key.f10) }
			23 { int(Key.f11) }
			24 { int(Key.f12) }
			else { 0 }
		}
	}
	if last == `u` { key = parts[0].int() }
	if key == 0 { return none }
	return Event{ key: key, shift: mods & 1 != 0, alt: mods & 2 != 0, ctrl: mods & 4 != 0 }
}
