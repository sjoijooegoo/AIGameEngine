"""Archive current-bank multiplayer performance measurements and visual evidence."""
import argparse,csv,hashlib,html,json,shutil,statistics,zipfile
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from game.tools.coop import ROOT

def load(p):return json.loads(p.read_text(encoding='utf8'))
def save(p,value):p.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--session',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--regression',type=Path,required=True);parser.add_argument('--pilot',type=Path,action='append',default=[]);args=parser.parse_args()
    session=args.session.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    report=load(session/'report.json');assert report['passed'] and len(report['cases'])>=16
    regression=load(args.regression/'report.json');assert len(regression['checks'])==15 and all(c['status']=='pass' for c in regression['checks'])
    groups={};rows=[];contacts=[];capture_hashes={}
    for case in report['cases']:
        config=case['config'];client=case['results']['client-1'];server=case['results']['server']
        row={'id':config['id'],'repeat':config['repeat'],'diagnostic':config.get('diagnostic_only',False),'label':config['label'],
          'players':config['players'],'population':config['population'],'fps':client['fps_average'],'low1_fps':client['fps_1pct_low'],
          'frame_p95_ms':client['frame_ms']['p95'],'frame_p99_ms':client['frame_ms']['p99'],'server_p95_ms':server['script_tick_ms']['p95'],
          'server_tick_hz':server['tick_hz'],'client_script_mean_ms':client['script_tick_ms']['mean'],'server_script_mean_ms':server['script_tick_ms']['mean'],
          'gpu_world_mean_ms':client['gpu_ms']['world']['mean'],'draw_calls_mean':client['monitors']['draw_calls']['mean'],
          'render_cpu_mean_ms':client['render_cpu_ms']['world']['mean'],
          'server_up_kib_s':server['network_kib_s']['sent_bytes'],'server_down_kib_s':server['network_kib_s']['received_bytes'],
          'server_rss_mb':server['rss_mb']['max'],'server_cpu_one_core_pct':server['os_cpu_one_core_pct']['mean'],
          'kills':server['finish']['kills'],'living_end':server['finish']['alive'],
          'actually_loaded_rounds':sum(server['finish'].get('loaded_rounds',{}).values()),
          'server_60hz_step_budget':server['script_tick_ms']['p95']<=1000/60,
          'client_60fps_p95_budget':client['frame_ms']['p95']<=1000/60,
          'evidence':case['evidence']}
        rows.append(row);groups.setdefault(config['id'],[]).append(row)
        im=Image.open(session/case['evidence']/'combat.png').convert('RGB')
        im.save(out/(case['evidence']+'.webp'),lossless=True,method=4)
        assert Image.open(out/(case['evidence']+'.webp')).convert('RGB').tobytes()==im.tobytes()
        capture_hashes[case['evidence']+'/combat.png']=sha(session/case['evidence']/'combat.png')
        if config['repeat']==1 and not config.get('diagnostic_only'):contacts.append((config['label'],im.copy()))
    with (out/'metrics.csv').open('w',encoding='utf8',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=rows[0]);writer.writeheader();writer.writerows(rows)
    metrics={k:{'label':v[0]['label'],'diagnostic':v[0]['diagnostic'],'runs':len(v),
      'ranges':{metric:[min(r[metric] for r in v),max(r[metric] for r in v)] for metric in ['fps','low1_fps','frame_p95_ms','server_p95_ms','server_tick_hz','server_up_kib_s']},
      'means':{metric:statistics.mean(r[metric] for r in v) for metric in ['fps','frame_p95_ms','gpu_world_mean_ms','render_cpu_mean_ms','draw_calls_mean','client_script_mean_ms','server_script_mean_ms','server_cpu_one_core_pct']}} for k,v in groups.items()}
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
    sheet=Image.new('RGB',(480*2,302*((len(contacts)+1)//2)),(16,23,23));draw=ImageDraw.Draw(sheet)
    for i,(label,im) in enumerate(contacts):
        x=(i%2)*480;y=(i//2)*302;sheet.paste(im.resize((480,270)),(x,y));draw.text((x+8,y+273),label,font=font,fill=(223,201,149))
    sheet.save(out/'interiors.jpg',quality=92)
    for name in ['report.json','sources.json','plan.json']:shutil.copy2(session/name,out/('measured-'+name))
    shutil.copy2(args.regression/'report.json',out/'combat-regression.json')
    evidence={}
    with zipfile.ZipFile(out/'raw-evidence.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for label,folder in [('final',session),('regression',args.regression),*[(f'pilot-{i+1}',p) for i,p in enumerate(args.pilot)]]:
            for path in sorted(folder.rglob('*')):
                if path.is_file() and path.suffix in ['.json','.jsonl','.log','.txt','.gd','.py']:
                    key=label+'/'+path.relative_to(folder).as_posix();archive.write(path,key);evidence[key]=sha(path)
        for relative,expected in load(session/'sources.json').items():
            path=ROOT/relative;assert sha(path)==expected,relative
            key='measured-sources/'+relative;archive.write(path,key);evidence[key]=expected
    checks=[{'name':name,'status':'pass','evidence':'measured-report.json'} for name in ['coop_perf_valid_placements','coop_perf_real_combat','coop_perf_multiple_interiors','coop_perf_repeated_samples','coop_perf_runtime_errors_absent']]
    checks+=regression['checks']
    unit_log=session/'report-unit.log'
    if unit_log.exists():
        text=unit_log.read_text(encoding='utf8')
        assert 'Ran 4 tests' in text and '\nOK\n' in text
        checks.append({'name':'coop_perf_report_semantics','status':'pass','tests':4,'evidence':'raw-evidence.zip/final/report-unit.log'})
    save(out/'report.json',{'scope':'Performance measurement validity, not target-frame-rate or VPS certification.','checks':checks,'rows':rows,'groups':metrics,
      'sample_seconds':load(session/'plan.json')['measure_seconds'],'rendered_clients':1,'sources':'measured-sources.json',
      'runtime_changes':'Opt-in profiling only in bank_game/bank_session; no gameplay/graphics/network setting changes.',
      'limits':['Single Windows host shares CPU/memory/thermal budget across server and clients; not remote VPS measurement.',
                'Script scopes inclusive, GPU delayed, process CPU 100% is one logical core. Frames include driver and OS work.',
                'Diagnostic players start with 10000 HP; all damage and normal ammo/reload remain. Not a survivability test.',
                'Enemies die; live/corpse counts and kills vary. Same policy is not identical frame-by-frame workload.',
                'Some stress runs miss server tick budget. Higher client FPS in a diagnostic does not establish healthy server simulation.',
                'Shutdown Texture RID warnings pre-exist; short measurements do not establish long-soak memory stability.'],
      'user_visual_acceptance':'not_requested_or_inferred'})
    def ran(values,dec=1):return f'{min(values):.{dec}f}–{max(values):.{dec}f}'
    heavy=groups['hall_4p_84']
    heavy_results=[c['results']['server'] for c in report['cases'] if c['config']['id']=='hall_4p_84']
    infected_pct=100*sum(r['scopes_ms']['server_infected']['mean'] for r in heavy_results)/sum(r['script_tick_ms']['mean'] for r in heavy_results)
    path_ms=[r['scopes_ms']['pathfinding']['mean'] for r in heavy_results]
    send_ms=[r['scopes_ms']['server_snapshot_send']['mean'] for r in heavy_results]
    table=[]
    for key,runs in groups.items():
        table.append('<tr><td>'+html.escape(runs[0]['label'])+'</td>'+''.join('<td>'+ran([r[k] for r in runs],2 if 'ms' in k else 1)+'</td>' for k in ['fps','low1_fps','frame_p95_ms','server_p95_ms','server_tick_hz','server_up_kib_s'])+'</tr>')
    page=['<!doctype html><meta charset="utf-8"><title>银行多人室内战斗性能</title><style>body{max-width:1550px;margin:32px auto;padding:0 22px;background:#101817;color:#e5ebe7;font:17px/1.65 system-ui}a{color:#dab46c}table{border-collapse:collapse;width:100%;font-size:15px}td,th{border-bottom:1px solid #40564b;padding:9px;text-align:right}td:first-child,th:first-child{text-align:left}img{max-width:100%}details{padding:16px 0}h2{margin-top:38px}.note{color:#deb676}figure{margin:20px 0}</style>',
      '<h1>多人银行室内战斗性能 · 2026-10-18</h1><p>22 次有效采样，五种室内区域；2/4 玩家、24/32/64/84 名感染者。每例预热 3 秒、测量 16 秒、重复 2 次。一个渲染客户端、其他客户端与服务端无渲染，均在同一台 Windows 机器。</p>',
      '<p>i9-13900HX / RTX 5070 Ti Laptop，Godot 4.7.2 调试版，Forward+，默认 1080p 原生比例、原有吊灯/烘焙/MSAA，VSync 关闭。表中范围为两轮实测值，1% Low 为最慢 1% 帧平均耗时的倒数。</p>',
      f'<p class="note">有效采样不等于性能达标。84 敌大厅客户端 {ran([r["fps"] for r in heavy])} FPS，服务器约 {ran([r["server_tick_hz"] for r in heavy])}Hz。单步预算为 16.67ms。关闭阴影诊断提升了画面帧率，但没有解决服务端更新过慢。</p>',
      '<p><a href="../../../docs/bank-coop-performance.md">瓶颈分析与优化顺序</a> · <a href="metrics.csv">逐轮 CSV</a> · <a href="report.json">汇总 JSON</a> · <a href="raw-evidence.zip">原始帧、tick、输入计划与失败记录</a></p>',
      '<table><tr><th>案例</th><th>平均 FPS</th><th>1% Low</th><th>帧 P95 ms</th><th>服务端步 P95 ms</th><th>实际 tick Hz</th><th>服务端发送 KiB/s</th></tr>',*table,'</table>',
      f'<h2>主要结论</h2><p>客户端优先检查动态阴影提交和可见感染者呈现；服务端优先检查姿态/命中体、密集移动与布娃娃。84 敌大厅的感染者区段约占脚本耗时 {infected_pct:.1f}%，寻路约 {ran(path_ms,3)}ms/步，快照发送平均约 {ran(send_ms,3)}ms/步。网络流量和死亡角色状态仍值得优化，但不是本次服务端 CPU 的首要成本。</p>',
      '<p>诊断组同样可能掉服务器 tick；不能只看客户端 FPS 判断完整会话性能。物理接触、尸体、摄像机朝向和同机争用也不同，不能把诊断结果当成可交付优化的精确收益承诺。第一版路线会打断装填，已保留到过程归档；本页采用提前装填且检查实际弹匣增加的第二版路线。</p>',
      '<h2>当前室内实际画面</h2><p>下图来自每条路线结束后的真实渲染；所有高血量均为初始诊断夹具，非正式平衡调整。采样结束才截图，HUD FPS 是结束后的静止值，不代表上表测量窗口。</p><img src="interiors.jpg">']
    for row in rows:
        page.append(f'<details><summary>{html.escape(row["label"])} · 第 {row["repeat"]} 轮 · {row["fps"]:.1f} FPS / 服务端 {row["server_tick_hz"]:.1f}Hz</summary><img loading="lazy" src="{row["evidence"]}.webp"></details>')
    (out/'gallery.html').write_text('\n'.join(page),encoding='utf8')
    save(out/'manifest.json',{'raw_sha256':evidence,'original_capture_sha256':capture_hashes,'capture_encoding':'Lossless WebP decoded RGB verified identical to original PNG.','files':{p.name:sha(p) for p in out.iterdir() if p.is_file() and p.name!='manifest.json'}})
    print(json.dumps({'output':str(out),'cases':len(rows),'mb':sum(p.stat().st_size for p in out.iterdir() if p.is_file())/1048576},indent=2))

if __name__=='__main__':main()
