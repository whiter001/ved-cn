module frontend

import core
import editor
import infra

fn test_apply_ime_text_inserts_multibyte_text() {
	mut window := Window{
		session: editor.new_session([core.new_buffer('', 'hello')], '')
		store: infra.new_file_store()
	}
	mut state := window.session.current_state_mut()
	state.mode = .insert
	window.apply_ime_text('你好')
	assert window.session.current_state().buffer.text() == '你好hello'
}

fn test_apply_ime_text_handles_backspace_and_enter() {
	mut window := Window{
		session: editor.new_session([core.new_buffer('', 'ab')], '')
		store: infra.new_file_store()
	}
	mut state := window.session.current_state_mut()
	state.mode = .insert
	window.apply_ime_text('你')
	window.apply_ime_text('[BACKSPACE]')
	window.apply_ime_text('[ENTER]')
	assert window.session.current_state().buffer.lines == ['', 'ab']
}