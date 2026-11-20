module vtk

fn test_pointer_support_probe_and_restoration() {
	mut pointer := MousePointer{}
	assert pointer.update(false, false, 0) == ''
	assert pointer.update(true, false, 1) == '\x1b]22;?none\x1b\\'
	assert pointer.update(true, true, 2) == ''
	pointer.reply('none', 3)
	assert pointer.support == .pending
	pointer.reply('1', 4)
	assert pointer.update(true, false, 5) == ''
	assert pointer.update(true, true, 6) == '\x1b]22;>none\x1b\\'
	assert pointer.hidden
	assert pointer.update(true, true, 7) == ''
	assert pointer.update(true, false, 8) == '\x1b]22;<\x1b\\'
	assert !pointer.hidden
	assert pointer.update(true, false, 9) == ''
	assert pointer.update(true, true, 10) == '\x1b]22;>none\x1b\\'
	assert pointer.update(false, true, 11) == '\x1b]22;<\x1b\\'
	assert pointer.update(false, false, 12) == ''
	assert pointer.update(true, true, 13) == '\x1b]22;>none\x1b\\'
	assert pointer.restore() == '\x1b]22;<\x1b\\'
	assert pointer.restore() == ''
}

fn test_pointer_unsupported_missing_and_late_replies() {
	mut unsupported := MousePointer{}
	unsupported.reply('1', 0)
	assert unsupported.support == .unknown
	assert unsupported.update(true, true, 0) != ''
	unsupported.reply('0', 1)
	assert unsupported.update(true, true, 2) == ''
	assert unsupported.support == .unsupported && !unsupported.hidden
	unsupported.reply('1', 3)
	assert unsupported.update(true, true, 4) == ''
	mut missing := MousePointer{}
	assert missing.update(true, true, 0) != ''
	assert missing.update(true, true, 1500) == ''
	assert missing.support == .unsupported
	assert missing.update(false, false, 2000) == ''
	assert missing.update(true, true, 3000) == ''
	mut late := MousePointer{}
	assert late.update(true, true, 0) != ''
	late.reply('1', 1500)
	assert late.support == .unsupported
	assert late.update(true, true, 1501) == ''
}

fn test_pointer_reply_chunking_never_produces_keys() {
	for reply in ['\x1b]22;1\x1b\\', '\x1b]22;0\x07'] {
		for split in 1 .. reply.len {
			mut input := Input{}
			assert input.feed(reply[..split]).len == 0
			events := input.feed(reply[split..] + 'x')
			assert events.len == 2
			assert events[0].kind == .pointer_shape
			assert events[0].text == if reply.contains(';1') { '1' } else { '0' }
			assert events[1].kind == .key && events[1].key == `x`
		}
	}
	mut input := Input{}
	events := input.feed('\x1b]0;ignored\x07\x1b]22;1\x1b\\\x1b[Ax')
	assert events.len == 3
	assert events[0].kind == .pointer_shape
	assert events[1].key == int(Key.up) && events[2].key == `x`
	mut app := new_app()
	mut w := app.window('Replies', 30, 8)
	mut field := entry('unchanged', 0)
	w.add(mut field)
	app.set_focus(field)
	app.dispatch(events[0])
	assert field.text == 'unchanged' && !app.mouse_pointer_supported()
	assert app.mouse_cursor.hide_pointer
	assert app.set_mouse_cursor(MouseCursor{ enabled: true, hide_pointer: false })
	assert !app.mouse_cursor.hide_pointer
}

fn test_pointer_replies_in_paste_and_oversized_or_aborted_osc() {
	mut input := Input{}
	pasted := input.feed('\x1b[200~\x1b]22;1\x1b\\\x1b[201~')
	assert pasted.len == 1 && pasted[0].kind == .paste
	assert pasted[0].text == '\x1b]22;1\x1b\\'
	assert input.feed('\x1b]22;' + '0'.repeat(400)).len == 0
	assert input.buffer.len <= 3
	assert input.feed('1\x1b').len == 0
	keys := input.feed('\\x')
	assert keys.len == 1 && keys[0].key == `x`
	assert input.feed('\x1b]22;' + '1'.repeat(400) + '\x07').len == 0
	aborted := input.feed('\x1b]22;\x1b[Ax')
	assert aborted.len == 2 && aborted[0].key == int(Key.up) && aborted[1].key == `x`
	assert input.feed('\x1b]22;1\x18').len == 0
	assert input.feed('\x1b]22;1\x1a').len == 0
	assert input.feed('\x1b]22;1\x07')[0].kind == .pointer_shape
}
