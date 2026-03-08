module frontend

import core
import editor
import gg
import infra
import os
import uiold

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
	marked_text    string
	emoji_font     string
	symbol_font    string
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
		emoji_font: resolve_emoji_font_path()
		symbol_font: resolve_symbol_font_path()
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
	$if macos {
		if os.getenv('VED_TEST') == '' {
			uiold.reg_ved_instance(window)
			spawn init_native_ime(window)
		}
	}
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
			window.sync_ime_focus()
			window.gg.refresh_ui()
		}
		return
	}
	if super && key == .p {
		window.open_picker()
		window.sync_ime_focus()
		window.gg.refresh_ui()
		return
	}
	if super && key == .left_bracket {
		window.session.switch_prev()
		window.message = '切换到上一个标签'
		window.ensure_cursor_visible()
		window.sync_ime_focus()
		window.gg.refresh_ui()
		return
	}
	if super && key == .right_bracket {
		window.session.switch_next()
		window.message = '切换到下一个标签'
		window.ensure_cursor_visible()
		window.sync_ime_focus()
		window.gg.refresh_ui()
		return
	}
	if super && key == .t {
		window.session.add_empty_buffer()
		window.message = '新建空标签'
		window.ensure_cursor_visible()
		window.sync_ime_focus()
		window.gg.refresh_ui()
		return
	}
	mut state := window.session.current_state_mut()
	action := state.key_down(key, mod, window.visible_line_count())
	if action.request_save {
		window.save_current_buffer()
	}
	if action.copy_to_system != '' {
		write_system_clipboard(action.copy_to_system) or {
			window.message = '复制到系统剪贴板失败: ${err.msg()}'
			window.ensure_cursor_visible()
			window.sync_ime_focus()
			window.gg.refresh_ui()
			return
		}
		window.message = '已复制到系统剪贴板'
	}
	if action.request_quit {
		exit(0)
	}
	window.ensure_cursor_visible()
	if key == .z && state.status == 'z' {
		append_test_log('center pending')
	}
	if state.status == 'CENTER' {
		append_test_log('center line=${state.buffer.cursor.line} top=${state.buffer.scroll_top} visible=${window.visible_line_count()}')
	}
	window.sync_ime_focus()
	window.gg.refresh_ui()
}

@[manualfree]
fn on_char(code u32, mut window Window) {
	if code < 32 {
		return
	}
	$if macos {
		if os.getenv('VED_TEST') == '' {
			if window.session.current_state().mode == .insert {
				return
			}
		}
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
	match event.typ {
		.resized, .resumed, .restored {
			window.sync_window_size(event.window_width, event.window_height)
		}
		.mouse_scroll {
			mut state := window.session.current_state_mut()
			if event.scroll_y < -0.2 {
				state.buffer.move_down()
			} else if event.scroll_y > 0.2 {
				state.buffer.move_up()
			}
			window.ensure_cursor_visible()
			window.gg.refresh_ui()
		}
		.mouse_down {
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
		else {}
	}
}

fn (mut window Window) sync_window_size(width int, height int) {
	mut next_width := width
	mut next_height := height
	if next_width <= 0 || next_height <= 0 {
		size := gg.window_size_real_pixels()
		if next_width <= 0 {
			next_width = size.width
		}
		if next_height <= 0 {
			next_height = size.height
		}
	}
	if next_width <= 0 || next_height <= 0 {
		return
	}
	if next_width == window.width && next_height == window.height {
		return
	}
	window.width = next_width
	window.height = next_height
	window.gg.resize(next_width, next_height)
	window.ensure_cursor_visible()
	window.sync_ime_focus()
	window.gg.refresh_ui()
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
	line_text := state.buffer.lines[state.buffer.cursor.line]
	viewport_width := window.editor_viewport_width()
	cursor_offset := window.text_width_before_column(line_text, state.buffer.cursor.column)
	mut left := state.buffer.scroll_left_px
	padding := 24
	if cursor_offset < left + padding {
		left = max_int(cursor_offset - padding, 0)
	}
	if cursor_offset > left + viewport_width - padding {
		left = max_int(cursor_offset - viewport_width + padding, 0)
	}
	if cursor_offset == 0 {
		left = 0
	}
	line_width := window.measure_text_with_fallback(expand_tabs(line_text, 4),
		text_cfg(window.theme.foreground, window.font_size))
	max_left := max_int(line_width - viewport_width + padding, 0)
	if left > max_left {
		left = max_left
	}
	state.buffer.scroll_left_px = max_int(left, 0)
}

fn (mut window Window) draw() {
	window.gg.draw_rect_filled(0, 0, window.width, window.height, window.theme.background)
	window.draw_top_bar()
	window.draw_editor_surface()
	window.draw_status_bar()
	window.draw_marked_text()
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
	text_left := gutter_width + 18
	text_width := window.editor_viewport_width()
	window.gg.draw_rect_filled(0, top, gutter_width, window.height - top - bottom, window.theme.panel)
	window.gg.draw_line(gutter_width, top, gutter_width, window.height - bottom, window.theme.border)
	window.gg.scissor_rect(text_left, top, text_width, window.height - top - bottom)
	visible := window.visible_line_count()
	start := state.buffer.scroll_top
	end := min_int(start + visible, state.buffer.line_count())
	sel_start, sel_end, has_selection := state.selection_range()
	for line_no := start; line_no < end; line_no++ {
		row := line_no - start
		y := top + row * window.line_height
		if line_no == state.buffer.cursor.line {
			window.gg.draw_rect_filled(gutter_width + 1, y, window.width - gutter_width - 1,
				window.line_height, window.theme.line_highlight)
		}
		if has_selection {
			window.draw_selection_line(line_no, y, text_left, state, sel_start, sel_end)
		}
		line_label := '${line_no + 1:4d}'
		window.gg.scissor_rect(0, top, window.width, window.height - top - bottom)
		window.gg.draw_text(12, y + 5, line_label, text_cfg(window.theme.muted, 16))
		window.gg.scissor_rect(text_left, top, text_width, window.height - top - bottom)
		content := expand_tabs(state.buffer.lines[line_no], 4)
		window.draw_text_with_fallback(text_left - state.buffer.scroll_left_px, y + 4, content,
			text_cfg(window.theme.foreground, window.font_size))
	}
	window.gg.scissor_rect(0, 0, window.width, window.height)
	window.draw_cursor(gutter_width, top, bottom)
}

fn (mut window Window) draw_selection_line(line_no int, y int, text_left int, state editor.State, sel_start core.Cursor, sel_end core.Cursor) {
	if line_no < sel_start.line || line_no > sel_end.line {
		return
	}
	line := state.buffer.lines[line_no]
	mut start_col := 0
	mut end_col := line.runes().len
	if line_no == sel_start.line {
		start_col = sel_start.column
	}
	if line_no == sel_end.line {
		end_col = sel_end.column
	}
	if end_col <= start_col {
		return
	}
	x1 := text_left + window.text_width_before_column(line, start_col) - state.buffer.scroll_left_px
	x2 := text_left + window.text_width_before_column(line, end_col) - state.buffer.scroll_left_px
	window.gg.draw_rect_filled(x1, y + 3, max_int(x2 - x1, 3), window.line_height - 6,
		window.theme.accent_soft)
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
	cursor_offset := window.text_width_before_column(line_text, state.buffer.cursor.column)
	x := gutter_width + 18 + cursor_offset - state.buffer.scroll_left_px
	y := top + (line - start) * window.line_height + 4
	if state.mode == .insert {
		$if macos {
			if os.getenv('VED_TEST') == '' {
				uiold.set_ime_position(x, y, window.line_height, window.gg.scale)
			}
		}
		window.gg.draw_rect_filled(x, y, 2, window.line_height - 8, window.theme.cursor)
		return
	}
	cursor_width := max_int(window.cursor_block_width(line_text, state.buffer.cursor.column), 2)
	window.gg.draw_line(x, y, x + cursor_width, y, window.theme.cursor)
	window.gg.draw_line(x, y + window.line_height - 8, x + cursor_width,
		y + window.line_height - 8, window.theme.cursor)
	window.gg.draw_line(x, y, x, y + window.line_height - 8, window.theme.cursor)
	window.gg.draw_line(x + cursor_width, y, x + cursor_width,
		y + window.line_height - 8, window.theme.cursor)
}

fn (mut window Window) draw_marked_text() {
	if window.marked_text == '' {
		return
	}
	state := window.session.current_state()
	if state.mode != .insert {
		return
	}
	gutter_width := window.gutter_width()
	start := state.buffer.scroll_top
	line := state.buffer.cursor.line
	if line < start || line >= start + window.visible_line_count() {
		return
	}
	line_text := state.buffer.lines[line]
	x := gutter_width + 22 + window.text_width_before_column(line_text,
		state.buffer.cursor.column) - state.buffer.scroll_left_px
	y := 52 + window.tab_bar_height + (line - start) * window.line_height + 4
	window.draw_text_with_fallback(x, y, window.marked_text,
		text_cfg(window.theme.accent, window.font_size))
	window.gg.draw_line(x, y + window.line_height - 3,
		x + window.measure_text_with_fallback(window.marked_text,
			text_cfg(window.theme.accent, window.font_size)), y + window.line_height - 3,
		window.theme.accent)
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

fn (window &Window) editor_viewport_width() int {
	gutter_width := window.gutter_width()
	return max_int(window.width - gutter_width - 26, 120)
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

struct TextSegment {
	text   string
	family string
}

fn (window &Window) draw_text_with_fallback(x int, y int, text string, cfg gg.TextCfg) {
	mut cur_x := x
	for segment in window.segment_text(text) {
		segment_cfg := gg.TextCfg{
			...cfg
			family: segment.family
		}
		window.gg.draw_text(cur_x, y, segment.text, segment_cfg)
		cur_x += window.gg.text_width(segment.text)
	}
}

fn (window &Window) measure_text_with_fallback(text string, cfg gg.TextCfg) int {
	mut width := 0
	for segment in window.segment_text(text) {
		segment_cfg := gg.TextCfg{
			...cfg
			family: segment.family
		}
		window.gg.set_text_cfg(segment_cfg)
		width += window.gg.text_width(segment.text)
	}
	window.gg.set_text_cfg(cfg)
	return width
}

fn (window &Window) segment_text(text string) []TextSegment {
	if text == '' {
		return []TextSegment{}
	}
	mut segments := []TextSegment{}
	mut current_text := ''
	mut current_family := ''
	for rune_value in text.runes() {
		family := window.family_for_rune(rune_value)
		glyph := rune_value.str()
		if current_text == '' {
			current_text = glyph
			current_family = family
			continue
		}
		if family == current_family {
			current_text += glyph
			continue
		}
		segments << TextSegment{current_text, current_family}
		current_text = glyph
		current_family = family
	}
	if current_text != '' {
		segments << TextSegment{current_text, current_family}
	}
	return segments
}

fn (window &Window) family_for_rune(r rune) string {
	if is_emoji_rune(r) && window.emoji_font != '' {
		return window.emoji_font
	}
	if is_symbol_rune(r) && window.symbol_font != '' {
		return window.symbol_font
	}
	return ''
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

fn (window &Window) text_width_before_column(text string, column int) int {
	prefix := rune_prefix(text, column)
	return window.measure_text_with_fallback(expand_tabs(prefix, 4),
		text_cfg(window.theme.foreground, window.font_size))
}

fn (window &Window) cursor_block_width(text string, column int) int {
	current := window.text_width_before_column(text, column)
	next := window.text_width_before_column(text, column + 1)
	if next > current {
		return next - current
	}
	return window.char_width
}

fn rune_prefix(text string, column int) string {
	if column <= 0 || text.len == 0 {
		return ''
	}
	runes := text.runes()
	end := min_int(column, runes.len)
	if end <= 0 {
		return ''
	}
	return runes[..end].string()
}

fn estimate_text_width(text string, size int) int {
	return text.runes().len * max_int(size / 2, 8)
}

fn resolve_font_path() string {
	paths := [
		os.join_path(os.dir(os.executable()), 'AlibabaPuHuiTi-2-55-Regular.ttf'),
		'AlibabaPuHuiTi-2-55-Regular.ttf',
		os.join_path(os.dir(os.executable()), 'RobotoMono-Regular.ttf'),
		'RobotoMono-Regular.ttf',
		'/System/Library/Fonts/Hiragino Sans GB.ttc',
		'/System/Library/Fonts/STHeiti Light.ttc',
		'/System/Library/Fonts/STHeiti Medium.ttc',
		'/System/Library/Fonts/Supplemental/Songti.ttc',
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

fn resolve_emoji_font_path() string {
	paths := [
		'/System/Library/Fonts/Apple Color Emoji.ttc',
	]
	for path in paths {
		if os.exists(path) {
			return path
		}
	}
	return ''
}

fn resolve_symbol_font_path() string {
	paths := [
		'/System/Library/Fonts/Apple Symbols.ttf',
		'/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
	]
	for path in paths {
		if os.exists(path) {
			return path
		}
	}
	return ''
}

fn is_emoji_rune(r rune) bool {
	code := u32(r)
	return (code >= 0x1f300 && code <= 0x1faff) || (code >= 0x2600 && code <= 0x27bf)
}

fn is_symbol_rune(r rune) bool {
	code := u32(r)
	if is_emoji_rune(r) {
		return true
	}
	return (code >= 0x2190 && code <= 0x21ff) || (code >= 0x2200 && code <= 0x22ff)
		|| (code >= 0x2300 && code <= 0x23ff) || (code >= 0x2460 && code <= 0x24ff)
		|| (code >= 0x25a0 && code <= 0x25ff) || (code >= 0x2b00 && code <= 0x2bff)
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