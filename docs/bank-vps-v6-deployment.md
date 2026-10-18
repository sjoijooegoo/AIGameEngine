# 211024 v6 公网部署记录

2026-10-18，用户明确要求把 `build/bank/combat-coop/20261018-211024` 部署到现有 VPS。本次使用这份现成发布包，没有重新构建或改变玩法。此前公网稳定性验收仍未通过；用户指定部署不代表该验收转为通过。

## 连接

- 地址：`207.57.124.243:24567`。
- 客户端：[BankCoop.exe](../build/bank/combat-coop/20261018-211024/windows/package/BankCoop.exe)；[Windows 压缩包](../build/bank/combat-coop/20261018-211024/windows/bank-coop-windows.zip)。
- 进入「多人模式 → 寻找服务器」，选择公网地址；服务器声明使用 TCP 兼容连接。TCP/UDP 游戏端口均为 24567，UDP 24568 用于服务器发现。
- 协议 4 / `bank-combat-v6`，需要配套 v6 客户端。旧 v5 客户端不兼容。
- 本次只更新公网 VPS。本地 WSL 仍为 v5；v6 客户端选择 localhost 时会提示版本不匹配。

## 发布与回滚

| 项目 | 值 |
|---|---|
| 当前发布 | `/opt/bank-coop/releases/20261018-211024-v6` |
| 当前入口 | `/opt/bank-coop/current` |
| 回滚入口 | `/opt/bank-coop/previous` → `/opt/bank-coop/releases/20261018-095340` |
| 服务 | `bank-coop.service`，active、enabled |
| 运行用户 | `bankcoop` |
| 参数 | `--headless --max-fps 60 -- --server --port=24567 --max-players=4 --prefer-tcp` |
| 资源约束 | MemoryHigh 1G、MemoryMax 1536M、CPUWeight 50 |
| 自恢复 | on-failure，3 秒后重启 |

Linux EXE SHA256：`38de641b7d3133c534dd0809dc90eba7e23cdb44a11bc62a406d6debf23e5df3`。

Windows EXE SHA256：`d62730ec50f527e035faa40659e8daf425133bfba0756f51aa5d504b703c8a16`。

复用此前已上传的隔离候选文件，逐项核对二进制、`build.json` 和 unit 的 SHA256 与本地发布包一致；在 VPS 组装同内容的 ZIP 交给原安装器，避免重新传输 432 MB 二进制。归档压缩方式可以不同，三个发布文件内容完全相同。安装在独立限时 systemd 任务中执行，不依赖 SSH 长连接。切换前本机发现查询确认 0/4；安装器检查依赖、协议、二进制哈希和新服务发现。

新版本通过专用 `current` 链接启用，未删除旧发布目录。回滚时先确认没有玩家，再使用原[部署文档的回滚命令](bank-vps-deployment.md#更新与回滚)。没有执行整机重启或本轮故障注入；开机自启与故障重启配置保留。

## 验证范围

本次检查文件身份、常驻服务、开机启用、版本与人数发现、配套 Windows 发布 EXE 双人短时连接、现有 481 网格烘焙和调试桥禁用。检查结果见[部署报告](../project/evidence/bank-vps-v6-deploy-20261018/report.json)。短时部署冒烟检查不能替代长期稳定性验证。

此前原网络两人 180 秒有 1 次重连、四人 180 秒有 3 次重连；六组手机热点战斗窗口没有触发网络/战斗问题，严格 CPU 预算仍未全部通过。详细反例继续保留在[公网修复报告](bank-vps-stability.md)，没有因本次部署而修改其失败结果。照明仍为既有 v46 间接光、481 网格与客户端 54 个吊灯，未重新烘焙。

两名配套发布版客户端均成功加入；30 秒冒烟期间一端再次出现响应超时，因此无重连断言失败。用户随后要求不再测试，本轮不继续压测或故障注入，已结束的失败记录保留。客户端退出后发现返回 v6、0/4；部署按用户指定保持启用，未回退旧版。
