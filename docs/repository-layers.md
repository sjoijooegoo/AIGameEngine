# 项目分层与维护规则

项目采用四个主要目录：`engine` 工具链、`game` 游戏内容、`logs` 运行记录、`build` 发行产物。另保留 `project` 管理任务和长期证据、`docs` 管理说明，并将本机依赖与缓存单独处理。目录统一使用小写，避免跨平台大小写差异。

目录迁移已落地。默认由项目 Skill 调用本地脚本，游戏 MCP 只保留可选兼容实现，不自动注册。正式银行移植仍未开始；本次只重组开发基础。迁移验证见 project/evidence/repository-layers-validation.json。

## 当前结构

```text
AIGameEngine/
├─ engine/                     工具链的源码与通用能力
│  ├─ core/                    路径配置、进程管理、协议、日志公共模块
│  ├─ tools/                   启动、导入、资产、QA、构建、项目验收命令
│  ├─ mcp/                     可选兼容接口，复用 CLI 实现，不自动启动
│  ├─ godot/                   通用测试桥、适配器契约、资源处理运行时
│  ├─ sandbox/                 lab、probe、装配示例及其 Godot 测试工程
│  ├─ tests/                   工具链测试、故障用例、试验素材和基准
│  └─ requirements.txt         工具链 Python 依赖
├─ game/                       当前银行游戏拥有的内容
│  ├─ runtime/                 正式 Godot 工程根目录
│  │  ├─ project.godot
│  │  ├─ scenes/
│  │  ├─ scripts/
│  │  ├─ assets/               实际进入游戏的资源
│  │  ├─ data/
│  │  ├─ ui/
│  │  ├─ testing/              银行适配器和游戏专属测试支持
│  │  └─ addons/ai_engine/     从 engine 部署的工具运行时
│  ├─ source_assets/           资产源文件和不可变来源快照
│  ├─ catalog/                 资产身份、版本、授权和转换元数据
│  ├─ recipes/                 正式游戏使用的装配配方
│  ├─ tests/                   银行场景用例、视觉策略及审阅基准
│  └─ reference/               后续参考资料与原作分析数据
├─ logs/                       每次运行的诊断资料，默认不提交 Git
│  ├─ calls/                   CLI 和游戏调用的结构化记录
│  ├─ runs/                    导入、普通游戏及编辑器的输出
│  ├─ migrations/              搬迁前的文件清单、备份和回归记录
│  ├─ sessions/<run_id>/       游戏日志、输入回放、状态、截图与 QA 报告
│  ├─ jobs/<job_id>/           资产作业日志、请求与结果
│  ├─ builds/<run_id>/         构建日志与启动验证
│  └─ latest/                 最近运行的轻量索引
├─ build/<project>/windows/<configuration>/<version>/
│                              EXE、资源包、授权说明和构建清单
├─ project/                    任务、验收标准、版本与长期证据
│  └─ evidence/               明确保留并绑定哈希的验收材料
├─ docs/                       使用、架构、移植与开发说明
├─ third_party/                第三方许可与说明
├─ .tools/                     固定版本 Godot、导出模板等本机依赖
├─ .cache/                     可重建的资产索引和处理中间文件
├─ .venv/                      Python 虚拟环境
├─ .agents/skills/             aigameengine-dev 项目 Skill
├─ .codex/                     其他项目客户端集成，如 Blender
├─ .github/                    CI 配置
├─ workspace.json             工程位置及输出路径配置
├─ tools/、tests/              旧命令与测试发现的兼容转发器
├─ artifacts/                  保留的旧运行证据，不再写入新运行
├─ OriginGame.html             原作参考，保持内容与当前位置不变
├─ AGENTS.md
└─ README.md
```

当前只有一个正式游戏，先使用 `game` 即可，不必提前引入多个游戏仓库或复杂包管理。`game/runtime` 让源素材、目录元数据和测试资料位于 Godot 工程外，避免编辑器误导入和发行包误收录。

原 game 工程现位于 engine/sandbox/runtime。game/runtime、game/source_assets、game/catalog、game/tests 等仅预留目录；未放置假游戏入口。`--project bank` 明确报工程尚未实现，银行工程由 PORT-002 建立。

## 各层边界

| 目录 | 应放内容 | 关键约束 |
| --- | --- | --- |
| engine | 启动与控制游戏、资产处理、测试、预览、构建、MCP、试验场 | 通用模块不得依赖银行钥匙、剧情和 NPC 字段；示例逻辑隔离在 sandbox |
| game | 银行场景、玩法、资源、交互、游戏适配器、专属测试 | 通过通用接口接入工具链，独立运行与导出不需要 Python/MCP |
| logs | 一次运行产生的日志、回放、截图、临时状态与诊断报告 | 同次运行按 ID 聚合；失败证据保留，不依赖 latest 才能找到历史 |
| build | 可交付游戏文件、版本清单、文件哈希和许可说明 | 不能把工具环境、试验场素材和原始资产混入正式包 |
| project | TODO、依赖、验收标准、已批准的证据引用 | 不能将临时日志的存在等同于任务完成或人工审美通过 |
| docs | 用法、设计决策、迁移计划 | 与实际路径、命令和支持能力同步 |

`logs` 和 `build` 是输出目录，不是代码依赖层。正式游戏依赖 Godot 和自身资源；开发模式可接入工具桥；工具通过声明的适配器和工程配置操作游戏。

## Godot 通用代码如何共享

共享 GDScript 的唯一维护源位于 `engine/godot`，由 `python engine/run.py sync` 显式部署到目标工程的 `addons/ai_engine`。同步清单记录版本和内容哈希，导入、启动与构建前检查一致性；目标副本不允许独立迭代，发现手动改动先报错，不静默覆盖。

这样共享脚本在每个 Godot 工程中都有有效的 `res://` 路径，也不要求 Windows 符号链接。银行适配器留在游戏层；通用桥、状态校验器和资源工作器留在工具链。检查点源码指纹必须包含实际使用的共享运行时版本。

资源工作器与装配预览使用 engine/godot/fixtures 中的工具自有角色和道具组件，不依赖正式游戏脚本。迁移保留其原始行为，并对共享运行时的依赖边界添加测试。

## 日志与资产的保存方式

通过 engine/run.py 发起的 CLI 调用、游戏桥命令和可选 MCP 调用记录 `run_id`、命令名、开始/结束时间、状态、耗时、退出码、父调用及关联游戏会话；失败记录错误和证据路径。游戏输出与工具输出分开文件，但同一次运行放在同一目录。这里指项目自身能够记录的调用，不声称自动收集客户端所有对话和外部工具活动。

会话目录保留 `engine.log`、`trace.jsonl`、启动参数、源码指纹、检查点、PNG、状态旁车及 HTML/JSON 报告，防止拆散后无法追踪截图来源。最新记录用索引指向历史目录，不覆盖旧报告。

资产源快照与 JSON 元数据是不可随意删除的工作数据；SQLite 搜索索引、处理中间文件及 Godot 导入缓存可以重建。试验素材源快照和目录元数据归 engine/sandbox，正式游戏素材归 game；SQLite 索引放 .cache/<project>。素材使用 Git、LFS 或外部存储的备份策略仍需随正式资产确定。Git 是否跟踪大型素材按授权和体积决定，必要时使用 Git LFS；忽略 Git 不意味着它们是临时文件。

可重建缓存可以清理；普通日志以后可以增加按体积和时间保留的规则，但本次迁移不自动清理历史。正式验收材料应显式保留到 `project/evidence`，记录报告及原始证据哈希；不会因为清空普通日志失去唯一完成依据。

正式玩家存档仍使用 Godot 的用户数据目录。自动测试使用隔离会话存档，避免真实进度被测试覆盖；玩家存档不能随 `logs` 清理。

## 迁移对照

| 原位置 | 现归属 | 已同步处理 |
| --- | --- | --- |
| `tools/*.py`、安装和构建脚本 | `engine/tools`，逐步提取 core/mcp | Python imports、根路径计算、子进程命令、CLI 入口 |
| `game/testing` 中通用 bridge/契约/校验器 | `engine/godot` | Godot preload、运行时同步、会话路径限制、版本指纹 |
| lab/probe 的场景、脚本、适配器和样例资产 | `engine/sandbox` | res 路径、场景注册、lab/probe 契约测试 |
| `game/asset_pipeline` | 通用部分进 `engine/godot`，示例部分进 sandbox | 去掉对 lab 玩家和 props 的直接依赖，生成场景脚本引用 |
| 当前 `tests` 与样例 `recipes` | `engine/tests` 与 sandbox 配方 | 现有用例均针对框架/试验场，银行测试实现时放 game/tests |
| `asset_sources`、`asset_catalog` | 已有样例归入 engine/sandbox/source_assets 与 catalog | 元数据中的相对路径、索引、版本引用及缓存有效性 |
| `game/assets/library`、`game/generated` | 归入对应 Godot 工程的生成资源目录 | 导入与导出范围、资源 URI、生成场景引用 |
| `artifacts` | 新运行写入 `logs`，历史先保留 | QA/MCP/作业目录、报告索引、桥路径校验和 CI 附件 |
| `build` | 按 lab/bank、平台、配置和版本分目录 | 导出预设、构建脚本、启动验证及产物清单 |
| `project`、`docs`、`third_party` | 保留现有归属 | 更新有效链接、命令和验收引用 |
| `.tools`、`.venv` | 保持当前位置 | 引擎和依赖固定版本不变；虚拟环境不直接搬移 |

历史报告和旧回放包含绝对路径、资源路径或源码指纹，不能仅替换字符串就视为迁移成功。优先保留原目录作为只读历史，新运行使用新布局；如要归档搬迁，生成旧新路径映射，保留原始字节和哈希。旧源码对应的回放不保证能在新结构上重放。

## 维护入口与迁移验收

- [x] **集中路径配置**：从现有散落的 `ROOT / game`、`artifacts/sessions`、模板与输出路径中提取统一配置。CLI 和 MCP 使用同一套解析逻辑，支持明确选择 lab、probe 和后续 bank。
- [x] **建立日志入口**：新会话统一写入 logs，同时更新 Python 与 Godot 的目录边界校验；不能通过放宽到任意目录来解决路径变化。
- [x] **迁移工具与自测**：移动工具、框架测试和测试素材，更新 imports、文档、CI 与项目级客户端入口；保持短期兼容入口，避免旧命令立即失效。
- [x] **拆分共享运行时和试验场**：建立同步清单，先证明 lab 和 probe 都可运行，再验证资产导入与装配示例。正式银行入口仍按移植任务实施。
- [x] **整理资产与构建输出**：保留源快照和版本引用，重建可丢弃的索引/导入缓存，检查导出收录范围和发布桥关闭。
- [x] **保留兼容入口**：旧 tools 命令和 tests 测试发现继续转发到 engine，避免打断既有脚本；不删除历史证据。

重构前后使用相同 Godot 版本和渲染环境。至少完成框架单元测试、lab/probe 接口测试、headless QA、rendered QA、资产 QA、真实输入装配流程和 Windows 导出启动验证。实际查看画面和连续帧，确认纯路径调整没有造成场景、字体、纹理和动画变化。

目录重构的完成标准是：工具可独立迭代、游戏入口由配置选择、运行证据可关联、素材来源与历史未丢失、产物可独立启动。现有显卡差异导致的 `needs_review` 继续保留，不通过修改基准使重构结果变绿。


日常入口是 `python engine/run.py <命令>`。共享运行时修改后执行 `sync` 和 `lab import`；Python 工具修改后下次进程直接读取新代码。`engine/tools/setup.ps1` 安装到本地 .venv，普通使用和测试应选用该解释器。

项目 Skill 位于 `.agents/skills/aigameengine-dev/SKILL.md`，其目录使用官方支持的仓库技能发现路径（[官方说明](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills)）。Skill 只保存开发决策与脚本入口，不复制工具实现，也不要求常驻 MCP。

正式玩家存档路径和游戏标识在本次迁移中保持不变。资产原始快照按字节验证；旧目录 JSON、生成场景和导入缓存有迁移前备份。旧素材处理版本仍保留，新工作器采用新版本签名生成新处理结果，不通过改写旧结果伪造缓存命中。
