module main

import os

fn test_vtk_generation_matches_examples() {
	template := read_template(vtk_template.to_string()) or { panic(err) }
	mut covered := map[string]bool{}
	for example in ['hello', 'preferences', 'markdown', 'widgets'] {
		file := os.join_path(@VMODROOT, 'vml', 'examples', example, 'ui.vml')
		source := os.read_file(file) or { panic(err) }
		root := parse(source, file) or { panic(err) }
		collect_example_tags(root, mut covered)
		generated := generate(source, file, 'build_ui', template) or { panic(err) }
		assert generated == os.read_file(file[..file.len - 4] + '.v') or { panic(err) }
		if example == 'hello' {
			assert generated.index('mut name :=') or { -1 } < generated.index('greet.link = name') or { -1 }
			assert generated.contains(".add_tab('Greeting', mut ")
			assert generated.contains('progress.set_value(0)')
		}
	}
	for tag, _ in template.widgets {
		assert covered[tag], 'no VML example demonstrates ${tag}'
	}
}

fn collect_example_tags(node Node, mut covered map[string]bool) {
	covered[node.tag] = true
	for child in node.children { collect_example_tags(child, mut covered) }
}

fn test_template_controls_construction_properties_and_attachment() {
	template := read_template('{"module_name":"demo", "imports":["other"],
		"params":"ctx other.Context", "result":"&other.Widget",
		"widgets": {
		  "Stack": {"create":"other.stack(ctx)", "add":"{{parent}}.append({{child}})"},
		  "Text": {"create":"other.text({{text}})", "defaults":{"text":"\\\"default\\\""},
		    "properties":{"enabled":"{{id}}.enable({{value}})"}}
		}}') or { panic(err) }
	output := generate('Stack { Text $label enabled; Text text="{{id}}"; }', 'other.vml',
		'build_other', template) or { panic(err) }
	assert output.contains('module demo') && output.contains('import other')
	assert output.contains('pub fn build_other(ctx other.Context) &other.Widget')
	assert output.contains('mut label := other.text("default")')
	assert output.contains('label.enable(true)')
	assert output.contains('vml_0.append(label)')
	assert output.contains("other.text('{{id}}')")
}

fn test_generation_rejects_invalid_rules_and_identifiers() {
	template := read_template(vtk_template.to_string()) or { panic(err) }
	for source in ['Missing;', 'Window { Button $same; Entry $same; }', 'Button { Label; }',
		'VBox { Label $app; }', 'Label $vml_0;', 'Label $return;', 'Tabs { VBox {} }', 'Canvas;'] {
		generate(source, 'bad.vml', 'build_bad', template) or {
			assert err.msg().starts_with('bad.vml:1:')
			continue
		}
		assert false, 'accepted invalid UI: ${source}'
	}
	mut used := []string{}
	expand('{{unfinished', map[string]string{}, mut used) or {
		assert err.msg().contains('unclosed')
		return
	}
	assert false
}

fn test_properties_do_not_consume_other_explicit_attributes() {
	template := read_template(vtk_template.to_string()) or { panic(err) }
	output := generate('Progress blocky value=42;', 'progress.vml', 'build_progress', template) or {
		panic(err)
	}
	assert output.contains('vml_0.blocky = true')
	assert output.contains('vml_0.set_value(42)')
}
