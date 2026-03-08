# Ved CN PyAutoGUI Tests

这组测试用于验证当前 Ved CN 已实现的图形交互闭环，而不是替代 V 层的单元测试。

覆盖范围：

- 基础插入和保存
- `x` 删除字符与 `u` 撤销
- `Ctrl/Cmd + r` 重做
- `dd` 删除整行
- `yy` / `p` 复制粘贴整行
- `o` / `O` 在下方或上方插入新行
- 中文逐字 `w` + `dw` 删除
- `/` 搜索后删除匹配字符
- 可视选择删除与 `+y` 系统剪贴板复制
- `r` 替换当前字符
- `J` 连接当前行与下一行
- `I` / `A` 行首和行尾插入
- `gg` / `G` 跳转到文件开头和结尾
- `<` / `>` 当前行缩进和反缩进
- `0` / `$` / `^` 行首、行尾、首个非空白字符跳转
- `L` / `H` 当前屏顶部和底部跳转
- `Ctrl/Cmd + n` 自动补全
- 多标签切换
- `Cmd/Ctrl + P` 工作区文件搜索和打开
- 空标签保存失败场景
- 搜索无结果场景
- macOS 原生粘贴路径（含多行中文与 emoji）

## 依赖

```bash
python3 -m pip install pyautogui pyperclip
```

macOS 需要给运行终端或 IDE 授予：

- 辅助功能
- 屏幕录制

说明：

- 当前自动化在 macOS 上使用 `Ctrl` 作为测试修饰键，而不是 `Command`。这是因为 PyAutoGUI 对 `Command` 组合键在 gg 窗口里的修饰键传递不稳定，但应用本身同时支持 `Ctrl` 和 `Command` 快捷键。
- `ci` 已有单元测试覆盖；在 PyAutoGUI 下，`c` 之后的第二个字符键在 macOS/gg 窗口中时序不稳定，所以暂未纳入默认 GUI 套件。
- `zz` 的逻辑已实现，但在当前 PyAutoGUI + gg 窗口环境里，`z` 键的 keydown 事件不稳定，默认 GUI 套件暂不包含该场景。

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
