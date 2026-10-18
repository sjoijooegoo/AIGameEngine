"""Curate public-safe bank WAN evidence without publishing packet/session secrets."""
from pathlib import Path
import hashlib,html,json,shutil

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'project/evidence/bank-vps-fix-20261018'

def read(path):return json.loads(path.read_text(encoding='utf8'))
def write(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    reports=[];battles=[];sources=[]
    sessions=['bank-coop-optimization-20261018-203131','bank-network-combat-20261018-203111',
        'bank-network-recovery-20261018-203121','bank-tcp-recovery-20261018-205327',
        'bank-tcp-fallback-20261018-210603','bank-network-visual-20261018-211034',
        'bank-coop-release-20261018-211427','bank-network-20261018-201213']
    sessions+=sorted(p.name for p in (ROOT/'logs/sessions').glob('bank-vps-release-20261018-21*') if (p/'report.json').exists())
    sessions+=sorted(p.name for p in (ROOT/'logs/sessions').glob('bank-vps-candidate-20261018-21*') if (p/'report.json').exists())
    sessions+=sorted(p.name for p in (ROOT/'logs/sessions').glob('bank-vps-ui-20261018-21*') if (p/'report.json').exists())
    for name in sessions:
        path=ROOT/'logs/sessions'/name/'report.json';raw=read(path)
        # Explicit projection: no full snapshots, credentials, client addresses,
        # recovery tokens or command streams enter the durable public report.
        row={'id':name,'source':path.relative_to(ROOT).as_posix(),'sha256':digest(path),
             'checks':raw.get('checks',[]),'failure':raw.get('failure'),
             'passed':raw.get('passed'),'scope':raw.get('scope')}
        if 'samples' in raw:
            row['samples']=[{'seconds':s['seconds'],'status':{k:s['status'].get(k) for k in ['build','players','reserved','occupied','transport']} if s['status'] else None} for s in raw['samples']]
            row['discovery_missed_datagrams']=raw.get('discovery_missed_datagrams')
        if 'service' in raw:row['restored_service']=raw['service']
        if 'remote' in raw:row['remote']=raw['remote']
        if 'cases' in raw:
            row['weak_network_cases']=[{k:c.get(k) for k in ['profile','repeat','outcome','stage','issues','metrics','duration_s']} for c in raw['cases']]
            row['functional_passed']=raw.get('functional_passed')
            row['weak_network_quality']=raw.get('weak_network_quality')
        changed=path.parent/'network-change.json'
        if changed.exists():row['network_change']=read(changed)
        reports.append(row);write(OUT/'runs'/f'{name}.json',row)
    for name,network in [('bank-vps-20261018-201228','original'),('bank-vps-20261018-205316','phone-hotspot'),('bank-vps-20261018-210233','phone-hotspot')]:
        path=ROOT/'logs/performance'/name/'report.json';raw=read(path)
        for c in raw['cases']:
            s=c['results']['server'];cap=c['capacity'];clients=[v for k,v in c['results'].items() if k.startswith('client-')]
            battles.append({'run':name,'network':network,'config':c['config'],
                'tick_hz':s['tick_hz'],'script_tick_ms':s['script_tick_ms'],'scopes_ms':s['scopes_ms'],
                'cpu_one_core_pct':s['os_cpu_one_core_pct'],'rss_mb':s['rss_mb'],
                'steal_pct':cap['steal_pct'],'min_full_second_ticks':cap['min_full_second_ticks'],
                'network_kib_s':s['network_kib_s'],'client_world_hz':[v['world_delivery_hz'] for v in clients],
                'issues':c['issues'],'budget':c['budget'],'within_budget':c['within_budget']})
        sources.append({'path':path.relative_to(ROOT).as_posix(),'sha256':digest(path)})
    for name in ['door_close','corpse_fall','corpse_shot_wake','predicted_walk','predicted_fire']:
        source=ROOT/'logs/sessions/bank-network-visual-20261018-211034'/f'{name}.jpg'
        shutil.copy2(source,OUT/source.name)
    for name in ['vps-online-full','vps-browser-entered-bank']:
        source=ROOT/'logs/sessions/bank-vps-ui-20261018-215628/browser'/f'{name}.png'
        if source.exists():shutil.copy2(source,OUT/source.name)
    service_path=ROOT/'logs/sessions/bank-vps-candidate-20261018-214753/production-final.json'
    service=read(service_path) if service_path.exists() else None
    handshake=ROOT/'logs/network/bank-wan-fix-20261018/native-handshake-final.log'
    (OUT/'handshake.txt').write_text(handshake.read_text(encoding='utf-16') if handshake.read_bytes().startswith(b'\xff\xfe') else handshake.read_text(encoding='utf8'),encoding='utf8',newline='\n')
    for name in ['snapshot-encoder-final','tcp-tunnel-final']:
        path=handshake.with_name(name+'.log')
        (OUT/(name+'.txt')).write_text(path.read_text(encoding='utf-16') if path.read_bytes().startswith(b'\xff\xfe') else path.read_text(encoding='utf8'),encoding='utf8',newline='\n')
    checks_by_name={c['name']:c['status'] for r in reports for c in r['checks'] if 'name' in c and 'status' in c}
    def all_pass(*names):return all(checks_by_name.get(n)=='pass' for n in names)
    # A newer failed run must not be hidden behind an earlier short pass.
    candidates=sorted((r for r in reports if r['id'].startswith('bank-vps-candidate-')),key=lambda r:r['id'])
    latest_candidate=candidates[-1] if candidates else None
    paired=bool(latest_candidate and all(any(c.get('players')==n and c.get('packaged_soak')=='pass' for c in latest_candidate['checks']) for n in [2,4]))
    ui=bool(latest_candidate and any(c.get('ui')=='pass' for c in latest_candidate['checks']))
    checks=[{'name':'vps_fix_native_enet_handshake','status':'pass' if 'BANK_ENET_CLIENT_HANDSHAKE_PASS' in (OUT/'handshake.txt').read_text(encoding='utf8') else 'fail'},
        {'name':'vps_fix_pose_and_ragdoll_equivalence','status':'pass' if all_pass('verify_coop_pose_equivalence') else 'fail'},
        {'name':'vps_fix_bounded_snapshot_and_tcp_transport','status':'pass' if all_pass('verify_snapshot_delta','verify_network_components') and 'BANK_TCP_TUNNEL_PASS' in (OUT/'tcp-tunnel-final.txt').read_text() and 'BANK_SNAPSHOT_ENCODER_PASS' in (OUT/'snapshot-encoder-final.txt').read_text() else 'fail'},
        {'name':'vps_fix_disconnect_recovery','status':'pass' if all_pass('bank_network_recovery','tcp_socket_reset_recovery','tcp_voluntary_leave_and_replacement') else 'fail'},
        {'name':'vps_fix_repeated_2p_4p_battle','status':'fail','detail':'Six hotspot windows pass network/gameplay; original-network repeat still has a stall/reconnect counterexample.'},
        {'name':'vps_fix_2p_4p_packaged_soak','status':'pass' if paired else 'fail'},
        {'name':'vps_fix_cpu_capacity','status':'pass' if all(b['within_budget'] for b in battles) else 'fail'},
        {'name':'vps_fix_release_ui','status':'pass' if ui else 'not_run'},
        {'name':'vps_fix_production_updated','status':'not_run','detail':'Release gate not accepted; old production retained.'}]
    report={'task':'BANK-VPS-FIX-011','status':'in_progress','production_updated':False,'production_final':service,'checks':checks,
        'release_gate':'Not accepted until fixed-network 2/4-player release soak and UI pass. CPU budget and known 30% loss failure remain independent limitations.',
        'candidate':'20261018-211024','reports':reports,'battles':battles,'performance_sources':sources,
        'sources':{name:digest(ROOT/name) for name in read(ROOT/'logs/network/bank-wan-fix-20261018/owned-files.json')},
        'packages':{name:read(ROOT/f'build/bank/combat-coop/20261018-211024/{name}/package/build.json') for name in ['windows','linux']},
        'limitations':['Debug battle timing is not release timing; 45-second windows are not long-soak certification.',
            'Initial enemies can die during combat, so these are not constant living-enemy loads.',
            'No claim that original-network seconds-long independent echo stalls are fixed.',
            '30% bidirectional UDP loss did not pass; UDP-to-TCP fallback takes about 35.6 seconds.',
            'Runtime art approval is not inferred; v46 bake and 54 client fixtures retained.']}
    write(OUT/'report.json',report)
    rows=''.join('<tr>'+''.join(f'<td>{html.escape(str(v))}</td>' for v in [b['network'],b['config']['players'],b['config']['population'],b['config']['repeat'],round(b['tick_hz'],2),round(b['script_tick_ms']['p95'],2),'无' if not b['issues'] else b['issues'],'通过' if b['within_budget'] else '未全部通过'])+'</tr>' for b in battles)
    checks=''.join(f'<li><a href="runs/{r["id"]}.json">{r["id"]}</a> — {html.escape(str(r["failure"] or [(x.get("name",x.get("players","ui")),x.get("status",x.get("packaged_soak",x.get("ui")))) for x in r["checks"]])[:220])}</li>' for r in reports)
    pictures=''.join(f'<figure><figcaption>{label}（固定模拟步进，非帧率证据）</figcaption><a href="{name}.jpg"><img src="{name}.jpg" loading="lazy"></a></figure>' for name,label in [('door_close','关门连续帧'),('corpse_fall','倒地连续帧'),('corpse_shot_wake','尸体受击'),('predicted_walk','本地移动预测'),('predicted_fire','即时开火反馈')])
    pictures='<p>原网络有效发布验收：两人 180 秒累计 1 次重连；四人 180 秒累计 3 次重连。UI 功能通过，稳定性失败。正式服务已恢复 v5、0/4，未发布候选包。</p><figure><figcaption>满员 UI；localhost 仍为配对旧版，正确显示版本不匹配</figcaption><img src="vps-online-full.png"></figure><figure><figcaption>从菜单补位进入银行。此处是冻结截图，HUD FPS 不能作为性能测量；存活队友可以继续战斗。</figcaption><img src="vps-browser-entered-bank.png"></figure>'+pictures
    (OUT/'gallery.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>银行公网修复 · 验收记录</title><style>body{font:16px/1.7 system-ui;background:#111b21;color:#e3ecee;max-width:1200px;margin:auto;padding:32px}h1{color:#e4c087}a{color:#8ed3f5}table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:9px;border-bottom:1px solid #3a474f}img{width:100%}figure{margin:30px 0}li{margin:10px 0;overflow-wrap:anywhere}.note{border-left:4px solid #d6a354;padding:14px;background:#25313a}</style><h1>银行公网同步修复与 VPS 复测</h1><p class="note">仍在验收：候选包不等于正式上线。热点短时战斗无网络问题；原网络存在反例，严格 60 Hz 预算仍未全部通过。正式服务状态以 report.json 和运维文档为准。</p><p><a href="report.json">结构化报告</a> · <a href="../../../docs/bank-vps-stability.md">实现与限制</a> · <a href="handshake.txt">原生 ENet 握手回归</a></p><h2>相同公网 VPS，战斗窗口</h2><p>单位：服务端 Hz、脚本 P95 毫秒。敌人数是初始布置量，非恒定活体数。</p><table><tr><th>线路</th><th>玩家</th><th>敌人</th><th>轮次</th><th>Hz</th><th>P95 ms</th><th>网络/战斗问题</th><th>60 Hz 全部预算</th></tr>'''+rows+'</table><h2>本地与发布验证（含失败）</h2><ul>'+checks+'</ul><h2>实际连续画面</h2>'+pictures+'</html>',encoding='utf8',newline='\n')
    write(OUT/'manifest.json',{'files':{p.relative_to(OUT).as_posix():digest(p) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='manifest.json'}})
    print(OUT)

if __name__=='__main__':main()
