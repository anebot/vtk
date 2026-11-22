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
	desk_fg  int = cyan
	desk_bg  int = blue
	bg       int = blue
	fg       int = white
	dim      int = cyan
	frame    int = 14
	title    int = black
	title_bg int = white
	inactive_title int = white
	inactive_title_bg int = black
	btn_bg   int = green
	btn_fg   int = black
	focus_bg int = cyan
	field_bg int = blue
	field_fg int = bright_white
	sel_bg   int = green
	sel_fg   int = bright_white
	bar_bg   int = blue
	bar_fg   int = bright_white
	menu_bg  int = gray
	menu_fg  int = bright_white
	tool_bg  int = cyan
	tool_fg  int = black
	accent   int = blue
	ascii    bool
}

pub fn theme_default() Theme { return Theme{} }

pub fn color_rgb(r int, g int, b int) int {
	return 0x1000000 | clamp(r, 0, 255) << 16 | clamp(g, 0, 255) << 8 | clamp(b, 0, 255)
}

pub fn color_256(index int) int { return 0x2000000 | clamp(index, 0, 255) }

pub enum Preset {
	borland
	light_borland
	dark
	light
	teal
	modern
	serial
}

pub fn theme_preset(preset Preset) Theme {
	mut t := Theme{}
	match preset {
		.borland {}
		.light_borland {
			t.bg = white
			t.fg = black
			t.dim = gray
			t.frame = blue
			t.title = bright_white
			t.title_bg = blue
			t.menu_bg = blue
		}
		.dark {
			t.desk_bg = black
			t.desk_fg = gray
			t.bg = black
			t.fg = white
			t.frame = white
			t.title = bright_white
			t.title_bg = blue
			t.tool_bg = gray
			t.tool_fg = white
			t.focus_bg = blue
		}
		.light {
			t.desk_bg = white
			t.desk_fg = gray
			t.bg = bright_white
			t.fg = black
			t.dim = gray
			t.frame = blue
			t.title = bright_white
			t.title_bg = blue
			t.field_bg = white
			t.field_fg = black
			t.tool_bg = white
			t.tool_fg = black
		}
		.teal {
			t.desk_bg = cyan
			t.desk_fg = blue
			t.bg = cyan
			t.fg = black
			t.frame = bright_white
			t.tool_bg = blue
			t.tool_fg = white
		}
		.modern {
			t.desk_bg = color_rgb(24, 27, 29)
			t.desk_fg = color_rgb(38, 42, 44)
			t.bg = color_rgb(35, 39, 41)
			t.fg = color_rgb(218, 222, 218)
			t.dim = color_rgb(110, 118, 114)
			t.frame = color_rgb(151, 177, 152)
			t.title = t.fg
			t.title_bg = color_rgb(53, 68, 58)
			t.inactive_title = color_rgb(178, 186, 180)
			t.inactive_title_bg = color_rgb(43, 48, 45)
			t.btn_bg = color_rgb(62, 73, 65)
			t.btn_fg = t.fg
			t.focus_bg = color_rgb(72, 98, 78)
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
			t.tool_bg = black
			t.tool_fg = white
		}
	}
	return t
}
