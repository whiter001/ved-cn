# Ved CN PyAutoGUI Tests

这组测试用于验证当前 Ved CN 已实现的图形交互闭环，而不是替代 V 层的单元测试。

覆盖范围：

- 基础插入和保存
- `x` 删除字符与 `u` 撤销
- `dd` 删除整行
- `yy` / `p` 复制粘贴整行
- 多标签切换
- `Cmd/Ctrl + P` 工作区文件搜索和打开

## 依赖

```bash
python3 -m pip install pyautogui pyperclip
```

macOS 需要给运行终端或 IDE 授予：

- 辅助功能
- 屏幕录制

说明：

- 当前自动化在 macOS 上使用 `Ctrl` 作为测试修饰键，而不是 `Command`。这是因为 PyAutoGUI 对 `Command` 组合键在 gg 窗口里的修饰键传递不稳定，但应用本身同时支持 `Ctrl` 和 `Command` 快捷键。

## 运行

构建后运行全部用例：

```bash
python3 tests/pyautogui/ved_cn_test.py --build
```

只运行指定用例：

```bash
python3 tests/pyautogui/ved_cn_test.py --names test_insert_and_save test_picker_open_file
```

列出用例：

```bash
python3 tests/pyautogui/ved_cn_test.py --list
```

跳过上次已通过的测试：

```bash
python3 tests/pyautogui/ved_cn_test.py --skip-passed
```

## 说明

测试会在 [tests/pyautogui/sandbox](tests/pyautogui/sandbox) 下创建和修改文件。
运行期间会真实抢占键盘输入，请不要同时操作鼠标和键盘。
