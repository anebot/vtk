module main

import os

const vtk_template = $embed_file('vtk.vmlt')

const usage = 'Usage: vmlc [-t template.vmlt] [-o output.v] input.vml [input.vml ...]

Compile Gtkon-style markup to ordinary V builder functions.
The default template is the bundled vtk.vmlt.
Each input generates a sibling .v file with a build_<filename> function.
-o chooses the output path for a single input.'

fn compile_files(args []string) ! {
	mut template_text := vtk_template.to_string()
	mut output := ''
	mut inputs := []string{}
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg in ['-t', '--template', '-o', '--output'] {
			i++
			if i == args.len {
				return error('missing value for ${arg}')
			}
			if arg in ['-t', '--template'] {
				template_text = os.read_file(args[i])!
			} else {
				output = args[i]
			}
		} else if arg.starts_with('-') {
			return error('unknown option ${arg}')
		} else {
			inputs << arg
		}
		i++
	}
	if inputs.len == 0 || (output != '' && inputs.len != 1) {
		return error(usage)
	}
	template := read_template(template_text)!
	// Generate every input before writing, so markup errors do not leave partial output.
	mut paths := []string{}
	mut sources := []string{}
	for input in inputs {
		if !input.ends_with('.vml') {
			return error('expected a .vml input: ${input}')
		}
		path := if output != '' { output } else { input[..input.len - 4] + '.v' }
		if !path.ends_with('.v') || os.real_path(path) == os.real_path(input) {
			return error('output must be a separate .v file: ${path}')
		}
		if path in paths {
			return error('duplicate output path ${path}')
		}
		stem := os.file_name(input)[..os.file_name(input).len - 4].replace('-', '_')
		sources << generate(os.read_file(input)!, input, 'build_${stem}', template)!
		paths << path
	}
	for index, path in paths {
		os.write_file(path, sources[index])!
		println(path)
	}
}

fn main() {
	args := os.args[1..]
	if args.len == 0 || args == ['-h'] || args == ['--help'] {
		println(usage)
		return
	}
	compile_files(args) or {
		eprintln('vmlc: ${err}')
		exit(1)
	}
}
