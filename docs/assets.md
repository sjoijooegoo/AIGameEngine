# AI 资产与场景工具链

本工具链把找资产、检查、处理、搭建、实拍和操作验证接在现有 Godot 测试桥上。代码、原创样例、配方和验收可直接克隆运行。这是通用格式的第一版，不包含其他游戏的解包器，也不是原作银行的正式移植。

## 快速跑通

在仓库根目录执行（先运行 `tools/setup.ps1` 安装固定引擎和 Pillow）：

```powershell
python tools/assets.py demo
python tools/assets.py scene_preview --args '{"scene_id":"bank_room"}'
python tools/lab.py play --scene assembly:bank_room
```

预览输出 HTML 报告、contact sheet 和原始 PNG 路径。手动游戏：WASD 移动、Shift 跑、靠近门按 E、单击捕获鼠标、Esc 释放。走到门外出口触发完成。房间暂无任务 HUD；AI 用 `state` 读取完成状态。

```powershell
python tools/asset_qa.py             # 11 项资产测试 + 5 组实拍/纹理证据
python tools/asset_qa.py --headless  # 导入、约束和真实输入；不证明画质
python tools/qa.py                  # 原有玩法、NPC、UI、动画和视觉基准回归
```

## 注册与处理

CLI 与 MCP 使用相同参数；较长 JSON 推荐存入文件后使用 `--args-file`。

```powershell
python tools/assets.py asset_ingest --args '{"path":"tests/asset_fixtures/chair.fbx","asset_id":"furniture.chair","tags":["chair","bank"],"usage":"project_owned","source_note":"Original fixture"}'
python tools/assets.py asset_prepare --args '{"asset_id":"furniture.chair","unit_scale":1.0,"yaw_degrees":0}'
python tools/assets.py asset_search --args '{"query":"chair","kind":"model","status":"prepared"}'
python tools/assets.py asset_inspect --args '{"asset_id":"furniture.chair"}'
python tools/assets.py asset_preview --args '{"asset_id":"furniture.chair","lighting":"raking"}'
```

支持模型 GLB / glTF / FBX，纹理 PNG / JPEG / TGA / WebP。GLB 为推荐交换格式。FBX 使用 Godot 自带导入器，运行不需要 Blender。样例 FBX 用 Blender 4.5.13 从本仓库原创 chair.glb 导出；`tools/export_fixture_fbx.py` 仅供再生。

每个稳定 ID 对应 `asset_catalog/<id>.json`，JSON 是元数据真源，SQLite 是可重建的搜索索引。源文件及依赖复制到 `asset_sources/<id>/<content revision>/`，不改用户原文件。处理版本包括输入哈希、明确转换参数、引擎版本和 worker 指纹，输出在 `game/assets/library/<id>/<preparation key>/`。同输入复用缓存，使用前校验已处理文件；原始快照被改动时拒绝。修改原文件后重新注册、准备，旧准备版本仍可引用。

这些目录默认是本机工作数据，不自动提交外部大文件。仓库提交原创 fixtures 和 recipe，由 `demo` 重建。正式素材应选择要共享的 JSON 元数据及原始包，在项目资产存储或 Git LFS 中管理，再明确调整忽略规则。不要把 SQLite 或 `.godot` 当资产真源。当前没有远程资产同步功能。

结果区分 `declared`（人为声明）、`measured`（Godot 实测）和 `inferred`（当前为空）。测量包含米制尺寸、包围盒、顶点/三角形、法线/UV 数量、材质与绑定贴图、骨骼数量和动画清单。Y 向上，X/Z 居中、底面 Y=0，提供 floor/top/center 锚点。单位和朝向由 `unit_scale`、`yaw_degrees` 声明。父节点转换保留导入层级；未验证蒙皮变形质量或重定向。

`asset_prepare` 的 `textures` 可显式设置 `{"albedo":"texture.wood"}`，支持 albedo/normal/roughness/metallic/ao/emission。第一版覆盖整个模型所有表面，不支持逐材质槽绑定。金属度、粗糙度、AO 使用 Godot 默认 R 通道，normal 使用 Godot/OpenGL 约定。不猜文件名、不自动拆 ORM 或翻转 DirectX 法线。未指定覆盖时保持原材质绑定。

glTF 缺少外链会阻止准备，包外路径和远程引用会拒绝。二进制 FBX 的外部依赖预检不完整，元数据会提示限制；需查看导入日志、绑定贴图清单和实拍，不能从导入成功推断贴图齐全。单素材包上限 512 MiB，纹理上限 64 MP。

## 场景配方与检查

参见 `recipes/bank_room.json`。实体引用资产 ID，可用 `revision` 固定准备版本；省略时采用当前版本。位置为米，yaw 为角度。支持直接坐标、贴墙 `placement.against`（north/south/east/west，margin 默认 0.1m）、桌面 `placement.on` + `anchor:"top"` + 局部 offset。子物体继承支撑物 yaw。避免同时声明互相矛盾的约束。

```powershell
python tools/assets.py scene_validate --args-file my-validation.json
python tools/assets.py scene_build --args-file my-build.json
python tools/assets.py scene_validate --args '{"scene_id":"bank_room"}'
```

前两个参数文件均为 `{"recipe":{完整配方}}`。构建前检查 ID、依赖环、资产完整性、边界、悬空、支撑高度/范围、物体相交、门扇空间和出口路径。失败返回 `built:false` 和诊断路径，不覆盖旧场景。成功生成 `game/generated/<id>/scene.tscn`、plan.json、build.json。相同配方可命中缓存。

第一版支持矩形单层房间、静态道具、一个北墙交互门。碰撞使用保守盒体；可达性是 0.2m 网格、按玩家半径扩大物体并假设门开启的二维检查，可能拒绝实际可走的细缝，不证明台阶、跳跃、动态物体或 NPC 导航。构建检查后仍要操作测试。

`python tools/lab.py start --scene assembly:bank_room` 返回 session，随后用现有 call 命令执行 state / act / capture / quit。装配适配器支持观察、操作、重置、捕获；describe 不声明检查点或动画控制。原有 lab 的 NPC/UI/存档测试不被该样例替代。

## MCP 工作流

原有 `.codex/config.toml` 加载同一服务，共 13 个工具，无需新服务：

| 阶段 | 工具 |
|---|---|
| 查找/分析 | asset_search、asset_inspect |
| 导入/处理/看图 | asset_ingest、asset_prepare、asset_preview |
| 搭建/复查/看图 | scene_build、scene_validate、scene_preview |
| 作业管理 | asset_job_status、asset_job_cancel |
| 试玩 | game_start、game_command、game_stop |

耗时工具立即返回 job_id；用 asset_job_status 查询 queued/running/completed/failed/cancelled。检查 completed 下的业务结果（例如 built:false），不能把拿到 ID 当完成。完成的 preview 同时返回 PNG contact sheet，视觉 AI 可以直接看图。最多 8 个未完成任务，串行导入，每个引擎进程限时 180 秒，可取消自有进程。退出服务会取消未完成作业，保留 `artifacts/asset_jobs` 中的日志；重启后不能继续控制旧 job_id。

不要同时用多个 CLI/MCP 服务修改同一项目的 Godot 导入缓存；编辑器导入和资产准备也应顺序进行。独立 AI 任务使用不同仓库目录。

模型预览有 neutral/dark/raking 灯光及 front/back/side/overview 视图，房间有 overview/reverse/player 视图，纹理有 RGB/R/G/B/A 通道图。图像统计和结构检查不等于美术验收；AI 必须看图，记录缺面、翻面、拉伸、比例、遮挡等问题，把修改证据与版本绑定。

默认发行预设排除 `assets/library/*`、`generated/*`，试验素材不会自动进入 Lab EXE。发行装配关卡前，需明确修改入口和导出范围。当前未实现正式资产发布清单、自动 LOD、烘焙、简化、复杂碰撞、逐材质槽编辑和跨游戏解包适配器；这些是后续独立任务。
