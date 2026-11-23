module main

import os

fn test_cli_generates_multiple_files_and_accepts_custom_templates() {
	dir := os.join_path(os.temp_dir(), 'vml_cli_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer { os.rmdir_all(dir) or {} }
	first := os.join_path(dir, 'first.vml')
	second := os.join_path(dir, 'second.vml')
	os.write_file(first, 'Label text=First;') or { panic(err) }
	os.write_file(second, 'Label text=Second;') or { panic(err) }
	compile_files([first, second]) or { panic(err) }
	assert os.read_file(os.join_path(dir, 'first.v')) or { '' }.contains('fn build_first(')
	assert os.read_file(os.join_path(dir, 'second.v')) or { '' }.contains("vtk.label('Second')")
	template := os.join_path(dir, 'plain.vmlt')
	output := os.join_path(dir, 'custom.v')
	os.write_file(template, '{"result":"string", "widgets":{"Label":{"create":"{{text}}"}}}') or {
		panic(err)
	}
	compile_files(['-t', template, '-o', output, first]) or { panic(err) }
	assert os.read_file(output) or { '' }.contains("mut vml_0 := 'First'")
}

fn test_cli_validates_all_inputs_before_writing() {
	dir := os.join_path(os.temp_dir(), 'vml_error_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer { os.rmdir_all(dir) or {} }
	first := os.join_path(dir, 'first.vml')
	broken := os.join_path(dir, 'broken.vml')
	output := os.join_path(dir, 'first.v')
	os.write_file(first, 'Label;') or { panic(err) }
	os.write_file(broken, 'Window {') or { panic(err) }
	os.write_file(output, 'existing output') or { panic(err) }
	for args in [[first, broken], ['-o', output, first, broken], ['--unknown'], ['-t'],
		['-o', first, first]] {
		compile_files(args) or {
			assert os.read_file(output) or { '' } == 'existing output'
			assert !os.exists(os.join_path(dir, 'broken.v'))
			continue
		}
		assert false, 'accepted invalid command: ${args}'
	}
}
