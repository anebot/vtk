module spread

import math
import strconv

struct Formula {
	sheet &Sheet
	text string
mut:
	pos int
	depth int
	visiting map[string]bool
}

fn (mut p Formula) space() { for p.pos < p.text.len && p.text[p.pos] in [` `, `\t`] { p.pos++ } }

fn (mut p Formula) take(ch u8) bool {
	p.space()
	if p.pos < p.text.len && p.text[p.pos] == ch { p.pos++; return true }
	return false
}

fn (mut p Formula) expression() !f64 {
	mut value := p.product()!
	for {
		if p.take(`+`) { value += p.product()! }
		else if p.take(`-`) { value -= p.product()! }
		else { return value }
	}
	return value
}

fn (mut p Formula) product() !f64 {
	mut value := p.factor()!
	for {
		if p.take(`*`) { value *= p.factor()! }
		else if p.take(`/`) {
			right := p.factor()!
			if right == 0 { return error('#DIV/0!') }
			value /= right
		} else { return value }
	}
	return value
}

fn (mut p Formula) reference() !(int, int) {
	p.space()
	start := p.pos
	for p.pos < p.text.len && ((p.text[p.pos] >= `A` && p.text[p.pos] <= `Z`) || (p.text[p.pos] >= `a` && p.text[p.pos] <= `z`)) { p.pos++ }
	for p.pos < p.text.len && p.text[p.pos] >= `0` && p.text[p.pos] <= `9` { p.pos++ }
	return cell_address(p.text[start..p.pos])!
}

fn (mut p Formula) factor() !f64 {
	p.space()
	p.depth++
	defer { p.depth-- }
	if p.depth > 128 { return error('#DEPTH!') }
	if p.take(`+`) { return p.factor()! }
	if p.take(`-`) { return -p.factor()! }
	if p.take(`(`) {
		value := p.expression()!
		if !p.take(`)`) { return error('#SYNTAX!') }
		return value
	}
	start := p.pos
	for p.pos < p.text.len && ((p.text[p.pos] >= `A` && p.text[p.pos] <= `Z`) || (p.text[p.pos] >= `a` && p.text[p.pos] <= `z`)) { p.pos++ }
	if p.pos > start {
		name := p.text[start..p.pos].to_upper()
		if p.take(`(`) { return p.function(name)! }
		p.pos = start
		row, column := p.reference()!
		return p.sheet.number(row, column, mut p.visiting)!
	}
	for p.pos < p.text.len && ((p.text[p.pos] >= `0` && p.text[p.pos] <= `9`) || p.text[p.pos] == `.`) { p.pos++ }
	if p.pos < p.text.len && p.text[p.pos] in [`e`, `E`] {
		p.pos++
		if p.pos < p.text.len && p.text[p.pos] in [`+`, `-`] { p.pos++ }
		for p.pos < p.text.len && p.text[p.pos] >= `0` && p.text[p.pos] <= `9` { p.pos++ }
	}
	if start == p.pos { return error('#SYNTAX!') }
	return strconv.atof64(p.text[start..p.pos], allow_overflow: true) or { return error('#SYNTAX!') }
}

fn (mut p Formula) function(name string) !f64 {
	if name !in ['SUM', 'AVG', 'MIN', 'MAX', 'COUNT'] { return error('#NAME?') }
	mut values := []f64{}
	if !p.take(`)`) {
		for {
			start := p.pos
			mut is_range := false
			if row, column := p.reference() {
				if p.take(`:`) {
					last_row, last_column := p.reference()!
					if last_row >= p.sheet.data.cells.len || last_column >= p.sheet.columns() || row >= p.sheet.data.cells.len || column >= p.sheet.columns() { return error('#REF!') }
					for r in math.min(row, last_row) .. math.max(row, last_row) + 1 {
						for c in math.min(column, last_column) .. math.max(column, last_column) + 1 {
							raw := p.sheet.raw(r, c).trim_space()
							if raw == '' { continue }
							if !raw.starts_with('=') { strconv.atof64(raw) or { continue } }
							values << p.sheet.number(r, c, mut p.visiting)!
						}
					}
					is_range = true
				}
			}
			if !is_range { p.pos = start; values << p.expression()! }
			if p.take(`)`) { break }
			if !p.take(`,`) { return error('#SYNTAX!') }
		}
	}
	if name == 'COUNT' { return f64(values.len) }
	if values.len == 0 { return if name == 'SUM' { f64(0) } else { return error('#DIV/0!') } }
	mut result := if name in ['MIN', 'MAX'] { values[0] } else { f64(0) }
	for value in values {
		result = match name {
			'MIN' { if value < result { value } else { result } }
			'MAX' { if value > result { value } else { result } }
			else { result + value }
		}
	}
	return if name == 'AVG' { result / values.len } else { result }
}

