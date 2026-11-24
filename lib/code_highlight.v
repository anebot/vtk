module vtk

import math { min }

// A small, language-independent lexer. State lives only for one code block;
// highlighting walks existing glyphs without allocating token arrays.
struct CodeHighlighter {
mut:
	plain         bool
	diff          bool
	auto_diff     bool
	block_comment bool
	quote         u8
	diff_state    DiffHighlighter
}

fn code_highlighter(info string) CodeHighlighter {
	if info == '' { return CodeHighlighter{ auto_diff: true } }
	fields := info.fields()
	language := if fields.len > 0 { fields[0].to_lower() } else { '' }
	return CodeHighlighter{
		plain:     language in ['text', 'txt', 'plain', 'plaintext']
		diff:      language in ['diff', 'patch', 'udiff', 'unified-diff']
		auto_diff: language == ''
	}
}

fn (mut h CodeHighlighter) highlight(line string, mut row TextRow) {
	if h.plain { return }
	if h.auto_diff && h.quote == 0 && !h.block_comment
		&& (line.starts_with('diff --git ') || line.starts_with('--- ')
		|| line.starts_with('@@ ')) {
		h.diff = true
	}
	if h.diff {
		h.diff_state.highlight(line, mut row)
		return
	}
	mut end := 0
	mut color := ?int(none)
	for i, glyph in row.glyphs {
		at := glyph.at - row.start
		if at >= end { end, color = h.token(line, at) }
		if color != none { row.glyphs[i] = Glyph{ ...glyph, color: color } }
	}
	// Backticks and block comments may span lines; ordinary quotes end here.
	if h.quote != 96 { h.quote = 0 }
}

fn (mut h CodeHighlighter) token(line string, start int) (int, ?int) {
	mut i := start
	if h.block_comment || (h.quote == 0 && line[i] == `/` && i + 1 < line.len && line[i + 1] == `*`) {
		if !h.block_comment { i += 2 }
		h.block_comment = true
		for i < line.len {
			if line[i] == `*` && i + 1 < line.len && line[i + 1] == `/` {
				h.block_comment = false
				i += 2
				break
			}
			i++
		}
		return i, gray
	}
	if h.quote != 0 || line[i] in [u8(`'`), u8(`"`), u8(96)] {
		if h.quote == 0 {
			h.quote = line[i]
			i++
		}
		for i < line.len {
			if line[i] == `\\` {
				i = min(line.len, i + 2)
			} else if line[i] == h.quote {
				h.quote = 0
				i++
				break
			} else {
				i++
			}
		}
		return i, green
	}
	if line[i] == `#` || (line[i] == `/` && i + 1 < line.len && line[i + 1] == `/`) { return line.len, gray }
	if line[i].is_digit() {
		i++
		for i < line.len && (line[i].is_hex_digit() || line[i] in [u8(`x`), u8(`X`), u8(`o`), u8(`b`), u8(`.`), u8(`_`)]) { i++ }
		return i, cyan
	}
	if line[i].is_letter() || line[i] == `_` || line[i] >= 0x80 {
		i++
		for i < line.len && (line[i].is_alnum() || line[i] == `_` || line[i] >= 0x80) { i++ }
		token := &line[start..i]
		color := match *token {
			'as', 'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
			'def', 'default', 'defer', 'do', 'else', 'enum', 'export', 'extern', 'fn', 'for',
			'from', 'func', 'function', 'if', 'impl', 'import', 'in', 'interface', 'let',
			'match', 'mut', 'new', 'package', 'private', 'protected', 'pub', 'public',
			'return', 'static', 'struct', 'switch', 'throw', 'try', 'type', 'typedef',
			'union', 'unsafe', 'use', 'var', 'void', 'while', 'yield' { ?int(magenta) }
			'false', 'true', 'null', 'nil', 'none', 'False', 'True', 'None' { ?int(cyan) }
			else { ?int(none) }
		}
		return i, color
	}
	return i + 1, none
}
