module editor

import core
import gg

pub enum Mode {
	normal
	insert
	visual
	search
}

pub struct EditorAction {
pub:
	request_save   bool
	request_quit   bool
	copy_to_system string
}

enum ClipboardKind {
	empty
	charwise
	linewise
}

struct Clipboard {
mut:
	kind ClipboardKind
	text string
}

enum InsertOrigin {
	none
	insert_before
	append_after
	append_end
	insert_line_start
	open_below
	open_above
	change_word_start
	change_word_end
	change_inside
}

enum RepeatKind {
	none
	delete_char
	delete_line
	delete_word_start
	delete_word_end
	delete_inside
	join_lines
	indent_right
	indent_left
	replace_char
	paste
	insert_session
}

struct RepeatAction {
mut:
	kind   RepeatKind
	text   string
	origin InsertOrigin
	lines  bool
}

pub struct State {
mut:
	pending           string
	skip_next_text    string
	visual_anchor     core.Cursor
	search_query      string
	last_search       string
	awaiting_replace  bool
	clipboard         Clipboard
	last_edit         RepeatAction
	insert_origin     InsertOrigin
	inserted_text     string
	insert_can_repeat bool
	completion_prefix string
	completion_items  []string
	completion_index  int
pub mut:
	buffer core.Buffer
	mode   Mode = .normal
	status string = 'NORMAL'
}

pub fn new_state(buffer core.Buffer) State {
	return State{
		buffer: buffer
	}
}

pub fn (mut state State) key_down(key gg.KeyCode, mod gg.Modifier, visible_lines int) EditorAction {
	super := mod.has(.super) || mod.has(.ctrl)
	ctrl := mod.has(.ctrl)
	shift := mod.has(.shift)
	if super && key == .s {
		return EditorAction{request_save: true}
	}
	if super && key == .q {
		return EditorAction{request_quit: true}
	}
	if super && key == .r && state.mode != .search {
		state.reset_pending()
		if state.buffer.redo() {
			state.status = 'REDO'
		}
		return EditorAction{}
	}
	if state.mode == .insert && super && key == .n {
		state.autocomplete()
		return EditorAction{}
	}
	match state.mode {
		.normal {
			return state.handle_normal(key, ctrl, shift, visible_lines)
		}
		.insert {
			state.handle_insert(key)
		}
		.visual {
			return state.handle_visual(key, ctrl, shift, visible_lines)
		}
		.search {
			state.handle_search_key(key)
		}
	}
	return EditorAction{}
}

pub fn (mut state State) handle_text(text string) {
	if state.skip_next_text != '' && text == state.skip_next_text {
		state.skip_next_text = ''
		return
	}
	state.skip_next_text = ''
	if state.awaiting_replace {
		state.awaiting_replace = false
		if state.buffer.replace_char(text) {
			state.last_edit = RepeatAction{kind: .replace_char, text: text}
			state.status = 'REPLACE'
		}
		return
	}
	match state.mode {
		.insert {
			state.buffer.insert_text(text)
			state.inserted_text += text
			state.status = 'INSERT'
		}
		.search {
			state.search_query += text
			state.status = '/' + state.search_query
		}
		else {}
	}
}

pub fn (state &State) mode_label() string {
	return match state.mode {
		.normal { 'NORMAL' }
		.insert { 'INSERT' }
		.visual { 'VISUAL' }
		.search { 'SEARCH' }
	}
}

pub fn (state &State) has_selection() bool {
	_, _, ok := state.selection_range()
	return ok
}

pub fn (state &State) selection_range() (core.Cursor, core.Cursor, bool) {
	if state.mode != .visual {
		return core.Cursor{}, core.Cursor{}, false
	}
	if same_cursor(state.visual_anchor, state.buffer.cursor) {
		return core.Cursor{}, core.Cursor{}, false
	}
	if cursor_before(state.buffer.cursor, state.visual_anchor) {
		return state.buffer.cursor, state.visual_anchor, true
	}
	return state.visual_anchor, state.buffer.cursor, true
}

fn (mut state State) handle_insert(key gg.KeyCode) {
	match key {
		.escape {
			state.finish_insert_mode()
		}
		.enter {
			state.buffer.insert_newline()
			state.inserted_text += '\n'
		}
		.backspace {
			state.buffer.backspace()
			state.insert_can_repeat = false
		}
		.left {
			state.buffer.move_left()
			state.insert_can_repeat = false
		}
		.right {
			state.buffer.move_right()
			state.insert_can_repeat = false
		}
		.up {
			state.buffer.move_up()
			state.insert_can_repeat = false
		}
		.down {
			state.buffer.move_down()
			state.insert_can_repeat = false
		}
		.home {
			state.buffer.move_to_line_start()
			state.insert_can_repeat = false
		}
		.end {
			state.buffer.move_to_line_end()
			state.insert_can_repeat = false
		}
		.tab {
			state.buffer.insert_text('    ')
			state.inserted_text += '    '
		}
		else {}
	}
}

fn (mut state State) handle_search_key(key gg.KeyCode) {
	match key {
		.escape {
			state.mode = .normal
			state.search_query = ''
			state.status = 'NORMAL'
		}
		.backspace {
			if state.search_query.len > 0 {
				state.search_query = state.search_query[..state.search_query.len - 1]
			}
			state.status = '/' + state.search_query
		}
		.enter {
			state.execute_search(state.search_query, false)
			state.mode = .normal
			state.search_query = ''
		}
		else {}
	}
}

fn (mut state State) handle_visual(key gg.KeyCode, ctrl bool, shift bool, visible_lines int) EditorAction {
	if state.pending == '+' {
		state.pending = ''
		if key == .y {
			state.mode = .normal
			state.status = 'SYSTEM YANK'
			return EditorAction{copy_to_system: state.current_system_copy_text()}
		}
		state.status = 'VISUAL'
		return EditorAction{}
	}
	if (ctrl && key == .f) || key == .page_down {
		state.buffer.move_page_down(max_int(visible_lines - 1, 1))
		state.status = 'VISUAL'
		return EditorAction{}
	}
	if (ctrl && key == .b) || key == .page_up {
		state.buffer.move_page_up(max_int(visible_lines - 1, 1))
		state.status = 'VISUAL'
		return EditorAction{}
	}
	if shift && key == .l {
		state.buffer.move_to_screen_top(visible_lines)
		state.status = 'VISUAL'
		return EditorAction{}
	}
	if shift && key == .h {
		state.buffer.move_to_screen_bottom(visible_lines)
		state.status = 'VISUAL'
		return EditorAction{}
	}
	if shift && key == ._4 {
		state.buffer.move_to_line_end()
		state.status = 'VISUAL'
		return EditorAction{}
	}
	if shift && key == ._6 {
		state.buffer.move_to_first_non_blank()
		state.status = 'VISUAL'
		return EditorAction{}
	}
	if shift && key == .g {
		state.buffer.move_to_file_end()
		state.status = 'VISUAL'
		return EditorAction{}
	}
	if shift && key == .comma {
		state.indent_selection(-1)
		return EditorAction{}
	}
	if shift && key == .period {
		state.indent_selection(1)
		return EditorAction{}
	}
	if shift && key == .equal {
		state.pending = '+'
		state.status = '+ '
		return EditorAction{}
	}
	match key {
		.escape, .v {
			state.mode = .normal
			state.status = 'NORMAL'
		}
		.left, .h {
			state.buffer.move_left()
		}
		.right, .l {
			state.buffer.move_right()
		}
		.up, .k {
			state.buffer.move_up()
		}
		.down, .j {
			state.buffer.move_down()
		}
		._0, .home {
			state.buffer.move_to_line_start()
		}
		.w {
			state.buffer.move_word_forward()
		}
		.b {
			state.buffer.move_word_backward()
		}
		.g {
			state.buffer.move_to_file_start()
		}
		.y {
			state.yank_selection()
		}
		.d {
			state.delete_selection()
		}
		else {}
	}
	state.status = 'VISUAL'
	return EditorAction{}
}

fn (mut state State) handle_normal(key gg.KeyCode, ctrl bool, shift bool, visible_lines int) EditorAction {
	if (ctrl && key == .f) || key == .page_down {
		state.reset_pending()
		state.buffer.move_page_down(max_int(visible_lines - 1, 1))
		state.status = 'PAGE DOWN'
		return EditorAction{}
	}
	if (ctrl && key == .b) || key == .page_up {
		state.reset_pending()
		state.buffer.move_page_up(max_int(visible_lines - 1, 1))
		state.status = 'PAGE UP'
		return EditorAction{}
	}
	if state.pending != '' {
		return state.handle_pending(key, visible_lines)
	}
	if shift && key == .l {
		state.buffer.move_to_screen_top(visible_lines)
		state.status = 'TOP'
		return EditorAction{}
	}
	if shift && key == .h {
		state.buffer.move_to_screen_bottom(visible_lines)
		state.status = 'BOTTOM'
		return EditorAction{}
	}
	if shift && key == ._4 {
		state.buffer.move_to_line_end()
		state.status = 'EOL'
		return EditorAction{}
	}
	if shift && key == ._6 {
		state.buffer.move_to_first_non_blank()
		state.status = 'FIRST NON BLANK'
		return EditorAction{}
	}
	if shift && key == .a {
		state.buffer.move_to_line_end()
		state.enter_insert_mode(.append_end, 'A')
		return EditorAction{}
	}
	if shift && key == .i {
		state.buffer.move_to_first_non_blank()
		state.enter_insert_mode(.insert_line_start, 'I')
		return EditorAction{}
	}
	if shift && key == .g {
		state.reset_pending()
		state.buffer.move_to_file_end()
		state.status = 'EOF'
		return EditorAction{}
	}
	if shift && key == .j {
		state.reset_pending()
		if state.buffer.join_with_next_line() {
			state.last_edit = RepeatAction{kind: .join_lines}
			state.status = 'JOIN'
		}
		return EditorAction{}
	}
	if shift && key == .comma {
		state.reset_pending()
		if state.buffer.indent_lines(state.buffer.cursor.line, state.buffer.cursor.line, -1) {
			state.last_edit = RepeatAction{kind: .indent_left}
			state.status = 'OUTDENT'
		}
		return EditorAction{}
	}
	if shift && key == .period {
		state.reset_pending()
		if state.buffer.indent_lines(state.buffer.cursor.line, state.buffer.cursor.line, 1) {
			state.last_edit = RepeatAction{kind: .indent_right}
			state.status = 'INDENT'
		}
		return EditorAction{}
	}
	if shift && key == ._8 {
		state.reset_pending()
		state.search_current_word()
		return EditorAction{}
	}
	match key {
		.left, .h {
			state.buffer.move_left()
			state.status = 'MOVE'
		}
		.right, .l {
			state.buffer.move_right()
			state.status = 'MOVE'
		}
		.up, .k {
			state.buffer.move_up()
			state.status = 'MOVE'
		}
		.down, .j {
			state.buffer.move_down()
			state.status = 'MOVE'
		}
		._0, .home {
			state.buffer.move_to_line_start()
			state.status = 'BOL'
		}
		.end {
			state.buffer.move_to_line_end()
			state.status = 'EOL'
		}
		.w {
			state.buffer.move_word_forward()
			state.status = 'WORD'
		}
		.b {
			state.buffer.move_word_backward()
			state.status = 'WORD'
		}
		.i {
			state.enter_insert_mode(.insert_before, 'i')
		}
		.a {
			if state.buffer.cursor.column < state.current_line_len() {
				state.buffer.move_right()
			}
			state.enter_insert_mode(.append_after, 'a')
		}
		.o {
			if shift {
				state.buffer.insert_line_above()
				state.enter_insert_mode(.open_above, 'O')
			} else {
				state.buffer.insert_line_below()
				state.enter_insert_mode(.open_below, 'o')
			}
		}
		.v {
			state.mode = .visual
			state.visual_anchor = state.buffer.cursor
			state.status = 'VISUAL'
		}
		.g {
			state.pending = 'g'
			state.status = 'g'
		}
		.z {
			state.pending = 'z'
			state.status = 'z'
		}
		.d {
			state.pending = 'd'
			state.status = 'd'
		}
		.c {
			state.pending = 'c'
			state.status = 'c'
		}
		.y {
			state.pending = 'y'
			state.status = 'y'
		}
		.p {
			state.paste_clipboard()
		}
		.x {
			state.reset_pending()
			state.buffer.delete_char()
			state.last_edit = RepeatAction{kind: .delete_char}
			state.status = 'DELETE CHAR'
		}
		.r {
			state.reset_pending()
			state.awaiting_replace = true
			state.skip_next_text = 'r'
			state.status = 'r'
		}
		.u {
			state.reset_pending()
			if state.buffer.undo() {
				state.status = 'UNDO'
			}
		}
		.slash {
			state.reset_pending()
			state.mode = .search
			state.search_query = ''
			state.skip_next_text = '/'
			state.status = '/'
		}
		.n {
			state.reset_pending()
			state.repeat_search()
		}
		.period {
			state.reset_pending()
			state.repeat_last_edit()
		}
		.equal {
			if shift {
				state.pending = '+'
				state.status = '+ '
			}
		}
		.escape {
			state.reset_pending()
			state.status = 'NORMAL'
		}
		else {
			state.reset_pending()
		}
	}
	return EditorAction{}
}

fn (mut state State) handle_pending(key gg.KeyCode, visible_lines int) EditorAction {
	match state.pending {
		'g' {
			if key == .g {
				state.buffer.move_to_file_start()
				state.status = 'BOF'
			}
			state.pending = ''
			return EditorAction{}
		}
		'z' {
			if key == .z {
				state.buffer.center_cursor(visible_lines)
				state.status = 'CENTER'
			}
			state.pending = ''
			return EditorAction{}
		}
		'y' {
			if key == .y {
				state.set_line_clipboard(state.buffer.current_line_text())
				state.status = 'YANK LINE'
			}
			state.pending = ''
			return EditorAction{}
		}
		'+' {
			state.pending = ''
			if key == .y {
				state.status = 'SYSTEM YANK'
				return EditorAction{copy_to_system: state.current_system_copy_text()}
			}
			return EditorAction{}
		}
		'd' {
			return state.handle_delete_pending(key)
		}
		'c' {
			return state.handle_change_pending(key)
		}
		else {
			state.pending = ''
			return EditorAction{}
		}
	}
}

fn (mut state State) handle_delete_pending(key gg.KeyCode) EditorAction {
	state.pending = ''
	match key {
		.d {
			state.set_line_clipboard(state.buffer.delete_line())
			state.last_edit = RepeatAction{kind: .delete_line}
			state.status = 'DELETE LINE'
		}
		.w {
			state.set_char_clipboard(state.buffer.delete_word(false))
			state.last_edit = RepeatAction{kind: .delete_word_start}
			state.status = 'DELETE WORD'
		}
		.e {
			state.set_char_clipboard(state.buffer.delete_word(true))
			state.last_edit = RepeatAction{kind: .delete_word_end}
			state.status = 'DELETE TO END'
		}
		.i {
			state.set_char_clipboard(state.buffer.delete_inside_object())
			state.last_edit = RepeatAction{kind: .delete_inside}
			state.status = 'DELETE INSIDE'
		}
		else {}
	}
	return EditorAction{}
}

fn (mut state State) handle_change_pending(key gg.KeyCode) EditorAction {
	state.pending = ''
	match key {
		.w {
			state.set_char_clipboard(state.buffer.delete_word(false))
			state.enter_insert_mode(.change_word_start, 'w')
			state.status = 'CHANGE WORD'
		}
		.e {
			state.set_char_clipboard(state.buffer.delete_word(true))
			state.enter_insert_mode(.change_word_end, 'e')
			state.status = 'CHANGE TO END'
		}
		.i {
			state.set_char_clipboard(state.buffer.delete_inside_object())
			state.enter_insert_mode(.change_inside, 'i')
			state.status = 'CHANGE INSIDE'
		}
		else {}
	}
	return EditorAction{}
}

fn (mut state State) enter_insert_mode(origin InsertOrigin, skip string) {
	state.reset_pending()
	state.mode = .insert
	state.insert_origin = origin
	state.inserted_text = ''
	state.insert_can_repeat = true
	state.skip_next_text = skip
	state.status = 'INSERT'
}

fn (mut state State) finish_insert_mode() {
	if state.insert_can_repeat && state.insert_origin != .none {
		state.last_edit = RepeatAction{
			kind: .insert_session
			text: state.inserted_text
			origin: state.insert_origin
		}
	}
	state.mode = .normal
	state.insert_origin = .none
	state.inserted_text = ''
	state.insert_can_repeat = false
	state.status = 'NORMAL'
}

fn (mut state State) autocomplete() {
	prefix := state.buffer.current_word_prefix()
	if prefix == '' {
		state.status = 'NO COMPLETION'
		return
	}
	if prefix != state.completion_prefix {
		state.completion_prefix = prefix
		state.completion_items = state.buffer.completion_candidates(prefix)
		state.completion_index = 0
	} else if state.completion_items.len > 0 {
		state.completion_index = (state.completion_index + 1) % state.completion_items.len
	}
	if state.completion_items.len == 0 {
		state.status = 'NO COMPLETION'
		return
	}
	if state.buffer.apply_completion(prefix, state.completion_items[state.completion_index]) {
		state.status = 'COMPLETE'
		state.insert_can_repeat = false
	}
}

fn (mut state State) paste_clipboard() {
	state.reset_pending()
	match state.clipboard.kind {
		.linewise {
			state.buffer.insert_lines_below(state.clipboard.text.split('\n'))
			state.last_edit = RepeatAction{kind: .paste, text: state.clipboard.text, lines: true}
		}
		.charwise {
			state.buffer.insert_text(state.clipboard.text)
			state.last_edit = RepeatAction{kind: .paste, text: state.clipboard.text, lines: false}
		}
		else {
			return
		}
	}
	state.status = 'PASTE'
}

fn (mut state State) execute_search(query string, include_current bool) {
	if query == '' {
		state.status = 'SEARCH EMPTY'
		return
	}
	state.last_search = query
	if state.buffer.search_next(query, include_current) {
		state.status = 'SEARCH ' + query
		return
	}
	state.status = 'NOT FOUND'
}

fn (mut state State) search_current_word() {
	query := state.buffer.current_word()
	if query == '' {
		state.status = 'NO WORD'
		return
	}
	state.execute_search(query, false)
}

fn (mut state State) repeat_search() {
	if state.last_search == '' {
		state.status = 'NO SEARCH'
		return
	}
	state.execute_search(state.last_search, false)
}

fn (mut state State) repeat_last_edit() {
	match state.last_edit.kind {
		.none {
			state.status = 'NO REPEAT'
		}
		.delete_char {
			state.buffer.delete_char()
			state.status = 'REPEAT'
		}
		.delete_line {
			state.set_line_clipboard(state.buffer.delete_line())
			state.status = 'REPEAT'
		}
		.delete_word_start {
			state.set_char_clipboard(state.buffer.delete_word(false))
			state.status = 'REPEAT'
		}
		.delete_word_end {
			state.set_char_clipboard(state.buffer.delete_word(true))
			state.status = 'REPEAT'
		}
		.delete_inside {
			state.set_char_clipboard(state.buffer.delete_inside_object())
			state.status = 'REPEAT'
		}
		.join_lines {
			if state.buffer.join_with_next_line() {
				state.status = 'REPEAT'
			}
		}
		.indent_right {
			state.buffer.indent_lines(state.buffer.cursor.line, state.buffer.cursor.line, 1)
			state.status = 'REPEAT'
		}
		.indent_left {
			state.buffer.indent_lines(state.buffer.cursor.line, state.buffer.cursor.line, -1)
			state.status = 'REPEAT'
		}
		.replace_char {
			if state.buffer.replace_char(state.last_edit.text) {
				state.status = 'REPEAT'
			}
		}
		.paste {
			if state.last_edit.lines {
				state.buffer.insert_lines_below(state.last_edit.text.split('\n'))
			} else {
				state.buffer.insert_text(state.last_edit.text)
			}
			state.status = 'REPEAT'
		}
		.insert_session {
			state.replay_insert_session()
		}
	}
}

fn (mut state State) replay_insert_session() {
	match state.last_edit.origin {
		.insert_before {}
		.append_after {
			if state.buffer.cursor.column < state.current_line_len() {
				state.buffer.move_right()
			}
		}
		.append_end {
			state.buffer.move_to_line_end()
		}
		.insert_line_start {
			state.buffer.move_to_first_non_blank()
		}
		.open_below {
			state.buffer.insert_line_below()
		}
		.open_above {
			state.buffer.insert_line_above()
		}
		.change_word_start {
			state.set_char_clipboard(state.buffer.delete_word(false))
		}
		.change_word_end {
			state.set_char_clipboard(state.buffer.delete_word(true))
		}
		.change_inside {
			state.set_char_clipboard(state.buffer.delete_inside_object())
		}
		else {}
	}
	if state.last_edit.text != '' {
		state.buffer.insert_text(state.last_edit.text)
	}
	state.status = 'REPEAT'
}

fn (mut state State) yank_selection() {
	start, end, ok := state.selection_range()
	if !ok {
		return
	}
	state.set_char_clipboard(state.buffer.text_in_range(start, end))
	state.mode = .normal
	state.status = 'YANK'
}

fn (mut state State) delete_selection() {
	start, end, ok := state.selection_range()
	if !ok {
		return
	}
	state.set_char_clipboard(state.buffer.delete_range(start, end))
	state.mode = .normal
	state.status = 'DELETE'
}

fn (mut state State) indent_selection(delta int) {
	start, end, ok := state.selection_range()
	if !ok {
		return
	}
	if state.buffer.indent_lines(start.line, end.line, delta) {
		state.mode = .normal
		state.last_edit = RepeatAction{kind: if delta > 0 { .indent_right } else { .indent_left }}
		state.status = if delta > 0 { 'INDENT' } else { 'OUTDENT' }
	}
}

fn (mut state State) set_char_clipboard(text string) {
	state.clipboard = Clipboard{
		kind: .charwise
		text: text
	}
}

fn (mut state State) set_line_clipboard(text string) {
	state.clipboard = Clipboard{
		kind: .linewise
		text: text
	}
}

fn (state &State) current_system_copy_text() string {
	start, end, ok := state.selection_range()
	if ok {
		return state.buffer.text_in_range(start, end)
	}
	return state.buffer.current_line_text()
}

fn (state &State) current_line_len() int {
	return state.buffer.current_line_text().runes().len
}

fn (mut state State) reset_pending() {
	state.pending = ''
	state.awaiting_replace = false
	state.completion_prefix = ''
	state.completion_items = []string{}
	state.completion_index = 0
}

fn cursor_before(left core.Cursor, right core.Cursor) bool {
	if left.line != right.line {
		return left.line < right.line
	}
	return left.column < right.column
}

fn same_cursor(left core.Cursor, right core.Cursor) bool {
	return left.line == right.line && left.column == right.column
}

fn max_int(left int, right int) int {
	if left > right {
		return left
	}
	return right
}
