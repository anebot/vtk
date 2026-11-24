module vtk

import strings

// FontStyle selects Unicode character substitutions, not an installed font.
pub enum FontStyle {
	none
	bold
	italic
	script
	doublestruck
	underline
	strikethrough
	fraktur
	bolditalic
	sansserif
	sansserifitalic
	monospace
	boldscript
	boldfraktur
	sansserifbold
	sansserifbolditalic
	openface
	smallcaps
}

// font_styles lists every FontStyle in declaration order, for pickers and menus.
pub const font_styles = [FontStyle.none, .bold, .italic, .script, .doublestruck,
	.underline, .strikethrough, .fraktur, .bolditalic, .sansserif, .sansserifitalic,
	.monospace, .boldscript, .boldfraktur, .sansserifbold, .sansserifbolditalic,
	.openface, .smallcaps]

// font_style_from_name accepts the names used by aholyc's FontStyleFromName.
pub fn font_style_from_name(name string) ?FontStyle {
	return match name.to_lower() {
		'none' { .none }
		'bold' { .bold }
		'italic' { .italic }
		'script' { .script }
		'doublestruck' { .doublestruck }
		'underline' { .underline }
		'strikethrough' { .strikethrough }
		'fraktur' { .fraktur }
		'bolditalic' { .bolditalic }
		'sansserif' { .sansserif }
		'sansserifitalic' { .sansserifitalic }
		'monospace' { .monospace }
		'boldscript' { .boldscript }
		'boldfraktur' { .boldfraktur }
		'sansserifbold', 'sansseribbold' { .sansserifbold }
		'sansserifbolditalic' { .sansserifbolditalic }
		'openface' { .openface }
		'smallcaps' { .smallcaps }
		else { return none }
	}
}

fn font_rune(r rune, style FontStyle) rune {
	if r >= `A` && r <= `Z` {
		i := int(r - `A`)
		return match style {
			.bold { rune(0x1d400 + i) }
			.italic { rune(0x1d434 + i) }
			.script {
				rune(match r { `B` { 0x212c } `E` { 0x2130 } `F` { 0x2131 } `H` { 0x210b } `I` { 0x2110 } `L` { 0x2112 } `M` { 0x2133 } `R` { 0x211b } else { 0x1d49c + i } })
			}
			.doublestruck, .openface {
				rune(match r { `C` { 0x2102 } `H` { 0x210d } `N` { 0x2115 } `P` { 0x2119 } `Q` { 0x211a } `R` { 0x211d } `Z` { 0x2124 } else { 0x1d538 + i } })
			}
			.fraktur {
				rune(match r { `C` { 0x212d } `H` { 0x210c } `I` { 0x2111 } `R` { 0x211c } `Z` { 0x2128 } else { 0x1d504 + i } })
			}
			.bolditalic { rune(0x1d468 + i) }
			.sansserif { rune(0x1d5a0 + i) }
			.sansserifitalic { rune(0x1d608 + i) }
			.monospace { rune(0x1d670 + i) }
			.boldscript { rune(0x1d4d0 + i) }
			.boldfraktur { rune(0x1d56c + i) }
			.sansserifbold { rune(0x1d5d4 + i) }
			.sansserifbolditalic { rune(0x1d63c + i) }
			else { r }
		}
	}
	if r >= `a` && r <= `z` {
		i := int(r - `a`)
		return match style {
			.bold { rune(0x1d41a + i) }
			.italic { if r == `h` { rune(0x210e) } else { rune(0x1d44e + i) } }
			.script {
				rune(match r { `e` { 0x212f } `g` { 0x210a } `o` { 0x2134 } else { 0x1d4b6 + i } })
			}
			.doublestruck, .openface { rune(0x1d552 + i) }
			.fraktur { rune(0x1d51e + i) }
			.bolditalic { rune(0x1d482 + i) }
			.sansserif { rune(0x1d5ba + i) }
			.sansserifitalic { rune(0x1d622 + i) }
			.monospace { rune(0x1d68a + i) }
			.boldscript { rune(0x1d4ea + i) }
			.boldfraktur { rune(0x1d586 + i) }
			.sansserifbold { rune(0x1d5ee + i) }
			.sansserifbolditalic { rune(0x1d656 + i) }
			.smallcaps { [rune(0x1d00), 0x299, 0x1d04, 0x1d05, 0x1d07, 0x493, 0x262, 0x29c, 0x26a, 0x1d0a, 0x1d0b, 0x29f, 0x1d0d, 0x274, 0x1d0f, 0x1d18, 0x1eb, 0x280, `s`, 0x1d1b, 0x1d1c, 0x1d20, 0x1d21, `x`, 0x28f, 0x1d22]![i] }
			else { r }
		}
	}
	if r >= `0` && r <= `9` {
		i := int(r - `0`)
		return match style {
			.bold { rune(0x1d7ce + i) }
			.doublestruck { rune(0x1d7d8 + i) }
			.sansserif { rune(0x1d7e2 + i) }
			.sansserifbold { rune(0x1d7ec + i) }
			.monospace { rune(0x1d7f6 + i) }
			else { r }
		}
	}
	return r
}

fn font_ascii(r rune) bool {
	return (r >= `A` && r <= `Z`) || (r >= `a` && r <= `z`) || (r >= `0` && r <= `9`)
}

fn font_mark(style FontStyle) rune {
	return match style {
		.underline { rune(0x332) }
		.strikethrough { rune(0x335) }
		else { rune(0) }
	}
}

// font_convert styles ASCII letters and supported digits; other text passes through.
pub fn font_convert(text string, style FontStyle) string {
	return font_translate(text, .none, style)
}

// font_translate converts characters produced by a known source style. Characters
// that a style leaves unchanged cannot be distinguished from original text.
pub fn font_translate(text string, from FontStyle, to FontStyle) string {
	if from == to { return text }
	mut out := strings.new_builder(text.len)
	runes := text.runes()
	mut i := 0
	for i < runes.len {
		mut r := runes[i]
		mark := font_mark(from)
		if mark != 0 && font_ascii(r) && i + 1 < runes.len && runes[i + 1] == mark {
			i++
		} else if from != .none && mark == 0 && !font_ascii(r) {
			alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
			for index in 0 .. alphabet.len {
				candidate := rune(alphabet[index])
				if font_rune(candidate, from) == r {
					r = candidate
					break
				}
			}
		}
		out.write_string(font_rune(r, to).str())
		if font_ascii(r) && font_mark(to) != 0 { out.write_string(font_mark(to).str()) }
		i++
	}
	return out.str()
}

// font_format_tags expands non-nested <bold>text</bold> style tags. Unknown
// paired tags lose their wrapper; unmatched tags remain literal.
pub fn font_format_tags(text string) string {
	mut out := strings.new_builder(text.len)
	mut i := 0
	for i < text.len {
		if text[i] == `<` {
			mut end := i + 1
			for end < text.len && ((text[end] >= `a` && text[end] <= `z`) || (text[end] >= `A` && text[end] <= `Z`)) { end++ }
			if end > i + 1 && end < text.len && text[end] == `>` {
				name := text[i + 1..end]
				mut close := end + 1
				for close + name.len + 3 <= text.len {
					if text[close..close + 2] == '</' && text[close + 2..close + 2 + name.len].to_lower() == name.to_lower() && text[close + 2 + name.len] == `>` {
						style := font_style_from_name(name) or { FontStyle.none }
						out.write_string(font_convert(text[end + 1..close], style))
						i = close + name.len + 3
						break
					}
					close++
				}
				if close + name.len + 3 <= text.len { continue }
			}
		}
		out.write_u8(text[i])
		i++
	}
	return out.str()
}
