# Ved CN

Ved CN 是对参考项目 Ved 的一次重新实现，目标不是复制单文件巨型状态机，而是在 V 里建立一个更易扩展、更易测试的编辑器架构。

当前版本提供第一阶段可运行能力：

- 基于 gg 的原生图形窗口
- 打开单个文件或以目录作为工作区启动
- 支持多文件启动和顶部标签切换
- 支持工作区文件索引与 Ctrl/Cmd+P 快速打开
- Normal / Insert 两种模式
- 基础 Vim 风格移动与编辑：h j k l、i、a、o / O、x、dd、yy、p、u、Ctrl/Cmd+r
- Cmd/Ctrl+s 保存，Cmd/Ctrl+q 退出
- Cmd/Ctrl+[ 和 Cmd/Ctrl+] 切换标签，Cmd/Ctrl+t 新建空标签
- Cmd/Ctrl+p 打开工作区文件搜索
- 行级撤销 / 重做栈
- 核心缓冲区单元测试

## 为什么重写

参考项目功能很多，但核心问题也很明显：

- 全局状态过大，UI、编辑逻辑、文件系统、外部命令高度耦合
- 输入处理直接改主状态，难以测试和替换交互后端
- 新功能容易继续堆在单个入口对象上，演进成本越来越高

这一版先把架构边界搭稳，再逐步补搜索、语法高亮、工作区文件树、多缓冲区等功能。

## 目录结构

- app: 启动装配与参数解析
- core: 纯编辑缓冲区模型与撤销重做
- editor: 模式状态机与键盘命令解释
- infra: 文件读写等基础设施
- frontend: gg 图形前端与渲染
- docs: 架构说明

## 运行

```bash
./build.sh
./ved-cn
./ved-cn path/to/file.txt
./ved-cn file1.txt file2.txt
./ved-cn path/to/workspace
```

也可以直接：

```bash
v run .
```

## 测试

```bash
v test .
```

图形交互测试：

```bash
python3 tests/pyautogui/ved_cn_test.py --build
```

## 当前键位

- Normal 模式: h j k l, i, a, o, O, x, dd, yy, p, u
- Insert 模式: 输入文本、Enter、Backspace、方向键、Tab、Esc
- 标签相关: Cmd/Ctrl+[, Cmd/Ctrl+], Cmd/Ctrl+t
- 文件搜索: Cmd/Ctrl+p，方向键选择，Enter 打开，Esc 关闭
- 通用快捷键: Cmd/Ctrl+s, Cmd/Ctrl+q, Ctrl/Cmd+r

## 下一步

建议的后续迭代顺序：

1. 多缓冲区与标签管理
2. 文件搜索与工作区索引
3. 语法高亮管线
4. 命令面板与外部任务执行
5. 更完整的 Vim 操作集
