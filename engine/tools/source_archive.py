"""Read-only Source VPK v1/v2 inventory and CRC-checked selective extraction."""
from pathlib import Path, PurePosixPath
import argparse, fnmatch, hashlib, json, struct, zlib


class VPK:
    def __init__(self, path):
        self.path = Path(path)
        with self.path.open('rb') as f:
            magic, version, size = struct.unpack('<III', f.read(12))
            if magic != 0x55AA1234 or version not in (1, 2):
                raise ValueError('Unsupported VPK header')
            self.header_size = 28 if version == 2 else 12
            f.seek(self.header_size)
            tree = f.read(size)
        self.data_start = self.header_size + size
        self.entries = {}
        at = 0

        def string():
            nonlocal at
            end = tree.index(b'\0', at)
            value = tree[at:end].decode('latin1')
            at = end + 1
            return value

        while ext := string():
            while directory := string():
                while name := string():
                    crc, preload, archive, offset, length, end = struct.unpack_from('<IHHIIH', tree, at)
                    at += 18
                    if end != 0xffff:
                        raise ValueError('Invalid VPK entry terminator')
                    key = ('' if directory == ' ' else directory + '/') + name + ('' if ext == ' ' else '.' + ext)
                    rel = PurePosixPath(key)
                    if rel.is_absolute() or '..' in rel.parts or '\\' in key or ':' in key:
                        raise ValueError('Unsafe VPK member')
                    self.entries[key.lower()] = (crc, archive, offset, length, tree[at:at + preload])
                    at += preload

    def read(self, key):
        crc, archive, offset, length, preload = self.entries[key.lower()]
        path = self.path if archive == 0x7fff else self.path.with_name(self.path.name.replace('_dir.vpk', f'_{archive:03}.vpk'))
        with path.open('rb') as f:
            f.seek(offset + (self.data_start if archive == 0x7fff else 0))
            data = preload + f.read(length)
        if len(data) != len(preload) + length or zlib.crc32(data) & 0xffffffff != crc:
            raise ValueError(f'Truncated or corrupt VPK member: {key}')
        return data


class Installation:
    # Game search paths: updated assets override DLC/base files.
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.entries = {}
        for folder in ('update', 'left4dead2_dlc3', 'left4dead2_dlc2', 'left4dead2_dlc1', 'left4dead2'):
            path = self.root / folder / 'pak01_dir.vpk'
            if not path.exists():
                continue
            archive = VPK(path)
            for key in archive.entries:
                self.entries.setdefault(key, archive)

    def extract(self, keys, destination):
        destination = Path(destination).resolve()
        if destination == self.root or self.root in destination.parents:
            raise ValueError('Never write into the game installation')
        items = []
        for key in sorted(set(keys)):
            archive = self.entries[key]
            data = archive.read(key)
            target = (destination / key).resolve()
            if destination not in target.parents:
                raise ValueError('Extraction escaped destination')
            if target.exists() and target.read_bytes() != data:
                raise FileExistsError(f'Immutable snapshot differs: {target}')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            items.append(dict(path=key, archive=str(archive.path), size=len(data), sha256=hashlib.sha256(data).hexdigest()))
        return items


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--pattern', action='append', default=[])
    parser.add_argument('--output', required=True)
    parser.add_argument('--extract')
    args = parser.parse_args()
    install = Installation(args.root)
    keys = [k for k in install.entries if any(fnmatch.fnmatchcase(k, p) for p in args.pattern)]
    items = install.extract(keys, args.extract) if args.extract else [dict(path=k, archive=str(install.entries[k].path)) for k in sorted(keys)]
    report = dict(root=str(install.root), total_entries=len(install.entries), selected=len(items), items=items)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(dict(total=report['total_entries'], selected=len(items), report=args.output)))


if __name__ == '__main__':
    main()
