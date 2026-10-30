from pathlib import Path
import hashlib,json,zipfile
from package_mod import package
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'Releases';OUT.mkdir(exist_ok=True)
source=ROOT/'Source/PreconstructionLibraryProbe';meta=json.loads((source/'mod.json').read_text());version=meta['version']
assert len(list((source/'Scripts').glob('*.dll')))==9,'Build the nine Main helper DLLs first'
manual=OUT/f'PreconstructionLibrary_{version}_Runtime.zip'
with zipfile.ZipFile(manual,'w',zipfile.ZIP_DEFLATED)as z:
 for p in sorted(source.rglob('*')):
  if not p.is_file():continue
  relative=p.relative_to(source).as_posix()
  assert not any(x in relative.split('/')for x in ['preconstructions','blades','Data','SaveGames'])
  z.write(p,'Bladesong/Binaries/Win64/ue4ss/Mods/PreconstructionLibraryProbe/'+relative)
 for p in sorted((ROOT/'Assets/Cooked').glob('PCLAnchor.*')):z.write(p,'Bladesong/Content/Paks/LogicMods/'+p.name)
 z.write(ROOT/'LICENSE','LICENSE_PreconstructionLibrary.txt');z.write(ROOT/'THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES_PreconstructionLibrary.md')
bmf=OUT/f'PreconstructionLibrary_{version}_BMF.zip';release=package(source,bmf)
release['repository']='https://github.com/LTR-JT/PreconstructionLibrary'
release['download']={'url':f'https://github.com/LTR-JT/PreconstructionLibrary/releases/download/v{version}/{bmf.name}','sha256':hashlib.sha256(bmf.read_bytes()).hexdigest()}
(OUT/'mod.json').write_text(json.dumps(release,indent=2)+'\n',encoding='utf-8')
for p in [manual,bmf]:
 with zipfile.ZipFile(p)as z:assert z.testzip()is None
(OUT/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n'for p in [manual,bmf]),encoding='utf-8')
print('Prepared PCL runtime, in-game archive, manifest and checksums:',OUT)
