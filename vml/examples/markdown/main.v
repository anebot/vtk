module main

import vtk

const sample_markdown = '# Live preview\n\nEdit this text to update the preview.\n\n## Try Markdown\n\n- **Bold** and *italic*\n- Inline `code`\n- [ ] A task to finish\n- [x] A completed task\n\n> Built from VML, updated with V callbacks.\n'

fn document_status(text string) string {
	return '${text.count('\n') + 1} lines | ${text.len} bytes | Adjust split above | Ctrl-C quits'
}

fn main() {
	mut app := vtk.new_app()
	build_ui(mut app)
	app.run() or { eprintln(err) }
}
