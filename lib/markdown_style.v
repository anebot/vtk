module vtk

// Unset colors inherit from the surrounding text or the active theme. Attributes
// add to explicit Markdown emphasis; 0 leaves that element's text unadorned.
pub struct MarkdownStyle {
pub mut:
	fg   ?int
	bg   ?int
	attr int
}

// Each Markdown control owns its styles. Resolve theme-derived colors at draw
// time, so changing a theme never leaves a stale dark or light code background.
pub struct MarkdownStyles {
pub mut:
	text         MarkdownStyle
	heading      MarkdownStyle = MarkdownStyle{ attr: bold }
	inline_code  MarkdownStyle
	code_block   MarkdownStyle
	link         MarkdownStyle = MarkdownStyle{ attr: underline }
	quote        MarkdownStyle
	table_header MarkdownStyle = MarkdownStyle{ attr: bold }
	table_border MarkdownStyle
	// Percentage of foreground mixed into the background; 0 disables automatic
	// code shading. An explicit inline_code/code_block bg always takes priority.
	code_shading int = 6
}

enum MarkdownElement {
	text
	heading
	inline_code
	code_block
	link
	quote
	table_header
	table_border
}

struct MarkdownPaint {
	fg   int
	bg   int
	attr int
}

fn (styles &MarkdownStyles) paint(element MarkdownElement, theme Theme, parent MarkdownPaint) MarkdownPaint {
	style := match element {
		.text { styles.text }
		.heading { styles.heading }
		.inline_code { styles.inline_code }
		.code_block { styles.code_block }
		.link { styles.link }
		.quote { styles.quote }
		.table_header { styles.table_header }
		.table_border { styles.table_border }
	}
	fg := style.fg or {
		if element in [.heading, .table_header] { theme.accent } else { parent.fg }
	}
	bg := style.bg or {
		if element in [.inline_code, .code_block] && styles.code_shading > 0 {
			color_blend(color_as_rgb(parent.bg), color_as_rgb(parent.fg), clamp(styles.code_shading, 0, 100), 100)
		} else {
			parent.bg
		}
	}
	return MarkdownPaint{ fg: fg, bg: bg, attr: parent.attr | style.attr }
}
