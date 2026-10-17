# 当前银行场景：2–4 人合作会话

本入口运行 `game/runtime/scenes/main.tscn` 的真实银行：四层地图、现有烘焙灯光、家具、可开关门、84 个感染者初始点位、原有枪械与近战规则。旧 `game/tools/coop.py` 仍是结构与移动原型；本版本使用 `game/tools/bank_coop.py`。

## 本机开始

```powershell
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank client
```

也可以普通方式打开银行，按 Esc，在暂停页选择「多人合作 / 创建或加入」。填写呼号、UDP 端口与人数上限，点击「创建本地会话」。客户端会启动一个独立、无渲染的 Godot 服务端进程，加载完银行后连接它。创建者自己占一个玩家名额，服务端不占名额。

第二个客户端填写服务器地址和相同端口，点击「加入指定服务器」。同一台机器填 `127.0.0.1`；局域网填创建者的局域网 IP；VPS 填其公网 IP。两人到齐后，房主点击「开始合作行动」。等待大厅期间敌人不行动。

操作：WASD 移动，Shift 奔跑，鼠标瞄准，左键射击或近战，右键推开，1/2/3/4 切换手枪/霰弹枪/手电/警棍，R 装填，E 开门，F 手电，Esc 会话菜单。被抓取时可交替 A/D 挣脱，也可由队友攻击抓取者救援。

菜单只停止本人的输入，战斗继续。当前规则关闭友军伤害；玩家死亡后等待队友，全队阵亡可从会话菜单重新开始。**尚无倒地扶起、检查点复活和任务通关目标**。本次闭环是会话建立、合作战斗、死亡重开和离开，并不等于完整银行剧情移植。

创建者点击离开会话时，会关闭其本机创建的服务端；其他客户端会返回会话面板。加入独立 VPS 的玩家离开不会关闭服务器。创建者进程异常退出时，本机服务端的心跳租约约 15 秒后失效，避免遗留服务端进程。

## 单独启动服务端

```powershell
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank server --port 24567 --max-players 4
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank client --host 127.0.0.1 --port 24567 --name Alpha
.venv/Scripts/python.exe -m game.tools.bank_coop --project bank client --host 127.0.0.1 --port 24567 --name Bravo
```

本地客户端创建只负责本机进程；没有自动端口映射、公网房间目录或 Steam 大厅。跨网连接需放行服务器 UDP 24567（或自选端口）。

## 状态归属

- 服务端：60 Hz 玩家碰撞移动、每人生命/弹药/枪械与近战计时、伤害射线、感染者感知/寻路/抓取/死亡与尸体碰撞、门的占用保护和回合重置。
- 客户端：第一人称视角与武器显示、队友骨骼角色、队伍状态 UI、音效和画面。没有客户端伤害或位置赋值 RPC。
- 玩家移动快照 20 Hz，世界战斗快照 10 Hz。完整世界快照用 Zstandard 压缩成不超过 900 字节的数据分片；丢失不完整快照时等下一份，另有每秒可靠快照补齐。解压长度有上限，并禁止对象反序列化。参考 [Godot PackedByteArray 文档](https://docs.godotengine.org/en/4.7/classes/class_packedbytearray.html)。
- 操作请求按连接身份归属，检查序号、有限角度、操作白名单、队列和速率上限。移动输入超时自动停止，开火也不会在输入停止后无限持续。迟加入接收当前敌人、门、队伍和击杀状态。
- 多人入口是 `coop/bank_game.gd`，继承原 `scripts/exploration.gd`。保留原银行构建脚本的字节内容与烘焙依赖校验，不靠改烘焙清单掩盖失效。

这是受信小队使用的直连原型，尚无账户认证、加密、反作弊服务或连接密码。已有输入与服务器伤害校验不等于生产级反作弊。移动采用服务器快照插值，尚无客户端预测与延迟补偿；公网高延迟手感需要另行验证。

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

systemd 使用原 [部署服务文件](../game/deploy/bank-coop.service)，安装目录 `/opt/bank-coop`、非 root 用户 `bankcoop`。防火墙和云安全组均需放行同一 UDP 端口。服务端与客户端须来自同一版本；地图和战斗参数在连接握手中校验。

原有感染者命中部位和尸体模拟依赖骨骼/网格数据，当前 Linux 无渲染包保留这些资源，不使用一键专用服务端资源剥离。完整银行比此前约 76 MB 的纯移动结构服务端明显更重；不能拿旧原型的内存数据估算本版本 VPS 容量。

当前工程已经使用本机的 L4D2/其他 Source 参考资产。它们不因联机代码而获得新的分发许可；本地预览包可用于本机验证，外部资产不随 Git 源码提交。新机器需要现有资产准备流程或用户自行保存的完整资源包。原创队友骨架仍可作为没有本地 Nick 参考模型时的替代。

## 定向验证

```powershell
.venv/Scripts/python.exe -m game.tests.verify_bank_coop --project bank
.venv/Scripts/python.exe -m game.tests.verify_bank_coop --project bank --rendered
.venv/Scripts/python.exe -m game.tests.verify_bank_session_ui --project bank --rendered
```

这些检查启动真实 UDP 服务端和两个实际银行客户端。输入经普通键鼠/UI 处理器；战斗场景复位仅用于明确的测试起点。`coop_wipe` 起点让两名玩家各有 5 点生命，以原有敌人攻击验证阵亡后重开，不修改攻击伤害或正式游戏初始生命。测试驱动只在 debug 中接受本地文件命令，未提供远程测试接口，也不随发布包导出。

报告和完整追踪在每次独立的 `logs/sessions/bank-combat-coop-*` / `bank-session-ui-*`，失败记录保留。当前 VPS 和真实公网网络未在本机验证中覆盖；视觉证据不代表用户最终美术验收。

## 本次结果

[验收报告与实际截图](../project/evidence/bank-coop-combat-20261017/gallery.html)记录双人战斗闭环、真实 UI 创建服务端、原单人 UI 回归和 WSL Ubuntu 发布服务端四客户端互通。四人连接后的 Linux 服务端 RSS 为 511168 kB（约 499.2 MiB），仅代表本机这次短程场景，不是 2 核 VPS 的性能承诺。
