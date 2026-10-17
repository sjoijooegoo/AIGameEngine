---
name: aigameengine-dev
description: 在 AIGameEngine 仓库通过本地脚本开发和调试 Godot 游戏、修复工具链、检查资产与运行回归。适用于本项目的玩法迭代、工具故障、截图观察和构建验证。
---

# AIGameEngine 开发

使用仓库脚本直接工作，不依赖游戏 MCP 服务。Skill 负责选择工作流程，实际工具逻辑只维护在 `engine`，不要在 Skill 中复制实现或创建第二套桥。

从当前目录向上查找同时包含 `workspace.json` 和 `engine/run.py` 的仓库根目录。以下命令在根目录运行；Windows 优先使用 `.venv/Scripts/python.exe`，示例中的 `python` 表示该解释器。缺少环境时运行 `engine/tools/setup.ps1`。

## 定位工作

先读根目录 `AGENTS.md`，然后运行 `python engine/run.py project`，按用户要求选择任务。工具链代码在 `engine/core`、`engine/tools`、`engine/godot`；lab/probe 在 `engine/sandbox/runtime`；正式银行预留在 `game/runtime`，尚无工程时不能用试验场替代。

项目选择来自 `workspace.json`：默认 sandbox。选择其他工程用 `python engine/run.py --project <id> ...`；不通过改全局客户端配置切换项目。

## 观察与真实操作

```powershell
python engine/run.py lab start
# 将 start 返回的真实 session 路径赋给 $session；仅测逻辑时可在 start 后加 --headless。
python engine/run.py lab call describe --session $session
python engine/run.py lab call state --session $session
python engine/run.py lab call act --session $session --args '{"keys":["W"],"frames":30}'
python engine/run.py lab call capture --session $session --args '{"name":"after_walk"}'
python engine/run.py lab call quit --session $session
```

复杂参数使用 `--args-file`，避免 PowerShell 引号损坏。按返回路径实际查看 PNG；动态行为查看 sequence 的帧或联系表。会话命令串行调用，输入通过 act/click 进入正常处理器；reset 仅建立起点。超时后保留证据并重启会话，不重复发送有副作用的请求。

## 修复工具与验证改动

脚本错误从异常、调用日志和关联会话追踪到实现文件，直接修改实现后重新运行具体命令。修改共享 GDScript 后先执行 `python engine/run.py sync`，再执行 `python engine/run.py lab import`。同步拒绝被手改的部署副本；先保留并核对差异，修复 `engine/godot` 的维护源，不强制覆盖。

按改动选择检查：

- 工具链：`python -m unittest discover -s engine/tests -p "test_*.py" -v`。
- 玩法/输入：`python engine/run.py qa --headless`。当前 qa 是 sandbox 套件，正式银行需单独实现专属套件。
- 模型/材质/相机/UI：`python engine/run.py qa` 并看实际图；退出码 2 是待审阅，不是执行失败。
- 资产管线：阅读 [资产说明](../../../docs/assets.md)，运行 `python engine/run.py asset_qa`，查看 contact sheet，并用装配场景真实输入验证。
- 发布：`python engine/run.py build`，再 `python engine/run.py smoke_release`。缺模板时使用 `engine/tools/setup.ps1 -ExportTemplates`。

不要通过改低断言、放宽路径边界或更新基准消除未知失败。修改通用桥必须同时验证 lab 和 probe。保留有界步进、debug gating、隔离存档与完整检查点语义。

## 找证据

`logs/calls` 记录 CLI/游戏调用；`logs/sessions` 同时保存游戏日志、trace、状态、截图和报告；`logs/jobs` 保存资产作业；`logs/builds` 保存构建验证。`logs/latest` 只是索引，引用具体运行路径才能定位历史结果。失败记录不覆盖。

工具产生的报告和截图不等于人工艺术验收。任务完成时更新 `project/tasks.json` 并引用可追溯证据；长期证据放 `project/evidence`。源素材、目录 JSON、玩家存档和历史验收不属于可随意清理的日志缓存。

布局说明见 [项目分层](../../../docs/repository-layers.md)，玩法移植任务见 [移植 TODO](../../../docs/porting-todo.md)。保持 `OriginGame.html` 原件不变，除非用户明确要求修改它。
