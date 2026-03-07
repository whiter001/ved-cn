module core

fn test_insert_delete_and_undo() {
	mut buffer := new_buffer('demo.txt', 'hello')
	buffer.move_right()
	buffer.move_right()
	buffer.insert_text('y')
	assert buffer.text() == 'heyllo'
	assert buffer.cursor.column == 3
	assert buffer.undo()
	assert buffer.text() == 'hello'
	assert buffer.redo()
	assert buffer.text() == 'heyllo'
	buffer.delete_char()
	assert buffer.text() == 'heylo'
}

fn test_newline_and_backspace_merge() {
	mut buffer := new_buffer('demo.txt', 'abc')
	buffer.move_right()
	buffer.insert_newline()
	assert buffer.lines == ['a', 'bc']
	buffer.backspace()
	assert buffer.lines == ['abc']
	assert buffer.cursor.line == 0
	assert buffer.cursor.column == 1
}

fn test_delete_line_and_paste_below() {
	mut buffer := new_buffer('demo.txt', 'one\ntwo\nthree')
	buffer.move_down()
	deleted := buffer.delete_line()
	assert deleted == 'two'
	assert buffer.lines == ['one', 'three']
	buffer.insert_lines_below([deleted])
	assert buffer.lines == ['one', 'three', 'two']
}