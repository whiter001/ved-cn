module editor

import core

pub struct Session {
pub mut:
	states         []State
	current        int
	workspace_root string
}

pub fn new_session(buffers []core.Buffer, workspace_root string) Session {
	mut states := []State{}
	for buffer in buffers {
		states << new_state(buffer)
	}
	if states.len == 0 {
		states << new_state(core.new_buffer('', ''))
	}
	return Session{
		states: states
		workspace_root: workspace_root
	}
}

pub fn (session &Session) current_state() State {
	return session.states[session.current]
}

pub fn (session &Session) current_index() int {
	return session.current
}

pub fn (session &Session) tab_count() int {
	return session.states.len
}

pub fn (session &Session) tab_titles() []string {
	mut titles := []string{cap: session.states.len}
	for index, state in session.states {
		mut title := tab_title(state.buffer.path)
		if state.buffer.dirty {
			title += ' *'
		}
		if session.current == index {
			title = '[' + title + ']'
		}
		titles << title
	}
	return titles
}

pub fn (mut session Session) current_state_mut() &State {
	return &session.states[session.current]
}

pub fn (mut session Session) switch_next() {
	if session.states.len <= 1 {
		return
	}
	session.current = (session.current + 1) % session.states.len
	}

pub fn (mut session Session) switch_prev() {
	if session.states.len <= 1 {
		return
	}
	session.current = (session.current - 1 + session.states.len) % session.states.len
	}

pub fn (mut session Session) add_buffer(buffer core.Buffer) {
	session.states << new_state(buffer)
	session.current = session.states.len - 1
	}

pub fn (mut session Session) add_empty_buffer() {
	session.add_buffer(core.new_buffer('', ''))
}

pub fn (session &Session) index_of_path(path string) int {
	for index, state in session.states {
		if state.buffer.path == path {
			return index
		}
	}
	return -1
}

pub fn (mut session Session) switch_to(index int) {
	if index < 0 || index >= session.states.len {
		return
	}
	session.current = index
}

fn tab_title(path string) string {
	if path == '' {
		return 'untitled'
	}
	parts := path.split('/')
	if parts.len == 0 {
		return path
	}
	return parts[parts.len - 1]
}