module vtk

import time

fn test_window_actions_reject_foreign_apps_before_mutation() {
	actions := [
		fn (mut app App, mut w Ctl) { app.raise(mut w) },
		fn (mut app App, mut w Ctl) { app.minimize(mut w) },
		fn (mut app App, mut w Ctl) { app.maximize(mut w) },
		fn (mut app App, mut w Ctl) { app.restore(mut w) },
		fn (mut app App, mut w Ctl) { app.always_on_top(mut w, true) },
		fn (mut app App, mut w Ctl) { app.tile_side(mut w, .left) },
		fn (mut app App, mut w Ctl) { app.begin_placement(mut w, true) },
		fn (mut app App, mut w Ctl) { app.window_menu(mut w, 0, 0) },
		fn (mut app App, mut w Ctl) { app.move_window_to_desktop(mut w, 2) },
		fn (mut app App, mut w Ctl) { app.close(mut w) },
		fn (mut app App, mut w Ctl) { app.destroy_ctl(mut w) },
	]
	for action in actions {
		for maximized in [false, true] {
			mut first := new_app()
			mut second := new_app()
			first.set_desktop_count(2)
			second.width, second.height = 40, 12
			mut w := first.window('Foreign', 60, 18)
			mut local := second.window('Local', 24, 6)
			w.maximized = maximized
			w.saved = Rect{5, 6, 20, 8}
			w.closing = fn (mut c Ctl, mut app App) bool {
				c.data++
				app.clipboard_set(c.text)
				return true
			}
			w.destroy = fn (mut c Ctl, mut app App) {
				c.data++
				app.clipboard_set(c.text)
			}
			mut menu := context_menu()
			menu.menu_item('Keep', fn (mut _ Ctl, mut _ App) {})
			second.open_menu(menu, 0, 0)
			popup := second.popups[0]
			rect, saved := w.rect(), w.saved
			first.dirty, second.dirty = false, false
			action(mut second, mut w)
			assert w.rect() == rect && w.saved == saved
			assert w.maximized == maximized && !w.minimized && !w.always_on_top
			assert !w.closed && w.desktop_id == 1 && w.data == 0
			assert first.windows == [w] && second.windows == [local]
			assert second.popups.len == 1 && second.popups[0] == popup
			assert isnil(second.focus) && isnil(second.placement)
			assert !first.dirty && !second.dirty
			assert first.clipboard_text() == '' && second.clipboard_text() == ''
			if !maximized {
				action(mut first, mut w)
				assert first.dirty
			}
		}
	}
}

fn test_control_actions_resolve_ownership_after_reparenting() {
	mut first := new_app()
	mut second := new_app()
	mut w1 := first.window('First', 30, 8)
	mut w2 := second.window('Second', 30, 8)
	mut editor := multiline('before')
	editor.scrollfn = fn (mut c Ctl, _ int, mut app App) bool {
		c.data++
		app.clipboard_set('scroll')
		return true
	}
	editor.destroy = fn (mut c Ctl, mut app App) {
		c.data++
		app.clipboard_set('destroy')
	}
	w1.add(mut editor)
	mut local_editor := multiline('local')
	w2.add(mut local_editor)
	editor.begin_edit_group()
	assert editor.replace_selection('after')
	first.dirty, second.dirty = false, false
	second.set_focus(editor)
	assert !second.scroll_ctl(mut editor, 1)
	second.history_for(unsafe { nil }, mut editor)
	second.history_for(w1, mut local_editor)
	second.destroy_ctl(mut editor)
	assert !editor.closed && editor.parent == w1 && editor.data == 0
	assert editor.edit.undo.len == 0 && isnil(second.focus)
	assert !first.dirty && !second.dirty
	w2.add(mut editor)
	first.dirty, second.dirty = false, false
	first.set_focus(editor)
	assert !first.scroll_ctl(mut editor, 1)
	first.destroy_ctl(mut editor)
	assert !editor.closed && editor.parent == w2 && isnil(first.focus)
	second.set_focus(editor)
	assert second.focus == editor && second.scroll_ctl(mut editor, 1)
	second.destroy_ctl(mut editor)
	assert editor.closed && editor.data == 2
	assert !first.dirty && first.clipboard_text() == ''
	assert second.clipboard_text() == 'destroy'
}

fn test_reparenting_clears_hover_and_stale_input_ownership() {
	mut first := new_app()
	mut second := new_app()
	mut w1 := first.window('First', 30, 8)
	mut w2 := second.window('Second', 30, 8)
	mut editor := multiline('initial')
	editor.mouse_leave = fn (mut c Ctl, mut app App) {
		assert c.root().app == &app
		c.data++
		app.clipboard_set('leave')
	}
	editor.keyfn = fn (mut c Ctl, _ Event, mut app App) bool {
		assert c.root().app == &app
		c.data++
		app.clipboard_set('key')
		return false
	}
	w1.add(mut editor)
	first.redraw()
	first.dispatch(Event{ kind: .mouse, x: editor.x, y: editor.y, button: .left, pressed: true })
	assert first.focus == editor && first.drag == editor && editor.hovered
	first.scroll_drag = editor
	w2.add(mut editor)
	assert editor.data == 1 && !editor.hovered && isnil(first.hovered_ctl())
	editor.anchor, editor.cursor = 0, 3
	assert !first.copy_focus() && first.clipboard_text() == 'leave'
	first.dispatch(Event{ key: int(`x`) })
	assert editor.text == 'initial' && editor.data == 1
	assert isnil(first.focus) && isnil(first.drag) && isnil(first.scroll_drag)
	second.set_focus(editor)
	second.dispatch(Event{ key: int(`x`) })
	assert editor.text != 'initial' && editor.data == 2
	assert second.clipboard_text() == 'key'
}

fn test_foreign_menu_requests_preserve_existing_popups_and_ownership() {
	mut first := new_app()
	mut second := new_app()
	mut w := first.window('First', 30, 8)
	mut field := entry('', 0)
	mut attached := context_menu()
	mut item := attached.menu_item('Attached', fn (mut _ Ctl, mut _ App) {})
	field.set_menu(mut attached)
	w.add(mut field)
	mut local := context_menu()
	local.menu_item('Keep', fn (mut _ Ctl, mut _ App) {})
	second.open_menu(local, 0, 0)
	popup := second.popups[0]
	first.dirty, second.dirty = false, false
	second.open_menu(attached, 0, 0)
	assert second.popups.len == 1 && second.popups[0] == popup
	assert item.root().app == first && !first.dirty && !second.dirty
}

fn test_modal_dialogs_reject_foreign_controls_without_entering_the_loop() {
	mut first := new_app()
	mut second := new_app()
	mut owner := first.window('Owner', 30, 8)
	mut foreign := first.window('Foreign dialog', 24, 6)
	mut local := second.window('Local dialog', 24, 6)
	foreign.dialog_result, local.dialog_result = 42, 42
	// A regression must fail rather than block in a modal event loop.
	second.after(0, fn (mut app App) { app.running = false })
	first.dirty, second.dirty = false, false
	assert second.modal_for(mut foreign, local) == -1
	assert second.modal_for(mut local, owner) == -1
	assert !foreign.modal && !local.modal && second.running
	assert foreign.dialog_result == 42 && local.dialog_result == 42
	actions := [
		fn (mut app App, owner &Ctl) { app.msgbox_for(owner, 'Message', 'Text') },
		fn (mut app App, owner &Ctl) { app.confirm_for(owner, 'Confirm', 'Text') },
		fn (mut app App, owner &Ctl) { app.prompt_for(owner, 'Prompt', 'Text', '') },
		fn (mut app App, owner &Ctl) { app.choice_for(owner, 'Choice', ['One'], 1) },
		fn (mut app App, owner &Ctl) { app.list_choice_for(owner, 'List', ['One'], 0) },
		fn (mut app App, owner &Ctl) { app.emoji_pick(owner) },
		fn (mut app App, owner &Ctl) { app.file_pick_for(owner, '.') },
		fn (mut app App, owner &Ctl) { app.color_pick(owner, 'Color', 0) },
		fn (mut app App, owner &Ctl) { app.date_pick(owner, 'Date', time.Time{}) },
	]
	for action in actions {
		action(mut second, owner)
		assert first.windows == [owner, foreign] && second.windows == [local]
		assert !first.dirty && !second.dirty && second.running
	}
}

fn test_standalone_menu_transfer_clears_old_hover_and_input() {
	mut first := new_app()
	mut second := new_app()
	mut menu := context_menu()
	mut item := menu.menu_item('Action', fn (mut c Ctl, mut app App) {
		assert c.root().app == &app
		c.data++
		app.clipboard_set('selected')
	})
	item.mouse_leave = fn (mut c Ctl, mut app App) {
		assert c.root().app == &app
		c.data++
	}
	first.open_menu(menu, 0, 0)
	first.dispatch(Event{ kind: .mouse, x: 1, y: 1, motion: true })
	assert item.hovered
	second.open_menu(menu, 0, 0)
	assert !item.hovered && item.data == 1 && isnil(first.hovered_ctl())
	first.dispatch(Event{ key: int(Key.enter) })
	assert first.popups.len == 0 && item.data == 1
	second.dispatch(Event{ key: int(Key.enter) })
	assert item.data == 2 && second.clipboard_text() == 'selected'
}

fn test_detached_adoption_explicit_transfer_and_notice_ownership() {
	mut first := new_app()
	mut second := new_app()
	mut w := new_ctl(.window)
	first.raise(mut w)
	assert w.app == first && first.windows == [w]
	mut body := box(true)
	w.add(mut body)
	mut dialog := second.dialog('Transfer body', mut body)
	assert body.parent == dialog && body.root().app == second
	mut detached := label('Detached')
	first.destroy_ctl(mut detached)
	assert detached.closed
	mut notice := first.notify('Owned', 0)
	first.dirty, second.dirty = false, false
	second.notice_close(mut notice)
	assert !notice.closed && !first.dirty && !second.dirty
	first.notice_close(mut notice)
	assert notice.closed && first.dirty
}
