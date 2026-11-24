module vtk

fn test_font_styles_and_names() {
	$for member in FontStyle.values {
		assert font_style_from_name(member.name) or { panic('missing name') } == member.value
	}
	assert font_style_from_name('SaNsSeRiBbOlD') or { panic('alias') } == FontStyle.sansserifbold
	assert font_style_from_name('missing') == none
	assert font_convert('Abz 09 é🙂', .bold) == '𝐀𝐛𝐳 𝟎𝟗 é🙂'
	assert font_convert('ABEFHILMRegoh', .script) == '𝒜ℬℰℱℋℐℒℳℛℯℊℴ𝒽'
	assert font_convert('CHNPQRZ', .doublestruck) == 'ℂℍℕℙℚℝℤ'
	assert font_convert('CHIRZ', .fraktur) == 'ℭℌℑℜℨ'
	assert font_convert('h0', .italic) == 'ℎ0'
	assert font_convert('a1 Z!', .underline) == 'a̲1̲ Z̲!'
	assert font_convert('a1', .strikethrough) == 'a̵1̵'
	assert font_convert('abcxyz', .smallcaps) == 'ᴀʙᴄxʏᴢ'
	assert font_convert('A0', .openface) == '𝔸0'
}

fn test_font_translation() {
	original := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 é🙂'
	$for member in FontStyle.values {
		styled := font_convert(original, member.value)
		assert font_translate(styled, member.value, .none) == original
		assert font_translate(styled, member.value, .bold) == font_convert(original, .bold)
	}
}

fn test_font_tags_and_screen() {
	assert font_format_tags('a <BOLD>Hi 2</bold> <unknown>é</UNKNOWN> <italic>oops') == 'a 𝐇𝐢 𝟐 é <italic>oops'
	assert font_format_tags('<bold>x</bold><underline>Hi</underline>') == '𝐱H̲i̲'
	mut screen := Screen{}
	screen.resize(10, 1)
	styled := font_format_tags('<bold>A</bold><underline>B</underline>!')
	assert text_width(styled) == 3
	screen.text(0, 0, styled, 1, 0, 0)
	assert screen.cells[0].glyph == '𝐀'
	assert screen.cells[1].glyph == 'B̲'
	assert screen.cells[2].glyph == '!'
}
