module main

import strconv
import strings

struct Attribute {
	name  string
	value string // A V expression, including quotes for literal strings.
}

struct Node {
	tag string
	pos int
mut:
	id       string
	attrs    []Attribute
	children []Node
	code     []string
}

struct Parser {
	source string
	file   string
mut:
	pos int
}

fn diagnostic(source string, file string, pos int, message string) IError {
	prefix := source[..pos]
	line := prefix.count('\n') + 1
	column := prefix.all_after_last('\n').len + 1
	return error('${file}:${line}:${column}: ${message}')
}

fn (p &Parser) fail(message string) IError {
	return diagnostic(p.source, p.file, p.pos, message)
}

fn (p &Parser) starts(text string) bool {
	return p.source[p.pos..].starts_with(text)
}

// Comments are shared by markup and embedded V blocks. V block comments nest.
fn (mut p Parser) comment() !bool {
	if p.starts('//') || p.starts('#') {
		for p.pos < p.source.len && p.source[p.pos] != `\n` {
			p.pos++
		}
		return true
	}
	if !p.starts('/*') {
		return false
	}
	p.pos += 2
	mut depth := 1
	for p.pos < p.source.len {
		if p.starts('/*') {
			depth++
			p.pos += 2
		} else if p.starts('*/') {
			depth--
			p.pos += 2
			if depth == 0 {
				return true
			}
		} else {
			p.pos++
		}
	}
	return p.fail('unterminated block comment')
}

fn (mut p Parser) space() ! {
	for p.pos < p.source.len {
		if p.source[p.pos].is_space() || p.source[p.pos] == `,` {
			p.pos++
		} else if !p.comment()! {
			break
		}
	}
}

fn (mut p Parser) word() !string {
	start := p.pos
	for p.pos < p.source.len {
		ch := p.source[p.pos]
		if ch.is_space() || ch in [`,`, `;`, `{`, `}`, `=`, `:`, `'`, `"`] {
			break
		}
		p.pos++
	}
	if p.pos == start {
		return p.fail('expected a name or value')
	}
	return p.source[start..p.pos]
}

fn (mut p Parser) quoted(v_code bool) !string {
	quote := p.source[p.pos]
	raw := v_code && quote != `\`` && p.pos > 0 && p.source[p.pos - 1] == `r`
	interpolation := v_code && quote != `\`` && !raw
	p.pos++
	start := p.pos
	for p.pos < p.source.len {
		if interpolation && p.starts('\${') {
			p.pos++
			p.block()!
			continue
		}
		if p.source[p.pos] == quote {
			body := p.source[start..p.pos]
			p.pos++
			return body
		}
		if !raw && p.source[p.pos] == `\\` {
			p.pos++
		}
		if p.pos < p.source.len {
			p.pos++
		}
	}
	return p.fail('unterminated quoted string')
}

// Read balanced braces without interpreting the V expressions inside them.
fn (mut p Parser) block() !string {
	p.pos++
	start := p.pos
	mut depth := 1
	for p.pos < p.source.len {
		ch := p.source[p.pos]
		if ch in [`'`, `"`, `\``] {
			p.quoted(true)!
			continue
		}
		if p.comment()! {
			continue
		}
		if ch == `{` {
			depth++
		} else if ch == `}` {
			depth--
			if depth == 0 {
				body := p.source[start..p.pos]
				p.pos++
				return body
			}
		}
		p.pos++
	}
	return p.fail('unterminated code or expression block')
}

fn v_string(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
		.replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace('\x00', '\\x00')
		.replace('\a', '\\a').replace('\b', '\\b').replace('\f', '\\f').replace('\v', '\\v') + "'"
}

fn dedent(code string) string {
	lines := code.split_into_lines()
	mut indent := code.len
	for line in lines {
		if line.trim_space() != '' {
			leading := line.len - line.trim_left(' \t').len
			if leading < indent {
				indent = leading
			}
		}
	}
	return lines.map(if it.len >= indent { it[indent..] } else { '' }).join('\n').trim_space()
}

fn (mut p Parser) value() !string {
	p.space()!
	if p.pos == p.source.len {
		return p.fail('expected an attribute value')
	}
	if p.source[p.pos] == `{` {
		value := p.block()!.trim_space()
		if value == '' {
			return p.fail('empty V expression')
		}
		return value
	}
	if p.source[p.pos] in [`'`, `"`] {
		quote := p.source[p.pos]
		mut body := p.quoted(false)!
		mut value := strings.new_builder(body.len)
		for body.len > 0 {
			ch := strconv.unquote_char(body, quote) or {
				return p.fail('invalid string escape')
			}
			value.write_string(ch.value.str())
			body = ch.tail
		}
		return v_string(value.str())
	}
	word := p.word()!
	// Gtkon's bare words are strings; numbers and booleans are convenient literals.
	if word in ['true', 'false'] || word[0].is_digit() || (word[0] == `-` && word.len > 1
		&& word[1].is_digit()) {
		return word
	}
	return v_string(word)
}

fn (mut p Parser) node(depth int) !Node {
	if depth > 128 {
		return p.fail('markup nesting exceeds 128 levels')
	}
	p.space()!
	pos := p.pos
	tag := p.word()!
	mut node := Node{ tag: tag, pos: pos }
	mut names := map[string]bool{}
	for {
		p.space()!
		if p.pos == p.source.len {
			return p.fail('expected { or ; after ${tag}')
		}
		if p.starts(';') {
			p.pos++
			return node
		}
		if p.starts('{') {
			p.pos++
			break
		}
		name := p.word()!
		if name.starts_with('$') {
			if node.id != '' {
				return p.fail('duplicate widget identifier')
			}
			node.id = name[1..]
			if !identifier(node.id) || node.id.starts_with('vml_') {
				return p.fail('invalid widget identifier ${name}')
			}
			continue
		}
		negative := name.starts_with('!')
		key := (if negative { name[1..] } else { name }).replace('-', '_')
		if !identifier(key) || key in ['id', 'parent', 'child'] {
			return p.fail('invalid or reserved attribute ${name}')
		}
		if key in names {
			return p.fail('duplicate attribute ${name}')
		}
		names[key] = true
		p.space()!
		mut value := if negative { 'false' } else { 'true' }
		if p.starts('=') || p.starts(':') {
			if negative {
				return p.fail('!${key} cannot also have a value')
			}
			p.pos++
			value = p.value()!
		}
		node.attrs << Attribute{key, value}
	}
	for {
		p.space()!
		if p.pos == p.source.len {
			return p.fail('expected } to close ${tag}')
		}
		if p.starts('}') {
			p.pos++
			return node
		}
		if p.starts('-{') {
			p.pos++
			node.code << dedent(p.block()!)
			if !p.starts('-') {
				return p.fail('embedded code must end with }-')
			}
			p.pos++
		} else {
			node.children << p.node(depth + 1)!
		}
	}
}

fn parse(source string, file string) !Node {
	mut p := Parser{ source: source, file: file }
	root := p.node(0)!
	p.space()!
	if p.pos != source.len {
		return p.fail('expected one root widget per file')
	}
	return root
}

fn identifier(name string) bool {
	if name.len == 0 || name[0] < `a` || name[0] > `z` {
		return false
	}
	for ch in name {
		if !(ch.is_letter() || ch.is_digit() || ch == `_`) {
			return false
		}
	}
	return name !in ['as', 'asm', 'assert', 'atomic', 'break', 'const', 'continue', 'defer', 'else',
		'enum', 'false', 'fn', 'for', 'go', 'goto', 'if', 'import', 'in', 'interface', 'is', 'isreftype',
		'lock', 'match', 'module', 'mut', 'none', 'or', 'pub', 'return', 'rlock', 'select', 'shared',
		'sizeof', 'spawn', 'static', 'struct', 'true', 'type', 'typeof', 'union', 'unsafe', 'volatile',
		'__global']
}
