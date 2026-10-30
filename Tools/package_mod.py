"""Generate a hashed BMF archive from a mod directory; never include user data."""
import argparse, hashlib, json, re, zipfile
from pathlib import Path, PurePosixPath

def validate(m):
    assert m.get('schema_version') == 1 and re.fullmatch(r'[A-Za-z0-9_-]{1,64}',m['id'])
    assert re.fullmatch(r'\d+\.\d+\.\d+(?:-[\w.-]+)?',m['version']) and m['name']
    assert m.get('api') and len(m['files']) <= 4096
    seen = set(); total = 0
    for f in m['files']:
        raw = f['path']; parts = PurePosixPath(raw).parts
        assert parts and not raw.startswith('/') and '\\' not in raw and ':' not in raw
        assert all(part not in ('..','.') and not part.endswith(('.',' ')) and not re.match(r'^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',part,re.I) for part in raw.split('/'))
        assert not re.search(r'(^|/)(SaveGames|preconstructions|blades|Data)(/|$)|\.(sav|log|dmp)$',raw,re.I)
        assert raw.casefold() not in seen and re.fullmatch('[a-f0-9]{64}',f['sha256']);seen.add(raw.casefold())
        assert 0 <= f['size'] <= 67108864;total += f['size']
    assert total <= 268435456

def package(folder, output):
    folder = Path(folder).resolve(); metadata=folder/'mod.json';metadata=metadata if metadata.exists() else folder/'bmf-manifest.json';manifest=json.loads(metadata.read_text(encoding='utf-8')); files={}
    for p in sorted(folder.rglob('*')):
        if not p.is_file(): continue
        rel=p.relative_to(folder).as_posix()
        if p.is_symlink(): raise ValueError('Symlink in package')
        if rel in ('mod.json','bmf-manifest.json','bmf-installed.json') or re.search(r'(^|/)(Data|preconstructions|blades|SaveGames|__pycache__)(/|$)|\.(sav|log|dmp|pyc)$',rel,re.I):continue
        files[rel]=p.read_bytes()
    manifest['files']=[dict(path=n,size=len(data),sha256=hashlib.sha256(data).hexdigest()) for n,data in files.items()]
    validate(manifest)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=9)as z:
        z.writestr('mod.json',json.dumps(manifest,indent=2))
        for name,data in files.items():z.writestr(name,data)
    with zipfile.ZipFile(output)as z:assert z.testzip() is None
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('folder');p.add_argument('output');a=p.parse_args();package(a.folder,a.output)
