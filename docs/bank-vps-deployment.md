# 银行合作服务器：公网部署与验收（2026-10-18）

服务器已部署并常驻，客户端寻找服务器页默认包含 **207.57.124.243:24567**。发现、立即加入、4 人容量、满员拒绝、退出补位和自动拉起均已验证。**稳定性验收未通过**：正式 EXE 在 120 秒直连测试中也出现自动重连；密集战斗在这台 VPS 上明显受主线程性能限制。目前适合问题复现和试用，不能称为稳定上线。

[测试画廊与逐组指标](../project/evidence/bank-vps-deploy-20261018/gallery.html) · [完整报告](../project/evidence/bank-vps-deploy-20261018/report.json) · [原始证据](../project/evidence/bank-vps-deploy-20261018/raw-sessions.zip)

## 连接与版本

- SSH：`ssh -p 5579 dev@207.57.124.243`，使用现有密钥。
- 游戏：UDP **24567**；服务器发现：UDP **24568**。SSH 的 5579 不是游戏端口。
- 客户端：`build/bank/combat-coop/20261018-095340/windows/bank-coop-windows.zip`。解压后运行 `BankCoop.exe`，选择「多人模式」，在列表选择公网服务器并加入；localhost 条目仍然保留。
- Godot 4.7.2，协议 3，网络版本 `bank-combat-v5`。单人/启动菜单逻辑保持原样。
- 发布包保留现有通过源哈希校验的 481 个烘焙网格以及客户端 54 个吊灯发光体；本次没有修改照明或重新烘焙。现有吊灯方案仍使用 v46 间接光数据，不能把导出验证称为新烘焙。

## VPS 环境与服务

Ubuntu 24.04.4 LTS、2 vCPU Xeon Platinum 8171M、约 3.82 GiB RAM、2 GiB swap。服务器原有 Java、Docker 等进程继续保留。已有系统库足够运行，本次没有进行系统升级或修改防火墙；实际公网 UDP 已双向连通。

| 项目 | 位置/设置 |
|---|---|
| 源码 | `/home/dev/AIGameEngine`，`codex/bank-enet-coop`，稀疏检出当前银行/工具/文档目录 |
| 当前发布 | `/opt/bank-coop/releases/20261018-095340` |
| 当前链接 | `/opt/bank-coop/current` |
| 服务 | `/etc/systemd/system/bank-coop.service`，已 enable |
| 用户及状态 | 系统用户 `bankcoop`，`/var/lib/bank-coop` |
| 自恢复 | `Restart=on-failure`，3 秒后重启 |
| 资源保护 | `MemoryHigh=1G`，`MemoryMax=1536M`，`CPUWeight=50` |
| 权限隔离 | `NoNewPrivileges`、`PrivateTmp`、只读系统与 home 保护 |

Linux EXE SHA256：`84d7a5acd844913619614b3f9a7951251dd34fc0737829c59a281d7bf939dcbf`。发布包有独立的 `build.json` 源码哈希与二进制校验。Git 仓库不包含全部本地素材，**只 git pull 不能生成这个完整游戏**；因此同时拉取源码并上传了已验证的自包含 Linux 发布包。

常用运维命令：

```bash
sudo systemctl status bank-coop
sudo journalctl -u bank-coop -n 100 --no-pager
sudo systemctl restart bank-coop
sudo systemctl stop bank-coop
sudo systemctl start bank-coop
```

已在 0/4 时对银行服务主进程发送一次 SIGKILL，验证 PID 改变、`NRestarts` 从 0 增加到 1、自动恢复发现为 0/4。未重启整台 VPS，开机自动运行由 systemd enable 配置保证，未执行整机重启验收。

## 真实公网结果

修正测试脚本的暂停模拟问题后，正式矩阵为 **2/4 人 × 16/32/84 初始敌人**，每组预热 5 秒、采样 30 秒，合计 6 个窗口。全部在一楼大厅密集交战；本次未重复此前的所有楼层路线。

| 人数 | 初始敌人 | 服务端实际 Hz | 脚本 P95 | 客户端 1 世界更新 Hz | 客户端 1 平均 FPS |
|---:|---:|---:|---:|---:|---:|
| 2 | 16 | 60.0 | 15.4 ms | 9.9 | 145.3 |
| 2 | 32 | 55.1 | 22.2 ms | 9.2 | 133.8 |
| 2 | 84 | 24.7 | 44.7 ms | 4.1 | 92.9 |
| 4 | 16 | 52.7 | 28.7 ms | 4.3 | 132.8 |
| 4 | 32 | 43.9 | 30.6 ms | 7.3 | 92.5 |
| 4 | 84 | 19.6 | 57.9 ms | 3.2 | 68.9 |

测量服务器用相同已部署发布包，搭配同版本 Linux debug 引擎和只通过 SSH 操作的测试驱动，以取得逐 tick 数据；正式服务使用 release EXE。驱动资源覆盖仅包含烘焙清单要求的原始源码字节，哈希逐项校验，没有关闭烘焙验证。debug 测量不能当作 release 的精确性能预测，但足以暴露主线程严重超预算。

客户端 1 为 Windows 实际渲染 1920×1080；其余为同机精简不可见骨骼呈现的负载端，仍有真实 ENet、输入、解码、插值和碰撞。FPS 只代表该台测试电脑，不能外推到玩家机器。测试配置仅在准备时给予 10000 HP；战斗使用正常按键、鼠标、换弹、攻击与受击。敌人会被杀死，因此初始数量不是全程活体数。

失败记录没有忽略：

- 双人 16 敌：客户端 2 停顿并重连；表中客户端 1 正常，不能用它代表全部玩家。
- 四人 16 敌：多个客户端超过 1.5 秒未收到世界状态，客户端 1 最长约 8 秒并重连。该组伴随较高 VPS steal，且敌人逐渐清空，不能简单理解为「16 敌比 32 敌更重」。
- 双人 84 敌：只有 1 次击杀、没有完成换弹，未通过完整战斗流程的有效性要求；CPU/时序数据仍保留为过载观测。
- 四人测试退出时出现一次 `broadcast_roster` 向已断开的 ENet peer 发送控制包错误（`max channels: 0`）；服务没有崩溃，仍是需要修复的竞态。
- **正式发布 EXE 双人 120 秒连接驻留测试失败**：人数短暂下降并出现自动重连。这个测试没有自动战斗输入，不是 120 秒持续战斗证明；它独立确认问题不只存在于 debug 压测。
- 早期暂停式测试、SSH 大结果回传超时、首次安装顺序错误以及首次 UI 脚本错误均保留在原始证据。修正后的测试连续运行世界，按测得的约 1.58 秒主机时钟差安排采样，结果通过 gzip 回传；不会用旧失败样本推导正式容量。

## 瓶颈及下一步

1. **主线程 CPU 是确定瓶颈。** 32/84 敌时总进程约占满一个核心，另一核心没有分摊主要脚本工作。双人 84 敌平均每步：感染者总区段约 34.8 ms，其中姿态 10.7 ms、移动/碰撞 9.6 ms、分离 4.8 ms、命中体 2.9 ms；这些子区段包含在总区段中，不能重复相加。应优先做服务端姿态/命中体按需求更新、AI 与物理调度分离、密集碰撞优化。直接提高服务器 tick 会更糟。
2. **还存在独立的公网同步问题。** 接收端缺失快照分片，增量基准缺失计数为 0；部分 peer 的可靠包统计也出现损失。需要两端有界抓包区分实际丢包、突发流量和 ENet 排队，再验证发送节奏、分片恢复及关键状态更新策略。仅凭当前数据不能断言 VPS 套餐带宽、运营商或某个网络设备是根因。ENet 的丢包统计只覆盖可靠包，不能当总 UDP 丢包率（[官方定义](https://docs.godotengine.org/en/stable/classes/class_enetpacketpeer.html)）。不应通过延长超时掩盖数秒画面冻结。
3. **内存不是已观察到的瓶颈。** 正式矩阵进程 swap 为 0，内存与峰值详见指标表；VPS 仍有约 1.3 GiB 可用内存。宿主机 steal 平均约 1.7–8.5%，表明共享宿主调度会影响表现。原有服务占用约束也必须保留，不能把整机 4 GB 全部视为游戏预算。

本次不能给出稳定的四人规模承诺，连双人小规模也有链路重连。先修复同步停顿，再重复 8/16/24 敌多轮测试；较强单核 VPS 有助于 CPU 问题，但不能保证同时解决网络问题。默认地图仍为 84 个分布于各楼层的敌人，未偷偷修改数量或玩法；大厅集中 84 敌属于极端负载，不等同于默认地图全员同时接战。

## 更新与回滚

先构建、验证匹配的 Windows/Linux 包，再上传新的 Linux zip；暂停服务前确认没有玩家。以下版本名仅为示例，必须使用新的唯一发布标识：

```powershell
scp -P 5579 <新Linux发布包.zip> dev@207.57.124.243:/home/dev/bank-coop-incoming/bank-coop-linux.zip
scp -P 5579 game/deploy/install_bank.sh dev@207.57.124.243:/home/dev/bank-coop-incoming/install_bank.sh
ssh -p 5579 dev@207.57.124.243
```

```bash
cd /home/dev/AIGameEngine
git pull --ff-only
sudo bash /home/dev/bank-coop-incoming/install_bank.sh /home/dev/bank-coop-incoming/bank-coop-linux.zip <新的发布标识>
```

安装器校验 archive 路径、平台、协议、EXE SHA256、动态库，写入独立发布目录，切换 current 链接，检查发现端口。更新前已有版本会保存在 `/opt/bank-coop/previous`；启动失败时尝试恢复旧链接和旧 unit。首次部署没有 previous，不能声称已有一份旧版可回滚。当前安装器最终版本已作 bash 语法检查；自动回滚分支未故障注入实测。

人工回滚（先确认 previous 存在）：

```bash
readlink -f /opt/bank-coop/previous
sudo ln -sfn "$(readlink -f /opt/bank-coop/previous)" /opt/bank-coop/current.new
sudo mv -Tf /opt/bank-coop/current.new /opt/bank-coop/current
sudo cp /opt/bank-coop/current/bank-coop.service /etc/systemd/system/bank-coop.service
sudo systemctl daemon-reload
sudo systemctl restart bank-coop
```

测试入口：`python -m game.tests.verify_vps --project bank`、`python -m game.tests.verify_vps_release --project bank --package <Windows package目录> --seconds 120`、`python -m game.tests.benchmark_vps_coop --project bank --players 2 4 --populations 16 32 84 --seconds 30 --repeat 1`。压测入口只在服务器空闲时临时停止正式服务，finally 恢复；需要先准备 `/home/dev/bank-coop-validation` 中的同版本引擎、测试驱动及验证覆盖包。调试桥只通过认证 SSH 的标准输入输出访问，正式发布包禁用调试桥。
