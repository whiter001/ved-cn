module core

enum RuneClass {
	space
	ascii_word
	cjk_word
	punct
}

pub fn (mut buffer Buffer) move_to_first_non_blank() {
	line := buffer.lines[buffer.cursor.line]
	buffer.cursor.column = first_non_blank_column(line)
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_to_file_start() {
	buffer.cursor.line = 0
	buffer.cursor.column = 0
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_to_file_end() {
	buffer.cursor.line = buffer.lines.len - 1
	buffer.cursor.column = rune_len(buffer.lines[buffer.cursor.line])
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_to_screen_top(visible int) {
	buffer.cursor.line = clamp(buffer.scroll_top, 0, buffer.lines.len - 1)
	buffer.cursor.column = min_int(buffer.cursor.column, rune_len(buffer.lines[buffer.cursor.line]))
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_to_screen_bottom(visible int) {
	last_visible := clamp(buffer.scroll_top + max_int(visible - 1, 0), 0, buffer.lines.len - 1)
	buffer.cursor.line = last_visible
	buffer.cursor.column = min_int(buffer.cursor.column, rune_len(buffer.lines[buffer.cursor.line]))
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) center_cursor(visible int) {
	if visible <= 1 {
		buffer.scroll_top = max_int(buffer.cursor.line, 0)
		return
	}
	buffer.scroll_top = clamp(buffer.cursor.line - visible / 2, 0, max_int(buffer.lines.len - visible, 0))
}

pub fn (mut buffer Buffer) move_word_forward() {
	offset := buffer.global_rune_offset(buffer.cursor)
	next := next_word_start_offset(buffer.text().runes(), offset)
	buffer.cursor = buffer.cursor_from_global_rune_offset(next)
	buffer.normalize_scroll_top()
}

pub fn (mut buffer Buffer) move_word_backward() {
	offset := buffer.global_rune_offset(buffer.cursor)
	prev := prev_word_start_offset(buffer.text().runes(), offset)
	buffer.cursor = buffer.cursor_from_global_rune_offset(prev)
	buffer.normalize_scroll_top()
}

pub fn (buffer &Buffer) next_word_start_cursor() Cursor {
	offset := buffer.global_rune_offset(buffer.cursor)
	return buffer.cursor_from_global_rune_offset(next_word_start_offset(buffer.text().runes(), offset))
}

pub fn (buffer &Buffer) word_end_cursor() Cursor {
	offset := buffer.global_rune_offset(buffer.cursor)
	return buffer.cursor_from_global_rune_offset(word_end_offset(buffer.text().runes(), offset))
}

pub fn (buffer &Buffer) current_word() string {
	start, end, ok := buffer.current_word_range()
	if !ok {
		return ''
	}
	return buffer.text_in_range(start, end)
}

pub fn (buffer &Buffer) current_word_prefix() string {
	line := buffer.lines[buffer.cursor.line]
	runes := line.runes()
	if buffer.cursor.column <= 0 || runes.len == 0 {
		return ''
	}
	mut end := clamp(buffer.cursor.column, 0, runes.len)
	mut start := end
	for start > 0 && rune_class(runes[start - 1]) == .ascii_word {
		start--
	}
	if start == end {
		return ''
	}
	return runes[start..end].string()
}

pub fn (buffer &Buffer) completion_candidates(prefix string) []string {
	if prefix == '' {
		return []string{}
	}
	mut seen := map[string]bool{}
	mut items := []string{}
	for line in buffer.lines {
		for token in ascii_word_tokens(line) {
			if token.len <= prefix.len || !token.starts_with(prefix) || token == prefix {
				continue
			}
			if token in seen {
				continue
			}
			seen[token] = true
			items << token
		}
	}
	items.sort()
	return items
}

pub fn (mut buffer Buffer) apply_completion(prefix string, completion string) bool {
	if prefix == '' || completion == '' || !completion.starts_with(prefix) {
		return false
	}
	line := buffer.lines[buffer.cursor.line]
	runes := line.runes()
	mut end := clamp(buffer.cursor.column, 0, runes.len)
	mut start := end
	for start > 0 && rune_class(runes[start - 1]) == .ascii_word {
		start--
	}
	if start == end {
		return false
	}
	return buffer.replace_range(Cursor{buffer.cursor.line, start}, Cursor{buffer.cursor.line, end}, completion)
}

pub fn (buffer &Buffer) text_in_range(start Cursor, end Cursor) string {
	left, right := normalize_range(start, end)
	if same_cursor(left, right) {
		return ''
	}
	if left.line == right.line {
		line := buffer.lines[left.line]
		start_idx := byte_index_at_column(line, left.column)
		end_idx := byte_index_at_column(line, right.column)
		return line[start_idx..end_idx]
	}
	mut parts := []string{}
	first_line := buffer.lines[left.line]
	parts << first_line[byte_index_at_column(first_line, left.column)..]
	for line_no := left.line + 1; line_no < right.line; line_no++ {
		parts << buffer.lines[line_no]
	}
	last_line := buffer.lines[right.line]
	parts << last_line[..byte_index_at_column(last_line, right.column)]
	return parts.join('\n')
}

pub fn (mut buffer Buffer) delete_range(start Cursor, end Cursor) string {
	left, right := normalize_range(start, end)
	if same_cursor(left, right) {
		return ''
	}
	deleted := buffer.text_in_range(left, right)
	buffer.push_undo()
	if left.line == right.line {
		line := buffer.lines[left.line]
		start_idx := byte_index_at_column(line, left.column)
		end_idx := byte_index_at_column(line, right.column)
		buffer.lines[left.line] = line[..start_idx] + line[end_idx..]
		buffer.cursor = left
		buffer.after_edit()
		return deleted
	}
	first_line := buffer.lines[left.line]
	last_line := buffer.lines[right.line]
	start_idx := byte_index_at_column(first_line, left.column)
	end_idx := byte_index_at_column(last_line, right.column)
	buffer.lines[left.line] = first_line[..start_idx] + last_line[end_idx..]
	for _ in 0 .. right.line - left.line {
		buffer.lines.delete(left.line + 1)
	}
	buffer.cursor = left
	buffer.after_edit()
	return deleted
}

pub fn (mut buffer Buffer) replace_range(start Cursor, end Cursor, text string) bool {
	buffer.delete_range(start, end)
	buffer.insert_text(text)
	return true
}

pub fn (mut buffer Buffer) delete_word(to_end bool) string {
	start := buffer.cursor
	end := if to_end { buffer.word_end_cursor() } else { buffer.next_word_start_cursor() }
	return buffer.delete_range(start, end)
}

pub fn (mut buffer Buffer) delete_inside_object() string {
	start, end, ok := buffer.inside_object_range()
	if !ok {
		return ''
	}
	return buffer.delete_range(start, end)
}

pub fn (buffer &Buffer) inside_object_range() (Cursor, Cursor, bool) {
	line := buffer.lines[buffer.cursor.line]
	runes := line.runes()
	if runes.len == 0 {
		return Cursor{}, Cursor{}, false
	}
	mut best_open := -1
	mut best_close := -1
	mut best_span := 1 << 30
	pairs := [
		[`(`, `)`],
		[`[`, `]`],
		[`{`, `}`],
		[`<`, `>`],
		[`"`, `"`],
		[`'`, `'`],
		[`\``, `\``],
	]
	for pair in pairs {
		open_col := last_index_of_rune_before(runes, pair[0], buffer.cursor.column)
		if open_col < 0 {
			continue
		}
		close_col := first_index_of_rune_after(runes, pair[1], max_int(buffer.cursor.column, open_col + 1))
		if close_col < 0 || close_col <= open_col {
			continue
		}
		if buffer.cursor.column < open_col || buffer.cursor.column > close_col {
			continue
		}
		span := close_col - open_col
		if span < best_span {
			best_open = open_col
			best_close = close_col
			best_span = span
		}
	}
	if best_open >= 0 && best_close > best_open {
		return Cursor{buffer.cursor.line, best_open + 1}, Cursor{buffer.cursor.line, best_close}, true
	}
	return buffer.current_word_range()
}

pub fn (buffer &Buffer) current_word_range() (Cursor, Cursor, bool) {
	runes := buffer.text().runes()
	if runes.len == 0 {
		return Cursor{}, Cursor{}, false
	}
	mut offset := buffer.global_rune_offset(buffer.cursor)
	if offset >= runes.len {
		offset = runes.len - 1
	}
	if rune_class(runes[offset]) == .space && offset > 0 {
		offset--
	}
	class := rune_class(runes[offset])
	if class == .space {
		return Cursor{}, Cursor{}, false
	}
	mut start := offset
	mut end := offset + 1
	if class == .ascii_word {
		for start > 0 && rune_class(runes[start - 1]) == .ascii_word {
			start--
		}
		for end < runes.len && rune_class(runes[end]) == .ascii_word {
			end++
		}
	}
	return buffer.cursor_from_global_rune_offset(start), buffer.cursor_from_global_rune_offset(end), true
}

pub fn (mut buffer Buffer) indent_lines(start_line int, end_line int, delta int) bool {
	left := clamp(min_int(start_line, end_line), 0, buffer.lines.len - 1)
	right := clamp(max_int(start_line, end_line), 0, buffer.lines.len - 1)
	if delta == 0 || left > right {
		return false
	}
	buffer.push_undo()
	for line_no := left; line_no <= right; line_no++ {
		if delta > 0 {
			buffer.lines[line_no] = '    '.repeat(delta) + buffer.lines[line_no]
			if line_no == buffer.cursor.line {
				buffer.cursor.column += 4 * delta
			}
			continue
		}
		remove := leading_indent_width(buffer.lines[line_no], -delta)
		if remove > 0 {
			buffer.lines[line_no] = buffer.lines[line_no][remove..]
			if line_no == buffer.cursor.line {
				buffer.cursor.column = max_int(buffer.cursor.column - remove, 0)
			}
		}
	}
	buffer.after_edit()
	return true
}

pub fn (mut buffer Buffer) join_with_next_line() bool {
	if buffer.cursor.line >= buffer.lines.len - 1 {
		return false
	}
	buffer.push_undo()
	left := trim_right_spaces(buffer.lines[buffer.cursor.line])
	right := trim_left_spaces(buffer.lines[buffer.cursor.line + 1])
	separator := if left == '' || right == '' || left.ends_with(' ') { '' } else { ' ' }
	buffer.lines[buffer.cursor.line] = left + separator + right
	buffer.lines.delete(buffer.cursor.line + 1)
	buffer.cursor.column = rune_len(left)
	buffer.after_edit()
	return true
}

pub fn (mut buffer Buffer) replace_char(text string) bool {
	if text == '' {
		return false
	}
	line := buffer.lines[buffer.cursor.line]
	if buffer.cursor.column >= rune_len(line) {
		return false
	}
	start := buffer.cursor
	end := Cursor{buffer.cursor.line, buffer.cursor.column + 1}
	return buffer.replace_range(start, end, text)
}

pub fn (mut buffer Buffer) search_next(query string, include_current bool) bool {
	if query == '' {
		return false
	}
	text := buffer.text()
	if text == '' {
		return false
	}
	mut start_cursor := buffer.cursor
	if !include_current {
		start_cursor = buffer.cursor_from_global_rune_offset(buffer.global_rune_offset(buffer.cursor) + 1)
	}
	start_idx := buffer.byte_offset_at_cursor(start_cursor)
	if start_idx < text.len {
		if idx := text[start_idx..].index(query) {
			buffer.cursor = buffer.cursor_from_byte_offset(start_idx + idx)
			buffer.normalize_scroll_top()
			return true
		}
	}
	if idx := text.index(query) {
		buffer.cursor = buffer.cursor_from_byte_offset(idx)
		buffer.normalize_scroll_top()
		return true
	}
	return false
}

fn (buffer &Buffer) global_rune_offset(cursor Cursor) int {
	mut offset := 0
	for line_no, line in buffer.lines {
		if line_no == cursor.line {
			return offset + clamp(cursor.column, 0, rune_len(line))
		}
		offset += rune_len(line)
		if line_no < buffer.lines.len - 1 {
			offset++
		}
	}
	return offset
}

fn (buffer &Buffer) cursor_from_global_rune_offset(offset int) Cursor {
	mut remaining := max_int(offset, 0)
	for line_no, line in buffer.lines {
		line_len := rune_len(line)
		if remaining <= line_len {
			return Cursor{line_no, remaining}
		}
		remaining -= line_len
		if line_no < buffer.lines.len - 1 {
			if remaining == 0 {
				return Cursor{line_no + 1, 0}
			}
			remaining--
		}
	}
	last := buffer.lines.len - 1
	return Cursor{last, rune_len(buffer.lines[last])}
}

fn (buffer &Buffer) byte_offset_at_cursor(cursor Cursor) int {
	mut offset := 0
	for line_no, line in buffer.lines {
		if line_no == cursor.line {
			return offset + byte_index_at_column(line, cursor.column)
		}
		offset += line.len
		if line_no < buffer.lines.len - 1 {
			offset++
		}
	}
	return offset
}

fn (buffer &Buffer) cursor_from_byte_offset(offset int) Cursor {
	mut remaining := max_int(offset, 0)
	for line_no, line in buffer.lines {
		if remaining <= line.len {
			return Cursor{line_no, column_from_byte_index(line, remaining)}
		}
		remaining -= line.len
		if line_no < buffer.lines.len - 1 {
			if remaining == 0 {
				return Cursor{line_no + 1, 0}
			}
			remaining--
		}
	}
	last := buffer.lines.len - 1
	return Cursor{last, rune_len(buffer.lines[last])}
}

fn normalize_range(start Cursor, end Cursor) (Cursor, Cursor) {
	if cursor_before(end, start) {
		return end, start
	}
	return start, end
}

fn cursor_before(left Cursor, right Cursor) bool {
	if left.line != right.line {
		return left.line < right.line
	}
	return left.column < right.column
}

fn same_cursor(left Cursor, right Cursor) bool {
	return left.line == right.line && left.column == right.column
}

fn first_non_blank_column(line string) int {
	for index, rune_value in line.runes() {
		if rune_value != ` ` && rune_value != `\t` {
			return index
		}
	}
	return 0
}

fn next_word_start_offset(runes []rune, offset int) int {
	if runes.len == 0 {
		return 0
	}
	mut index := clamp(offset, 0, runes.len)
	if index >= runes.len {
		return runes.len
	}
	class := rune_class(runes[index])
	if class == .space {
		for index < runes.len && rune_class(runes[index]) == .space {
			index++
		}
		return index
	}
	if class == .ascii_word {
		for index < runes.len && rune_class(runes[index]) == .ascii_word {
			index++
		}
	} else {
		index++
	}
	for index < runes.len && rune_class(runes[index]) == .space {
		index++
	}
	return index
}

fn prev_word_start_offset(runes []rune, offset int) int {
	if runes.len == 0 || offset <= 0 {
		return 0
	}
	mut index := clamp(offset - 1, 0, runes.len - 1)
	for index > 0 && rune_class(runes[index]) == .space {
		index--
	}
	if rune_class(runes[index]) == .ascii_word {
		for index > 0 && rune_class(runes[index - 1]) == .ascii_word {
			index--
		}
	}
	return index
}

fn word_end_offset(runes []rune, offset int) int {
	if runes.len == 0 {
		return 0
	}
	mut index := clamp(offset, 0, runes.len)
	for index < runes.len && rune_class(runes[index]) == .space {
		index++
	}
	if index >= runes.len {
		return runes.len
	}
	class := rune_class(runes[index])
	if class == .ascii_word {
		for index < runes.len && rune_class(runes[index]) == .ascii_word {
			index++
		}
		return index
	}
	return min_int(index + 1, runes.len)
}

fn rune_class(r rune) RuneClass {
	if r == ` ` || r == `\t` || r == `\n` || r == `\r` {
		return .space
	}
	code := u32(r)
	if (code >= `0` && code <= `9`) || (code >= `A` && code <= `Z`) || (code >= `a` && code <= `z`) || r == `_` {
		return .ascii_word
	}
	if is_cjk_rune(code) {
		return .cjk_word
	}
	return .punct
}

fn is_cjk_rune(code u32) bool {
	return (code >= 0x3400 && code <= 0x4dbf) || (code >= 0x4e00 && code <= 0x9fff)
		|| (code >= 0xf900 && code <= 0xfaff) || (code >= 0x3040 && code <= 0x30ff)
		|| (code >= 0xac00 && code <= 0xd7af)
}

fn ascii_word_tokens(line string) []string {
	mut tokens := []string{}
	mut current := ''
	for rune_value in line.runes() {
		if rune_class(rune_value) == .ascii_word {
			current += rune_value.str()
			continue
		}
		if current != '' {
			tokens << current
			current = ''
		}
	}
	if current != '' {
		tokens << current
	}
	return tokens
}

fn leading_indent_width(line string, levels int) int {
	mut removed := 0
	mut remaining := levels * 4
	for removed < line.len && remaining > 0 {
		if line[removed] == ` ` {
			removed++
			remaining--
			continue
		}
		if line[removed] == `\t` {
			removed++
			break
		}
		break
	}
	return removed
}

fn trim_left_spaces(text string) string {
	mut index := 0
	for index < text.len && (text[index] == ` ` || text[index] == `\t`) {
		index++
	}
	return text[index..]
}

fn trim_right_spaces(text string) string {
	mut end := text.len
	for end > 0 && (text[end - 1] == ` ` || text[end - 1] == `\t`) {
		end--
	}
	return text[..end]
}

fn column_from_byte_index(line string, byte_index int) int {
	if byte_index <= 0 {
		return 0
	}
	mut current := 0
	mut column := 0
	for rune_value in line.runes() {
		if current >= byte_index {
			return column
		}
		current += rune_value.length_in_bytes()
		column++
	}
	return column
}

fn last_index_of_rune_before(runes []rune, target rune, before int) int {
	mut index := min_int(before - 1, runes.len - 1)
	for index >= 0 {
		if runes[index] == target {
			return index
		}
		index--
	}
	return -1
}

fn first_index_of_rune_after(runes []rune, target rune, after int) int {
	mut index := max_int(after, 0)
	for index < runes.len {
		if runes[index] == target {
			return index
		}
		index++
	}
	return -1
}