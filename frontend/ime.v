module frontend

import os
import time
import uiold

fn ime_insert_text(window_ptr voidptr, text &char) {
	s := unsafe { text.vstring() }
	if s.len == 0 {
		return
	}
	mut window := unsafe { &Window(window_ptr) }
	window.apply_ime_text(s)
	window.marked_text = ''
	window.ensure_cursor_visible()
	window.gg.refresh_ui()
}

fn ime_marked_text(window_ptr voidptr, text &char) {
	s := unsafe { text.vstring() }
	mut window := unsafe { &Window(window_ptr) }
	window.marked_text = s
	window.gg.refresh_ui()
}

fn init_native_ime(window &Window) {
	$if macos {
		if os.getenv('VED_TEST') == '' {
			time.sleep(1 * time.second)
			uiold.setup_mac_app()
			uiold.reg_ved_insert_cb(ime_insert_text)
			uiold.reg_ved_marked_cb(ime_marked_text)
			uiold.reg_ved_instance(window)
			window.sync_ime_focus()
		}
	}
}

fn (mut window Window) apply_ime_text(text string) {
	mut state := window.session.current_state_mut()
	match text {
		'[ENTER]' {
			state.buffer.insert_newline()
		}
		'[BACKSPACE]' {
			state.buffer.backspace()
		}
		'[ESC]' {
			state.mode = .normal
			state.status = 'NORMAL'
			window.sync_ime_focus()
		}
		'[TAB]' {
			state.buffer.insert_text('    ')
		}
		'[UP]' {
			state.buffer.move_up()
		}
		'[DOWN]' {
			state.buffer.move_down()
		}
		'[LEFT]' {
			state.buffer.move_left()
		}
		'[RIGHT]' {
			state.buffer.move_right()
		}
		'[HOME]' {
			state.buffer.move_to_line_start()
		}
		'[END]' {
			state.buffer.move_to_line_end()
		}
		'[PGUP]' {
			state.buffer.move_page_up(max_int(window.visible_line_count() - 1, 1))
		}
		'[PGDN]' {
			state.buffer.move_page_down(max_int(window.visible_line_count() - 1, 1))
		}
		else {
			if state.mode == .insert {
				state.buffer.insert_text(text)
				state.status = 'INSERT'
			}
		}
	}
}

fn (window &Window) sync_ime_focus() {
	$if macos {
		if os.getenv('VED_TEST') == '' {
			state := window.session.current_state()
			uiold.focus_native_input(state.mode == .insert && !window.picker.active)
		}
	}
}