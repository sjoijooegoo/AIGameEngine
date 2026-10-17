# Godot 插件候选与接入顺序

调研日期：2026-10-02。目标环境：仓库固定的 Godot 4.7.2、Windows、GDScript，以及 Skill + 本地 CLI 开发流程。Phantom Camera 和 Debug Draw 3D 见 [首轮验证](godot-addons-validation.md)；Dialogue Manager、LimboAI、Puzzle Dependencies 已加入同一独立试验场，见 [新增插件入口与边界](godot-addons-expansion.md)。FuncGodot 暂未安装。上游支持声明不等于本项目所有功能验证通过。

## 候选清单

| 插件 | 本次查到的版本及上游依据 | 在银行游戏中的用途 | 建议顺序 |
| --- | --- | --- | --- |
| [Phantom Camera](https://github.com/ramokz/phantom-camera) | [v0.11.0.3](https://github.com/ramokz/phantom-camera/releases)，包含 Godot 4.7.1 相关修复，但发布说明仍提示部分 Manager 查找错误 | 第三人称跟随、瞄准视角切换、室内镜头；对应 PORT-003/016/017 | 优先在 sandbox 试验，重点实测墙角和楼梯 |
| [Debug Draw 3D](https://github.com/DmitriySalnikov/godot_debug_draw_3d) | [1.7.3，标注 4.4.1+](https://github.com/DmitriySalnikov/godot_debug_draw_3d/releases/tag/1.7.3)；C++ GDExtension | 显示敌人视线、路径、攻击范围与碰撞调试信息；对应 PORT-006/007 | 优先作为引擎调试工具试验 |
| [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) | [v4.1.0，面向 Godot 4.7](https://github.com/nathanhoad/godot_dialogue_manager/releases/tag/v4.1.0)；[商店页面](https://store.godotengine.org/asset/nathanhoad/dialogue-manager/)仍有不稳定版本标记 | 调查文本、条件对话、剧情分支；对应 PORT-002/016 | 文本分支变多时引入，少量提示可先用原生 UI |
| [LimboAI](https://github.com/limbonaut/limboai) | [v1.8.1](https://github.com/limbonaut/limboai/releases)；1.8.x 表格列出 GDExtension 支持 4.6+，发行内容包含 4.7.2 引擎构建 | 行为树、层级状态机、可视化调试；适合六类敌人及 Boss，对应 PORT-006/012/015 | 跨层导航原型通过后再评估；选 GDExtension，不替换固定引擎 |
| [Puzzle Dependencies](https://github.com/nathanhoad/godot_puzzle_dependencies) | [v3.0.1，面向 Godot 4.6](https://github.com/nathanhoad/godot_puzzle_dependencies/releases)；4.7.2 待实测 | 绘制门卡、供电、世界钟、现金箱和逃生之间的依赖图；对应 PORT-001 | 可选设计工具；不是运行时任务系统，也不自动证明无死锁 |
| [FuncGodot](https://github.com/func-godot/func_godot_plugin) | [2025.12](https://github.com/func-godot/func_godot_plugin/releases)；Godot 4 插件，未核实明确的 4.7.2 支持声明 | 将 Quake MAP/Valve VMF 转为场景，可配合 TrenchBroom 编辑室内关卡 | 后续手工扩建关卡时考虑；首版先按原作数据重建 |

## 项目适配判断

优先验证 Phantom Camera 和 Debug Draw 3D。前者直接服务第三人称体验，后者能让 AI 调试时看到空间判定。它们都是 Godot 插件，不要求 MCP；AI 仍然通过本地脚本修改、运行、截图和回归。

跨楼层追击先用 Godot 原生导航建立小型实验。[NavigationAgent3D](https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html)提供路径与避障，但角色移动仍由游戏脚本处理。楼梯连接、门开闭、导航更新与多人拥堵需要本项目验证；LimboAI 负责决策，不能代替导航。

背包、钥匙链、任务标志和存档继续由游戏层拥有。Dialogue Manager 可以读取条件、提出游戏动作，但不成为这些状态的第二份权威来源。暂不引入通用存档或整套 RPG 框架，以免增加原作规则映射和检查点恢复成本。

## 与分层和测试框架的边界

以下边界已用于 addon_probe 的独立试验；正式银行依赖与升级流程仍待实现：

- 第三方原包集中保存在 `engine/vendor/`，锁定下载来源、版本、包哈希及许可证；修复使用可追溯补丁，不直接修改每个工程的部署副本。
- 插件按项目声明依赖，分别部署到对应 Godot 工程的 `addons/<插件名>`。调试工具和编辑器工具不因此自动成为正式游戏发布依赖。
- 银行的镜头配置、对话、行为树和关卡资产归 `game/`；实验及兼容用例归 `engine/sandbox/` 和 `engine/tests/`；证据归 `logs/`；导出归 `build/`。
- 当前 `engine/core/runtime.py` 同步仅覆盖共享 GDScript 的 `.gd`/`.uid`，不能直接用来部署带场景、资源或动态库的第三方插件。需要独立的完整包部署与校验流程。

试验通过再进入正式游戏。最低验证范围：

1. 固定版本在 Godot 4.7.2 下导入、启动、headless 和 Windows 导出；GDExtension 使用匹配平台的二进制包。
2. 插件随固定帧推进，暂停截图时不自行演进。[PhantomCameraHost](https://phantom-camera.dev/core-nodes/phantom-camera-host)有手动插值模式；[LimboAI BTPlayer](https://limboai.readthedocs.io/en/stable/classes/class_btplayer.html)有手动更新模式，但这不自动保证完整状态可恢复。
3. 检查镜头过渡、对话进度、行为树执行状态与黑板等新增状态，明确哪些进入开发检查点。实际输入后的连续帧与恢复结果需要独立验证。
4. Debug Draw 的覆盖层在视觉基准和正式发行中关闭；按其 README 关闭编辑器统计设置 `debug_draw_3d/settings/telemetry_state`，保持本项目本地工具流程。

选型阶段仅添加记录；后续试验的修改、测试和限制单独记录在验证文档中。试验通过不等于插件所有功能或完整银行游戏通过验收。
