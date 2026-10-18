"""Package bank optimization comparison with exact measured sources and verification evidence."""
import argparse, hashlib, html, json, statistics, sys, zipfile
from pathlib import Path
from game.tools.package_coop_performance import main as package_performance

def read(path):return json.loads(path.read_text(encoding='utf8'))
def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf8')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--performance',type=Path,required=True)
    p.add_argument('--baseline',type=Path,required=True)
    p.add_argument('--regression',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--verification',action='append',default=[],help='label=folder, archived without editing')
    args=p.parse_args();out=args.output.resolve()
    original=sys.argv
    try:
        sys.argv=[original[0],'--session',str(args.performance),'--output',str(out),'--regression',str(args.regression)]
        package_performance()
    finally:sys.argv=original
    baseline=read(args.baseline/'report.json');report=read(out/'report.json')
    report['runtime_changes']='Infected dirty-bone reads and typed hit/crowd references; replica hit areas disabled; hidden/static presentation skipped; acknowledged-base deltas with reliable keyframes. Graphics/lighting/collision rules unchanged.'
    report['baseline']={'path':str(args.baseline),'report_sha256':sha(args.baseline/'report.json'),'manifest_sha256':sha(args.baseline/'manifest.json')}
    comparison=[]
    for key,after in report['groups'].items():
        if key not in baseline['groups'] or after['diagnostic']:continue
        before=baseline['groups'][key]
        a=[x for x in report['rows'] if x['id']==key];b=[x for x in baseline['rows'] if x['id']==key]
        values={}
        for metric in ['fps','frame_p95_ms','server_p95_ms','server_tick_hz','server_up_kib_s','client_script_mean_ms','server_script_mean_ms']:
            old=statistics.mean(x[metric] for x in b);new=statistics.mean(x[metric] for x in a)
            values[metric]={'before':[min(x[metric] for x in b),max(x[metric] for x in b)],'after':[min(x[metric] for x in a),max(x[metric] for x in a)],'mean_change_pct':(new/old-1)*100}
        comparison.append({'id':key,'label':after['label'],'metrics':values})
    report['comparison']=comparison
    evidence={};archives={}
    with zipfile.ZipFile(out/'verification-evidence.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for item in args.verification:
            label,folder=item.split('=',1);folder=Path(folder)
            assert folder.is_dir(),folder
            evidence[label]={'folder':str(folder),'reports':[]}
            for path in sorted(folder.rglob('*')):
                if not path.is_file() or path.suffix not in ['.json','.jsonl','.gd','.py','.log','.txt','.jpg','.webp']:continue
                key=label+'/'+path.relative_to(folder).as_posix();archive.write(path,key);archives[key]=sha(path)
                if path.name=='report.json':evidence[label]['reports'].append({'path':key,'sha256':sha(path)})
    report['verification']=evidence
    write(out/'report.json',report)
    def span(values):return f'{values[0]:.1f}–{values[1]:.1f}'
    rows=[]
    for item in comparison:
        cells=[html.escape(item['label'])]
        for metric in ['fps','server_p95_ms','server_tick_hz','server_up_kib_s']:
            value=item['metrics'][metric];cells.append(span(value['before'])+' → '+span(value['after']))
        rows.append('<tr>'+''.join('<td>'+c+'</td>' for c in cells)+'</tr>')
    page=['<!doctype html><meta charset="utf-8"><title>银行联机优化 1、3 · 对照报告</title><style>body{max-width:1500px;margin:32px auto;padding:0 24px;background:#111a18;color:#e1e8e3;font:17px/1.7 system-ui}a{color:#e0be7b}table{width:100%;border-collapse:collapse;font-size:15px}td,th{padding:12px;border-bottom:1px solid #3c5045;text-align:left}img{max-width:100%}details{padding:14px 0}.note{color:#e3ba79}</style>',
      '<h1>银行多人战斗：感染者计算与增量复制优化</h1>',
      '<p>同一台 Windows 机器、原 1080p 画质和吊灯/阴影，真实专用服务端 + 2/4 个客户端，其中一个渲染。8 个案例各预热 3 秒、测量 16 秒、重复 2 次。正常输入触发射击、装填、推搡和移动。范围是两轮值，并非置信区间。</p>',
      '<p class="note">同机竞争和战斗结果有波动；相同输入策略不等于每帧完全相同的敌人/尸体数量。服务端单步 P95 超过 16.67 ms 的案例仍未达到稳定 60 Hz。此报告不证明 2 核 VPS 容量、长期稳定性或所有弱网条件达标。</p>',
      '<p><a href="../../../docs/bank-coop-optimization.md">实现、验证与剩余瓶颈</a> · <a href="report.json">完整对照</a> · <a href="metrics.csv">优化后逐轮 CSV</a> · <a href="raw-evidence.zip">性能原始数据和精确源码</a> · <a href="verification-evidence.zip">定向回归、弱网与动态证据</a></p>',
      '<table><tr><th>案例</th><th>平均 FPS：前 → 后</th><th>服务端步 P95 ms</th><th>实际服务端 Hz</th><th>服务端发送 KiB/s</th></tr>',*rows,'</table>',
      '<h2>画面检查</h2><p>截图在采样结束后冻结场景取得，HUD FPS 是静止时的值，不用于性能统计。高血量为诊断夹具；未改变正式玩法平衡。近距离拥挤和模型遮挡保留在证据中；最终动作观感仍由用户试玩判断。</p><img src="interiors.jpg">']
    for row in report['rows']:page.append(f'<details><summary>{html.escape(row["label"])} · 第 {row["repeat"]} 轮 · {row["fps"]:.1f} FPS</summary><img loading="lazy" src="{row["evidence"]}.webp"></details>')
    (out/'gallery.html').write_text('\n'.join(page),encoding='utf8')
    manifest=read(out/'manifest.json');manifest['verification_archive_sha256']=archives
    manifest['files']={path.name:sha(path) for path in out.iterdir() if path.is_file() and path.name!='manifest.json'}
    write(out/'manifest.json',manifest)

if __name__=='__main__':main()
