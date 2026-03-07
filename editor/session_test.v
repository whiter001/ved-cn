module editor

import core

fn test_session_switches_between_tabs() {
	mut session := new_session([
		core.new_buffer('/tmp/one.txt', 'one'),
		core.new_buffer('/tmp/two.txt', 'two'),
	], '/tmp')
	assert session.tab_count() == 2
	assert session.current_state().buffer.path == '/tmp/one.txt'
	session.switch_next()
	assert session.current_state().buffer.path == '/tmp/two.txt'
	session.switch_prev()
	assert session.current_state().buffer.path == '/tmp/one.txt'
}

fn test_session_adds_empty_buffer() {
	mut session := new_session([], '/tmp')
	assert session.tab_count() == 1
	session.add_empty_buffer()
	assert session.tab_count() == 2
	assert session.current_state().buffer.path == ''
}