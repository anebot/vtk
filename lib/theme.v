module vtk

// Basic ANSI colors retain the same numbering as lib/term.
pub const black = 0
pub const red = 1
pub const green = 2
pub const yellow = 3
pub const blue = 4
pub const magenta = 5
pub const cyan = 6
pub const white = 7
pub const gray = 8
pub const bright_white = 15
pub const bold = 1
pub const underline = 2
pub const italic = 4
pub const reverse = 8

pub struct Theme {
pub mut:
	desk_fg           int = cyan
	desk_bg           int = blue
	bg                int = blue
	fg                int = white
	dim               int = cyan
	frame             int = 14
	title             int = black
	title_bg          int = white
	title_bg_end      int = color_rgb(112, 168, 224)
	inactive_title    int = black
	inactive_title_bg int = color_rgb(128, 144, 164)
	inactive_title_bg_end int = color_rgb(200, 212, 228)
	btn_bg            int = green
	btn_fg            int = black
	focus_bg          int = cyan
	focus_fg          int = black
	field_bg          int = blue
	field_fg          int = bright_white
	sel_bg            int = green
	sel_fg            int = black
	bar_bg            int = blue
	bar_fg            int = bright_white
	menu_bg           int = gray
	menu_fg           int = black
	tool_bg           int = cyan
	tool_fg           int = black
	accent            int = bright_white
	ascii             bool
}

pub fn theme_default() Theme { return Theme{} }

pub fn color_rgb(r int, g int, b int) int {
	return 0x1000000 | clamp(r, 0, 255) << 16 | clamp(g, 0, 255) << 8 | clamp(b, 0, 255)
}

pub fn color_256(index int) int { return 0x2000000 | clamp(index, 0, 255) }

fn color_as_rgb(color int) int {
	if color & 0x1000000 != 0 { return color & 0xffffff }
	index := if color & 0x2000000 != 0 { color & 255 } else { color & 15 }
	if index < 16 {
		return [0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, 0xe5e5e5,
			0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff][index]
	}
	if index >= 232 {
		level := 8 + (index - 232) * 10
		return level << 16 | level << 8 | level
	}
	levels := [0, 95, 135, 175, 215, 255]
	cube := index - 16
	return levels[cube / 36] << 16 | levels[cube / 6 % 6] << 8 | levels[cube % 6]
}

fn color_blend(start int, end int, position int, span int) int {
	return color_rgb(
		(((start >> 16) & 255) * (span - position) + ((end >> 16) & 255) * position) / span,
		(((start >> 8) & 255) * (span - position) + ((end >> 8) & 255) * position) / span,
		((start & 255) * (span - position) + (end & 255) * position) / span)
}

const theme_names = ['Borland', 'Light Borland', 'Dark', 'Light', 'Teal', 'Modern', 'Serial', 'wineight']

fn default_title_gradient_end(background int, foreground int, inactive bool) int {
	for i in 0 .. theme_names.len {
		t := theme_preset(unsafe { Preset(i) })
		if background == if inactive { t.inactive_title_bg } else { t.title_bg } {
			return if inactive { t.inactive_title_bg_end } else { t.title_bg_end }
		}
	}
	return color_blend(color_as_rgb(background), color_as_rgb(foreground), 1, 4)
}

pub enum Preset {
	borland
	light_borland
	dark
	light
	teal
	modern
	serial
	wineight
}

pub fn theme_preset(preset Preset) Theme {
	mut t := Theme{}
	match preset {
		.borland {}
		.light_borland {
			t.bg = white
			t.fg = black
			t.dim = color_rgb(90, 96, 104)
			t.frame = blue
			t.title = bright_white
			t.title_bg = blue
			t.title_bg_end = color_rgb(16, 120, 192)
			t.menu_bg = blue
			t.menu_fg = bright_white
			t.accent = blue
		}
		.dark {
			t.desk_bg = color_rgb(16, 18, 22)
			t.desk_fg = color_rgb(27, 31, 37)
			t.bg = color_rgb(24, 27, 32)
			t.fg = color_rgb(230, 233, 239)
			t.dim = color_rgb(166, 174, 186)
			t.frame = color_rgb(128, 151, 179)
			t.title = color_rgb(248, 250, 252)
			t.title_bg = color_rgb(44, 67, 96)
			t.title_bg_end = color_rgb(16, 116, 188)
			t.inactive_title = color_rgb(244, 246, 250)
			t.inactive_title_bg = color_rgb(56, 64, 76)
			t.inactive_title_bg_end = color_rgb(100, 112, 128)
			t.btn_bg = color_rgb(55, 65, 81)
			t.btn_fg = t.fg
			t.focus_bg = color_rgb(52, 84, 125)
			t.focus_fg = t.title
			t.field_bg = color_rgb(14, 17, 22)
			t.field_fg = t.fg
			t.sel_bg = color_rgb(41, 65, 94)
			t.sel_fg = t.title
			t.bar_bg = color_rgb(33, 38, 47)
			t.bar_fg = t.fg
			t.menu_bg = t.bar_bg
			t.menu_fg = t.fg
			t.tool_bg = color_rgb(38, 44, 54)
			t.tool_fg = t.fg
			t.accent = color_rgb(141, 184, 239)
		}
		.light {
			t.desk_bg = white
			t.desk_fg = gray
			t.bg = bright_white
			t.fg = black
			t.dim = color_rgb(90, 96, 104)
			t.frame = blue
			t.title = bright_white
			t.title_bg = blue
			t.title_bg_end = color_rgb(16, 120, 192)
			t.field_bg = white
			t.field_fg = black
			t.tool_bg = white
			t.tool_fg = black
			t.accent = blue
		}
		.teal {
			t.desk_bg = cyan
			t.desk_fg = blue
			t.bg = cyan
			t.fg = black
			t.dim = blue
			t.frame = bright_white
			t.title_bg = color_rgb(102, 210, 198)
			t.title_bg_end = color_rgb(184, 236, 226)
			t.inactive_title_bg = color_rgb(100, 150, 150)
			t.inactive_title_bg_end = color_rgb(180, 206, 206)
			t.focus_bg = blue
			t.focus_fg = bright_white
			t.sel_bg = blue
			t.sel_fg = bright_white
			t.tool_bg = blue
			t.tool_fg = white
			t.accent = blue
		}
		.modern {
			t.desk_bg = color_rgb(24, 27, 29)
			t.desk_fg = color_rgb(38, 42, 44)
			t.bg = color_rgb(35, 39, 41)
			t.fg = color_rgb(218, 222, 218)
			t.dim = color_rgb(143, 153, 146)
			t.frame = color_rgb(151, 177, 152)
			t.title = t.fg
			t.title_bg = color_rgb(26, 44, 30)
			t.title_bg_end = color_rgb(70, 96, 76)
			t.inactive_title = color_rgb(232, 238, 232)
			t.inactive_title_bg = color_rgb(54, 64, 54)
			t.inactive_title_bg_end = color_rgb(88, 104, 92)
			t.btn_bg = color_rgb(62, 73, 65)
			t.btn_fg = t.fg
			t.focus_bg = color_rgb(72, 98, 78)
			t.focus_fg = t.fg
			t.field_bg = color_rgb(26, 29, 30)
			t.field_fg = t.fg
			t.sel_bg = t.focus_bg
			t.sel_fg = t.fg
			t.bar_bg = t.field_bg
			t.bar_fg = t.fg
			t.menu_bg = color_rgb(46, 51, 49)
			t.menu_fg = t.fg
			t.tool_bg = t.menu_bg
			t.tool_fg = t.fg
			t.accent = t.frame
		}
		.serial {
			t.ascii = true
			t.desk_fg = black
			t.desk_bg = black
			t.bg = black
			t.fg = white
			t.dim = gray
			t.frame = white
			t.title = white
			t.title_bg = blue
			t.title_bg_end = color_rgb(16, 100, 170)
			t.inactive_title_bg = white
			t.inactive_title_bg_end = color_rgb(144, 144, 144)
			t.tool_bg = black
			t.tool_fg = white
		}
		.wineight {
			t.desk_bg = color_rgb(0, 128, 128)
			t.desk_fg = t.desk_bg
			t.bg = color_rgb(192, 192, 192)
			t.fg = color_rgb(0, 0, 0)
			t.dim = color_rgb(72, 72, 72)
			t.frame = color_rgb(128, 128, 128)
			t.title = color_rgb(255, 255, 255)
			t.title_bg = color_rgb(0, 0, 128)
			t.title_bg_end = color_rgb(16, 120, 192)
			t.inactive_title = t.fg
			t.inactive_title_bg = color_rgb(128, 128, 128)
			t.inactive_title_bg_end = t.bg
			t.btn_bg = t.bg
			t.btn_fg = t.fg
			t.focus_bg = t.title_bg
			t.focus_fg = t.title
			t.field_bg = t.title
			t.field_fg = t.fg
			t.sel_bg = t.title_bg
			t.sel_fg = t.title
			t.bar_bg = t.bg
			t.bar_fg = t.fg
			t.menu_bg = t.bg
			t.menu_fg = t.fg
			t.tool_bg = t.bg
			t.tool_fg = t.fg
			t.accent = t.title_bg
		}
	}
	return t
}
