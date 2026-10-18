"""Preserve the October 18 public-VPS deployment audit, including failed runs."""
import csv
import hashlib
import html
import json
from pathlib import Path
import shutil
import zipfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'project/evidence/bank-vps-deploy-20261018'
PERF=ROOT/'logs/performance/bank-vps-20261018-104112'
UI=ROOT/'logs/sessions/bank-vps-ui-20261018-102144'
SOAK=ROOT/'logs/sessions/bank-vps-release-20261018-105121'


def read(p):return json.loads(p.read_text(encoding='utf8'))
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    formal=read(PERF/'report.json');ui=read(UI/'report.json');soak=read(SOAK/'report.json');recovery=read(SOAK/'service-recovery.json')
    rows=[]
    for case in formal['cases']:
        s=case['results']['server'];c=case['results']['client-1'];osrows=read(PERF/case['evidence']/'linux-os-samples.json')
        row={'players':case['config']['players'],'initial_enemies':case['config']['population'],'server_hz':s['tick_hz'],
             'server_script_p95_ms':s['script_tick_ms']['p95'],'server_cpu_one_core_percent':s['os_cpu_one_core_pct']['mean'],
             'server_rss_peak_mib':max(r['rss_mb'] for r in osrows),'system_available_min_mib':min(r['mem_available_mb'] for r in osrows),
             'server_swap_max_mib':max(r['swap_mb'] for r in osrows),'steal_mean_percent':case['capacity']['steal_pct']['mean'],
             'server_tx_kib_s':s['network_kib_s']['sent_bytes'],'client1_rendered_fps':c['fps_average'],
             'client1_world_hz':c['world_delivery_hz'],'client1_rtt_p95_ms':c['rtt_ms']['p95'],
             'worst_client_world_age_ms':max(x['world_age_ms']['max'] for n,x in case['results'].items() if n!='server'),
             'kills':s['finish']['kills'],'issues':'; '.join(case['issues']),'all_budgets_met':case['within_budget']}
        rows.append(row)
    with (OUT/'metrics.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');writer.writeheader();writer.writerows(rows)
    reconnects={p.parent.name:p.read_text(encoding='utf8').count('正在自动重连（第') for p in SOAK.rglob('engine.log')}
    checks=ui['checks']+[recovery,
        {'name':'vps_combat_matrix_collected','status':'pass' if len(rows)==6 and not formal['failures'] else 'fail'},
        {'name':'vps_release_connection_soak','status':'fail' if soak['failure'] else 'pass','failure':soak['failure'],'reconnections':reconnects},
        {'name':'vps_combat_capacity_60hz','status':'pass' if all(r['all_budgets_met'] for r in rows) else 'fail'},
        {'name':'vps_runtime_errors_absent','status':'fail' if any(formal['engine_errors'].values()) else 'pass','errors':formal['engine_errors']}]
    compact=json.loads(json.dumps(formal))
    for case in compact['cases']:
        for result in case['results'].values():result.pop('phase_states',None)
    report={'status':'deployed_with_stability_and_capacity_failures','date':'2026-10-18','endpoint':'207.57.124.243:24567',
        'checks':checks,'metrics':rows,'production_soak':soak,'performance':compact,'phase_states_preserved_in_raw_archive':True,'ui':ui,
        'windows_build':read(ROOT/'build/bank/combat-coop/20261018-095340/windows/package/build.json'),
        'linux_build':read(ROOT/'build/bank/combat-coop/20261018-095340/linux/package/build.json'),
        'limitations':['Six 30-second dense-hall samples, not long-term capacity certification.','Profiling uses debug engine plus exact deployed release pack; production connection soak uses release binaries.',
                       'One fully rendered Windows client, others lean presentation load generators.','Early paused-driver results are diagnostic failures, excluded from the formal capacity table.',
                       'Reconnects and one shutdown roster send error remain unresolved.','No automatic rollback fault injection or whole-host reboot was performed.']}
    write(OUT/'report.json',report)
    for name in ['vps-online-empty.png','vps-online-full.png','vps-browser-entered-bank.png','vps-still-online-after-leave.png']:
        shutil.copy2(UI/'browser'/name,OUT/name)
    for case in formal['cases']:shutil.copy2(PERF/case['evidence']/'combat.png',OUT/(case['evidence']+'.png'))
    folders=[ROOT/'logs/deploy/bank-vps-20261018-095313',ROOT/'logs/runs/import-5732c26b',
        ROOT/'logs/performance/bank-vps-20261018-102358',ROOT/'logs/performance/bank-vps-20261018-103425',PERF,
        ROOT/'logs/sessions/bank-vps-ui-20261018-101844',UI,SOAK,ROOT/'logs/sessions/bank-coop-release-20261018-101854']
    with zipfile.ZipFile(OUT/'raw-sessions.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for folder in folders:
            for p in folder.rglob('*'):
                if p.is_file():z.write(p,p.relative_to(ROOT).as_posix())
    body=''.join('<tr>'+''.join(f'<td>{x}</td>' for x in [r['players'],r['initial_enemies'],f"{r['server_hz']:.1f}",f"{r['server_script_p95_ms']:.1f}",f"{r['server_cpu_one_core_percent']:.1f}%",f"{r['server_rss_peak_mib']:.0f}",f"{r['client1_world_hz']:.1f}",f"{r['client1_rendered_fps']:.1f}",html.escape(r['issues'] or '未触发流程断言；仍未达60Hz预算')])+'</tr>' for r in rows)
    pictures=''.join(f'<figure><img src="{name}" loading="lazy"><figcaption>{caption}</figcaption></figure>' for name,caption in [
        ('vps-online-empty.png','默认列表：公网服务器 0/4，可加入'),('vps-online-full.png','4/4 满员，加入按钮禁用'),
        ('vps-browser-entered-bank.png','真实 UI 进入银行；此图不作为实时 FPS 证据'),('vps-still-online-after-leave.png','所有玩家离开后仍在线'),
        ('hall_2p_32-r1.png','公网双人 32 敌密集战斗，诊断初始 HP 10000'),('hall_4p_84-r1.png','公网四人 84 敌压力场景')])
    (OUT/'gallery.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>银行合作 · VPS 部署验收</title>
<style>body{font:16px/1.65 system-ui,sans-serif;background:#111b20;color:#e0e9e6;margin:0}main{max-width:1320px;margin:auto;padding:40px 24px}h1{font-size:34px}h2{margin-top:36px}a{color:#7cdbc8}.warning{border-left:4px solid #dfae68;background:#332c23;padding:20px}table{border-collapse:collapse;width:100%;font-size:14px}td,th{padding:12px;text-align:left;border-bottom:1px solid #34434a}th{color:#e2bd7a}figure{margin:22px 0}img{width:100%;border-radius:8px}figcaption{color:#b2c4c8}.scroll{overflow:auto}.muted{color:#aac0c4}</style><main>
<p class="muted">2026-10-18 · Ubuntu 24.04 · 2 vCPU / 4 GB · 真实公网 ENet</p><h1>207.57.124.243 已部署，稳定性验收未通过</h1>
<div class="warning">基础加入与 4 人容量流程通过；正式 EXE 的 120 秒驻留测试出现 2 次自动重连。大规模战斗受主线程 CPU 限制。服务器保持在线供试用，不能将本报告理解为稳定上线认证。</div>
<p><a href="../../../docs/bank-vps-deployment.md">部署和运维文档</a> · <a href="report.json">完整报告</a> · <a href="metrics.csv">逐组指标 CSV</a> · <a href="raw-sessions.zip">原始日志（含失败）</a> · <a href="manifest.json">文件校验</a></p>
<h2>密集大厅：6 组连续运行采样</h2><p>每组预热 5 秒、采样 30 秒。服务端 debug 引擎读取已部署 release 包；客户端 1 实际渲染，其余使用精简呈现负载端。初始尸群会被消耗，FPS 只代表本次测试电脑。</p>
<div class="scroll"><table><thead><tr><th>人数</th><th>初始敌人</th><th>服务端 Hz</th><th>脚本 P95 ms</th><th>CPU/单核</th><th>RSS峰值 MiB</th><th>客户端1世界 Hz</th><th>客户端1 FPS</th><th>流程问题</th></tr></thead><tbody>'''+body+'''</tbody></table></div>
<p>两人16敌的客户端1正常，客户端2却重连；因此不能只看单个客户端。四人16敌的异常受网络和宿主调度波动影响。双人84敌没有达到足够击杀/换弹要求。四人退出出现一次向已断开 peer 广播错误，均保留在报告中。</p>
<h2>部署验证</h2><p>游戏 UDP 24567，发现 UDP 24568。开机启动已 enable；空服 SIGKILL 后自动恢复，当前 0/4。进程内存约 578–597 MiB，无进程 swap；32/84 敌约占满单核。正式服务和调试测量的区别、早期失效样本与后续优化见文档。</p>
<h2>实际客户端证据</h2>'''+pictures+'</main></html>',encoding='utf8',newline='\n')
    if (OUT/'acceptance.json').exists():write(OUT/'acceptance.json',read(OUT/'acceptance.json'))
    write(OUT/'manifest.json',{'files':{p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in OUT.iterdir() if p.is_file() and p.name!='manifest.json'}})
    print(OUT);print('raw archive MiB',round((OUT/'raw-sessions.zip').stat().st_size/1048576,2))


if __name__=='__main__':main()
