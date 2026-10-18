#!/usr/bin/env bash
# Install a verified immutable release. Requires root; touches only bank-coop.
set -euo pipefail
archive=${1:?usage: install_bank.sh archive.zip release-id}
release_id=${2:?release-id required}
[[ "$release_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$ ]] || exit 2
[[ $(id -u) == 0 ]] || { echo 'Run with sudo'; exit 2; }
root=/opt/bank-coop
release="$root/releases/$release_id"
[[ ! -e "$release" ]] || { echo "Release already exists: $release"; exit 2; }
if [[ -f /etc/systemd/system/bank-coop.service ]]; then
    grep -q 'Description=Bank Crisis ENet co-op server' /etc/systemd/system/bank-coop.service || { echo 'Unexpected existing unit'; exit 2; }
fi
getent passwd bankcoop >/dev/null || useradd --system --user-group --home-dir /var/lib/bank-coop --shell /usr/sbin/nologin bankcoop
install -d -m 755 "$root/releases" "$release"
python3 - "$archive" "$release" <<'PY'
import hashlib,json,pathlib,sys,zipfile
dest=pathlib.Path(sys.argv[2]).resolve()
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        target=(dest/name).resolve()
        if not target.is_relative_to(dest):raise ValueError('Invalid archive path')
    z.extractall(dest)
build=json.loads((dest/'build.json').read_text())
assert build['platform']=='linux' and build['wire_protocol']==4
binary=dest/build['executable']
assert binary.parent==dest and hashlib.sha256(binary.read_bytes()).hexdigest()==build['sha256']
print(json.dumps({'engine':build['engine'],'build':build['network_build'],'sha256':build['sha256']}))
PY
chmod 755 "$release/bank-coop-server.x86_64"
chown -R root:root "$release"
ldd "$release/bank-coop-server.x86_64" | tee "$release/runtime-libraries.txt"
! grep -q 'not found' "$release/runtime-libraries.txt"
previous=$(readlink -f "$root/current" || true)
rollback() {
    if [[ -n "$previous" && -d "$previous" ]]; then
        ln -sfn "$previous" "$root/current.new"; mv -Tf "$root/current.new" "$root/current"
        install -m 644 "$previous/bank-coop.service" /etc/systemd/system/bank-coop.service
        systemctl daemon-reload
        systemctl restart bank-coop.service
    fi
}
if [[ -n "$previous" && -d "$previous" ]]; then
    ln -sfn "$previous" "$root/previous"
fi
install -m 644 "$release/bank-coop.service" /etc/systemd/system/bank-coop.service
ln -sfn "$release" "$root/current.new"
mv -Tf "$root/current.new" "$root/current"
if ! systemd-analyze verify /etc/systemd/system/bank-coop.service; then
    rollback
    exit 1
fi
systemctl daemon-reload
systemctl enable bank-coop.service
if ! systemctl restart bank-coop.service; then
    rollback
    exit 1
fi
if ! python3 - "$release/build.json" <<'PY'
import json,socket,time,uuid,sys
build=json.load(open(sys.argv[1]))
deadline=time.monotonic()+120
while time.monotonic()<deadline:
    nonce=uuid.uuid4().hex
    with socket.socket(type=socket.SOCK_DGRAM) as sock:
        sock.settimeout(1)
        sock.sendto(json.dumps({'magic':'BANK_STATUS_1','query':True,'nonce':nonce,'padding':' '*192}).encode(),('127.0.0.1',24568))
        try:
            row=json.loads(sock.recv(512))
            if row.get('nonce')==nonce and row.get('build')==build['network_build'] and row.get('capacity')==4:
                print(json.dumps(row));break
        except (OSError,ValueError):pass
    time.sleep(1)
else:raise SystemExit('Server did not answer discovery within 120 seconds')
PY
then
    rollback
    exit 1
fi
systemctl show bank-coop.service -p ActiveState -p MainPID -p MemoryCurrent -p NRestarts
