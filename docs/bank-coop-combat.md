# 当前银行场景：随时加入，最多 4 人合作

2026-10-18 最新包与测试结果见[弱网加固说明](bank-network-hardening.md)：本地移动预测、快照丢片恢复、网络 HUD 和保留生命/弹药/位置的自动重连；本机 WSL 已更新。协议 2 / bank-combat-v4 客户端和服务端需要配对。

默认入口是轻量的 `game/runtime/frontend/main.tscn`：启动 EXE 只显示主菜单，选择单人或确认服务器连接后才加载 `game/runtime/scenes/main.tscn` 的真实银行。多人保留四层地图、烘焙灯光、家具、可开关门、84 个感染者初始点位和原有战斗规则。旧 `game/tools/coop.py` 仍是结构与移动原型；本版本使用 `game/tools/bank_coop.py`。

单人模式直接进入银行，清除默认出生点 `(23, 0.04, 8.2)` 同层 8 米内的 7 个感染者（剩余 77 个）。重新开始时同样应用；测试战斗布置和多人敌人配置不受影响。Esc 暂停后可以返回主菜单，银行场景随之卸载。菜单包含设置、操作手册和退出游戏。

## 本机开始

```powershell
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank client
```

直接打开 `BankCoop.exe` 后选择「多人模式」。也可用上方命令或 `Play Co-op.cmd` 直接到多人表单。选择「创建本地会话」页签，填写呼号、端口与人数上限，点击「创建并进入会话」。客户端会启动一个独立、无渲染的 Godot 服务端进程，加载完银行后连接它。创建者自己占一个玩家名额，服务端不占名额。

多人页默认打开「寻找服务器」，每 2 秒查询本机、局域网和最近填写的地址。列表显示在线状态、`0/4`～`4/4` 和延迟；满员时禁用加入按钮，服务端也会独立拒绝第五个连接。状态查询不占玩家名额。公网地址可在「直接连接」页签填写（不带 `http://` 和端口），同机可填 `localhost` 或 `127.0.0.1`。

**连接成功并收到世界状态后直接进入银行，不再等待队友或房主点击开始。** 第一个玩家也可移动、战斗；后续玩家加入当前世界。所有人离开且没有暂留名额后，下一名玩家进入时重置为新一轮。连接中可以取消；初次连接失败、版本不符或满员会返回连接表单。游戏中断线会先自动重连，恢复原生命、弹药和位置，取消或恢复失败再返回表单。协议场景指纹现为 `bank-combat-v4` / 协议 2，客户端与服务端需要一起更新。

## 常驻的本机 WSL 服务

本机 Ubuntu 已安装 `bank-coop-local.service`，Windows 上使用仅绑定 `127.0.0.1` 的 UDP 转发进程。游戏端口 **24567/UDP**，状态端口 **24568/UDP**；WSL NAT 不自动转发 localhost UDP，因此转发器为每个客户端建立独立上游套接字，保持 ENet 身份分离。WSL 内有前台管道保活，避免仅有 systemd 服务时被 WSL 空闲回收。

Windows 登录启动项是 `AIGameEngine Bank Local Server.lnk`，指向本仓库的管理脚本。客户端退出不停止该服务，关闭所有测试客户端后应恢复 `0/4`。未修改 WSL 全局网络模式或其他服务。

```powershell
.venv/Scripts/python.exe -m game.tools.local_bank_server status
.venv/Scripts/python.exe -m game.tools.local_bank_server start
.venv/Scripts/python.exe -m game.tools.local_bank_server stop

# 更新到新导出的 Linux 包，开启当前用户的登录自启动
.venv/Scripts/python.exe -m game.tools.local_bank_server install --package <Linux包目录> --autostart
```

`stop` 结束本次常驻运行；若要停止登录自启动，在 Windows 启动文件夹中移除上述快捷方式，并运行 `wsl -d Ubuntu -u root -- systemctl disable bank-coop-local.service`。诊断在 `logs/local-bank-server/`，服务日志用 `wsl -d Ubuntu -- journalctl -u bank-coop-local.service -n 50`。本机转发只对本机开放；跨机器使用正式服务端 IP。

操作：WASD 移动，Shift 奔跑，鼠标瞄准，左键射击或近战，右键推开，1/2/3/4 切换手枪/霰弹枪/手电/警棍，R 装填，E 开门，F 手电，Esc 会话菜单。被抓取时可交替 A/D 挣脱，也可由队友攻击抓取者救援。

菜单只停止本人的输入，战斗继续。当前规则关闭友军伤害；玩家死亡后等待队友，全队阵亡可从会话菜单重新开始。**尚无倒地扶起、检查点复活和任务通关目标**。本次闭环是会话建立、合作战斗、死亡重开和离开，并不等于完整银行剧情移植。

创建者点击离开会话时，会关闭其本机创建的服务端；其他客户端进入重连，取消或超时后返回连接表单。加入独立 VPS 的玩家离开不会关闭服务器。创建者进程异常退出时，本机服务端的心跳租约约 15 秒后失效，避免遗留服务端进程。

菜单和模式切换由 autoload `frontend/app_flow.gd` 管理，地图采用后台资源读取，构建场景时显示加载页。`--server` 仍直接进入无渲染服务端；`--connect=...` 支持直接连接。测试驱动位于 `game/tests/`，不放进发布包；正式包不会启用本地调试桥。

## 远端角色与世界武器

当前银行客户端使用本机 L4D2 Nick 的 85 骨骼和原生武器动作。远端手枪使用 `w_pistol_a`（3002 面），泵动霰弹枪使用 `w_pumpshotgun_a`（3228 面），替换旧胸前方块；武器、弹匣和枪机按同名骨骼跟随角色。角色待机、步行、奔跑分武器，瞄准俯仰作用于上身；开火和装填根据服务器阶段播放上身动画，腿部继续移动。枪口效果跟随武器骨骼。

原动作保留源快照，手枪行走由原步行腿部与持手枪上身组合；Source 开火增量姿势在转换时合成到对应持枪姿势。Godot 使用手动动画推进，使固定步进截图与运行一致。当前没有复制完整 Source 着色器，也没有增加第三人称手电和警棍模型；无本地参考资产时仍保留原创身体与占位装备回退。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe' --background --factory-startup --python-exit-code 1 --python game/tools/prepare_coop_survivor.py -- --source 'D:/dev/Steam/steamapps/common/Left 4 Dead 2'
& 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe' --background --factory-startup --python-exit-code 1 --python game/tools/prepare_coop_equipment.py -- --source 'D:/dev/Steam/steamapps/common/Left 4 Dead 2'
.venv/Scripts/python.exe engine/run.py --project bank lab import
```

转换器只读原安装，版本化 GLB 和贴图在 `coop/local_reference/`，源快照在 `outerasset/source-snapshots/`。保留显式单位、贴图角色和哈希，Git 不上传外部 GLB/VTF；本地完整导出包包含当前资源。

## 烘焙数据

2026-10-17 修复：新主菜单原先进入普通银行构建器，遗漏了独立吊灯预览的实时配光。现在单人和联机客户端统一执行 `line_luminaire_profile.gd`，启用 54 个发光源、向下余弦配光、柔阴影和前楼梯走廊灯具修正，并同步第一人称武器的投影纹理。服务端不创建这套客户端灯光。入口与原预览的五个固定视角、正常进入/移动及发布包灯光数量均有独立检查。

当前主场景使用 `generated/bank_lighting_v2` 六次反弹、仅间接光烘焙：481 个网格。它与原吊灯预览使用的 v46 间接光相同；这次修复恢复实时直接光，不声称已按新配光重新烘焙。导出前与导出副本分别核对 13 个源文件及 3 个烘焙产物的 SHA-256，过期则停止构建，校验记录写入 `build.json`。烘焙有效与实时灯光配置启用是两个独立检查，不能互相替代。

旧清单中部分父节点名带 Godot 进程内自动编号；菜单先创建节点或重复进入银行会改变编号。加载器现在只归一化这些临时编号，并继续精确匹配完整父子路径和稳定 `BankRenderSource` 标识；缺失或重复匹配仍拒绝加载。源文件哈希校验保持原有严格规则。检查日志应看到 `BANK_LIGHTING` 的 `loaded: true`、`meshes: 481`。

## 单独启动服务端

```powershell
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank server --port 24567 --max-players 4
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank client --host 127.0.0.1 --port 24567 --name Alpha
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank client --host 127.0.0.1 --port 24567 --name Bravo
```

本地客户端创建只负责本机进程；没有自动端口映射、公网房间目录或 Steam 大厅。跨网连接需放行服务器 UDP 24567（或自选端口）。

## 状态归属

2026-10-18 已接入[弱网加固](bank-network-hardening.md)：协议 2 / `bank-combat-v4`，需要成对更新客户端和服务端。包括本地移动预测、权威校正、快照抗乱序与单片恢复、操作去重、网络提示和保留角色状态的自动重连。临时保留的名额也计入容量，列表会单独显示。

- 服务端：60 Hz 玩家碰撞移动、每人生命/弹药/枪械与近战计时、伤害射线、感染者感知/寻路/抓取/死亡与尸体碰撞、门的占用保护和回合重置。
- 客户端：第一人称视角与武器显示、队友骨骼角色、队伍状态 UI、音效和画面。没有客户端伤害或位置赋值 RPC。
- 玩家移动快照 20 Hz，世界战斗快照 10 Hz。完整世界快照用 Zstandard 压缩成不超过 900 字节的数据分片，并增加一片 XOR 校验；客户端有界缓存多份在途快照，单片缺失时可补齐，另有每秒可靠快照。解压长度有上限，并禁止对象反序列化。参考 [Godot PackedByteArray 文档](https://docs.godotengine.org/en/4.7/classes/class_packedbytearray.html)。
- 操作请求按连接身份归属，检查序号、有限角度、操作白名单、队列和速率上限。移动输入超时自动停止，开火也不会在输入停止后无限持续。迟加入接收当前敌人、门、队伍和击杀状态。
- 多人入口是 `coop/bank_game.gd`，继承原 `scripts/exploration.gd`。保留原银行构建脚本的字节内容与烘焙依赖校验，不靠改烘焙清单掩盖失效。

这是受信小队使用的直连原型，尚无账户认证、加密、反作弊服务或连接密码。已有输入与服务器伤害校验不等于生产级反作弊。当前本地移动采用预测与权威校正，远端角色插值；尚无历史命中回溯。极端延迟下仍可能拉回校正，真实公网手感需要另行验证。

## 构建和 Ubuntu

```powershell
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank export --platform windows
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank export --platform linux
```

构建复制当前银行到独立 `build/bank/combat-coop/<时间>/<平台>/project`，不改当前项目导出预设。Windows 包中运行 `Play Co-op.cmd` 直接打开会话页；Linux 包包含 `bank-coop-server.x86_64` 和 systemd 示例。

```bash
chmod +x bank-coop-server.x86_64
./bank-coop-server.x86_64 --headless -- --server --port=24567 --max-players=4
```

systemd 使用原 [部署服务文件](../game/deploy/bank-coop.service)，安装目录 `/opt/bank-coop`、非 root 用户 `bankcoop`。防火墙和云安全组均需放行游戏 UDP 端口；要在列表查询状态，还需放行游戏端口 +1 的 UDP 端口（默认 24568；游戏端口为 65535 时状态端口为 65534）。服务端与客户端须来自同一版本；地图和战斗参数在连接握手中校验。

原有感染者命中部位和尸体模拟依赖骨骼/网格数据，当前 Linux 无渲染包保留这些资源，不使用一键专用服务端资源剥离。完整银行比此前约 76 MB 的纯移动结构服务端明显更重；不能拿旧原型的内存数据估算本版本 VPS 容量。

当前工程已经使用本机的 L4D2/其他 Source 参考资产。它们不因联机代码而获得新的分发许可；本地预览包可用于本机验证，外部资产不随 Git 源码提交。新机器需要现有资产准备流程或用户自行保存的完整资源包。原创队友骨架仍可作为没有本地 Nick 参考模型时的替代。

## 定向验证

2026-10-17 已补[弱网实测与加固计划](bank-network-resilience.md)：100–800 ms RTT、5%–30% 丢包、强抖动/重复包及短时断网。当前仅有基础容错，高延迟响应和快照空档仍不合格；不能将本机战斗通过视为公网稳定性通过。

```powershell
.venv/Scripts/python.exe -m game.tests.verify_open_server --project bank --rendered
.venv/Scripts/python.exe -m game.tests.verify_local_wsl_bank --project bank
.venv/Scripts/python.exe -m game.tests.verify_teammate_weapons --project bank
.venv/Scripts/python.exe -m game.tests.verify_frontend --project bank --rendered
.venv/Scripts/python.exe -m game.tests.verify_frontend_layout --project bank
.venv/Scripts/python.exe -m game.tests.verify_bank_coop --project bank
.venv/Scripts/python.exe -m game.tests.verify_bank_coop --project bank --rendered
.venv/Scripts/python.exe -m game.tests.verify_bank_session_ui --project bank --rendered
```

这些检查启动真实 UDP 服务端和实际银行客户端；战斗使用两人，容量检查使用四人并尝试第五人加入。输入经普通键鼠/UI 处理器；战斗场景复位仅用于明确的测试起点。`coop_wipe` 起点让两名玩家各有 5 点生命，以原有敌人攻击验证阵亡后重开，不修改攻击伤害或正式游戏初始生命。测试驱动只在 debug 中接受本地文件命令，未提供远程测试接口，也不随发布包导出。

报告和完整追踪在每次独立的 `logs/sessions/bank-combat-coop-*` / `bank-session-ui-*`，失败记录保留。当前 VPS 和真实公网网络未在本机验证中覆盖；视觉证据不代表用户最终美术验收。

## 本次结果

[吊灯入口修复与对照画面](../project/evidence/bank-lighting-entry-20261017/gallery.html)记录普通旧入口、原预览、单人及联机的同视角比较。新版 Windows/Linux 包位于 `build/bank/combat-coop/20261017-182250/`，修复此前联机包没有启用吊灯配置的问题。

[之前的 46 项检查与动态画面](../project/evidence/bank-open-coop-20261017/gallery.html)覆盖原生世界武器、状态列表、立即入场、四人上限、常驻 WSL 服务，以及受影响的菜单、战斗和发布包。对应 `20261017-172326` 包尚未包含上述吊灯入口修复；原验证通过不代表当时启用了预览灯光。登录启动项已配置并检查，但没有执行 Windows 注销或重启测试。

[上一版双人战斗证据](../project/evidence/bank-coop-combat-20261017/gallery.html)保留原会话流程和当时的 Linux 内存数据；它不是本版本或 2 核 VPS 的性能结论。
