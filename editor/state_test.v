module editor

import core
import gg

fn no_mod() gg.Modifier {
	return unsafe { gg.Modifier(0) }
}

fn test_insert_trigger_key_is_not_inserted() {
	mut state := new_state(core.new_buffer('', 'hello'))
	state.key_down(.i, no_mod(), 12)
	state.handle_text('i')
	state.handle_text('X')
	assert state.buffer.text() == 'Xhello'
}

fn test_open_below_trigger_key_is_not_inserted() {
	mut state := new_state(core.new_buffer('', 'one\ntwo'))
	state.key_down(.o, no_mod(), 12)
	state.handle_text('o')
	state.handle_text('Z')
	assert state.buffer.lines == ['one', 'Z', 'two']
}

fn test_change_inside_trigger_key_is_not_inserted() {
	mut state := new_state(core.new_buffer('', 'call(foo, bar)'))
	state.buffer.set_cursor(0, 6)
	state.key_down(.c, no_mod(), 12)
	state.key_down(.i, no_mod(), 12)
	state.handle_text('i')
	state.handle_text('Z')
	state.key_down(.escape, no_mod(), 12)
	assert state.buffer.text() == 'call(Z)'
}

fn test_delete_change_and_repeat_support_cjk() {
	mut state := new_state(core.new_buffer('', 'hello 世界 again'))
	state.key_down(.w, no_mod(), 12)
	assert state.buffer.cursor.column == 6
	state.key_down(.d, no_mod(), 12)
	state.key_down(.w, no_mod(), 12)
	assert state.buffer.text() == 'hello 界 again'
	state.key_down(.c, no_mod(), 12)
	state.key_down(.e, no_mod(), 12)
	state.handle_text('X')
	state.key_down(.escape, no_mod(), 12)
	assert state.buffer.text() == 'hello X again'
	state.key_down(.period, no_mod(), 12)
	assert state.buffer.text() == 'hello XX'
}

fn test_search_visual_delete_and_system_yank() {
	mut state := new_state(core.new_buffer('', 'one two one'))
	state.key_down(.slash, no_mod(), 5)
	state.handle_text('o')
	state.handle_text('n')
	state.handle_text('e')
	state.key_down(.enter, no_mod(), 5)
	assert state.buffer.cursor.column == 8
	state.key_down(.n, no_mod(), 5)
	assert state.buffer.cursor.column == 0
	state.key_down(.v, no_mod(), 5)
	state.key_down(.l, no_mod(), 5)
	state.key_down(.l, no_mod(), 5)
	state.key_down(.d, no_mod(), 5)
	assert state.buffer.text() == 'e two one'
	action_1 := state.key_down(.equal, gg.Modifier.shift, 5)
	assert !action_1.request_save
	action_2 := state.key_down(.y, no_mod(), 5)
	assert action_2.copy_to_system == 'e two one'
}

fn test_navigation_join_replace_and_file_bounds() {
	mut state := new_state(core.new_buffer('', 'alpha\nbeta\ngamma'))
	state.key_down(.g, no_mod(), 2)
	state.key_down(.g, no_mod(), 2)
	assert state.buffer.cursor.line == 0
	state.key_down(.g, gg.Modifier.shift, 2)
	assert state.buffer.cursor.line == 2
	state.key_down(.h, gg.Modifier.shift, 2)
	assert state.buffer.cursor.line == 1
	state.key_down(.l, gg.Modifier.shift, 2)
	assert state.buffer.cursor.line == 0
	state.key_down(.j, gg.Modifier.shift, 2)
	assert state.buffer.lines[0] == 'alpha beta'
	state.key_down(.r, no_mod(), 2)
	state.handle_text('A')
	assert state.buffer.lines[0] == 'alphaAbeta'
}
