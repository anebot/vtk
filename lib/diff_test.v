module vtk

fn test_diff_colors_preserve_headers_context_scrolling_and_selection() {
	text := [
		'diff --git a/a b/a',
		'index 123..456 100644',
		'--- a/a',
		'+++ b/a',
		'@@ -1,3 +1,3 @@',
		' context',
		'--- removed heading',
		'+++ added heading',
		'-old',
		'+new',
		'--- /dev/null',
		'+++ b/b',
		'@@ -0,0 +1 @@',
		'+added file',
	].join('\n')
	mut app := new_app()
	app.screen.resize(50, 30)
	mut view := multiline(text)
	view.readonly = true
	view.syntax = .diff
	view.layout(Rect{0, 0, 40, 20})
	app.draw_editor(mut view)
	for row in [0, 1, 2, 3, 10, 11] {
		cell := app.screen.cells[row * app.screen.width]
		assert cell.fg == app.theme.fg && cell.attr & bold != 0
	}
	for row in [4, 12] {
		assert app.screen.cells[row * app.screen.width].fg == cyan
	}
	for row in [6, 8] {
		assert app.screen.cells[row * app.screen.width].fg == red
	}
	for row in [7, 9, 13] {
		assert app.screen.cells[row * app.screen.width].fg == green
	}
	assert app.screen.cells[5 * app.screen.width].fg == app.theme.fg
	view.left = 3
	view.scroll_hold = true
	app.draw_editor(mut view)
	assert app.screen.cells[6 * app.screen.width].fg == red
	assert app.screen.cells[9 * app.screen.width].fg == green
	view.scroll_hold = false
	view.anchor = text.index('-old') or { panic('missing removal') }
	view.cursor = view.anchor + 4
	app.draw_editor(mut view)
	assert app.screen.cells[8 * app.screen.width].fg == app.theme.sel_fg
	assert app.screen.cells[8 * app.screen.width].bg == app.theme.sel_bg
	view.anchor = -1
	view.cursor = 0
	view.disabled = true
	app.draw_editor(mut view)
	assert app.screen.cells[8 * app.screen.width].fg == app.theme.dim
	view.disabled = false
	view.wrap = true
	view.w = 10
	for row in view.editor_rows() {
		if row.line == 6 {
			assert (row.color or { -1 }) == red
		}
		if row.line == 7 {
			assert (row.color or { -1 }) == green
		}
	}
	view.wrap = false
	view.w = 40
	view.syntax = .plain
	app.draw_editor(mut view)
	assert app.screen.cells[8 * app.screen.width].fg == app.theme.fg
	assert app.screen.cells[9 * app.screen.width].fg == app.theme.fg
}

fn test_diff_counts_handle_no_newline_markers_and_deletions() {
	text := '@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n--- a/b\n+++ /dev/null\n@@ -1 +0,0 @@\n-gone'
	rows := diff_rows(text)
	assert (rows[1].color or { -1 }) == red
	assert (rows[3].color or { -1 }) == green
	assert rows[5].attr == bold && rows[6].attr == bold
	assert (rows[8].color or { -1 }) == red
}
