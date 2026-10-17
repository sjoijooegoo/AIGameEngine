# 银行游戏内容

这里保存正式银行游戏的独立工程和内容。当前只预留目录，原作尚未移植；开发试验场位于 engine/sandbox/runtime。

- runtime：未来的 Godot 工程、场景、脚本、UI 与运行资源。
- source_assets：原始素材与来源快照；不能作为缓存清理。
- catalog：资产身份、版本与授权元数据。
- recipes：正式游戏的场景配方。
- tests：游戏专属场景、视觉策略及审阅基准。
- reference：原作分析与参考资料。OriginGame.html 原件仍保留在仓库根目录。

workspace.json 已预留 bank 项目。待 PORT-002 创建真实 project.godot 和入口后，通过 python engine/run.py --project bank lab play 运行。当前选择 bank 会明确报错，不会替换成 lab。
