module editor

import core
import gg

fn test_insert_trigger_key_is_not_inserted() {
	mut state := new_state(core.new_buffer('', 'hello'))
	state.key_down(.i, unsafe { gg.Modifier(0) })
	state.handle_text('i')
	state.handle_text('X')
	assert state.buffer.text() == 'Xhello'
}

fn test_open_below_trigger_key_is_not_inserted() {
	mut state := new_state(core.new_buffer('', 'one\ntwo'))
	state.key_down(.o, unsafe { gg.Modifier(0) })
	state.handle_text('o')
	state.handle_text('Z')
	assert state.buffer.lines == ['one', 'Z', 'two']
}