# 银行合作联机框架 · 第一阶段

本阶段是当前银行项目的独立联机入口：一个 Godot 专用服务端、2–4 个客户端，通过 ENet/UDP 连接，服务端校验并推进移动，客户端显示完整队友身体和站立、行走、奔跑动画。服务端本身不占玩家名额。

联机入口复用当前银行四层布局、墙体、门洞、楼梯坡面与静态关闭的门，采用独立的简化材质显示。当前单人入口、原始 `OriginGame.html` 和已有资产版本不改动。此阶段没有接入感染者、开门交互、武器战斗、任务、存档、复活或语音；不代表完整合作玩法已实现。

## 从仓库启动

需要 Python 3.11+ 和项目锁定的 Godot **4.7.2**。优先使用仓库 `.venv/Scripts/python.exe`；下面的 `python` 指该解释器。工具没有额外 pip 依赖。

Godot 默认读取 `workspace.json` 的路径，也可以用 `GODOT_BIN` 指定相同版本的可执行文件。网络协议和资源格式要求服务端、客户端使用相同版本构建。

```powershell
# 终端一：专用服务器，默认 UDP 24567
python -m game.tools.coop --project bank server --max-players 4

# 终端二、三：本地两个玩家；继续启动可达到四人
python -m game.tools.coop --project bank client --host 127.0.0.1 --name PlayerA
python -m game.tools.coop --project bank client --host 127.0.0.1 --name PlayerB
```

WASD 移动、Shift 奔跑、鼠标转向、Esc 菜单。菜单可退出房间并重新加入。失焦会清除移动输入；用“继续游戏”恢复控制。服务端关闭后，客户端清空角色并返回连接界面。客户端可以填 IP 或域名；同机验证用 `127.0.0.1`。

每次工具运行会在 `build/bank/coop/<运行编号>/project` 创建独立构建目录，只复制明确列出的联机资源，不依赖未提交的单人素材库或历史 sandbox。运行时维护源码在 `game/runtime/coop/`，构建目录内文件是生成物。

若在现有完整银行 Godot 工程内操作，可直接运行 `res://coop/main.tscn`；服务器通过用户参数 `--server --port=24567 --max-players=4` 启动。请不要把“使用 headless 运行”单独当作启动服务器的条件，headless 客户端也用于测试。

## 完整角色与本地 L4D2 参考

干净克隆自带原创 17 骨骼完整身体及三种循环动画，没有外部素材也可联机。所有玩家共享同一种身体结构，用四种衣服颜色区分。第一人称隐藏自己的第三人称身体，队友身体正常可见。

本地可选参考使用用户安装的 L4D2 **Nick / survivor_gambler**：85 骨骼、原始蒙皮、显式基础颜色贴图，原版 `@Idle_Calm_Pistol`、`a_WalkN_Rifle`、`a_RunN_Rifle`。目前四名玩家使用相同 Nick 外观；未接入角色选择、武器模型、持枪 IK、侧移/倒退专用动画和动作重定向优化。原动作中的持枪手势会保留。

该资源是本地开发参考，沿用项目 `local_reference_only_rights_unverified` 标记。原始游戏文件与转换后的 GLB 不提交到 Git。Git 保存转换器、锁定版本和证据；默认客户端使用原创身体，服务端完全不依赖这套素材。

准备转换工具（已有 `.tools/SourceIO` 时不要重新克隆或重置现有修改）：

```powershell
git clone https://github.com/REDxEYE/SourceIO.git .tools/SourceIO
git -C .tools/SourceIO checkout 472e81542a6750cf3c282daac41af96a2f5d4fd3

& 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe' `
  --background --factory-startup --python-exit-code 1 `
  --python game/tools/prepare_coop_survivor.py -- `
  --source 'D:/dev/Steam/steamapps/common/Left 4 Dead 2'

python -m game.tools.coop --project bank client --reference --name PlayerA
```

转换器只读原安装，选择性提取 VPK 并检查 CRC，将不可变源快照和 SHA256 清单保存在 `outerasset/source-snapshots/coop-gambler-v2/`。输出位于被忽略的 `game/runtime/coop/local_reference/`。单位显式为每 Source 单位 0.0254 米，前方为 Godot −Z；水平根位移由角色控制器负责。当前材质只转换 albedo，不宣称完整复现 Source 着色器。

## 导出可运行包

```powershell
# Ubuntu x86_64 专用服务端（不包含本地参考模型）
python -m game.tools.coop --project bank export --platform linux --server

# 可分享的原创角色 Windows 客户端
python -m game.tools.coop --project bank export --platform windows

# 本地参考角色客户端，仅用于已有授权范围内的本地测试
python -m game.tools.coop --project bank export --platform windows --reference
```

工具输出 `package/` 路径，并在其上一级生成 ZIP。包内 `build.json` 记录源码哈希、协议、平台与可执行文件 SHA256。Windows 客户端直接运行 `BankCoop.exe`，连接页填写 VPS IP 和端口。也支持 `BankCoop.exe -- --connect=服务器IP --port=24567 --name=PlayerA`。

构建只复制版本化 GLB 和清单，不复制 Godot 从旧模型提取的图片缓存，避免材质更新被旧纹理覆盖。

导出需要对应版本模板。工具优先使用 `.tools/templates/`，缺少 Linux 模板时从现有 `.tools/Godot_v4.7.2-stable_export_templates.tpz` 中选择性提取。缺少归档时，先按项目 `engine/tools/setup.ps1 -ExportTemplates` 安装模板。Linux 当前只提供 x86_64 包；先在 VPS 用 `uname -m` 确认架构，不要把该包用于 ARM64。

## Ubuntu VPS 部署

只上传 Linux 包，VPS 不需要 Python、Blender、桌面环境或 L4D2。先解压到临时目录，检查包内哈希，再把整个包复制到 `/opt/bank-coop/`。以下假设 ZIP 已上传到当前目录：

```bash
uname -m
sudo apt-get update
sudo apt-get install -y unzip
unzip server-linux.zip -d bank-coop-package
sudo adduser --system --group --home /var/lib/bank-coop bankcoop
sudo install -d -o root -g root /opt/bank-coop
sudo cp -a bank-coop-package/. /opt/bank-coop/
sudo chmod 755 /opt/bank-coop/bank-coop-server.x86_64

# 先前台确认启动；Ctrl+C 结束
sudo -u bankcoop /opt/bank-coop/bank-coop-server.x86_64 \
  --headless -- --server --port=24567 --max-players=4

# 安装守护服务
sudo cp /opt/bank-coop/bank-coop.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now bank-coop
sudo systemctl status bank-coop
sudo journalctl -u bank-coop -f
```

云平台安全组开放入站 **UDP 24567**；如果启用了 UFW，执行 `sudo ufw allow 24567/udp`。TCP 同端口不能代替 UDP。修改端口时同步修改服务文件、客户端与防火墙，然后 `sudo systemctl daemon-reload && sudo systemctl restart bank-coop`。

升级时先 `sudo systemctl stop bank-coop`，备份 `/opt/bank-coop/` 中当前版本，再替换完整包、恢复执行权限、重新启动。不要混合不同构建的客户端和服务端。

当前协议提供版本/地图校验和人数限制，尚未提供账号、房间口令、传输加密或重连后恢复原角色。重新加入创建新的玩家身份和出生点。默认只运行一个房间。

## 网络与代码边界

| 文件 | 职责 |
|---|---|
| `main.gd` | 服务端/客户端入口，按模式构建世界与会话 |
| `session.gd` | ENet、握手、席位、加入退出、输入与状态消息 |
| `player.gd` | 角色碰撞与移动，服务端才调用 `move_and_slide()` |
| `world.gd` / `bank_layout.json` | 同源银行结构与碰撞；服务端不创建灯光和显示网格 |
| `avatar.gd` | 客户端骨骼、动画和可选本地参考角色 |
| `ui.gd` | 连接页、玩家列表、继续和退出 |
| `game/tools/coop.py` | 独立构建、导出和启动 |

服务端物理 60 Hz，状态发送 20 Hz。移动输入是序号、方向、视角和奔跑标志，没有客户端位置、速度、时间步长或任意代码执行消息。服务端按发送者 ID 找到角色，限制方向长度、俯仰，拒绝非有限数字和旧序号；每个物理步最多模拟一次，输入洪泛不能增加移动步数。超过 18 个服务端 tick 未收到新输入就停止水平移动。

ENet 通道 0 发送不可靠有序输入；输入状态变化和 5 Hz 确认走同通道的可靠子流，避免自适应限流吞掉持续输入。通道 1 发送不可靠有序快照，通道 2 可靠传送完整人员列表。地图摘要规范化 CRLF/LF，避免 Git 的换行转换导致 Windows/Linux 误报版本不一致。列表版本防止不同通道到达顺序造成幽灵角色；新玩家会收到全部当前角色状态。服务器 ID 1 不生成角色。对象反序列化保持关闭。

当前客户端对位置插值，视角即时响应；**尚未实现本地移动预测、重演纠正和命中延迟补偿**。公网较高延迟下会有移动响应延迟，后续接战斗前应补齐。玩家之间暂不互相阻挡，碰撞只针对银行结构；此规则是第一阶段明确范围。

## 验证与限制

```powershell
# 原创角色、实际多进程 UDP、无画面逻辑
python -m game.tests.verify_coop --project bank

# 原版完整角色与实际截图
python -m game.tests.verify_coop --project bank --rendered --reference
```

测试使用独立 session，冻结在命令之间、在真实物理帧内推进有界 60 Hz 步长。移动通过正常 `InputEvent` 处理器，退出/重新加入通过真实 GUI 点击。它覆盖两人移动、四人加入、满员拒绝、墙体碰撞、异常输入、输入超时、晚加入状态、正常退出、重新加入、进程异常退出、版本拒绝和服务端断开。测试驱动只在本地 debug 入口运行，不进入发行包，也不改变共享自动化桥。

本机已另外使用 WSL Ubuntu 运行正式 Linux 服务端，并连接四个 Windows 客户端验证真实时间移动与退出；此结果仍不等于 Ubuntu VPS 容量或公网体验通过。Linux 包是否在用户具体系统运行、UDP 可达性、实际 RTT/丢包以及 2 核 4 GB 上接入完整感染者后的负载仍需部署后验证。本阶段服务端没有运行感染者，因此不能用其占用估算完整战斗容量。

Godot 依据：[高层多人 API](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)、[专用服务器导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html)。
