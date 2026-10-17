# 文本、行为树和谜题编辑插件接入

2026-10-02：已将下列三个插件加入锁文件，部署到 `engine/sandbox/addon_probe`，并完成最小功能与 Windows 构建验证。加上原有相机、调试绘图，目前共五个插件。正式银行工程仍按移植 TODO 推进。

| 插件 | 固定版本 | 已提供的入口 | 后续使用位置 |
| --- | --- | --- | --- |
| [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager/releases/tag/v4.1.0) | 4.1.0 | 中文终端调查、门卡条件分支、按钮与数字键选项 | 调查文件、剧情、提示；对应 PORT-002/016 |
| [LimboAI](https://github.com/limbonaut/limboai/releases/tag/v1.8.1) | 1.8.1 GDExtension | 自定义 BTAction、黑板警戒状态、手动步进和暂停示例 | 敌人决策；对应 PORT-006/012/015 |
| [Puzzle Dependencies](https://github.com/nathanhoad/godot_puzzle_dependencies/releases/tag/v3.0.1) | 3.0.1 | Godot 的 Puzzles 页签、三个节点和两条连线的示例图 | 谜题设计；对应 PORT-001，非运行时任务系统 |

FuncGodot 暂未安装。先提取原作空间数据，等需要 TrenchBroom 关卡制作流程时再接入。没有另外引入存档、背包或整套 RPG 框架，避免这些核心状态出现多份权威来源。

## 使用

`python` 使用仓库 `.venv/Scripts/python.exe`。所有操作继续走 Skill + CLI，不需要 MCP。

```powershell
# 新机器安装全部五个固定版本，原包哈希不符会拒绝。
python engine/run.py --project addon_probe addons install
python engine/run.py --project addon_probe sync
python engine/run.py --project addon_probe lab import

# 新的文本 / AI 示例：E 调查，K 切换测试门卡，F 警戒，空格暂停 AI。
python engine/run.py --project addon_probe lab play --scene systems

# 原有相机 / 调试绘图示例。
python engine/run.py --project addon_probe lab play

# 编辑器顶部可打开 Dialogue、LimboAI、Puzzles。
python engine/run.py --project addon_probe lab editor

# 新插件回归与谜题编辑器验证。
python engine/run.py --project addon_probe addon_systems_qa --headless
python engine/run.py --project addon_probe addon_systems_qa
python engine/run.py --project addon_probe addon_systems_qa --editor
python engine/run.py --project addon_probe addons verify

# 两个发行入口由导出预设选择；release 不允许用 --scene 覆盖入口。
python engine/run.py --project addon_probe build --preset "Windows Systems Probe"
python engine/run.py --project addon_probe smoke_release
# 原有相机入口继续使用默认 build 预设。
```

示例源码在 `engine/sandbox/addon_probe/systems/`，对话文件是 `terminal.dialogue`，行为树任务是 `ai_action.gd`。示例门卡由正常 K 键输入切换，仅用来验证外部状态条件，不代表正式游戏的拾取流程。UI 使用立即显示的文本，尚未接入打字机效果。

谜题图由插件存入该试验工程的 `project.godot` 中，标题明确标为“待原作核对”。它不是已确认的通关依赖图。编辑器插件及检查插件从发行资源中排除。正式设计图进入游戏层时应单独确定数据维护位置。

## 已验证与修复

- 新系统 headless 13 项、rendered 15 项检查通过：实际输入与按钮命中、文本条件、黑板状态、固定步进、暂停恢复、等待时状态及像素冻结。实际查看了中文界面与 AI 进度连续帧。
- 编辑器实际加载三个谜题节点、两条连线；Dialogue 插件启用、BTPlayer 类存在；已查看编辑器截图。
- 原相机/调试绘图 13 项 headless、17 项 rendered 回归通过；原 sandbox 53 项执行检查通过，19 项视觉基准仍因环境指纹差异待审阅。
- 39 个工具单元测试通过，包括追加新包不改旧包、拒绝隐式升级/删除、源文件和二进制完整性。
- 文本/AI 专用 Windows release 导出与有画面、headless 启动通过。日志确认对话资源可加载、AI 手动模式、谜题插件已排除、自动化桥不启动。

本轮发现并处理了三项接入问题：

1. Headless 的窗口尺寸默认很小，导致 UI 在视口外。配置 Canvas Items 缩放后真实按钮点击通过；异步对话等待布局稳定后才报告 ready。
2. Dialogue Manager 4.1.0 将资源引用注入自身行字典，示例退出时产生循环引用。试验场退出时清理这一单资源自引用；原包不变，失败日志保留。多文件引用图、同时打开多段对话的资源生命周期仍需后续验证。
3. 导出全资源时会遇到原包的 C# 示例场景。当前为 GDScript 引擎，导出配置明确排除这些场景，不替换引擎。另对 LimboAI 导入时自动写入的 `has_editor_variant` 元数据作了精确兼容：仅允许该 SVG 导入标记变化，导入参数、源码与 DLL 被改动仍拒绝。

完整运行引用、失败记录、原包来源和证据哈希见 `project/evidence/godot-addons-expansion.json`。第一次用 release 的 `--scene` 切换入口被固定引擎拒绝，已改为专用导出预设，保留这次失败证据。

构建前会核验已部署插件；发行目录显式附带 `licenses/`，并在构建清单记录许可证哈希，不依赖 PCK 自动包含非资源文本。

## 后续迭代边界

先将正式游戏状态通过薄适配层交给插件，继续由游戏持有门锁、物品、事件和存档。LimboAI 负责决策，导航仍使用 Godot 原生导航另行实现。

当前试验不支持插件内部状态的 checkpoint/restore/reset。正式使用前需补齐对话当前位置、分支上下文、行为树执行状态、黑板、随机数与冷却的完整恢复，并覆盖真实任务。暂停兼容仅证明本示例的手动更新策略，不代表全部插件节点自动具备确定性。

上游 Dialogue Manager 商店的不稳定标记没有因本次通过而消失。这里验证的是固定版本、Windows、GL Compatibility 与列出的功能；其他平台、复杂剧情、完整导航和最终美术未验收。
