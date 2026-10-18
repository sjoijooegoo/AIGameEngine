"""Archive current-bank WSL capacity measurements and emit a local HTML table."""
from __future__ import annotations
import argparse
import csv
import hashlib
import html
import json
from pathlib import Path
import shutil
import zipfile
from game.tools.coop import ROOT


def write(path, data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sessions',type=Path,nargs='+',required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--environment',type=Path,required=True)
    parser.add_argument('--extra-sessions',type=Path,nargs='*',default=[],help='Preserve preparatory evidence without mixing it into formal metrics')
    args=parser.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    rows=[];reports=[]
    for session in args.sessions:
        session=session.resolve();report=json.loads((session/'report.json').read_text(encoding='utf8'))
        reports.append({'session':str(session.relative_to(ROOT)),'report':report})
        for case in report['cases']:
            s=case['results']['server'];c=case['config'];cap=case['capacity']
            clients=[v for k,v in case['results'].items() if k!='server']
            row={'session':session.name,'case':c['id'],'route':c.get('route','combat'),'lean_clients':c.get('lean_clients',False),'players':c['players'],
                 'initial_enemies':c['population'],'repeat':c['repeat'],'seconds':round(s['wall_seconds'],2),
                 'tick_hz':s['tick_hz'],'min_second_ticks':cap['min_full_second_ticks'],
                 'script_p95_ms':s['script_tick_ms']['p95'],'physics_peak_monitor_p95_ms':s['monitors']['physics_ms']['p95'],
                 'tick_gap_p99_ms':cap['tick_interval_ms']['p99'],
                 'cpu_one_core_pct':s['os_cpu_one_core_pct']['mean'],'rss_max_mib':s['rss_mb']['max'],
                 'available_min_mib':min(r['mem_available_mb'] for r in json.loads((session/case['evidence']/'linux-os-samples.json').read_text(encoding='utf8'))),
                 'send_kib_s':s['network_kib_s']['sent_bytes'],'receive_kib_s':s['network_kib_s']['received_bytes'],
                 'start_alive':s['start']['alive'],'end_alive':s['finish']['alive'],'kills':s['finish']['kills'],
                 'slowest_client_hz':min(v['tick_hz'] for v in clients),
                 'slowest_world_delivery_hz':min(v['world_delivery_hz'] or 0 for v in clients),
                 'worst_world_age_p95_ms':max(v['world_age_ms']['p95'] for v in clients),
                 'clients_keep_up':all(v['tick_hz']>=59.5 and (v['world_delivery_hz'] or 0)>=9 for v in clients),
                 'within_budget':case['within_budget'],'issues':'; '.join(case['issues'])}
            rows.append(row)
    with (out/'metrics.csv').open('w',encoding='utf-8-sig',newline='') as file:
        writer=csv.DictWriter(file,fieldnames=list(rows[0]),lineterminator='\n');writer.writeheader();writer.writerows(rows)
    write(out/'measured-reports.json',reports)
    with zipfile.ZipFile(out/'raw-sessions.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for session in args.sessions:
            for file in session.rglob('*'):
                if file.is_file():archive.write(file,session.name+'/'+file.relative_to(session).as_posix())
        for session in args.extra_sessions:
            for file in session.rglob('*'):
                if file.is_file():archive.write(file,'preparatory/'+session.name+'/'+file.relative_to(session).as_posix())
        for file in args.environment.rglob('*'):
            if file.is_file():archive.write(file,'environment/'+file.relative_to(args.environment).as_posix())
        for name in ['benchmark_wsl_coop.py','wsl_proc_sampler.py','wsl_coop_performance.gd','wsl_coop_hold.gd','wsl_load_presentation.gd','coop_combat_performance.gd','bank_coop_driver.gd','benchmark_coop_combat.py','test_wsl_capacity_report.py']:
            file=ROOT/'game/tests'/name
            archive.write(file,'sources/game/tests/'+name)
        seen=set()
        for session in args.sessions:
            sources=json.loads((session/'sources.json').read_text(encoding='utf8'))
            for path in sources:
                if path.startswith(('game/runtime/','engine/godot/')) and path not in seen:
                    archive.write(ROOT/path,'sources/'+path);seen.add(path)
    headers=['案例','路线','客户端','轮次','服务端 Hz','最低单秒 tick','脚本 P95 ms','物理秒峰 P95 ms','CPU %/核','RSS MiB','发送 KiB/s','存活 开始→结束','最慢客户端 Hz','最慢世界状态 Hz','服务端预算']
    body=[]
    for r in rows:
        values=[r['case'],r['route'],'精简骨骼负载端' if r['lean_clients'] else '完整',r['repeat'],f"{r['tick_hz']:.2f}",r['min_second_ticks'],f"{r['script_p95_ms']:.2f}",f"{r['physics_peak_monitor_p95_ms']:.2f}",f"{r['cpu_one_core_pct']:.1f}",f"{r['rss_max_mib']:.0f}",f"{r['send_kib_s']:.1f}",f"{r['start_alive']} → {r['end_alive']}",f"{r['slowest_client_hz']:.1f}",f"{r['slowest_world_delivery_hz']:.1f}",'达标' if r['within_budget'] else '超预算/证据不足']
        body.append('<tr data-player="'+str(r['players'])+'" data-route="'+r['route']+'" class="'+('pass' if r['within_budget'] else 'fail')+(' clientslow' if not r['clients_keep_up'] else '')+'">'+''.join('<td>'+html.escape(str(v))+'</td>' for v in values)+'</tr>')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>银行联机 · WSL 2核4GB容量实测</title>
<style>body{font:16px system-ui;background:#111923;color:#e2e8ef;margin:32px}h1{font-size:30px}p{max-width:1100px;line-height:1.8}a{color:#9ed7ff}select{padding:8px;background:#243447;color:white;margin:8px}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:right;padding:10px;border-bottom:1px solid #304152}th{position:sticky;top:0;background:#243447}td:first-child,td:nth-child(2){text-align:left}.pass td:last-child{color:#8de0ac}.fail td:last-child,.clientslow td:nth-last-child(2),.clientslow td:nth-last-child(3){color:#ffac8d}.scroll{overflow:auto}small{color:#a8b7c8}.summary{padding:18px 24px;background:#1b2c3e;border-left:4px solid #82c7ee;max-width:1050px;line-height:1.8}</style>
<h1>银行联机 · WSL 2 核 / 4 GB</h1>
<!-- SUMMARY -->
<p>WSL Ubuntu 整机限制为 2 个逻辑处理器、4 GiB 内存、交换空间 0。Windows 客户端位于 VM 外。服务端使用固定 Godot 4.7.2 Linux 调试引擎，无渲染。真实 UDP 与普通输入；玩家仅在夹具设置时使用 10000 生命。该结果不等同于真实 VPS 单核性能、公网或长期稳定性。</p>
<p><b>combat</b>：射击、装填、移动与击杀，初始敌群会逐渐转为尸体。<b>hold</b>：持续追击、推搡和挣脱，保留全量活体，是独立的拥挤诊断，不代表枪战或尸体开销。场景和模式分开比较。</p>
<p><b>精简骨骼负载端</b>：测试客户端仅省去不可见远端骨骼更新，保留普通输入、解包、插值和移动碰撞；服务端不变。此诊断用于排除生成负载的客户端先降速，不代表完整客户端体验。完整客户端在高负载下的失败仍保留。</p>
<p>每轮预算：平均 ≥59.5 Hz，脚本 P95 及引擎每秒物理峰值监视器 P95 ≤16.67 ms，完整单秒 ≥57 tick，且连接和负载证据有效。每个规模所有轮次均达标才能列为本次通过。物理监视器每秒发布峰值，不能解读为逐 tick P95。CPU 100% 代表一个逻辑核；分段耗时有包含关系，不能相加。超预算样本完整保留。</p>
<p><a href="../../../docs/bank-wsl-capacity.md">结论与复现说明</a> · <a href="metrics.csv">CSV</a> · <a href="measured-reports.json">完整汇总</a> · <a href="raw-sessions.zip">原始数据与脚本</a></p>
<label>人数 <select id="players"><option value="">全部</option><option>2</option><option>4</option></select></label><label>路线 <select id="route"><option value="">全部</option><option>combat</option><option>hold</option></select></label>
<div class="scroll"><table><thead><tr>'''+''.join('<th>'+v+'</th>' for v in headers)+'</tr></thead><tbody>'+''.join(body)+'''</tbody></table></div>
<script>function filter(){document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!!((players.value&&r.dataset.player!==players.value)||(route.value&&r.dataset.route!==route.value)))}players.onchange=route.onchange=filter;</script></html>'''
    (out/'gallery.html').write_text(page,encoding='utf8',newline='\n')
    if (out/'summary.json').exists():
        brief=json.loads((out/'summary.json').read_text(encoding='utf8'))
        summary_html='<div class="summary"><b>'+html.escape(brief['headline'])+'</b><ul>'+''.join('<li>'+html.escape(item)+'</li>' for item in brief['points'])+'</ul></div>'
        (out/'gallery.html').write_text(page.replace('<!-- SUMMARY -->',summary_html),encoding='utf8',newline='\n')
    manifest={p.name:{'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in out.iterdir() if p.is_file() and p.name!='manifest.json'}
    write(out/'manifest.json',manifest)
    print(out)


if __name__=='__main__':main()
