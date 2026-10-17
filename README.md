# 银行危机 · AI 游戏开发与测试框架

已修复主菜单/联机入口遗漏吊灯配置的问题：单人和多人现在启用原预览的 54 个发光源及走廊灯具修正。[对照画面和 12 项定向检查](project/evidence/bank-lighting-entry-20261017/gallery.html) · [当前试玩包](build/bank/combat-coop/20261017-182250/windows/package/BankCoop.exe)。

当前 [多人合作支持寻找服务器、随时加入和常驻 localhost WSL 服务](docs/bank-coop-combat.md)，人数实时显示，满 4 人拒绝加入；队友使用原生手枪/霰弹枪世界模型与骨骼动作。[46 项验证与动态画面](project/evidence/bank-open-coop-20261017/gallery.html)。

新增 [当前银行 2–4 人合作会话与战斗](docs/bank-coop-combat.md)：创建/加入独立服务端、实时人数、共享门与感染者、独立生命和弹药、队友救援及全队重开。[验证画面与报告](project/evidence/bank-coop-combat-20261017/gallery.html)。

这是一套已经能运行的 **Godot 4.7.2 + Python** 开发框架。AI 可以启动游戏、读取实际渲染截图、发送键鼠事件、推进固定帧数、检查 UI 与游戏状态、复现错误并在修改后回归测试。

当前附带的是开发试验场。`OriginGame.html` 保留为后续移植参考，原游戏尚未整体移植。试验场的方块人物、木箱和材质球用于验证工具，不代表最终美术效果。

第二版已加入通用 `GameAdapter`、独立场景契约测试、完整游戏状态检查点、固定时间动画采样、连续帧证据，以及可校验的任务/验收清单。接手前先运行 `python engine/run.py project`；当前进度与下一项任务以 `project/tasks.json` 为准。

完整移植规划见 [Godot 移植 TODO](docs/porting-todo.md)：从原作规格、一楼可玩切片，到四层主线、表现与发行，共 20 项待办。银行专属验收项目前是计划，尚未实现或运行，不能用试验场通过结果替代。

当前目录与维护规则见 [项目分层说明](docs/repository-layers.md)。默认使用 [项目开发 Skill](.agents/skills/aigameengine-dev/SKILL.md) 调用本地脚本；游戏 MCP 为可选兼容入口，不自动注册。

独立插件试验场已提供相机、调试绘图、文本分支、行为树和谜题编辑工具，版本锁、启动命令与接入边界见 [插件使用说明](docs/godot-addons-expansion.md)。默认 lab 和正式银行工程的职责保持独立。

## 现在可以做什么

| 领域 | 已实现 | 不能据此自动证明的事情 |
| --- | --- | --- |
| 模型 | 加载 GLB；多角度截图；网格、材质、包围盒、顶点/三角形审计 | 生产角色骨骼、蒙皮、动画接缝正确性 |
| 材质与纹理 | 固定灯光材质球；导入纹理与 UV 检查；截图基准与差异标记 | 美术风格是否符合用户审美；全部 PBR 通道正确性 |
| UI | 4 种分辨率；游戏/背包/暂停状态；越界与文字最小尺寸检查；真实点击命中 | 全部控件重叠、颜色对比度、中文缺字自动识别 |
| 用户操作 | WASD、奔跑、鼠标视角、拾取、攻击、暂停与按钮；输入释放检查 | 操作系统焦点、实体鼠标/手柄、输入延迟与真实手感 |
| 玩法 | 门卡、锁门、碰撞、通关、存读档、可重复状态 | 原 HTML 的全剧情、跨楼层谜题与通关覆盖 |
| NPC | 巡逻、视线遮挡、追击、攻击、死亡停止攻击 | 完整寻路、楼梯、多 NPC 拥堵、大规模压力测试 |

报告将逻辑通过、视觉回归通过、失败、待审阅分开。空白截图是失败；缺少基准或显卡/引擎不一致是待审阅。像素相似不等于画质好，需要 AI 看图与用户审美判断共同参与。

## 启动

在 PowerShell 中进入本目录：

```powershell
cd D:\AIGameEngine
# 本机已安装；新机器上执行：官方归档 + SHA512 校验，不修改系统 PATH。
.\engine\tools\setup.ps1
.\.venv\Scripts\Activate.ps1

# 普通游戏窗口 / Godot 编辑器
python engine/run.py lab play
python engine/run.py lab editor

# 逻辑与操作测试，不需要 GPU
python engine/run.py qa --headless

# 包含实际渲染、UI 分辨率矩阵和视觉回归，需要可用的 GPU/桌面会话
python engine/run.py qa

# 测试框架自身：含“故意制造画面差异应该失败”等负例
python -m unittest discover -s engine/tests -p 'test_*.py' -v
```

普通游戏：WASD 移动，Shift 奔跑；点击画面后鼠标控制视角；E 拾取/开门；左键近战；Tab 背包；Esc 暂停。门卡在中央矮台上，门在前方。NPC 的追击、遮挡与战斗通过独立测试场景运行。

`logs/latest/report.json` 指向最近的 HTML/JSON 报告。每次运行创建独立目录，保存原图、截图时的状态、输入回放、资产审计、源码摘要、日志和失败用例。

退出码：`0` 已请求的检查通过；`1` 存在失败；`2` 存在待审阅视觉项。首次无基准时，可用 `--allow-unreviewed` 允许退出 0，但报告仍保留待审阅。无窗口测试明确跳过视觉检查。

## AI 看、玩、调试

无需额外插件，任何可以调用 Python 并查看本地图片的代码助手都可以使用：

```powershell
python engine/run.py lab start
# 使用上一步打印的真实 session 路径，勿复用已退出的会话。
$session = 'D:\AIGameEngine\logs\sessions\这里替换为实际目录'
python engine/run.py lab call state --session $session
python engine/run.py lab call act --session $session --args '{"keys":["W"],"frames":30}'
python engine/run.py lab call capture --session $session --args '{"name":"after_walk"}'
python engine/run.py lab call ui --session $session
python engine/run.py lab call quit --session $session
```

截图命令返回 PNG 的绝对路径；AI 应实际打开该图片。键盘通过 `Input.parse_input_event` 进入 InputMap 与游戏处理函数；UI 点击通过控件位置生成鼠标按下/抬起，走 GUI 命中测试，不直接调用按钮回调。坐标转换覆盖窗口缩放。

| 命令 | 参数示例 | 用途 |
| --- | --- | --- |
| `state` | `{}` | 角色、NPC、背包、门、任务、事件 |
| `describe` | `{}` | 当前适配器、实体、场景、观察视角和支持能力 |
| `ui` | `{}` | 控件文本、矩形、可见性、是否越界 |
| `act` | `{"keys":["W","SHIFT"],"mouse":[30,0],"frames":60}` | 同时按键、相对视角输入，推进 1–600 个物理帧后自动松开 |
| `act` | `{"buttons":["left"],"frames":1}` | 鼠标攻击 |
| `step` | `{"frames":120}` | 不带输入推进逻辑 |
| `click` | `{"control":"resume"}` | 命中真实按钮；另有 save/load/restart |
| `reset` | `{"fixture":"npc_chase"}` | 重置场景；default / door_locked / npc_chase / npc_occluded / combat / gallery |
| `view` | `{"name":"materials","hud":false}` | player / overview / materials / model / npc |
| `view` | `{"name":"model","orbit_degrees":90}` | 模型定角度观察 |
| `resize` | `{"width":1024,"height":768}` | 调整真实窗口与渲染尺寸 |
| `capture` | `{"name":"material_review"}` | PNG + 同一时刻状态；headless 会拒绝 |
| `sequence` | `{"name":"walk","count":13,"interval":5,"keys":["W"]}` | 首帧 + 每 5 个模拟帧采集；结束后释放输入，输出 PNG/每帧状态 |
| `animation` | `{"entity":"npc","clip":"walk","time":0.25,"preview":true}` | 指定 AnimationPlayer 的动画与时间；preview 模式防止玩法自动切回 idle |
| `checkpoint` | `{"name":"before_attack"}` | 保存适配器完整状态与源码指纹 |
| `restore` | `{"name":"before_attack"}` | 校验版本、游戏、源码指纹后恢复；属于测试准备操作 |
| `audit` | `{}` | 网格、材质、纹理、UV 和基础渲染计数 |
| `asset` | `{"path":"res://assets/my_model.glb"}` | 替换模型检查台上的已导入资源 |
| `quit` | `{}` | 正常关闭，保留证据 |

所有参数也可以用 `--args-file path.json` 传递，避免 shell 引号问题。测试在命令之间停止玩法推进，渲染继续；一次只允许一个客户端写入。超时会话应关闭并重新启动，不应重发有副作用的命令。输入桥是引擎内操作，不能证明 Windows 原生设备链路。

重放：`python engine/run.py lab replay logs/sessions/<运行目录>/trace.jsonl`。第二版会话具有 `context.json`；默认校验源码/资源指纹，代码变化时仅在有意回归验证时使用 `--allow-source-change`。历史版本不会自动恢复。可加 `--headless` 重放不含截图/序列的轨迹；第一版旧轨迹缺少 context，需要在第二版重新采集。

## 连续帧、慢放和状态恢复

```powershell
python engine/run.py lab call reset --session $session --args '{"fixture":"gallery","seed":12345}'
python engine/run.py lab call view --session $session --args '{"name":"npc","hud":false}'
python engine/run.py lab call animation --session $session --args '{"entity":"npc","clip":"walk","time":0}'
python engine/run.py lab call checkpoint --session $session --args '{"name":"start_pose"}'
python engine/run.py lab call sequence --session $session --args '{"name":"walk_cycle","count":13,"interval":5}'
python engine/run.py sequence "$session/walk_cycle.sequence.json" --speed 0.25
python engine/run.py lab call restore --session $session --args '{"name":"start_pose"}'
```

序列生成原始 PNG、逐帧状态、HTML 查看页、联系表与无损 WebP 动画。13 张、间隔 5 帧覆盖 1 秒模拟时间。HTML 可前后逐帧、拖动和切换播放速度；WebP 可由支持动画的图片查看器打开。PNG 写入时玩法停止推进，因此慢机器不会造成采样时间漂移。序列最多 120 张、1200 个逻辑步；不录制声音，也不用于测量实际 FPS。

角色动画由真实 `AnimationPlayer` 以手动模式推进。样例使用刚体部件摆动，未建立生产角色骨骼/蒙皮/落脚约束。接入新角色时，适配器负责选择实体、动画和根运动策略。

检查点覆盖试验场的角色位置/速度/生命、NPC 冷却和巡逻点、动画时刻、背包与门、任务、逻辑时钟、事件与待处理命令、随机数状态、UI 和观察相机。恢复前完整校验，错误不得造成半恢复。源码、游戏 ID 或资源检查台不一致会拒绝恢复；路径仅限当前会话。Godot 的接触缓存等引擎内部数据会重新计算，不保证跨平台逐比特一致。

正常存档使用同一游戏状态格式和临时文件替换，已增加真实保存/读取按钮后的战斗续跑测试。格式版本升级为 2；版本 1 的旧试验场存档明确拒绝，未实现迁移。后续正式游戏需要单独设计版本迁移。

## 模型、材质、纹理开发

1. 将自有或已获授权的 GLB/glTF/纹理放入 `engine/sandbox/runtime/assets/`；在 Godot 中导入或运行 `python engine/run.py lab import`。
2. 启动测试会话，使用 `asset` 加载目标资源，再用 `view` / `capture` / `audit` 检查。
3. 目前转台按约 1.3 米大小的样例模型布置；大模型需要调整 `engine/sandbox/runtime/scripts/lab.gd` 中相机与检查台位置。场景资源属于可信项目代码，加载 `.tscn` 也会运行其脚本。
4. 检查轮廓、比例、表面朝向、UV 拉伸、纹理方向、光照、阴影、透明排序等。对于骨骼动画，新增固定动画时间点的场景和断言，不应沿用静态模型结论。
5. 样例资产可由 `python engine/run.py make_sample_assets` 重建，无外部资产下载。1 Godot 单位约定为 1 米。

## 视觉基准与迭代纪律

`engine/tests/baselines/` 存放经 AI 查看确认的**试验场初始基准**；这不表示用户批准了最终画风。`manifest.json` 记录引擎、渲染器、GPU 和审阅来源。`engine/tests/visual_policy.json` 定义差异阈值，默认不屏蔽区域。

当变化符合需求并经过实际看图后，才更新基准：

```powershell
python engine/run.py visual logs/sessions/<运行目录>/report.json --reviewer '审阅者与变更原因'
python engine/run.py qa
```

若报告中的失败来自**预期的画面改动**，而所有执行检查通过，可明确选择审阅过的图：

```powershell
python engine/run.py visual logs/sessions/<运行目录>/report.json --reviewer 'AI' --names model model_90 --accept-visual-changes --reason '按需求修改木箱纹理，已查看原图及差异'
```

该参数不能绕过玩法、采集或 UI 检查失败。更新会检查原图哈希、记录审阅原因，并保留未选择的旧基准。更换显卡/渲染器时必须重新审阅所有既有基准，避免混合环境。回归会核对基准图与审阅清单中的哈希。

不要用更新基准来消除未知失败。换 GPU/引擎后会标记待审阅。当前字体使用系统字体，跨系统字体差异也可能引起回归；正式发行建议嵌入获授权的固定字体。高光差异、阴影、抗锯齿也需要结合实际图片判断。

## 扩展玩法与移植原游戏

```text
engine/godot/fixtures/player.gd     玩家运动
engine/sandbox/runtime/scripts/npc.gd        示例 NPC 状态机
engine/sandbox/runtime/scripts/hud.gd        UI 与可检查控件注册
engine/sandbox/runtime/scripts/lab.gd        示例世界、交互、存档、场景重置
engine/godot/testing/bridge.gd     本地测试桥
engine/tests/scenarios.json       可读的操作步骤与预期断言
engine/run.py lab               启动、协议、回放
engine/run.py qa                测试编排与报告
engine/run.py visual            图片差异与显式基准提升
engine/mcp/server.py        可选 MCP stdio 适配器
```

新增游戏/关卡通过 `engine/godot/testing/game_adapter.gd` 接入。`lab_adapter.gd` 封装银行的特定逻辑，`probe_adapter.gd` 用独立计数场景证明桥不依赖玩家/背包/NPC。桥不再直接访问银行字段。接口说明见 [适配契约](docs/adapter-contract.md)，新能力应在适配器中实现，别把完整关卡塞进测试桥。

可直接验证独立场景：`python engine/run.py lab start --headless --scene probe`，然后调用 `describe`、`reset`、`act {"keys":["SPACE"],"frames":2}`、`checkpoint`/`restore`。它有不同的按键映射和随机计数逻辑，不支持美术观察命令。

将成功标准写入 `engine/tests/scenarios.json`。支持 `eq`、`near`、`gte`、`lt`、`contains`、`length`，路径支持字典键和数组下标。用 fixture 准备起点，用 `act`/`click` 证明真实流程；禁止通过改状态直接伪造通关。

建议移植顺序：一楼场景与角色 → 调查/背包/门锁 → 单 NPC 战斗 → 存档 → 多楼层与解谜。每加入一个系统，增加对应的成功、失败和边界场景，再进行渲染回归。

## 资产管理与场景装配

执行 `python engine/run.py assets demo` 可注册原创 GLB/PNG 样例并搭建可玩的房间，再运行 `python engine/run.py lab play --scene assembly:bank_room`。支持 GLB/glTF/FBX 与常见纹理，提供内容版本、几何/材质分析、锚点摆放、空间检查、真实引擎预览和 MCP 后台作业。完整命令、参数与第一版范围见 [资产工具链](docs/assets.md)。`python engine/run.py asset_qa` 运行故障案例和真实输入测试并生成预览证据。

## 任务与验收

`project/tasks.json` 保存里程碑、下一项任务、依赖、状态与完成证据。`project/acceptance.json` 保存机器检查和视觉评审的明确标准。`python engine/run.py project` 会检查 ID、依赖环和缺失验收项；它是接手与验收工具，不会自行启动无限开发循环。

`python engine/run.py project --report <report.json>` 会生成该次运行的 `acceptance.json`。没有执行的测试是 `not_run`，没有视觉评审的是 `needs_review`，不能从测试通过推断用户美术认可。添加 `--review <review.json>` 可附上具名、说明范围、绑定报告及证据 SHA256 的视觉评审；具体格式见 [适配契约](docs/adapter-contract.md)。

## AI 开发入口

默认使用项目 Skill [aigameengine-dev](.agents/skills/aigameengine-dev/SKILL.md) 和 `python engine/run.py <命令>`。Skill 描述如何定位、复现、修复和验证，工具实现集中在 `engine/`；修改 Python 脚本后下次调用直接使用新代码。

`workspace.json` 集中定义项目和路径。默认 `sandbox` 指向 `engine/sandbox/runtime`，包含 lab/probe 和装配示例；`bank` 指向预留的 `game/runtime`，尚未实现，选择它运行会明确报错。

修改共享 Godot 脚本后执行 `python engine/run.py sync`，再执行 `python engine/run.py lab import`。部署副本位于目标工程的 `addons/ai_engine`；不要在那里修改维护源。同步前核验旧副本，发现手动改动会拒绝覆盖。

日志入口：`logs/calls` 记录 CLI、游戏命令和可选 MCP 调用；`logs/sessions` 保存回放、状态、截图与游戏日志；`logs/jobs` 保存资产作业；`logs/runs` 保存导入和普通游戏/编辑器输出。历史 `artifacts` 保持原样，新索引位于 `logs/latest`。旧 `tools/*.py` 命令和 `tests` 测试发现入口保留为转发器，实际实现位于 engine。

可选 MCP 适配器在 `engine/mcp`，需其他客户端接入时手动运行 `python engine/run.py mcp`。它与 CLI 使用同一实现，但当前项目不默认注册游戏 MCP；已有 Blender 配置独立保留。本工具链无需模型 API 密钥。

## Windows 导出与持续集成

```powershell
.\engine\tools\setup.ps1 -ExportTemplates
.\engine\tools\build.ps1
python engine/run.py smoke_release
```

输出 `build/sandbox/windows/release/<版本>/BankCrisisLab.exe`。构建包附带 `manifest.json` 和文件哈希；`logs/latest/build-sandbox-release.json` 指向最近发布构建，构建日志和启动检查保存在 `logs/builds/`。发布构建不激活测试桥，即使传入 `--ai-session`。模板固定版本且校验 SHA512。当前 EXE 未签名，仅是试验场演示程序。

`.github/workflows/qa.yml` 是可用的 Windows headless CI 配置，推送到 GitHub 仓库后运行。每次推送会在干净环境执行框架、资产管线及 headless 玩法检查，结果以对应 GitHub Actions 运行记录为准。渲染回归需要带 GPU 的环境；`audit` 中计数是诊断信息，固定帧率测试不代表真实性能基准。

技术参考：[Godot 命令行](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)、[Input](https://docs.godotengine.org/en/stable/classes/class_input.html)、[Viewport](https://docs.godotengine.org/en/stable/classes/class_viewport.html)、[MCP stdio](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)。
