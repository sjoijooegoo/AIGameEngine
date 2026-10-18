"""Read Linux counters into memory; write only after the sampling window."""
import argparse
import json
import os
import time
from pathlib import Path


def fields(path):
    return {k: v.strip() for k, v in (line.split(':', 1) for line in Path(path).read_text().splitlines() if ':' in line)}


def sample(pid):
    status = fields(f'/proc/{pid}/status')
    stat = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    memory = fields('/proc/meminfo')
    threads = {}
    for path in Path(f'/proc/{pid}/task').glob('*/stat'):
        try:
            content = path.read_text()
            values = content.rsplit(')', 1)[1].split()
            threads[path.parent.name] = {'name': content.split('(', 1)[1].rsplit(')', 1)[0],
                                         'cpu_seconds': (int(values[11])+int(values[12]))/os.sysconf('SC_CLK_TCK')}
        except FileNotFoundError:
            pass
    return {'time': time.time(), 'monotonic': time.monotonic(),
            'cpu_seconds': (int(stat[11])+int(stat[12]))/os.sysconf('SC_CLK_TCK'),
            'rss_mb': int(status['VmRSS'].split()[0])/1024,
            # Not Windows Private Bytes. Kept null to prevent false comparisons.
            'private_mb': None,
            'rss_peak_mb': int(status['VmHWM'].split()[0])/1024,
            'swap_mb': int(status['VmSwap'].split()[0])/1024,
            'mem_available_mb': int(memory['MemAvailable'].split()[0])/1024,
            'mem_total_mb': int(memory['MemTotal'].split()[0])/1024,
            'system_cpu': [int(x) for x in Path('/proc/stat').read_text().splitlines()[0].split()[1:]],
            'threads': threads,
            'pressure': {k: Path('/proc/pressure/'+k).read_text() for k in ['cpu', 'memory', 'io']}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--start', type=float, required=True)
    parser.add_argument('--seconds', type=float, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert 5 <= args.seconds <= 60
    rows = []
    time.sleep(max(0, args.start-time.time()))
    finish = time.monotonic()+args.seconds
    while time.monotonic() < finish:
        rows.append(sample(args.pid))
        time.sleep(min(.5, max(0, finish-time.monotonic())))
    args.output.write_text(json.dumps(rows), encoding='utf8')


if __name__ == '__main__':
    main()
