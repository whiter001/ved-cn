module core

pub struct Cursor {
pub mut:
	line   int
	column int
}

struct Snapshot {
	lines  []string
	cursor Cursor
	dirty  bool
}

pub struct Buffer {
mut:
	undo_stack []Snapshot
	redo_stack []Snapshot
pub mut:
	path       string
	lines      []string
	cursor     Cursor
	scroll_top int
	scroll_left_px int
	dirty      bool
}

pub fn new_buffer(path string, text string) Buffer {
	mut lines := parse_lines(text)
	if lines.len == 0 {
		lines = ['']
	}
	return Buffer{
		path: path
		lines: lines
	}
}

pub fn (buffer &Buffer) line_count() int {
	return buffer.lines.len
}

pub fn (buffer &Buffer) current_line_text() string {
	if buffer.lines.len == 0 {
		return ''
	}
	return buffer.lines[buffer.cursor.line]
}

pub fn (buffer &Buffer) text() string {
	return buffer.lines.join('\n')
}

pub fn (mut buffer Buffer) set_cursor(line int, column int) {
	buffer.cursor.line = clamp(line, 0, buffer.lines.len - 1)
	buffer.cursor.column = clamp(column, 0, rune_len(buffer.lines[buffer.cursor.line]))
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_left() {
	if buffer.cursor.column > 0 {
		buffer.cursor.column--
	} else if buffer.cursor.line > 0 {
		buffer.cursor.line--
		buffer.cursor.column = rune_len(buffer.lines[buffer.cursor.line])
	}
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_right() {
	line_len := rune_len(buffer.lines[buffer.cursor.line])
	if buffer.cursor.column < line_len {
		buffer.cursor.column++
	} else if buffer.cursor.line < buffer.lines.len - 1 {
		buffer.cursor.line++
		buffer.cursor.column = 0
	}
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_up() {
	if buffer.cursor.line > 0 {
		buffer.cursor.line--
		buffer.cursor.column = min_int(buffer.cursor.column, rune_len(buffer.lines[buffer.cursor.line]))
	}
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_down() {
	if buffer.cursor.line < buffer.lines.len - 1 {
		buffer.cursor.line++
		buffer.cursor.column = min_int(buffer.cursor.column, rune_len(buffer.lines[buffer.cursor.line]))
	}
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_to_line_start() {
	buffer.cursor.column = 0
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_to_line_end() {
	buffer.cursor.column = rune_len(buffer.lines[buffer.cursor.line])
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_page_up(amount int) {
	steps := max_int(amount, 1)
	buffer.cursor.line = clamp(buffer.cursor.line - steps, 0, buffer.lines.len - 1)
	buffer.cursor.column = min_int(buffer.cursor.column, rune_len(buffer.lines[buffer.cursor.line]))
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_page_down(amount int) {
	steps := max_int(amount, 1)
	buffer.cursor.line = clamp(buffer.cursor.line + steps, 0, buffer.lines.len - 1)
	buffer.cursor.column = min_int(buffer.cursor.column, rune_len(buffer.lines[buffer.cursor.line]))
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) insert_text(text string) {
	if text.len == 0 {
		return
	}
	buffer.push_undo()
	normalized := text.replace('\r\n', '\n').replace('\r', '\n')
	parts := normalized.split('\n')
	line := buffer.lines[buffer.cursor.line]
	insert_at := byte_index_at_column(line, buffer.cursor.column)
	before := line[..insert_at]
	after := line[insert_at..]
	if parts.len == 1 {
		buffer.lines[buffer.cursor.line] = before + normalized + after
		buffer.cursor.column += rune_len(normalized)
		buffer.after_edit()
		return
	}
	buffer.lines[buffer.cursor.line] = before + parts[0]
	insert_pos := buffer.cursor.line + 1
	for index, part in parts[1..parts.len - 1] {
		buffer.lines.insert(insert_pos + index, part)
	}
	last_line := parts[parts.len - 1] + after
	buffer.lines.insert(insert_pos + parts.len - 2, last_line)
	buffer.cursor.line += parts.len - 1
	buffer.cursor.column = rune_len(parts[parts.len - 1])
	buffer.after_edit()
}

pub fn (mut buffer Buffer) insert_newline() {
	buffer.push_undo()
	line := buffer.lines[buffer.cursor.line]
	insert_at := byte_index_at_column(line, buffer.cursor.column)
	before := line[..insert_at]
	after := line[insert_at..]
	buffer.lines[buffer.cursor.line] = before
	buffer.lines.insert(buffer.cursor.line + 1, after)
	buffer.cursor.line++
	buffer.cursor.column = 0
	buffer.after_edit()
}

pub fn (mut buffer Buffer) backspace() {
	if buffer.cursor.column == 0 && buffer.cursor.line == 0 {
		return
	}
	buffer.push_undo()
	if buffer.cursor.column > 0 {
		line := buffer.lines[buffer.cursor.line]
		start := byte_index_at_column(line, buffer.cursor.column - 1)
		end := byte_index_at_column(line, buffer.cursor.column)
		buffer.lines[buffer.cursor.line] = line[..start] + line[end..]
		buffer.cursor.column--
	} else {
		current := buffer.lines[buffer.cursor.line]
		previous_index := buffer.cursor.line - 1
		previous := buffer.lines[previous_index]
		previous_len := rune_len(previous)
		buffer.lines[previous_index] = previous + current
		buffer.lines.delete(buffer.cursor.line)
		buffer.cursor.line = previous_index
		buffer.cursor.column = previous_len
	}
	buffer.after_edit()
}

pub fn (mut buffer Buffer) delete_char() {
	line := buffer.lines[buffer.cursor.line]
	if buffer.cursor.column == rune_len(line) {
		if buffer.cursor.line >= buffer.lines.len - 1 {
			return
		}
		buffer.push_undo()
		next := buffer.lines[buffer.cursor.line + 1]
		buffer.lines[buffer.cursor.line] = line + next
		buffer.lines.delete(buffer.cursor.line + 1)
		buffer.after_edit()
		return
	}
	buffer.push_undo()
	start := byte_index_at_column(line, buffer.cursor.column)
	end := byte_index_at_column(line, buffer.cursor.column + 1)
	buffer.lines[buffer.cursor.line] = line[..start] + line[end..]
	buffer.after_edit()
}

pub fn (mut buffer Buffer) delete_line() string {
	deleted := buffer.lines[buffer.cursor.line]
	buffer.push_undo()
	if buffer.lines.len == 1 {
		buffer.lines[0] = ''
		buffer.cursor.column = 0
		buffer.after_edit()
		return deleted
	}
	buffer.lines.delete(buffer.cursor.line)
	if buffer.cursor.line >= buffer.lines.len {
		buffer.cursor.line = buffer.lines.len - 1
	}
	buffer.cursor.column = min_int(buffer.cursor.column, rune_len(buffer.lines[buffer.cursor.line]))
	buffer.after_edit()
	return deleted
}

pub fn (mut buffer Buffer) insert_line_below() {
	buffer.push_undo()
	insert_at := buffer.cursor.line + 1
	buffer.lines.insert(insert_at, '')
	buffer.cursor.line = insert_at
	buffer.cursor.column = 0
	buffer.after_edit()
}

pub fn (mut buffer Buffer) insert_line_above() {
	buffer.push_undo()
	insert_at := buffer.cursor.line
	buffer.lines.insert(insert_at, '')
	buffer.cursor.column = 0
	buffer.after_edit()
}

pub fn (mut buffer Buffer) insert_lines_below(lines []string) {
	if lines.len == 0 {
		return
	}
	buffer.push_undo()
	mut insert_at := buffer.cursor.line + 1
	for line in lines {
		buffer.lines.insert(insert_at, line)
		insert_at++
	}
	buffer.cursor.line += lines.len
	buffer.cursor.column = 0
	buffer.after_edit()
}

pub fn (mut buffer Buffer) undo() bool {
	if buffer.undo_stack.len == 0 {
		return false
	}
	buffer.redo_stack << buffer.snapshot()
	state := buffer.undo_stack.pop()
	buffer.restore(state)
	return true
}

pub fn (mut buffer Buffer) redo() bool {
	if buffer.redo_stack.len == 0 {
		return false
	}
	buffer.undo_stack << buffer.snapshot()
	state := buffer.redo_stack.pop()
	buffer.restore(state)
	return true
}

fn (mut buffer Buffer) push_undo() {
	buffer.undo_stack << buffer.snapshot()
	buffer.redo_stack.clear()
	if buffer.undo_stack.len > 200 {
		buffer.undo_stack.delete(0)
	}
}

fn (buffer &Buffer) snapshot() Snapshot {
	return Snapshot{
		lines: buffer.lines.clone()
		cursor: buffer.cursor
		dirty: buffer.dirty
	}
}

fn (mut buffer Buffer) restore(state Snapshot) {
	buffer.lines = state.lines.clone()
	buffer.cursor = state.cursor
	buffer.dirty = state.dirty
	buffer.ensure_invariants()
}

fn (mut buffer Buffer) after_edit() {
	buffer.dirty = true
	buffer.ensure_invariants()
}

fn (mut buffer Buffer) ensure_invariants() {
	if buffer.lines.len == 0 {
		buffer.lines = ['']
	}
	buffer.cursor.line = clamp(buffer.cursor.line, 0, buffer.lines.len - 1)
	buffer.cursor.column = clamp(buffer.cursor.column, 0, rune_len(buffer.lines[buffer.cursor.line]))
	buffer.normalize_scroll_top()
}

fn (mut buffer Buffer) normalize_scroll_top() {
	buffer.scroll_top = max_int(buffer.scroll_top, 0)
}

fn parse_lines(text string) []string {
	if text == '' {
		return ['']
	}
	return text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
}

fn byte_index_at_column(line string, column int) int {
	if column <= 0 {
		return 0
	}
	mut byte_index := 0
	mut rune_index := 0
	for rune_value in line.runes() {
		if rune_index == column {
			return byte_index
		}
		byte_index += rune_value.length_in_bytes()
		rune_index++
	}
	return line.len
}

fn rune_len(line string) int {
	return line.runes().len
}

fn clamp(value int, low int, high int) int {
	if high < low {
		return low
	}
	if value < low {
		return low
	}
	if value > high {
		return high
	}
	return value
}

fn min_int(left int, right int) int {
	if left < right {
		return left
	}
	return right
}

fn max_int(left int, right int) int {
	if left > right {
		return left
	}
	return right
}