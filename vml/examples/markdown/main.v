module main

import vtk

const sample_markdown = '# Live preview\n\nEdit this text to update the preview.\n\n## Try Markdown\n\n- **Bold** and *italic*\n- Inline `code`\n- [ ] A task to finish\n- [x] A completed task\n\n> Built from VML, updated with V callbacks.\n'

fn update_preview(mut source vtk.Ctl, mut _ vtk.App) {
	mut preview := source.link or { return }
	preview.set_text(source.text)
}

fn main() {
	mut app := vtk.new_app()
	build_ui(mut app)
	app.run() or { eprintln(err) }
}
