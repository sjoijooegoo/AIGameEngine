# Phantom Camera / Debug Draw 3D 验证

2026-10-02，Godot 4.7.2 official、Windows、OpenGL Compatibility、RTX 5070 Ti Laptop GPU。

结论：Phantom Camera 0.11.0.3 与 Debug Draw 3D 1.7.3 可继续作为候选使用。已验证导入、实际输入、渲染和 Windows release；当前仅部署在独立 `engine/sandbox/addon_probe`，未替换默认 lab 或正式银行工程。

## 实际发现与处理

PhantomCameraHost 的 MANUAL 模式只控制 Host，未激活的 PhantomCamera 默认仍在自动更新。第一次渲染测试在切换后的等待期间发现旧镜头坐标继续变化，虽然当前截图没有变化。保留失败报告；在试验场包装代码中关闭两个 PhantomCamera 的自动 process/physics_process，固定帧内手动更新非活动镜头，再调用 Host.process。没有修改插件原包，也没有放宽冻结断言。修复后，静止、运动阻尼和切换中途的状态及 PNG 均保持冻结。

第三人称 SpringArm 测试覆盖后墙压缩、坡道高度变化、鼠标旋转和跟随→瞄准过渡。坡道与旁侧阶梯是相机试验素材；这不是角色跨台阶能力、银行窄楼梯净空或跨楼层寻路的验收。

Debug Draw 通过球、线和盒显示范围及调试标记。覆盖层在渲染回调中从固定状态重绘，等待 PNG 时没有用墙钟驱动玩法；G 键走正常输入处理器关闭显示。Headless 和 release 关闭调试绘制，release 自动化桥也不启动。

## 测试范围

- 插件 headless：13 项检查；插件 rendered：17 项检查，包括冻结前后像素相等及实际连续帧。
- 原有 sandbox：逻辑回归通过，渲染报告 53 项执行检查通过、0 失败；19 项视觉基准因设备指纹差异继续 needs_review，未更新基准。
- 工具层：37 个 unittest 通过，包含下载哈希不符、ZIP 路径越界和部署副本被改动的拒绝用例。
- Windows release：导出成功；headless 与有画面启动均通过，运行日志确认 overlay=false、debug_build=false，桥关闭。
- 实际查看了坡道跟随、瞄准切换联系表以及调试覆盖开/关、后墙截图。只评审试验功能的可见性，不代表最终画风批准。

完整原始运行引用、文件哈希和保留的失败记录见 `project/evidence/godot-addons-validation.json`。

## 复现

在仓库根目录，`python` 使用 `.venv/Scripts/python.exe`：

```powershell
python engine/run.py --project addon_probe addons install
python engine/run.py --project addon_probe sync
python engine/run.py --project addon_probe lab import
python engine/run.py --project addon_probe addon_qa --headless
python engine/run.py --project addon_probe addon_qa
python engine/run.py --project addon_probe build
python engine/run.py --project addon_probe smoke_release

# 手动体验：WASD 移动，鼠标转向，F 切换瞄准，G 切换调试显示。
python engine/run.py --project addon_probe lab play
```

锁文件 `engine/vendor/addons.lock.json` 保存来源、版本、SHA256 和 ZIP 内目录。原包位于忽略的 `engine/vendor/*.zip`；丢失时 install 按锁下载并校验。完整部署支持插件资源和动态库，独立于仅同步共享 GDScript 的 ai_engine。部署拒绝被修改的已知副本，不做隐式升级。两插件的 MIT 许可证随原包部署；后续插件扩展已让构建脚本显式输出 licenses 目录，避免依赖 Godot 对非资源文件的打包行为。

## 正式接入前仍需补齐

Phantom Camera 的插件内部状态还没有纳入完整检查点；试验适配器明确不支持 checkpoint/restore 或 reset，独立测试使用新会话。正式银行使用前，需处理过渡、阻尼及非活动镜头状态恢复，并补充真实窄楼梯、墙角和瞄准体验用例。

Debug Draw 的短时图元生命周期不等于模拟时钟。用于框架调试时继续采用本试验的固定状态重绘策略；正式截图基准关闭覆盖层。没有验证其他平台、渲染器、全部图元或性能预算。

插件 README 的统计开关属于 Godot EditorSettings，不能靠同名 ProjectSettings 保证关闭。本次未修改用户全局编辑器设置，也未进行网络流量审计；后续团队编辑器配置需单独核实此开关。
