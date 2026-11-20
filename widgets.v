module vtk

import time

pub fn label(text string) &Ctl { return &Ctl{ kind: .label, text: text } }

pub fn separator() &Ctl { return new_ctl(.separator) }

pub fn button(text string) &Ctl { return &Ctl{ kind: .button, text: text, focusable: true } }

pub fn toolbutton(text string) &Ctl {
	return &Ctl{ kind: .toolbutton, text: text, focusable: true }
}

pub fn checkbox(text string, checked bool) &Ctl {
	return &Ctl{ kind: .checkbox, text: text, value: int(checked), focusable: true }
}

pub fn switch_ctl(text string, on bool) &Ctl {
	return &Ctl{ kind: .switch, text: text, value: int(on), focusable: true }
}

pub fn spinner(text string) &Ctl { return &Ctl{ kind: .spinner, text: text } }

pub fn slider(low int, high int) &Ctl {
	return &Ctl{ kind: .slider, low: low, high: max(low, high), value: low, expand: true, focusable: true }
}

pub fn progress() &Ctl { return &Ctl{ kind: .progress, high: 100, expand: true } }

pub fn spin(low int, high int) &Ctl {
	return &Ctl{ kind: .spin, low: low, high: max(low, high), value: low, focusable: true }
}

pub fn radio() &Ctl { return &Ctl{ kind: .radio, value: -1, focusable: true } }

pub fn combo() &Ctl { return &Ctl{ kind: .combo, value: -1, focusable: true } }

pub fn tree() &Ctl { return &Ctl{ kind: .tree, expand: true, focusable: true, scrollbar: true } }

pub fn table(fetch CellCallback) &Ctl {
	return &Ctl{ kind: .table, cellfn: fetch, value: -1, expand: true, focusable: true, scrollbar: true }
}

pub fn canvas(width int, height int, paint PaintCallback) &Ctl {
	return &Ctl{ kind: .canvas, pw: width, ph: height, paint: paint }
}

pub fn (mut c Ctl) add_item(text string) &Ctl {
	mut item := &Ctl{ kind: .item, text: text }
	c.add(mut item)
	return item
}

pub fn (mut c Ctl) table_column(title string) { c.add_item(title) }

pub fn (c &Ctl) table_cell(row int, col int) string {
	if f := c.cellfn { return f(c, row, col) }
	return ''
}

pub fn (mut c Ctl) set_value(value int, mut app App) {
	v := if c.kind in [.slider, .spin, .progress] { clamp(value, c.low, c.high) } else { value }
	if c.value != v {
		c.value = v
		c.fire(mut app)
	}
}

pub fn (mut c Ctl) scroll_rows(rows int, total int, viewport int) bool {
	c.top = clamp(c.top + rows, 0, total - max(1, viewport))
	c.scroll_hold = true
	return true
}

fn (mut c Ctl) scroll_into_view(row int, height int) {
	if c.scroll_hold { return }
	if row < c.top { c.top = max(0, row) }
	if row >= c.top + max(1, height) { c.top = max(0, row - max(1, height) + 1) }
}

fn (mut app App) draw_ctl(mut c Ctl) {
	if c.hidden || c.closed || c.minimized || c.w <= 0 || c.h <= 0 { return }
	old := app.screen.set_clip(c.rect())
	t := app.theme
	focused := app.focus == &c
	mut fg := if c.disabled { t.dim } else { t.fg }
	mut bg := t.bg
	mut p := c.parent
	for !isnil(p) {
		if p.kind == .toolbar {
			fg = t.tool_fg
			bg = t.tool_bg
			break
		}
		if p.kind == .status {
			fg = t.title
			bg = t.dim
			break
		}
		p = p.parent
	}
	mut focus_bg := if focused { t.focus_bg } else { bg }
	match c.kind {
		.window { app.draw_window(mut c) }
		.label, .status {
			if c.kind == .status {
				fg = t.title
				bg = t.dim
			}
			app.screen.fill(c.rect(), ` `, fg, bg)
			for i, line in c.text.split('\n') { app.screen.text(c.x, c.y + i, line, fg, bg, 0) }
			for mut child in c.kids { app.draw_ctl(mut child) }
		}
		.button, .toolbutton {
			if c.kind == .button {
				bg = if focused { t.focus_bg } else { t.btn_bg }
				fg = if c.disabled { t.dim } else { t.btn_fg }
			} else if focused || c.value != 0 {
				bg = t.sel_bg
				fg = t.sel_fg
			}
			app.screen.fill(c.rect(), ` `, fg, bg)
			if c.kind == .toolbutton {
				app.screen.text(c.x, c.y, '[${c.text}]', fg, bg, if focused { bold } else { 0 })
			} else {
				app.screen.text(c.x + max(0, (c.w - text_width(c.text)) / 2), c.y, c.text, fg, bg, if focused {
					bold
				} else {
					0
				})
			}
		}
		.checkbox, .switch {
			mark := if c.kind == .switch {
				if c.value != 0 { '[ ON  ] ' } else { '[ OFF ] ' }
			} else if c.value != 0 {
				'[x] '
			} else {
				'[ ] '
			}
			app.screen.fill(c.rect(), ` `, fg, focus_bg)
			app.screen.text(c.x, c.y, mark + c.text, fg, focus_bg, 0)
		}
		.spinner {
			c.value = int(time.ticks() / 125) & 3
			app.screen.text(c.x, c.y, '|/-\\'[c.value].ascii_str() + ' ' + c.text, t.accent, bg, 0)
		}
		.separator { app.screen.fill(Rect{c.x, c.y, c.w, 1}, `─`, t.dim, bg) }
		.slider {
			app.screen.fill(Rect{c.x, c.y, c.w, 1}, `─`, t.dim, bg)
			thumb := (clamp(c.value, c.low, c.high) - c.low) * max(0, c.w - 1) / max(1, c.high - c.low)
			app.screen.put(c.x + thumb, c.y, `█`, if focused { t.focus_bg } else { t.field_fg }, bg, 0)
		}
		.progress {
			fill := clamp(c.value, 0, 100) * c.w / 100
			app.screen.fill(c.rect(), `░`, t.dim, bg)
			app.screen.fill(Rect{c.x, c.y, fill, 1}, `█`, t.field_fg, bg)
		}
		.spin {
			app.screen.fill(c.rect(), ` `, t.field_fg, if focused { t.focus_bg } else { t.field_bg })
			app.screen.text(c.x, c.y, '◄', fg, focus_bg, 0)
			app.screen.text(c.x + max(1, (c.w - c.value.str().len) / 2), c.y, c.value.str(), fg, focus_bg, 0)
			app.screen.text(c.x + c.w - 1, c.y, '►', fg, focus_bg, 0)
		}
		.entry, .multiline, .markdown { app.draw_editor(mut c) }
		.combo {
			app.screen.fill(c.rect(), ` `, t.field_fg, if focused { t.focus_bg } else { t.field_bg })
			if c.value >= 0 && c.value < c.kids.len {
				app.screen.text(c.x, c.y, c.kids[c.value].text, t.field_fg, t.field_bg, 0)
			}
			app.screen.text(c.x + c.w - 1, c.y, '▼', t.field_fg, t.field_bg, 0)
		}
		.radio {
			for i, child in c.kids {
				app.screen.text(c.x, c.y + i, (if i == c.value { '(•) ' } else { '( ) ' }) + child.text, fg, if i == c.value {
					focus_bg
				} else {
					bg
				}, 0)
			}
		}
		.table {
			n := c.kids.len
			if n > 0 {
				span := max(1, (c.w - int(c.scrollbar)) / n)
				for i, col in c.kids {
					clip := app.screen.set_clip(Rect{c.x + i * span, c.y, span - 1, 1})
					app.screen.text(c.x + i * span, c.y, col.text, fg, bg, bold | underline)
					app.screen.restore_clip(clip)
				}
				c.scroll_into_view(c.value, c.h - 1)
				c.top = clamp(c.top, 0, c.high - max(1, c.h - 1))
				for row := c.top; row < c.high && row < c.top + c.h - 1; row++ {
					rowbg := if row == c.value {
						if focused { t.focus_bg } else { t.dim }
					} else {
						bg
					}
					app.screen.fill(Rect{c.x, c.y + row - c.top + 1, c.w, 1}, ` `, fg, rowbg)
					for col in 0 .. n {
						clip := app.screen.set_clip(Rect{c.x + col * span, c.y + row - c.top + 1, max(0, span - 1), 1})
						app.screen.text(c.x + col * span, c.y + row - c.top + 1, c.table_cell(row, col), fg, rowbg, 0)
						app.screen.restore_clip(clip)
					}
				}
				app.draw_scrollbar(c, c.high, max(1, c.h - 1), 1)
			}
		}
		.tree {
			rows := c.tree_rows()
			for i, row in rows {
				if row.node == c.link {
					c.scroll_into_view(i, c.h)
					break
				}
			}
			c.top = clamp(c.top, 0, rows.len - c.h)
			for i := c.top; i < rows.len && i < c.top + c.h; i++ {
				row := rows[i]
				rowbg := if row.node == c.link {
					if focused { t.focus_bg } else { t.dim }
				} else {
					bg
				}
				app.screen.fill(Rect{c.x, c.y + i - c.top, c.w, 1}, ` `, fg, rowbg)
				if row.node.kids.len > 0 {
					app.screen.text(c.x + row.depth * 2, c.y + i - c.top, if row.node.value != 0 {
						'▾'
					} else {
						'▸'
					}, fg, rowbg, 0)
				}
				app.screen.text(c.x + row.depth * 2 + 2, c.y + i - c.top, row.node.text, fg, rowbg, 0)
			}
			app.draw_scrollbar(c, rows.len, c.h, 0)
		}
		.tabs {
			app.screen.frame(c.rect(), false, t.dim, bg)
			for i, mut page in c.kids {
				app.screen.text(page.tab_x, c.y, ' ${page.text} ', if i == c.value {
					fg
				} else {
					t.dim
				}, bg, if i == c.value { bold } else { 0 })
				if !page.hidden { app.draw_ctl(mut page) }
			}
		}
		.group {
			app.screen.frame(c.rect(), false, t.dim, bg)
			app.screen.text(c.x + 1, c.y, ' ${c.text} ', fg, bg, 0)
			for mut child in c.kids { app.draw_ctl(mut child) }
		}
		.toolbar {
			app.screen.fill(c.rect(), ` `, t.tool_fg, t.tool_bg)
			for mut child in c.kids { app.draw_ctl(mut child) }
		}
		.canvas {
			app.screen.fill(c.rect(), ` `, white, black)
			if paint := c.paint { paint(mut c, mut app.screen) }
		}
		.terminal { app.draw_terminal(mut c) }
		.split {
			if c.kids.len > 0 {
				first := c.kids[0]
				if c.vertical {
					app.screen.fill(Rect{c.x, first.y + first.h, c.w, 1}, `─`, t.dim, bg)
				} else {
					app.screen.fill(Rect{first.x + first.w, c.y, 1, c.h}, `│`, t.dim, bg)
				}
			}
			for mut child in c.kids { app.draw_ctl(mut child) }
		}
		.scroll {
			clip := app.screen.set_clip(Rect{c.x, c.y, max(0, c.w - int(c.scrollbar)), c.h})
			for mut child in c.kids { app.draw_ctl(mut child) }
			app.screen.restore_clip(clip)
			if c.kids.len > 0 { app.draw_scrollbar(c, c.kids[0].ph, c.h, 0) }
		}
		.menu, .menuitem, .item, .treenode {}
		else {
			for mut child in c.kids { app.draw_ctl(mut child) }
		}
	}
	app.screen.restore_clip(old)
}

fn (mut app App) draw_scrollbar(c &Ctl, total int, viewport int, inset int) {
	if !c.scrollbar || c.w < 1 || viewport < 1 { return }
	t := app.theme
	app.screen.fill(Rect{c.x + c.w - 1, c.y + inset, 1, viewport}, `░`, t.dim, t.bg)
	thumb := max(1, viewport * viewport / max(viewport, total))
	at := if total > viewport { c.top * (viewport - thumb) / max(1, total - viewport) } else { 0 }
	app.screen.fill(Rect{c.x + c.w - 1, c.y + inset + at, 1, thumb}, `█`, t.frame, t.bg)
}

fn (c &Ctl) scroll_dimensions() (int, int) {
	match c.kind {
		.table { return c.high, max(1, c.h - 1) }
		.tree { return c.tree_rows().len, c.h }
		.multiline, .markdown { return c.editor_rows().len, c.editor_height() }
		.scroll {
			total := if c.kids.len > 0 { c.kids[0].ph } else { 0 }
			return total, c.h
		}
		else { return 0, 0 }
	}
}
