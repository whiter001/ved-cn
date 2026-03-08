module frontend

import core
import editor
import gg
import infra
import os

struct Theme {
	background       gg.Color
	panel            gg.Color
	panel_alt        gg.Color
	line_highlight   gg.Color
	foreground       gg.Color
	muted            gg.Color
	accent           gg.Color
	accent_soft      gg.Color
	border           gg.Color
	cursor           gg.Color
	status_ok        gg.Color
	status_attention gg.Color
}

@[heap]
pub struct Window {
pub mut:
	gg             &gg.Context = unsafe { nil }
	session        editor.Session
	store          infra.FileStore
	workspace      infra.WorkspaceIndex
	workspace_root string
	width          int = 1280
	height         int = 820
	font_size      int = 20
	char_width     int = 11
	line_height    int = 28
	message        string
	tab_bar_height int = 38
	tab_rects      []TabRect
	picker         FilePicker
	skip_next_text string
	theme          Theme = default_theme()
}

struct TabRect {
	x     int
	y     int
	w     int
	h     int
	index int
}

struct FilePicker {
mut:
	active   bool
	query    string
	selected int
	results  []string
}

pub fn new_window(buffers []core.Buffer, store infra.FileStore, workspace_root string) Window {
	workspace := infra.build_workspace_index(workspace_root) or { infra.WorkspaceIndex{} }
	append_test_log('workspace root=${workspace_root} files=${workspace.files.len}')
	return Window{
		session: editor.new_session(buffers, workspace_root)
		store: store
		workspace: workspace
		workspace_root: workspace_root
	}
}

pub fn (mut window Window) run() {
	window.gg = gg.new_context(
		width: window.width
		height: window.height
		window_title: 'Ved CN'
		create_window: true
		user_data: window
		bg_color: window.theme.background
		frame_fn: frame
		on_event: window.on_event
		keydown_fn: on_key_down
		char_fn: on_char
		font_path: resolve_font_path()
		ui_mode: true
	)
	window.gg.run()
}

fn frame(mut window Window) {
	window.gg.begin()
	window.draw()
	window.gg.end()
}

fn on_key_down(key gg.KeyCode, mod gg.Modifier, mut window Window) {
	super := mod.has(.super) || mod.has(.ctrl)
	if super {
		window.skip_next_text = shortcut_text(key)
	}
	if window.picker.active {
		if window.handle_picker_key(key) {
			window.gg.refresh_ui()
		}
		return
	}
	if super && key == .p {
		window.open_picker()
		window.gg.refresh_ui()
		return
	}
	if super && key == .left_bracket {
		window.session.switch_prev()
		window.message = '切换到上一个标签'
		window.ensure_cursor_visible()
		window.gg.refresh_ui()
		return
	}
	if super && key == .right_bracket {
		window.session.switch_next()
		window.message = '切换到下一个标签'
		window.ensure_cursor_visible()
		window.gg.refresh_ui()
		return
	}
	if super && key == .t {
		window.session.add_empty_buffer()
		window.message = '新建空标签'
		window.ensure_cursor_visible()
		window.gg.refresh_ui()
		return
	}
	mut state := window.session.current_state_mut()
	action := state.key_down(key, mod)
	if action.request_save {
		window.save_current_buffer()
	}
	if action.request_quit {
		exit(0)
	}
	window.ensure_cursor_visible()
	window.gg.refresh_ui()
}

@[manualfree]
fn on_char(code u32, mut window Window) {
	if code < 32 {
		return
	}
	mut buf := [5]u8{}
	text := unsafe { utf32_to_str_no_malloc(code, mut &buf[0]) }
	if window.skip_next_text != '' && text == window.skip_next_text {
		window.skip_next_text = ''
		return
	}
	window.skip_next_text = ''
	if window.picker.active {
		window.handle_picker_text(text)
		window.gg.refresh_ui()
		return
	}
	mut state := window.session.current_state_mut()
	state.handle_text(text)
	window.ensure_cursor_visible()
	window.gg.refresh_ui()
}

pub fn (mut window Window) on_event(event &gg.Event) {
	if event.typ == .mouse_scroll {
		mut state := window.session.current_state_mut()
		if event.scroll_y < -0.2 {
			state.buffer.move_down()
		} else if event.scroll_y > 0.2 {
			state.buffer.move_up()
		}
		window.ensure_cursor_visible()
		window.gg.refresh_ui()
	}
	if event.typ == .mouse_down {
		for rect in window.tab_rects {
			if point_in_rect(event.mouse_x, event.mouse_y, rect) {
				window.session.current = rect.index
				window.message = '切换到标签 ${rect.index + 1}'
				window.ensure_cursor_visible()
				window.gg.refresh_ui()
				return
			}
		}
	}
}

fn (mut window Window) save_current_buffer() {
	mut state := window.session.current_state_mut()
	if state.buffer.path == '' {
		append_test_log('save blocked: empty path')
		window.message = '当前缓冲区没有路径，无法保存。请以文件路径参数启动。'
		return
	}
	window.store.save(state.buffer.path, state.buffer.text()) or {
		append_test_log('save failed path=${state.buffer.path} err=${err.msg()}')
		window.message = '保存失败: ${err.msg()}'
		return
	}
	state.buffer.dirty = false
	append_test_log('saved path=${state.buffer.path}')
	window.message = '已保存 ${state.buffer.path}'
	state.status = 'SAVED'
}

fn (mut window Window) ensure_cursor_visible() {
	visible := window.visible_line_count()
	mut state := window.session.current_state_mut()
	mut top := state.buffer.scroll_top
	if state.buffer.cursor.line < top {
		top = state.buffer.cursor.line
	}
	if state.buffer.cursor.line >= top + visible {
		top = state.buffer.cursor.line - visible + 1
	}
	state.buffer.scroll_top = max_int(top, 0)
}

fn (mut window Window) draw() {
	window.gg.draw_rect_filled(0, 0, window.width, window.height, window.theme.background)
	window.draw_top_bar()
	window.draw_editor_surface()
	window.draw_status_bar()
	if window.picker.active {
		window.draw_picker()
	}
}

fn (mut window Window) draw_top_bar() {
	current_state := window.session.current_state()
	window.gg.draw_rect_filled(0, 0, window.width, 52 + window.tab_bar_height, window.theme.panel)
	window.gg.draw_line(0, 52 + window.tab_bar_height, window.width, 52 + window.tab_bar_height,
		window.theme.border)
	window.gg.draw_text(20, 14, 'Ved CN', text_cfg(window.theme.foreground, 24))
	window.gg.draw_text(150, 18, display_path(current_state.buffer.path), text_cfg(window.theme.muted, 16))
	mode_color := if current_state.mode == .insert { window.theme.accent } else { window.theme.foreground }
	window.gg.draw_rect_filled(window.width - 170, 12, 130, 28, window.theme.panel_alt)
	window.gg.draw_text(window.width - 145, 18, current_state.mode_label(), text_cfg(mode_color, 16))
	if window.workspace_root != '' {
		workspace_text := 'Workspace: ' + window.workspace_root
		workspace_x := window.width - estimate_text_width(workspace_text, 14) - 200
		window.gg.draw_text(workspace_x, 18, workspace_text, text_cfg(window.theme.muted, 14))
	}
	window.draw_tab_bar()
}

fn (mut window Window) draw_editor_surface() {
	state := window.session.current_state()
	top := 52 + window.tab_bar_height
	bottom := 42
	gutter_width := window.gutter_width()
	window.gg.draw_rect_filled(0, top, gutter_width, window.height - top - bottom, window.theme.panel)
	window.gg.draw_line(gutter_width, top, gutter_width, window.height - bottom, window.theme.border)
	visible := window.visible_line_count()
	start := state.buffer.scroll_top
	end := min_int(start + visible, state.buffer.line_count())
	for line_no := start; line_no < end; line_no++ {
		row := line_no - start
		y := top + row * window.line_height
		if line_no == state.buffer.cursor.line {
			window.gg.draw_rect_filled(gutter_width + 1, y, window.width - gutter_width - 1,
				window.line_height, window.theme.line_highlight)
		}
		line_label := '${line_no + 1:4d}'
		window.gg.draw_text(12, y + 5, line_label, text_cfg(window.theme.muted, 16))
		content := expand_tabs(state.buffer.lines[line_no], 4)
		window.gg.draw_text(gutter_width + 18, y + 4, content, text_cfg(window.theme.foreground,
			window.font_size))
	}
	window.draw_cursor(gutter_width, top, bottom)
}

fn (mut window Window) draw_cursor(gutter_width int, top int, bottom int) {
	state := window.session.current_state()
	visible := window.visible_line_count()
	start := state.buffer.scroll_top
	line := state.buffer.cursor.line
	if line < start || line >= start + visible {
		return
	}
	line_text := state.buffer.lines[line]
	visual_col := visual_column(line_text, state.buffer.cursor.column, 4)
	x := gutter_width + 18 + visual_col * window.char_width
	y := top + (line - start) * window.line_height + 4
	if state.mode == .insert {
		window.gg.draw_rect_filled(x, y, 2, window.line_height - 8, window.theme.cursor)
		return
	}
	window.gg.draw_line(x, y, x + window.char_width, y, window.theme.cursor)
	window.gg.draw_line(x, y + window.line_height - 8, x + window.char_width,
		y + window.line_height - 8, window.theme.cursor)
	window.gg.draw_line(x, y, x, y + window.line_height - 8, window.theme.cursor)
	window.gg.draw_line(x + window.char_width, y, x + window.char_width,
		y + window.line_height - 8, window.theme.cursor)
}

fn (mut window Window) draw_status_bar() {
	state := window.session.current_state()
	y := window.height - 42
	window.gg.draw_rect_filled(0, y, window.width, 42, window.theme.panel)
	window.gg.draw_line(0, y, window.width, y, window.theme.border)
	left := '${state.status}  Ln ${state.buffer.cursor.line + 1}, Col ${state.buffer.cursor.column + 1}  Tab ${window.session.current_index() + 1}/${window.session.tab_count()}'
	window.gg.draw_text(20, y + 11, left, text_cfg(window.theme.foreground, 16))
	right_color := if window.message == '' { window.theme.status_ok } else { window.theme.status_attention }
	right_text := if window.message == '' { keyboard_hint() } else { window.message }
	right_x := window.width - estimate_text_width(right_text, 16) - 20
	window.gg.draw_text(right_x, y + 11, right_text, text_cfg(right_color, 16))
}

fn (mut window Window) open_picker() {
	window.picker.active = true
	window.picker.query = ''
	window.picker.selected = 0
	window.refresh_picker_results()
	append_test_log('picker opened results=${window.picker.results.len}')
	window.message = '打开文件搜索'
}

fn (mut window Window) close_picker() {
	window.picker.active = false
	window.picker.query = ''
	window.picker.selected = 0
	window.picker.results = []string{}
}

fn (mut window Window) handle_picker_text(text string) {
	window.picker.query += text
	window.picker.selected = 0
	window.refresh_picker_results()
	append_test_log('picker query=${window.picker.query} results=${window.picker.results.len}')
}

fn (mut window Window) handle_picker_key(key gg.KeyCode) bool {
	match key {
		.escape {
			window.close_picker()
			window.message = '关闭文件搜索'
			return true
		}
		.backspace {
			if window.picker.query.len > 0 {
				window.picker.query = window.picker.query[..window.picker.query.len - 1]
				window.refresh_picker_results()
			}
			return true
		}
		.up {
			if window.picker.selected > 0 {
				window.picker.selected--
			}
			return true
		}
		.down {
			if window.picker.selected < window.picker.results.len - 1 {
				window.picker.selected++
			}
			return true
		}
		.enter {
			window.open_picker_selection()
			return true
		}
		else {
			return false
		}
	}
}

fn (mut window Window) refresh_picker_results() {
	window.picker.results = infra.filter_paths(window.workspace.files, window.picker.query, 12)
	if window.picker.selected >= window.picker.results.len {
		window.picker.selected = max_int(window.picker.results.len - 1, 0)
	}
}

fn (mut window Window) open_picker_selection() {
	if window.picker.results.len == 0 {
		append_test_log('picker selection blocked: no results query=${window.picker.query}')
		window.message = '没有匹配文件'
		return
	}
	rel_path := window.picker.results[window.picker.selected]
	full_path := os.join_path(window.workspace.root, rel_path)
	append_test_log('picker open rel=${rel_path} full=${full_path}')
	window.open_path_in_tab(full_path)
	window.close_picker()
	window.ensure_cursor_visible()
	window.message = '已打开 ${rel_path}'
}

fn (mut window Window) open_path_in_tab(path string) {
	existing := window.session.index_of_path(path)
	if existing >= 0 {
		append_test_log('switch existing tab path=${path}')
		window.session.switch_to(existing)
		return
	}
	buffer := core.new_buffer(path, window.store.load(path) or { '' })
	mut current := window.session.current_state_mut()
	if current.buffer.path == '' && current.buffer.text() == '' && !current.buffer.dirty {
		current.buffer = buffer
		current.status = 'OPEN'
		current.mode = .normal
		append_test_log('reused empty tab path=${path}')
		return
	}
	append_test_log('added new tab path=${path}')
	window.session.add_buffer(buffer)
}

fn (mut window Window) draw_picker() {
	overlay_color := gg.rgba(40, 32, 24, 140)
	window.gg.draw_rect_filled(0, 0, window.width, window.height, overlay_color)
	box_width := 720
	box_x := (window.width - box_width) / 2
	box_y := 110
	window.gg.draw_rect_filled(box_x, box_y, box_width, 360, window.theme.panel)
	window.gg.draw_line(box_x, box_y, box_x + box_width, box_y, window.theme.accent)
	window.gg.draw_text(box_x + 20, box_y + 18, 'Open File', text_cfg(window.theme.foreground, 22))
	query_text := if window.picker.query == '' { '输入以过滤工作区文件...' } else { window.picker.query }
	query_color := if window.picker.query == '' { window.theme.muted } else { window.theme.foreground }
	window.gg.draw_rect_filled(box_x + 18, box_y + 48, box_width - 36, 42, window.theme.background)
	window.gg.draw_text(box_x + 28, box_y + 60, query_text, text_cfg(query_color, 18))
	mut row_y := box_y + 108
	for index, path in window.picker.results {
		row_color := if index == window.picker.selected { window.theme.line_highlight } else { window.theme.panel }
		window.gg.draw_rect_filled(box_x + 18, row_y - 4, box_width - 36, 30, row_color)
		window.gg.draw_text(box_x + 28, row_y, path, text_cfg(window.theme.foreground, 16))
		row_y += 30
	}
	if window.picker.results.len == 0 {
		window.gg.draw_text(box_x + 28, row_y, '没有匹配结果', text_cfg(window.theme.muted, 16))
	}
}

fn (window &Window) visible_line_count() int {
	height := window.height - 52 - window.tab_bar_height - 42
	if height <= 0 {
		return 1
	}
	return max_int(height / window.line_height, 1)
}

fn (window &Window) gutter_width() int {
	state := window.session.current_state()
	line_count_text := '${state.buffer.line_count()}'
	return estimate_text_width(line_count_text, 16) + 36
}

fn (mut window Window) draw_tab_bar() {
	window.tab_rects = []TabRect{}
	mut x := 16
	y := 52 + 5
	for index, title in window.session.tab_titles() {
		width := estimate_text_width(title, 14) + 28
		color := if index == window.session.current_index() {
			window.theme.panel_alt
		} else {
			window.theme.accent_soft
		}
		window.gg.draw_rect_filled(x, y, width, 28, color)
		window.gg.draw_line(x, y + 28, x + width, y + 28, window.theme.border)
		window.gg.draw_text(x + 14, y + 7, title, text_cfg(window.theme.foreground, 14))
		window.tab_rects << TabRect{x, y, width, 28, index}
		x += width + 10
		if x > window.width - 220 {
			break
		}
	}
}

fn default_theme() Theme {
	return Theme{
		background: gg.rgb(244, 238, 229)
		panel: gg.rgb(228, 220, 208)
		panel_alt: gg.rgb(212, 199, 180)
		line_highlight: gg.rgb(255, 247, 220)
		foreground: gg.rgb(52, 43, 32)
		muted: gg.rgb(120, 105, 88)
		accent: gg.rgb(183, 82, 48)
		accent_soft: gg.rgb(228, 177, 154)
		border: gg.rgb(187, 171, 150)
		cursor: gg.rgb(32, 116, 150)
		status_ok: gg.rgb(77, 118, 89)
		status_attention: gg.rgb(183, 82, 48)
	}
}

fn text_cfg(color gg.Color, size int) gg.TextCfg {
	return gg.TextCfg{
		size: size
		color: color
		align: gg.align_left
	}
}

fn display_path(path string) string {
	if path == '' {
		return '[No Name]'
	}
	home := os.home_dir()
	if path.starts_with(home) {
		return '~' + path[home.len..]
	}
	return path
}

fn keyboard_hint() string {
	return 'Cmd/Ctrl+P 打开文件  Cmd/Ctrl+[ 或 ] 切换标签  Cmd/Ctrl+T 新标签'
}

fn expand_tabs(text string, tab_size int) string {
	return text.replace_each(['\t', ' '.repeat(tab_size)])
}

fn visual_column(text string, column int, tab_size int) int {
	mut visual := 0
	mut index := 0
	for rune_value in text.runes() {
		if index >= column {
			break
		}
		if rune_value == `\t` {
			visual += tab_size
		} else {
			visual++
		}
		index++
	}
	return visual
}

fn estimate_text_width(text string, size int) int {
	return text.runes().len * max_int(size / 2, 8)
}

fn resolve_font_path() string {
	paths := [
		'RobotoMono-Regular.ttf',
		'/System/Library/Fonts/Supplemental/Courier New.ttf',
		'/System/Library/Fonts/Supplemental/Andale Mono.ttf',
		'/System/Library/Fonts/Menlo.ttc',
	]
	for path in paths {
		if os.exists(path) {
			append_test_log('font path=${path}')
			return path
		}
	}
	append_test_log('font path=<empty>')
	return ''
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

fn point_in_rect(x f32, y f32, rect TabRect) bool {
	return int(x) >= rect.x && int(x) <= rect.x + rect.w && int(y) >= rect.y
		&& int(y) <= rect.y + rect.h
}

fn shortcut_text(key gg.KeyCode) string {
	return match key {
		.s { 's' }
		.q { 'q' }
		.r { 'r' }
		.p { 'p' }
		.t { 't' }
		else { '' }
	}
}

fn append_test_log(line string) {
	path := os.getenv('VED_CN_TEST_LOG')
	if path == '' {
		return
	}
	mut existing := ''
	if os.exists(path) {
		existing = os.read_file(path) or { '' }
	}
	os.write_file(path, existing + line + '\n') or {}
}