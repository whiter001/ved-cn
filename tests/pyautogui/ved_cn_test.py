import argparse
import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path

import pyautogui

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
    'notes.txt': 'workspace note\n',
    'picker_target.txt': 'pick me\n',
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