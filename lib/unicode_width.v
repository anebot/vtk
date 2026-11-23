module vtk

import encoding.utf8

struct RuneRange {
	first rune
	last  rune
}

fn in_rune_ranges(r rune, ranges []RuneRange) bool {
	mut low, mut high := 0, ranges.len
	for low < high {
		middle := low + (high - low) / 2
		if r < ranges[middle].first {
			high = middle
		} else if r > ranges[middle].last {
			low = middle + 1
		} else {
			return true
		}
	}
	return false
}

// A terminal draws an emoji sequence as one grapheme, including its variation
// selector, skin tone, flag pair or joined pictographs. Never add their widths.
fn grapheme_width(text string) int {
	if text.len == 1 { return rune_width(rune(text[0])) }
	mut width := 0
	mut emoji, mut presentation := false, false
	mut at := 0
	for at < text.len {
		r, n := utf8.decode_rune_at(text, at)
		at += max(1, n)
		width = max(width, rune_width(r))
		emoji = emoji || in_rune_ranges(r, emoji_base)
		presentation = presentation || r == 0xfe0f || r == 0x20e3
	}
	return if emoji && presentation { 2 } else { width }
}

fn glyph_text(g Glyph) string { return if g.text == '' { display_rune(g.r) } else { g.text } }

fn glyph_width(g Glyph) int {
	return if g.text == '' { rune_width(g.r) } else { grapheme_width(g.text) }
}

// Inline parsing retains styles and source spans per rune. Coalesce contiguous
// runs afterwards so Markdown and plain editors wrap, hit-test and draw exactly
// the same graphemes as Screen.text(). Syntax and link boundaries stay intact.
fn grapheme_glyphs(glyphs []Glyph) []Glyph {
	mut result := []Glyph{cap: glyphs.len}
	mut first := 0
	for first < glyphs.len {
		mut end := first + 1
		for end < glyphs.len && glyphs[end].at == glyphs[end - 1].end
			&& glyphs[end].attr == glyphs[first].attr && glyphs[end].link == glyphs[first].link
			&& glyphs[end].element == glyphs[first].element
			&& glyphs[end].task == glyphs[first].task {
			end++
		}
		if end == first + 1 {
			result << glyphs[first]
			first = end
			continue
		}
		if glyphs[first..end].all(it.r < 0x80 && it.text == '') {
			result << glyphs[first..end]
			first = end
			continue
		}
		text := glyphs[first..end].map(glyph_text(it)).join('')
		mut index := first
		for cluster in text.graphemes() {
			start := index
			mut bytes := 0
			for index < end && bytes < cluster.len {
				bytes += glyph_text(glyphs[index]).len
				index++
			}
			result << Glyph{
				...glyphs[start]
				end:  glyphs[index - 1].end
				text: if index == start + 1 { glyphs[start].text } else { cluster }
			}
		}
		first = end
	}
	return result
}
