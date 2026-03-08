import argparse
import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path

import pyautogui
import pyperclip

DELAY_KEY = 0.20
DELAY_TEXT = 0.45
DELAY_START = 1.80
DELAY_SWITCH = 0.65
FOCUS_DELAY = 0.80

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / 'ved-cn'
SANDBOX = ROOT / 'tests' / 'pyautogui' / 'sandbox'
STATE_FILE = ROOT / 'tests' / 'pyautogui' / '.test_state.json'
RESULT_FILE = ROOT / 'tests' / 'pyautogui' / 'test_results.txt'
APP_LOG = ROOT / 'tests' / 'pyautogui' / 'app_test.log'

BASE_TEXT = 'line 1: alpha\nline 2: beta\nline 3: gamma\n'
FIXTURE_FILES = {
    'alpha.txt': BASE_TEXT,
    'beta.txt': 'second file\n',
    'cjk.txt': '你好 世界 again\n',
    'completion.txt': 'alphabet\nal\n',
    'indent.txt': 'word\n',
    'long.txt': ''.join(f'row {index:02d}\n' for index in range(1, 61)),
    'motion.txt': '    abc\nnext\n',
    'objects.txt': 'call(foo, bar)\n',
    'notes.txt': 'workspace note\n',
    'picker_target.txt': 'pick me\n',
    'search.txt': 'one two one\n',
}


def require_dependencies():
    missing = []
    try:
        import pyautogui  # noqa: F401
    except Exception:
        missing.append('pyautogui')
    if missing:
        print('Missing dependencies:', ', '.join(missing))
        sys.exit(1)


def load_state():
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}


def save_state(state):
    STATE_FILE.write_text(json.dumps(state, indent=2, ensure_ascii=False))


def write_result_line(line):
    with RESULT_FILE.open('a', encoding='utf-8') as handle:
        handle.write(line + '\n')


def reset_sandbox():
    SANDBOX.mkdir(parents=True, exist_ok=True)
    APP_LOG.write_text('', encoding='utf-8')
    for name, content in FIXTURE_FILES.items():
        (SANDBOX / name).write_text(content, encoding='utf-8')


def wait_until(predicate, timeout=5.0, interval=0.1):
    start = time.time()
    while time.time() - start < timeout:
        if predicate():
            return True
        time.sleep(interval)
    return False


def os_modifier_key():
    if platform.system() == 'Darwin':
        return 'ctrl'
    return 'ctrl'


class VedCnAutomator:
    def __init__(self, args):
        self.args = args
        self.process = None
        self.mod = os_modifier_key()

    def start(self):
        env = os.environ.copy()
        env['VED_TEST'] = '1'
        env['VED_CN_TEST_LOG'] = str(APP_LOG)
        cmd = [str(BIN)] + [str(arg) for arg in self.args]
        self.process = subprocess.Popen(cmd, cwd=ROOT, env=env)
        time.sleep(DELAY_START)
        if self.process.poll() is not None:
            raise RuntimeError('ved-cn process exited early')
        self.focus()

    def focus(self):
        if self.process is None:
            return
        if platform.system() == 'Darwin':
            script = f'tell application "System Events" to set frontmost of (first process whose unix id is {self.process.pid}) to true'
            subprocess.run(['osascript', '-e', script], check=False, capture_output=True)
        time.sleep(FOCUS_DELAY)

    def press(self, key, count=1, interval=DELAY_KEY):
        self.focus()
        pyautogui.press(key, presses=count, interval=interval)
        time.sleep(DELAY_KEY)

    def hotkey(self, *keys):
        self.focus()
        if len(keys) < 2:
            pyautogui.press(keys[0])
            time.sleep(DELAY_SWITCH)
            return
        modifiers = keys[:-1]
        final_key = keys[-1]
        for key in modifiers:
            pyautogui.keyDown(key)
            time.sleep(0.10)
        pyautogui.press(final_key)
        time.sleep(0.10)
        for key in reversed(modifiers):
            pyautogui.keyUp(key)
        time.sleep(DELAY_SWITCH)

    def native_paste(self):
        self.focus()
        paste_mod = 'command' if platform.system() == 'Darwin' else 'ctrl'
        for key in [paste_mod]:
            pyautogui.keyDown(key)
            time.sleep(0.10)
        pyautogui.press('v')
        time.sleep(0.10)
        pyautogui.keyUp(paste_mod)
        time.sleep(DELAY_SWITCH)

    def write(self, text):
        self.focus()
        pyautogui.write(text, interval=0.06)
        time.sleep(DELAY_TEXT)

    def save(self):
        self.press('esc')
        self.hotkey(self.mod, 's')
        time.sleep(DELAY_SWITCH)

    def quit(self):
        if self.process is None:
            return
        if self.process.poll() is None:
            for _ in range(2):
                self.press('esc')
            self.hotkey(self.mod, 'q')
            if not wait_until(lambda: self.process.poll() is not None, timeout=3.0):
                self.process.terminate()
                self.process.wait(timeout=3)


def read_file(name):
    return (SANDBOX / name).read_text(encoding='utf-8')


def read_app_log():
    if not APP_LOG.exists():
        return ''
    return APP_LOG.read_text(encoding='utf-8')


def test_insert_and_save():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.press('i')
        app.write('START ')
        app.save()
        content = read_file('alpha.txt')
        return content.startswith('START line 1: alpha')
    finally:
        app.quit()


def test_delete_char_and_undo():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.press('x')
        app.press('u')
        app.save()
        return read_file('alpha.txt') == BASE_TEXT
    finally:
        app.quit()


def test_redo_shortcut():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.press('x')
        app.press('u')
        app.hotkey(app.mod, 'r')
        app.save()
        expected = 'ine 1: alpha\nline 2: beta\nline 3: gamma\n'
        return read_file('alpha.txt') == expected
    finally:
        app.quit()


def test_delete_line():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.press('d')
        app.press('d')
        app.save()
        content = read_file('alpha.txt')
        return 'line 1: alpha' not in content and content.startswith('line 2: beta')
    finally:
        app.quit()


def test_yank_and_paste_line():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.press('y')
        app.press('y')
        app.press('p')
        app.save()
        lines = [line for line in read_file('alpha.txt').splitlines() if line]
        return len(lines) >= 2 and lines[0] == lines[1] == 'line 1: alpha'
    finally:
        app.quit()


def test_open_line_below_without_inserting_trigger_key():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.press('o')
        app.write('below')
        app.save()
        lines = read_file('alpha.txt').splitlines()
        return len(lines) >= 2 and lines[1] == 'below'
    finally:
        app.quit()


def test_open_line_above_without_inserting_trigger_key():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.hotkey('shift', 'o')
        app.write('above')
        app.save()
        lines = read_file('alpha.txt').splitlines()
        return len(lines) >= 2 and lines[0] == 'above' and lines[1] == 'line 1: alpha'
    finally:
        app.quit()


def test_tab_switching_between_files():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt', SANDBOX / 'beta.txt'])
    try:
        app.start()
        app.press('i')
        app.write('A-')
        app.save()
        app.hotkey(app.mod, ']')
        app.press('i')
        app.write('B-')
        app.save()
        alpha_content = read_file('alpha.txt')
        beta_content = read_file('beta.txt')
        return alpha_content.startswith('A-line 1: alpha') and beta_content.startswith('B-second file')
    finally:
        app.quit()


def test_picker_open_file():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX])
    try:
        app.start()
        app.hotkey(app.mod, 'p')
        app.write('target')
        app.press('enter')
        time.sleep(1.0)
        app.press('i')
        app.write('OPENED ')
        app.save()
        content = read_file('picker_target.txt')
        return content.startswith('OPENED pick me')
    finally:
        app.quit()


def test_save_empty_tab_is_blocked():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX])
    try:
        app.start()
        app.hotkey(app.mod, 't')
        app.hotkey(app.mod, 's')
        time.sleep(0.8)
        log = read_app_log()
        return 'save blocked: empty path' in log
    finally:
        app.quit()


def test_picker_no_results_does_not_open_file():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX])
    try:
        app.start()
        app.hotkey(app.mod, 'p')
        app.write('zzznomatch')
        app.press('enter')
        time.sleep(0.8)
        log = read_app_log()
        files_unchanged = all(read_file(name) == content for name, content in FIXTURE_FILES.items())
        return 'picker selection blocked: no results query=zzznomatch' in log and files_unchanged
    finally:
        app.quit()


def test_native_paste_multiline_text():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        pyperclip.copy('中文第一行\n第二行😂')
        app.start()
        app.press('i')
        app.native_paste()
        app.save()
        content = read_file('alpha.txt')
        return content.startswith('中文第一行\n第二行😂line 1: alpha')
    finally:
        app.quit()


def test_delete_word_with_cjk_motion():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'cjk.txt'])
    try:
        app.start()
        app.press('w')
        app.press('d')
        app.press('w')
        app.save()
        return read_file('cjk.txt') == '你世界 again\n'
    finally:
        app.quit()


def scenario_change_inside_pair():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'objects.txt'])
    try:
        app.start()
        app.press('right', count=6)
        app.press('c')
        app.press('i')
        app.write('baz')
        app.press('esc')
        app.save()
        return read_file('objects.txt') == 'call(baz)\n'
    finally:
        app.quit()


def test_search_and_delete_match():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'search.txt'])
    try:
        app.start()
        app.press('/')
        app.write('one')
        app.press('enter')
        app.press('x')
        app.save()
        return read_file('search.txt') == 'one two ne\n'
    finally:
        app.quit()


def test_visual_delete_selection():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'search.txt'])
    try:
        app.start()
        app.press('v')
        app.press('right', count=3)
        app.press('d')
        app.save()
        return read_file('search.txt') == ' two one\n'
    finally:
        app.quit()


def test_system_clipboard_yank_current_line():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'search.txt'])
    try:
        pyperclip.copy('')
        app.start()
        app.hotkey('shift', '=')
        app.press('y')
        time.sleep(0.5)
        return pyperclip.paste() == 'one two one'
    finally:
        app.quit()


def test_replace_char_command():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.press('r')
        time.sleep(0.25)
        app.press('z')
        time.sleep(0.25)
        app.save()
        return read_file('alpha.txt') == 'zine 1: alpha\nline 2: beta\nline 3: gamma\n'
    finally:
        app.quit()


def test_join_lines_command():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.hotkey('shift', 'j')
        app.save()
        return read_file('alpha.txt') == 'line 1: alpha line 2: beta\nline 3: gamma\n'
    finally:
        app.quit()


def test_insert_line_start_and_append_end():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.hotkey('shift', 'i')
        app.write('HEAD ')
        app.press('esc')
        app.hotkey('shift', 'a')
        app.write(' TAIL')
        app.save()
        first_line = read_file('alpha.txt').splitlines()[0]
        return first_line == 'HEAD line 1: alpha TAIL'
    finally:
        app.quit()


def test_goto_file_start_and_end():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'alpha.txt'])
    try:
        app.start()
        app.hotkey('shift', 'g')
        app.hotkey('shift', 'i')
        app.write('LAST ')
        app.press('esc')
        app.press('g')
        app.press('g')
        app.hotkey('shift', 'i')
        app.write('FIRST ')
        app.save()
        lines = read_file('alpha.txt').splitlines()
        return lines[0] == 'FIRST line 1: alpha' and lines[-1] == 'LAST '
    finally:
        app.quit()


def scenario_center_current_line_with_zz():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'long.txt'])
    try:
        app.start()
        app.hotkey(app.mod, 'f')
        app.hotkey(app.mod, 'f')
        app.press('z')
        app.press('z')
        time.sleep(0.8)
        center_lines = [line for line in read_app_log().splitlines() if line.startswith('center line=')]
        if not center_lines:
            return False
        latest = center_lines[-1]
        parts = dict(item.split('=') for item in latest.split())
        line = int(parts['line'])
        top = int(parts['top'])
        visible = int(parts['visible'])
        return abs((line - top) - (visible // 2)) <= 1
    finally:
        app.quit()


def test_indent_and_outdent_current_line():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'indent.txt'])
    try:
        app.start()
        app.hotkey('shift', '.')
        app.hotkey('shift', ',')
        app.hotkey('shift', '.')
        app.save()
        return read_file('indent.txt') == '    word\n'
    finally:
        app.quit()


def test_zero_dollar_caret_motion_commands():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'motion.txt'])
    try:
        app.start()
        app.hotkey('shift', '4')
        app.press('x')
        app.press('u')
        app.hotkey('shift', '6')
        app.press('x')
        app.press('u')
        app.press('0')
        app.press('x')
        app.hotkey('shift', '4')
        app.press('x')
        app.save()
        return read_file('motion.txt') == '   abcnext\n'
    finally:
        app.quit()


def test_screen_top_and_bottom_motion():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'long.txt'])
    try:
        app.start()
        app.hotkey(app.mod, 'f')
        app.hotkey(app.mod, 'f')
        app.hotkey('shift', 'l')
        app.hotkey('shift', 'i')
        app.write('TOP ')
        app.press('esc')
        app.hotkey('shift', 'h')
        app.hotkey('shift', 'i')
        app.write('BOTTOM ')
        app.save()
        lines = read_file('long.txt').splitlines()
        top_index = next((i for i, line in enumerate(lines) if line.startswith('TOP ')), -1)
        bottom_index = next((i for i, line in enumerate(lines) if line.startswith('BOTTOM ')), -1)
        return top_index >= 0 and bottom_index >= 0 and top_index < bottom_index
    finally:
        app.quit()


def test_ctrl_n_completion():
    reset_sandbox()
    app = VedCnAutomator([SANDBOX / 'completion.txt'])
    try:
        app.start()
        app.press('down')
        app.press('end')
        app.press('i')
        app.hotkey(app.mod, 'n')
        app.save()
        return read_file('completion.txt') == 'alphabet\nalphabet\n'
    finally:
        app.quit()


def get_tests():
    return [name for name in globals() if name.startswith('test_') and callable(globals()[name])]


def build_binary():
    subprocess.run(['./build.sh'], cwd=ROOT, check=True)


def main():
    require_dependencies()

    parser = argparse.ArgumentParser(description='Ved CN PyAutoGUI test runner')
    parser.add_argument('--build', action='store_true', help='Build ved-cn before running tests')
    parser.add_argument('--list', action='store_true', help='List available tests')
    parser.add_argument('--skip-passed', action='store_true', help='Skip tests that passed last run')
    parser.add_argument('--names', nargs='+', help='Run only selected tests')
    args = parser.parse_args()

    if args.build:
        build_binary()

    all_tests = get_tests()
    if args.list:
        for name in all_tests:
            print(name)
        return 0

    state = load_state()
    last_results = state.get('results', {})
    if args.names:
        to_run = [name for name in args.names if name in all_tests]
    elif args.skip_passed:
        to_run = [name for name in all_tests if last_results.get(name) is not True]
    else:
        to_run = all_tests

    RESULT_FILE.write_text('', encoding='utf-8')

    current_results = dict(last_results)
    passed = 0
    failed = 0
    for name in to_run:
        print(f'Running {name}...')
        success = False
        try:
            success = bool(globals()[name]())
        except KeyboardInterrupt:
            raise
        except Exception as err:
            print(f'{name} raised exception: {err}')
            success = False
        current_results[name] = success
        if success:
            passed += 1
            write_result_line(f'PASS {name}')
            print(f'PASS {name}')
        else:
            failed += 1
            write_result_line(f'FAIL {name}')
            print(f'FAIL {name}')

    state['results'] = current_results
    state['last_run_time'] = time.strftime('%Y-%m-%d %H:%M:%S')
    save_state(state)

    print(f'Summary: {passed} passed, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())