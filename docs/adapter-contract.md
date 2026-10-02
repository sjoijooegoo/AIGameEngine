# 游戏接入契约 v1 / 测试协议 v2

`bridge.gd` 只负责受限命令、文件通信、输入事件、逻辑步进和渲染采集。每个游戏提供继承 `game_adapter.gd` 的对象。`lab_adapter.gd` 是真实接入示例；`probe_adapter.gd` 是无玩家/背包/UI 的独立反例测试。

| 方法 | 责任 |
| --- | --- |
| `describe()` | 返回稳定 game_id、adapter_version、state_version、capabilities、fixtures、views、entities |
| `input_keys()` | 返回允许注入的按键名到 Godot Key 的映射；例如 probe 只支持 SPACE |
| `advance(dt)` | 推进一个 1/60 秒逻辑步，驱动玩法与手动动画 |
| `observe()` | 返回 JSON 可序列化观测状态；使用稳定实体 ID |
| `inspect_ui()` / `find_control(id)` | 提供 UI 证据与真实命中测试目标，无 UI 可返回空集合 |
| `reset(fixture, seed)` | 建立可复现起点；仅测试准备，不能算真实玩家完成任务 |
| `configure_view(options)` | 选择测试观察相机与 HUD；无能力时返回清晰错误 |
| `load_asset(path)` | 接入可信项目资源；资源路径由桥限制在 assets 下 |
| `sample_animation(options)` | 选择动画与时刻；由适配器定义角色 ID 和动画集合 |
| `save_state()` / `restore_state(data)` | 序列化全部自有状态；先校验后原子应用，失败返回错误字符串 |

所有可选操作返回 `""` 表示成功，否则返回错误文本。桥持有基类 `game` 根节点仅用于通用资源审计，不访问其玩家、NPC、背包或检查台。

## 模拟与确定性

测试会话中必须关闭普通 `_physics_process` 中的玩法推进，由 `advance` 驱动。`AnimationPlayer` 使用手动模式；自定义 Timer、Tween、粒子或异步逻辑也必须由接入方定义如何冻结/采样，桥不会自动冻结任意第三方脚本。渲染始终可继续，捕获序列时只有指定逻辑步数改变玩法。

随机过程使用自有 `RandomNumberGenerator`。保存 seed/state 时编码为字符串，避免 JSON 数字的 64 位精度损失。probe 的随机计数测试实际验证随机序列的恢复。

检查点封装包括 format、game_id、源码/资源 build_id、payload。兼容性验证发生在恢复前；如果修改过代码，需先通过显式回归重放确认新行为，不能静默宣称旧检查点兼容。`restore` 会释放注入按键；真实用户持续按住的物理设备不在此恢复协议内。

游戏状态必须包含决定未来行为的计时器、巡逻目标、队列、任务与动画状态。不要只保存可见位置。物理引擎接触缓存、音频设备、网络或外部文件副作用不属于自有状态，需另行设计恢复策略。

## 连续画面证据

`sequence` 在第 0 帧捕获一次，随后每 interval 个逻辑步捕获一次，共 count 张。可指定 keys 以真实输入驱动移动，结束或采集失败时释放输入。每张原图有状态旁车文件；清单记录 index、simulation_time 和 state。不要把截图耗时当作游戏帧耗时。

`tools/sequence.py` 从这些原图生成联系表、无损 WebP 与 HTML 滑块查看页。查看页可按 0.25/0.5/1 倍模拟速度播放。适合检查相机、动画和 UI 的时间连续性；蒙皮质量、脚底滑动、root motion、混合树和音画同步需要专门场景及验收项。

## 视觉评审文件

`tools/project.py --report ... --review ...` 接受如下结构。哈希必须来自本次实际审阅的文件；工具验证报告与证据未在审阅后改变。判定应由审阅者看过证据后填写，不应仅由工具自动生成 pass。

```json
{
  "report": "D:/.../report.json",
  "report_sha256": "实际报告哈希",
  "reviewer": "AI / 审阅者姓名",
  "scope": "试验场质量检查，不代表用户最终美术认可",
  "evidence_sha256": {"model.png": "实际原图哈希"},
  "decisions": {
    "ART-CRATE": {"status": "pass", "notes": "逐面查看，标签朝向与表面完整性符合试验场标准"}
  }
}
```

每条准则所要求的全部文件都需有哈希。缺失证据为 `not_run`，有证据无评审为 `needs_review`。报告的像素回归与此语义评审相互独立。

## 后续扩展边界

下一项任务是 `PORT-001`：先提取原 HTML 一楼布局和规则并补专属验收项，再迁移。通用接口不是完整游戏引擎替代物；导航网格、骨骼动画、资源预算、音频、手柄和自动探索策略应随着实际游戏需求逐项接入。
