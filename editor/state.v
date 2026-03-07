module editor

import core
import gg

pub enum Mode {
	normal
	insert
}

pub struct EditorAction {
pub:
	request_save bool
	request_quit bool
}

pub struct State {
mut:
	pending         string
	skip_next_text  string
pub mut:
	buffer    core.Buffer
	mode      Mode = .normal
	status    string = 'NORMAL'
	clipboard []string
}

pub fn new_state(buffer core.Buffer) State {
	return State{
		buffer: buffer
	}
}

pub fn (mut state State) key_down(key gg.KeyCode, mod gg.Modifier) EditorAction {
	super := mod.has(.super) || mod.has(.ctrl)
	shift := mod.has(.shift)
	if super && key == .s {
		return EditorAction{request_save: true}
	}
	if super && key == .q {
		return EditorAction{request_quit: true}
	}
	if (mod.has(.ctrl) || mod.has(.super)) && key == .r {
		if state.buffer.redo() {
			state.status = 'REDO'
		}
		return EditorAction{}
	}
	match state.mode {
		.normal {
			state.handle_normal(key, shift)
		}
		.insert {
			state.handle_insert(key)
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
	if state.mode != .insert {
		return
	}
	state.buffer.insert_text(text)
	state.status = 'INSERT'
}

pub fn (state &State) mode_label() string {
	return match state.mode {
		.normal { 'NORMAL' }
		.insert { 'INSERT' }
	}
}

fn (mut state State) handle_insert(key gg.KeyCode) {
	match key {
		.escape {
			state.mode = .normal
			state.status = 'NORMAL'
		}
		.enter {
			state.buffer.insert_newline()
		}
		.backspace {
			state.buffer.backspace()
		}
		.left {
			state.buffer.move_left()
		}
		.right {
			state.buffer.move_right()
		}
		.up {
			state.buffer.move_up()
		}
		.down {
			state.buffer.move_down()
		}
		.tab {
			state.buffer.insert_text('    ')
		}
		else {}
	}
}

fn (mut state State) handle_normal(key gg.KeyCode, shift bool) {
	match key {
		.left, .h {
			state.reset_pending()
			state.buffer.move_left()
		}
		.right, .l {
			state.reset_pending()
			state.buffer.move_right()
		}
		.up, .k {
			state.reset_pending()
			state.buffer.move_up()
		}
		.down, .j {
			state.reset_pending()
			state.buffer.move_down()
		}
		.i {
			state.reset_pending()
			state.mode = .insert
			state.skip_next_text = 'i'
			state.status = 'INSERT'
		}
		.a {
			state.reset_pending()
			state.buffer.move_right()
			state.mode = .insert
			state.skip_next_text = 'a'
			state.status = 'INSERT'
		}
		.o {
			state.reset_pending()
			if shift {
				state.buffer.insert_line_above()
				state.skip_next_text = 'O'
			} else {
				state.buffer.insert_line_below()
				state.skip_next_text = 'o'
			}
			state.mode = .insert
			state.status = 'INSERT'
		}
		.x {
			state.reset_pending()
			state.buffer.delete_char()
			state.status = 'DELETE CHAR'
		}
		.u {
			state.reset_pending()
			if state.buffer.undo() {
				state.status = 'UNDO'
			}
		}
		.d {
			if state.pending == 'd' {
				deleted := state.buffer.delete_line()
				state.clipboard = [deleted]
				state.pending = ''
				state.status = 'DELETE LINE'
			} else {
				state.pending = 'd'
				state.status = 'd'
			}
		}
		.y {
			if state.pending == 'y' {
				state.clipboard = [state.buffer.current_line_text()]
				state.pending = ''
				state.status = 'YANK LINE'
			} else {
				state.pending = 'y'
				state.status = 'y'
			}
		}
		.p {
			state.reset_pending()
			state.buffer.insert_lines_below(state.clipboard)
			state.status = 'PASTE'
		}
		.escape {
			state.reset_pending()
			state.status = 'NORMAL'
		}
		else {
			state.reset_pending()
		}
	}
}

fn (mut state State) reset_pending() {
	state.pending = ''
}