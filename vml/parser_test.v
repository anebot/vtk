module main

fn test_gtkon_attributes_and_comments() {
	root := parse('# heading\nWindow $window title: "Hello" width=40 {\n' +
		'/* outer /* nested */ comment */ VBox expand !hidden {\n' +
		"Label text='Hello \\'V\\''; // line comment\n" +
		'Entry byte-limit=12; } }', 'test.vml') or { panic(err) }
	assert root.tag == 'Window' && root.id == 'window'
	assert root.attrs[0] == Attribute{'title', "'Hello'"}
	assert root.attrs[1] == Attribute{'width', '40'}
	box := root.children[0]
	assert box.attrs == [Attribute{'expand', 'true'}, Attribute{'hidden', 'false'}]
	assert box.children[0].attrs[0].value == "'Hello \\'V\\''"
	assert box.children[1].attrs[0] == Attribute{'byte_limit', '12'}
}

fn test_strings_are_literals_and_expressions_stay_v() {
	root := parse('Label text="Hello $name \\n \\u263a {{id}}" changed={fn () {\n' +
		'println("}") /* } */\nprintln(`}`)\n}};', 'test.vml') or { panic(err) }
	assert root.attrs[0].value == "'Hello \\$name \\n ☺ {{id}}'"
	assert root.attrs[1].value.contains('println("}") /* } */')
	assert root.attrs[1].value.ends_with('}')
	bare := parse('Label text=World;', 'test.vml') or { panic(err) }
	assert bare.attrs[0].value == "'World'"
}

fn test_embedded_code_handles_braces_quotes_and_comments() {
	root := parse('VBox { -{ if true { println("}-") } /* } */ }- }', 'code.vml') or {
		panic(err)
	}
	assert root.code == ['if true { println("}-") } /* } */']
}

fn test_v_interpolation_can_contain_quoted_braces() {
	source := r"Label text={'${if true { '}' } else { '{' }}'};"
	root := parse(source, 'interpolation.vml') or { panic(err) }
	assert root.attrs[0].value == r"'${if true { '}' } else { '{' }}'"
	raw := parse(r"Label text={r'C:\'};", 'raw.vml') or { panic(err) }
	assert raw.attrs[0].value == r"r'C:\'"
}

fn test_malformed_markup_reports_file_line_and_column() {
	for source in ['', 'VBox {', 'Label text="oops;', 'Label text={oops;', 'Label text={};',
		'Label text=;', 'Label text=a text=b;', 'Label $x $y;', 'Label !hidden=true;', 'Label $;',
		'VBox { -{ println(1) } }', '/* unfinished', 'Label; Label;', 'Label byte-limit=1 byte_limit=2;'] {
		parse(source, 'broken.vml') or {
			assert err.msg().starts_with('broken.vml:1:')
			continue
		}
		assert false, 'accepted malformed markup: ${source}'
	}
	parse('VBox {\n\tLabel text=;\n}', 'line.vml') or {
		assert err.msg().starts_with('line.vml:2:13:')
		return
	}
	assert false
}
