module core

fn test_word_motion_delete_and_completion_with_cjk() {
	mut buffer := new_buffer('', 'hello 世界 again\nalphabet\nal')
	buffer.move_word_forward()
	assert buffer.cursor.column == 6
	assert buffer.delete_word(false) == '世'
	assert buffer.lines[0] == 'hello 界 again'
	assert buffer.delete_word(true) == '界'
	assert buffer.lines[0] == 'hello  again'
	buffer.set_cursor(2, 2)
	assert buffer.current_word_prefix() == 'al'
	assert buffer.completion_candidates('al') == ['alphabet']
	assert buffer.apply_completion('al', 'alphabet')
	assert buffer.lines[2] == 'alphabet'
}

fn test_delete_inside_join_indent_and_search() {
	mut buffer := new_buffer('', 'call(foo, bar)\n    next line\ncall')
	buffer.set_cursor(0, 7)
	assert buffer.delete_inside_object() == 'foo, bar'
	assert buffer.lines[0] == 'call()'
	assert buffer.join_with_next_line()
	assert buffer.lines[0] == 'call() next line'
	assert buffer.indent_lines(0, 0, 1)
	assert buffer.lines[0].starts_with('    ')
	assert buffer.indent_lines(0, 0, -1)
	assert !buffer.lines[0].starts_with('    ')
	buffer.set_cursor(0, 0)
	assert buffer.search_next('call', false)
	assert buffer.cursor.line == 1
}