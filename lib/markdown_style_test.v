module vtk

fn test_markdown_code_is_subtle_in_dark_and_light_themes() {
	for preset in [Preset.modern, .dark, .light, .wineight, .borland] {
		mut app := new_app()
		app.theme = theme_preset(preset)
		app.screen.resize(60, 12)
		mut c := markdown('before `inline` after\n\n```v\nblock()\n\nend()\n```')
		c.markdown_mode(.read)
		c.md.hide_status = true
		c.layout(Rect{0, 0, 60, 12})
		app.draw_editor(mut c)
		code := app.screen.cells[7]
		assert code.attr & reverse == 0, '${preset}: code must not invert foreground and background'
		assert code.fg == app.theme.fg
		foreground := color_as_rgb(app.theme.fg)
		background := color_as_rgb(app.theme.bg)
		shade := color_as_rgb(code.bg)
		for shift in [0, 8, 16] {
			assert abs(((shade >> shift) & 255) - ((background >> shift) & 255)) <= 16
		}
		assert shade != foreground
		assert app.screen.cells[3 * 60].bg == code.bg
		assert app.screen.cells[4 * 60 + 30].bg == code.bg // Empty code rows retain the same subtle panel.
	}
}

fn test_markdown_styles_are_per_control_and_can_override_colors_and_attributes() {
	mut app := new_app()
	app.theme = theme_preset(.modern)
	app.screen.resize(60, 14)
	mut c := markdown('# Heading\nplain `code` [link](target)\n> quote\n```v\nblock()\n```\n\n| Header |\n| --- |\n| `value` |')
	c.markdown_mode(.read)
	c.md.hide_status = true
	c.md.styles = MarkdownStyles{
		heading:      MarkdownStyle{ fg: green, attr: italic }
		inline_code:  MarkdownStyle{ fg: yellow, bg: black, attr: underline }
		code_block:   MarkdownStyle{ fg: cyan, bg: blue, attr: italic }
		link:         MarkdownStyle{ fg: magenta, attr: italic }
		quote:        MarkdownStyle{ fg: gray }
		table_header: MarkdownStyle{ fg: red, attr: underline }
		table_border: MarkdownStyle{ fg: green }
	}
	c.layout(Rect{0, 0, 60, 14})
	app.draw_editor(mut c)
	heading := app.screen.cells[0]
	assert heading.fg == green && heading.attr == italic
	code := app.screen.cells[60 + 6]
	assert code.fg == yellow && code.bg == black && code.attr == underline
	link := app.screen.cells[60 + 11]
	assert link.fg == magenta && link.attr == italic
	assert app.screen.cells[2 * 60].fg == gray
	assert app.screen.cells[4 * 60].fg == cyan && app.screen.cells[4 * 60].bg == blue
	assert app.screen.cells[4 * 60].attr == italic
	assert app.screen.cells[8 * 60].fg == green // Table border.
	assert app.screen.cells[8 * 60 + 2].fg == red // Header text.
	assert app.screen.cells[8 * 60 + 2].attr == underline
	mut other := markdown('`code`')
	other.md.hide_status = true
	other.layout(Rect{0, 12, 60, 1})
	app.draw_editor(mut other)
	assert app.screen.cells[12 * 60].fg == app.theme.fg
	assert app.screen.cells[12 * 60].attr == 0
}

fn test_code_background_follows_theme_changes_and_can_be_disabled() {
	mut app := new_app()
	app.screen.resize(40, 6)
	mut c := markdown('plain `code`\n```v\nblock\n```')
	c.markdown_mode(.read)
	c.md.hide_status = true
	c.layout(Rect{0, 0, 40, 6})
	app.theme = theme_preset(.modern)
	app.draw_editor(mut c)
	dark := app.screen.cells[6].bg
	app.theme = theme_preset(.wineight)
	app.draw_editor(mut c)
	assert app.screen.cells[6].bg != dark
	assert app.screen.cells[6].fg == app.theme.fg
	c.md.styles.code_shading = 0
	app.draw_editor(mut c)
	assert app.screen.cells[6].bg == app.theme.bg
	assert app.screen.cells[2 * 40 + 15].bg == app.theme.bg
	c.md.styles.inline_code.bg = black // An explicit black background is not inheritance.
	c.md.styles.inline_code.attr = reverse
	c.anchor = 'plain `'.len
	c.cursor = 'plain `code'.len
	app.draw_editor(mut c)
	selected := app.screen.cells[6]
	assert selected.fg == app.theme.sel_fg && selected.bg == app.theme.sel_bg
	assert selected.attr & reverse == 0
	c.anchor = -1
	c.disabled = true
	c.md.styles.inline_code.fg = red
	app.draw_editor(mut c)
	assert app.screen.cells[6].fg == app.theme.dim
}
