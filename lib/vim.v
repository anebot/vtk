module vtk

import math { max, min }

pub enum VimMode {
	normal
	insert
	visual
	visual_line
}

pub struct Vim {
pub mut:
	enabled bool
	mode    VimMode
mut:
	pending        int
	visual_start   int = -1
	visual_head    int
	line_clipboard bool
	kill           bool
}

pub fn (mut c Ctl) vim_mode(enabled bool) {
	c.end_edit_group()
	c.vim.enabled = enabled
	c.vim.mode = .normal
	c.vim.pending = 0
	c.vim.visual_start = -1
	c.anchor = -1
	c.invalidate()
}

pub fn (mut app App) vim_set(enabled bool) {
	app.vim_mode = enabled
	for mut w in app.windows { apply_vim(mut w, enabled) }
	app.dirty = true
}

fn apply_vim(mut c Ctl, enabled bool) {
	if c.kind in [.multiline, .markdown] { c.vim_mode(enabled) }
	for mut child in c.kids { apply_vim(mut child, enabled) }
}

fn (mut c Ctl) vim_select() {
	if c.vim.visual_start < 0 { return }
	if c.vim.mode == .visual_line {
		c.anchor = line_start(c.text, min(c.vim.visual_start, c.vim.visual_head))
		c.cursor = min(c.text.len, line_end(c.text, max(c.vim.visual_start, c.vim.visual_head)) + 1)
	} else {
		c.anchor = min(c.vim.visual_start, c.vim.visual_head)
		c.cursor = next_char(c.text, max(c.vim.visual_start, c.vim.visual_head))
	}
}

fn (mut c Ctl) vim_insert(at int) {
	c.cursor = clamp(at, 0, c.text.len)
	c.anchor = -1
	c.vim.mode = .insert
	c.vim.pending = 0
	c.begin_edit_group()
}

fn (mut c Ctl) vim_copy_range(a int, b int, linewise bool, mut app App) {
	if c.secret { return }
	text := c.text[a..b]
	app.clipboard_set(if linewise && !text.ends_with('\n') { text + '\n' } else { text })
	c.vim.line_clipboard = linewise
}

fn (mut c Ctl) vim_key(e Event, mut app App) bool {
	if e.key == int(Key.escape) {
		c.end_edit_group()
		c.vim.mode = .normal
		c.vim.pending = 0
		c.vim.visual_start = -1
		c.anchor = -1
		app.dirty = true
		return true
	}
	if e.key in [int(Key.page_down), int(Key.page_up)] || (e.ctrl && e.key in [
		int(`f`),
		int(`b`),
	]) {
		visual := c.vim.mode in [.visual, .visual_line]
		if visual { c.cursor = c.vim.visual_head }
		c.vertical_move((if e.key in [int(Key.page_up), int(`b`)] { -1 } else { 1 }) * max(1, c.editor_height() - 2), false)
		if visual {
			c.vim.visual_head = c.cursor
			c.vim_select()
		}
		return true
	}
	if c.vim.mode == .insert {
		if e.ctrl && e.key in [int(`a`), int(`e`), int(`p`), int(`n`), int(`d`), int(`h`), int(`k`),
			int(`u`), int(`w`), int(`y`), int(`t`)] {
			c.end_edit_group()
			match e.key {
				`a` { c.move_cursor(line_start(c.text, c.cursor), false) }
				`e` { c.move_cursor(line_end(c.text, c.cursor), false) }
				`p` { c.vertical_move(-1, false) }
				`n` { c.vertical_move(1, false) }
				`d` { c.replace_range(c.cursor, next_char(c.text, c.cursor), '') }
				`h` { c.replace_range(prev_char(c.text, c.cursor), c.cursor, '') }
				`y` {
					c.replace_selection(app.clipboard)
					c.vim.kill = false
				}
				`t` {
					b := if c.cursor == c.text.len { prev_char(c.text, c.cursor) } else { c.cursor }
					a, end := prev_char(c.text, b), next_char(c.text, b)
					if a < b && b < c.text.len && c.text[a] != `\n` && c.text[b] != `\n` {
						c.replace_range(a, end, c.text[b..end] + c.text[a..b])
					}
				}
				else {
					mut a, mut b := c.cursor, c.cursor
					if e.key == `k` {
						b = line_end(c.text, c.cursor)
						if b == a { b = min(c.text.len, b + 1) }
					} else if e.key == `u` {
						a = line_start(c.text, c.cursor)
					} else {
						a = word_back(c.text, c.cursor, false)
					}
					if !c.readonly && b > a {
						cut := c.text[a..b]
						app.clipboard_set(if c.vim.kill {
							if a < c.cursor { cut + app.clipboard } else { app.clipboard + cut }
						} else {
							cut
						})
						c.replace_range(a, b, '')
						c.vim.kill = true
					}
				}
			}
			c.begin_edit_group()
			return true
		}
		if e.key >= 0x110000 || e.key == int(Key.tab) {
			c.end_edit_group()
		} else if !c.edit.grouping {
			c.begin_edit_group()
		}
		return false
	}
	if e.ctrl {
		if e.key == `r` {
			c.redo()
			return true
		}
		return false
	}
	visual := c.vim.mode in [.visual, .visual_line]
	if visual {
		if e.key in [int(`y`), int(`d`), int(`x`), int(`c`), int(`p`), int(`P`)] {
			a, b := c.selection()
			paste := app.clipboard
			if e.key !in [int(`p`), int(`P`)] {
				c.vim_copy_range(a, b, c.vim.mode == .visual_line, mut app)
			}
			if e.key == `c` { c.begin_edit_group() }
			if e.key in [int(`d`), int(`x`), int(`c`)] {
				c.replace_range(a, b, '')
			} else if e.key in [int(`p`), int(`P`)] {
				c.replace_range(a, b, paste)
			} else {
				c.cursor = a
			}
			c.vim.mode = if e.key == `c` { VimMode.insert } else { VimMode.normal }
			c.vim.visual_start = -1
			c.anchor = -1
			return true
		}
		if e.key == `o` {
			old := c.vim.visual_start
			c.vim.visual_start = c.vim.visual_head
			c.vim.visual_head = old
			c.vim_select()
			return true
		}
		c.cursor = c.vim.visual_head
	}
	mut moved := true
	match e.key {
		`h`, int(Key.left) { c.cursor = prev_char(c.text, c.cursor) }
		`l`, int(Key.right) { c.cursor = next_char(c.text, c.cursor) }
		`j`, int(Key.down) { c.vertical_move(1, false) }
		`k`, int(Key.up) { c.vertical_move(-1, false) }
		`w`, `W` { c.cursor = word_forward(c.text, c.cursor, e.key == `W`) }
		`b`, `B` { c.cursor = word_back(c.text, c.cursor, e.key == `B`) }
		`0`, int(Key.home) { c.cursor = line_start(c.text, c.cursor) }
		`^` {
			c.cursor = line_start(c.text, c.cursor)
			for c.cursor < c.text.len && c.text[c.cursor] in [u8(` `), u8(`\t`)] { c.cursor++ }
		}
		`$`, int(Key.end) { c.cursor = line_end(c.text, c.cursor) }
		`G` { c.cursor = line_start(c.text, c.text.len) }
		`g` {
			if c.vim.pending == `g` {
				c.cursor = 0
				c.vim.pending = 0
			} else {
				c.vim.pending = `g`
			}
			return true
		}
		else { moved = false }
	}
	if moved {
		if c.vim.pending in [int(`d`), int(`c`), int(`y`)] {
			if c.vim.pending == `c` && e.key in [int(`w`), int(`W`)] && word_class(c.text, c.vim.visual_head, e.key == `W`) != 0 {
				c.cursor = c.vim.visual_head
				class := word_class(c.text, c.cursor, e.key == `W`)
				for c.cursor < c.text.len && word_class(c.text, c.cursor, e.key == `W`) == class {
					c.cursor = next_char(c.text, c.cursor)
				}
			}
			end, start := max(c.cursor, c.vim.visual_head), min(c.cursor, c.vim.visual_head)
			c.cursor = c.vim.visual_head
			c.vim_copy_range(start, end, false, mut app)
			if c.vim.pending != `y` {
				if c.vim.pending == `c` { c.begin_edit_group() }
				c.replace_range(start, end, '')
			}
			if c.vim.pending == `c` { c.vim.mode = .insert }
			c.vim.pending = 0
		}
		if visual {
			c.vim.visual_head = c.cursor
			c.vim_select()
		}
		c.scroll_hold = false
		app.dirty = true
		return true
	}
	match e.key {
		`i` { c.vim_insert(c.cursor) }
		`a` { c.vim_insert(next_char(c.text, c.cursor)) }
		`I` { c.vim_insert(line_start(c.text, c.cursor)) }
		`A` { c.vim_insert(line_end(c.text, c.cursor)) }
		`o`, `O` {
			c.begin_edit_group()
			at := if e.key == `O` {
				line_start(c.text, c.cursor)
			} else {
				line_end(c.text, c.cursor)
			}
			if c.replace_range(at, at, '\n') {
				c.vim.mode = .insert
				if e.key == `O` { c.cursor = at }
			}
		}
		`u` { c.undo() }
		`x` {
			end := next_char(c.text, c.cursor)
			if !c.readonly && end > c.cursor { c.vim_copy_range(c.cursor, end, false, mut app) }
			c.replace_range(c.cursor, end, '')
		}
		`J` {
			a := line_end(c.text, c.cursor)
			if a < c.text.len {
				mut b := a + 1
				for b < c.text.len && c.text[b] in [u8(` `), u8(`\t`)] { b++ }
				c.replace_range(a, b, if a > 0 && c.text[a - 1] !in [u8(` `), u8(`\t`)] && b < c.text.len && c.text[b] != `\n` {
					' '
				} else {
					''
				})
			}
		}
		`d`, `y`, `c` {
			if c.vim.pending == e.key {
				a, b := line_start(c.text, c.cursor), min(c.text.len, line_end(c.text, c.cursor) + 1)
				c.vim_copy_range(a, b, true, mut app)
				if e.key != `y` {
					if e.key == `c` { c.begin_edit_group() }
					c.replace_range(a, b, '')
				}
				if e.key == `c` { c.vim.mode = .insert }
				c.vim.pending = 0
			} else {
				c.vim.pending = e.key
				c.vim.visual_head = c.cursor
			}
		}
		`p`, `P` {
			mut at := if e.key == `P` { c.cursor } else { next_char(c.text, c.cursor) }
			mut text := app.clipboard
			if c.vim.line_clipboard {
				at = if e.key == `P` {
					line_start(c.text, c.cursor)
				} else {
					min(c.text.len, line_end(c.text, c.cursor) + 1)
				}
				if e.key == `p` && c.text.len > 0 && at == c.text.len && !c.text.ends_with('\n') {
					text = '\n' + text
				}
			}
			c.replace_range(at, at, text)
		}
		`v`, `V` {
			c.vim.mode = if e.key == `V` { VimMode.visual_line } else { VimMode.visual }
			c.vim.visual_start = c.cursor
			c.vim.visual_head = c.cursor
			c.vim_select()
		}
		else { c.vim.pending = 0 }
	}
	app.dirty = true
	return true
}
