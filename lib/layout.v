module vtk

pub fn box(vertical bool) &Ctl { return &Ctl{ kind: .box, vertical: vertical } }

pub fn grid() &Ctl { return new_ctl(.grid) }

pub fn split(vertical bool, share int) &Ctl {
	return &Ctl{ kind: .split, vertical: vertical, value: share, expand: true }
}

pub fn scroll() &Ctl { return &Ctl{ kind: .scroll, expand: true, scrollbar: true } }

pub fn flow() &Ctl { return new_ctl(.flow) }

pub fn group(title string) &Ctl { return &Ctl{ kind: .group, text: title } }

pub fn toolbar() &Ctl { return new_ctl(.toolbar) }

pub fn button_bar() &Ctl { return &Ctl{ kind: .box, right: true, bottom: true } }

pub fn statusbar(text string) &Ctl { return &Ctl{ kind: .status, text: text, bottom: true } }

pub fn tabs() &Ctl { return &Ctl{ kind: .tabs, focusable: true, expand: true } }

pub fn (mut c Ctl) add_tab(title string, mut child Ctl) &Ctl {
	mut page := &Ctl{ kind: .tabpage, text: title }
	page.add(mut child)
	c.add(mut page)
	return page
}

fn (c &Ctl) content_kids() []&Ctl {
	return c.kids.filter(!it.hidden && it.kind != .menu)
}

pub fn (mut c Ctl) measure() {
	for mut child in c.kids { child.measure() }
	mut kids := c.content_kids()
	mut w, mut h := 0, 1
	match c.kind {
		.box, .toolbar, .status, .window, .tabpage, .popup {
			if kids.len == 0 {
				w = text_width(c.text) + 2
			} else {
				w = 0
				h = 0
				for child in kids {
					if c.vertical || c.kind == .window {
						w = max(w, child.pw)
						h += child.ph
					} else {
						w += child.pw
						h = max(h, child.ph)
					}
				}
				if !c.vertical && c.kind != .window { w += max(0, kids.len - 1) }
				if c.kind == .status {
					for mut child in kids {
						if child.expand {
							w -= child.pw
							child.pw = 0
						}
					}
				}
			}
		}
		.grid {
			cols, rows := c.grid_dims()
			for n in cols { w += n + 1 }
			w = max(0, w - 1)
			h = 0
			for n in rows { h += n }
		}
		.flow {
			w = 0
			h = 0
			mut roww, mut rowh := 0, 0
			for child in kids {
				if c.w > 0 && roww > 0 && roww + child.pw > c.w {
					h += rowh
					w = max(w, roww)
					roww = 0
					rowh = 0
				}
				roww += child.pw + 1
				rowh = max(rowh, child.ph)
			}
			w = max(w, roww)
			h += rowh
		}
		.split {
			w = 0
			h = 0
			for child in kids {
				if c.vertical {
					w = max(w, child.pw)
					h += child.ph
				} else {
					w += child.pw
					h = max(h, child.ph)
				}
			}
			if c.vertical { h++ } else { w++ }
		}
		.group {
			w = text_width(c.text) + 4
			h = 2
			for child in c.kids {
				w = max(w, child.pw + 2)
				h = max(h, child.ph + 2)
			}
		}
		.tabs {
			mut headers := 2
			h = 3
			for page in c.kids {
				headers += text_width(page.text) + 5
				w = max(w, page.pw + 2)
				h = max(h, page.ph + 3)
			}
			w = max(w, headers)
		}
		.scroll {
			w = 16
			h = 6
		}
		.label {
			h = c.text.split('\n').len
			for line in c.text.split('\n') { w = max(w, text_width(line)) }
		}
		.button, .checkbox { w = text_width(c.text) + 4 }
		.toolbutton { w = text_width(c.text) + 2 }
		.switch { w = text_width(c.text) + 8 }
		.spinner { w = text_width(c.text) + 2 }
		.entry { w = 16 }
		.multiline, .markdown {
			w = 24
			h = 8
		}
		.date_picker {
			w = 24
			h = 9
		}
		.slider, .progress { w = 12 }
		.spin { w = 10 }
		.combo, .radio {
			for child in kids { w = max(w, text_width(child.text) + 4) }
			w = max(w, 8)
			if c.kind == .radio { h = kids.len }
		}
		.table {
			w = max(16, c.kids.len * 8)
			h = 6
		}
		.tree {
			w = 16
			h = 6
		}
		.canvas, .terminal {
			w = c.pw
			h = c.ph
		}
		else {
			w = text_width(c.text)
			h = 1
		}
	}
	c.pw = max(c.min_w, w)
	c.ph = max(c.min_h, h)
}

fn (c &Ctl) grid_dims() ([]int, []int) {
	mut cols := []int{len: 64}
	mut rows := []int{len: 64}
	for child in c.content_kids() {
		if child.col < 0 || child.col >= 64 || child.row < 0 || child.row >= 64 { continue }
		cols[child.col] = max(cols[child.col], child.pw)
		rows[child.row] = max(rows[child.row], child.ph)
	}
	mut nc, mut nr := 0, 0
	for child in c.content_kids() {
		if child.col >= 0 && child.col < 64 && child.row >= 0 && child.row < 64 {
			nc = max(nc, child.col + 1)
			nr = max(nr, child.row + 1)
		}
	}
	return cols[..nc], rows[..nr]
}

pub fn (mut c Ctl) layout(r Rect) {
	c.x = r.x
	c.y = r.y
	c.w = max(0, r.w)
	c.h = max(0, r.h)
	mut kids := c.content_kids()
	if kids.len == 0 { return }
	match c.kind {
		.window {
			mut y := c.y + 1
			for mut menu in c.kids {
				if menu.kind == .menu {
					menu.x = c.x + 2
					menu.y = y
					menu.w = text_width(menu.text) + 2
					menu.h = 1
				}
			}
			mut menus := c.kids.filter(it.kind == .menu && !it.hidden)
			mut mx := c.x + 2
			for mut menu in menus {
				menu.x = mx
				mx += menu.w + 1
			}
			if menus.len > 0 { y++ }
			for mut child in kids { child.layout(Rect{c.x + 1, y, c.w - 2, c.h - (y - c.y) - 1}) }
		}
		.box, .toolbar, .status, .popup {
			if c.vertical {
				for mut child in kids {
					if child.kind == .flow {
						child.w = c.w
						child.measure()
					}
				}
			}
			mut fixed, mut stretchy, mut dock := 0, 0, 0
			for child in kids {
				fixed += if c.vertical { child.ph } else { child.pw }
				if child.expand { stretchy++ }
				if c.vertical && child.bottom { dock += child.ph }
			}
			if !c.vertical { fixed += max(0, kids.len - 1) }
			extra := max(0, (if c.vertical { c.h } else { c.w }) - fixed)
			mut remainder := extra
			mut at := if c.vertical {
				c.y
			} else {
				c.x + if c.right && stretchy == 0 { extra } else { 0 }
			}
			mut bottom_at := c.y + c.h - dock
			for mut child in kids {
				mut size := if c.vertical { child.ph } else { child.pw }
				if child.expand && stretchy > 0 {
					grow := remainder / stretchy
					size += grow
					remainder -= grow
					stretchy--
				}
				if c.vertical {
					cy := if child.bottom { bottom_at } else { at }
					child.layout(Rect{c.x, cy, c.w, size})
					if child.bottom { bottom_at += size } else { at += size }
				} else {
					child.layout(Rect{at, c.y, size, c.h})
					at += size + 1
				}
			}
		}
		.grid {
			mut cols, rows := c.grid_dims()
			mut used, mut grow := max(0, cols.len - 1), []int{}
			for n in cols { used += n }
			for child in kids {
				if child.expand && child.col >= 0 && child.col < cols.len && child.col !in grow {
					grow << child.col
				}
			}
			mut spare := max(0, c.w - used)
			for i, col in grow {
				n := spare / (grow.len - i)
				cols[col] += n
				spare -= n
			}
			for mut child in kids {
				if child.col < 0 || child.col >= cols.len || child.row < 0 || child.row >= rows.len {
					continue
				}
				mut x, mut y := c.x, c.y
				for n in cols[..child.col] { x += n + 1 }
				for n in rows[..child.row] { y += n }
				child.layout(Rect{x, y, cols[child.col], rows[child.row]})
			}
		}
		.split {
			if kids.len == 1 {
				mut child := kids[0]
				child.layout(c.rect())
				return
			}
			mut first, mut second := kids[0], kids[1]
			space := max(0, (if c.vertical { c.h } else { c.w }) - 1)
			keep := clamp(if c.value > 0 && c.value < 1000 {
				space * c.value / 1000
			} else if c.vertical {
				first.ph
			} else {
				first.pw
			}, 0, space)
			if c.vertical {
				first.layout(Rect{c.x, c.y, c.w, keep})
				second.layout(Rect{c.x, c.y + keep + 1, c.w, space - keep})
			} else {
				first.layout(Rect{c.x, c.y, keep, c.h})
				second.layout(Rect{c.x + keep + 1, c.y, space - keep, c.h})
			}
		}
		.flow {
			mut x, mut y, mut rowh := c.x, c.y, 0
			for mut child in kids {
				if x > c.x && x + child.pw > c.x + c.w {
					x = c.x
					y += rowh
					rowh = 0
				}
				child.layout(Rect{x, y, min(child.pw, c.w), child.ph})
				x += child.pw + 1
				rowh = max(rowh, child.ph)
			}
			c.ph = y - c.y + rowh
		}
		.group, .tabs, .tabpage {
			if c.kind == .tabs {
				c.value = clamp(c.value, 0, c.kids.len - 1)
				mut x := c.x + 2
				for i, mut page in c.kids {
					page.hidden = i != c.value
					page.tab_x = x
					page.tab_w = min(text_width(page.text) + 4, max(0, c.w - 3))
					x += page.tab_w + 1
					if !page.hidden { page.layout(Rect{c.x + 1, c.y + 2, c.w - 2, c.h - 3}) }
				}
				// Keep the selected header visible when the strip is wider than the pane.
				selected := c.kids[c.value]
				offset := max(0, selected.tab_x + selected.tab_w - (c.x + c.w - 1))
				for mut page in c.kids { page.tab_x -= offset }
			} else {
				padding := if c.kind == .group { 1 } else { 0 }
				for mut child in kids {
					child.layout(Rect{c.x + padding, c.y + padding, c.w - 2 * padding, c.h - 2 * padding})
				}
			}
		}
		.scroll {
			mut child := kids[0]
			c.top = clamp(c.top, 0, child.ph - c.h)
			child.layout(Rect{c.x, c.y - c.top, max(c.w - int(c.scrollbar), child.pw), max(c.h, child.ph)})
		}
		else {}
	}
}

pub struct TreeRow {
pub:
	node  &Ctl
	depth int
}

pub fn (c &Ctl) tree_rows() []TreeRow {
	mut rows := []TreeRow{}
	c.walk_tree(0, mut rows)
	return rows
}

fn (c &Ctl) walk_tree(depth int, mut rows []TreeRow) {
	for node in c.kids {
		if node.hidden { continue }
		rows << TreeRow{node, depth}
		if node.expanded { node.walk_tree(depth + 1, mut rows) }
	}
}

pub fn (mut c Ctl) tree_add(parent &Ctl, text string) &Ctl {
	mut node := &Ctl{ kind: .treenode, text: text, expanded: true }
	mut p := if isnil(parent) { &c } else { unsafe { parent } }
	p.add(mut node)
	if isnil(c.selected_node) { c.selected_node = node }
	return node
}

pub fn (c &Ctl) hit(x int, y int) &Ctl {
	if c.hidden || c.closed || c.minimized || !c.rect().contains(x, y) { return unsafe { nil } }
	if c.kind == .scroll && c.scrollbar && x == c.x + c.w - 1 { return unsafe { c } }
	for i := c.kids.len - 1; i >= 0; i-- {
		child := c.kids[i]
		if child.kind in [.menu, .item, .treenode, .menuitem] { continue }
		hit := child.hit(x, y)
		if !isnil(hit) { return hit }
	}
	return unsafe { c }
}
