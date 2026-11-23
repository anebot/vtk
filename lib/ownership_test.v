module vtk

fn ownership_changed(mut c Ctl, mut app App) {
	c.data++
	app.clipboard_set('${c.value}:${c.text}')
}

fn test_value_controls_inherit_app_and_notify_only_on_change() {
	mut app := new_app()
	mut w := app.window('Values', 40, 12)
	mut body := box(true)
	mut controls := [progress(), slider(0, 10), spin(0, 10), checkbox('', false),
		switch_ctl('', false), radio(), combo(), tabs(),
		table(fn (_ &Ctl, _ int, _ int) string { return '' }, 0)]
	for mut c in controls {
		c.changed = ownership_changed
		c.set_value(1)
		assert c.value == 1 && c.data == 0
		body.add(mut c)
	}
	w.add(mut body)
	for mut c in controls {
		assert c.data == 0
		app.dirty = false
		c.set_value(0)
		assert app.dirty && c.data == 1 && app.clipboard_text() == '0:'
		app.dirty = false
		c.set_value(0)
		assert !app.dirty && c.data == 1
	}
	controls[0].set_value(150)
	assert controls[0].value == 100
	controls[1].set_value(-1)
	assert controls[1].value == 0
	controls[2].set_value(20)
	assert controls[2].value == 10
}

fn test_subtrees_follow_reparenting_detachment_and_destruction() {
	mut first := new_app()
	mut second := new_app()
	mut w1 := first.window('First', 30, 8)
	mut w2 := second.window('Second', 30, 8)
	mut body := box(true)
	mut bar := progress()
	bar.changed = ownership_changed
	body.add(mut bar)
	w1.add(mut body)
	bar.set_value(10)
	assert first.clipboard_text() == '10:' && second.clipboard_text() == ''
	first.dirty = false
	second.dirty = false
	w2.add(mut body)
	assert first.dirty && second.dirty
	first.dirty = false
	second.dirty = false
	bar.set_value(20)
	assert !first.dirty && second.dirty && bar.data == 2
	assert first.clipboard_text() == '10:' && second.clipboard_text() == '20:'
	second.dirty = false
	body.detach()
	assert second.dirty
	second.dirty = false
	bar.set_value(30)
	bar.fire()
	assert !first.dirty && !second.dirty && bar.data == 2
	w2.add(mut body)
	assert bar.data == 2
	second.destroy_ctl(mut w2)
	second.dirty = false
	bar.set_value(40)
	assert !second.dirty && bar.data == 2
}

fn test_programmatic_text_update_is_drawn_by_the_next_step() {
	mut app := new_app()
	app.desktop = false
	app.bar_clock = false
	mut w := app.window('Redraw', 30, 8)
	mut text := label('Before')
	text.changed = ownership_changed
	w.add(mut text)
	app.redraw()
	text.set_text('After')
	assert app.dirty && text.data == 0
	app.step(0)
	assert !app.dirty
	assert app.screen.cells[text.y * app.width + text.x].glyph == 'A'
	text.text = 'Direct'
	text.invalidate()
	assert app.dirty
	app.step(0)
	assert app.screen.cells[text.y * app.width + text.x].glyph == 'D'
}

fn test_structural_and_presentation_mutations_invalidate_without_callbacks() {
	mut app := new_app()
	mut w := app.window('Mutations', 40, 12)
	mut choices := combo()
	mut pages := tabs()
	mut nodes := tree()
	mut text := markdown('hello')
	mut controls := [choices, pages, nodes, text]
	for mut c in controls {
		c.changed = ownership_changed
		w.add(mut c)
	}
	app.dirty = false
	choices.add_item('New')
	assert app.dirty
	app.dirty = false
	mut page := label('Page')
	pages.add_tab('New', mut page)
	assert app.dirty
	app.dirty = false
	nodes.tree_add(unsafe { nil }, 'Node')
	assert app.dirty
	app.dirty = false
	text.scroll_rows(1, 20, 5)
	assert app.dirty
	app.dirty = false
	text.markdown_mode(.source)
	assert app.dirty
	app.dirty = false
	text.vim_mode(true)
	assert app.dirty
	app.dirty = false
	w.set_size_limits(20, 8, 60, 20)
	assert app.dirty
	for c in [choices, pages, nodes, text] {
		assert c.data == 0
	}
}

fn test_editor_and_markdown_mutations_use_the_owning_app() {
	mut app := new_app()
	mut w := app.window('Editors', 40, 12)
	mut text := entry('abc', 10)
	text.changed = ownership_changed
	w.add(mut text)
	app.dirty = false
	assert text.replace_range(0, 1, 'x')
	assert app.dirty && text.data == 1 && text.text == 'xbc'
	text.anchor = 0
	text.cursor = 1
	app.dirty = false
	assert text.replace_selection('y')
	assert app.dirty && text.data == 2 && text.text == 'ybc'
	app.dirty = false
	assert text.undo()
	assert app.dirty && text.data == 3 && text.text == 'xbc'
	app.dirty = false
	assert text.redo()
	assert app.dirty && text.data == 4 && text.text == 'ybc'
	text.detach()
	app.dirty = false
	assert text.replace_selection('z')
	assert text.undo()
	assert text.redo()
	assert !app.dirty && text.data == 4
	mut task := markdown('- [ ] task')
	task.changed = ownership_changed
	task.markdown_mode(.read)
	w.add(mut task)
	app.dirty = false
	assert task.toggle_task(4)
	assert app.dirty && task.data == 1 && task.text == '- [x] task'
	task.detach()
	app.dirty = false
	assert task.toggle_task(4)
	assert !app.dirty && task.data == 1 && task.text == '- [ ] task'
}

fn test_context_menus_and_standalone_menus_receive_the_correct_app() {
	mut first := new_app()
	mut second := new_app()
	mut w1 := first.window('First', 30, 8)
	mut w2 := second.window('Second', 30, 8)
	mut text := entry('', 0)
	mut menu := context_menu()
	mut item := menu.menu_item('Action', ownership_changed)
	text.set_menu(mut menu)
	assert text.kids.len == 0
	w1.add(mut text)
	item.fire()
	assert item.data == 1 && first.clipboard_text() == '0:Action'
	w2.add(mut text)
	item.fire()
	assert item.data == 2 && second.clipboard_text() == '0:Action'
	mut replacement := context_menu()
	text.set_menu(mut replacement)
	item.fire()
	assert item.data == 2
	replacement.detach()
	assert isnil(text.menu)
	mut standalone := context_menu()
	mut submenu := standalone.add_menu('Submenu')
	mut action := submenu.menu_item('Standalone', ownership_changed)
	action.fire()
	assert action.data == 0
	first.open_menu(standalone, 0, 0)
	first.choose_popup()
	first.choose_popup()
	assert action.data == 1 && first.clipboard_text() == '0:Standalone'
	second.open_menu(standalone, 0, 0)
	second.choose_popup()
	second.choose_popup()
	assert action.data == 2 && second.clipboard_text() == '0:Standalone'
	mut choices := combo()
	choices.add_item('Choice')
	mut choices_menu := context_menu()
	mut choices_item := choices_menu.menu_item('Context', ownership_changed)
	choices.set_menu(mut choices_menu)
	assert choices.kids.len == 1
	w2.add(mut choices)
	choices_item.fire()
	assert choices_item.data == 1 && second.clipboard_text() == '0:Context'
	second.destroy_ctl(mut choices)
	second.dirty = false
	choices_item.fire()
	assert choices_item.data == 1 && !second.dirty
}
