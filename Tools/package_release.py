from pathlib import Path
import hashlib,json,zipfile,tempfile,shutil
from package_mod import package
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'Releases';OUT.mkdir(exist_ok=True)
source=ROOT/'Source/PreconstructionLibraryProbe';meta=json.loads((source/'mod.json').read_text());version=meta['version']
assert len(list((source/'Scripts').glob('*.dll')))==9,'Build the nine Main helper DLLs first'
manual=OUT/f'PreconstructionLibrary_{version}_Runtime.zip'
bmf=OUT/f'PreconstructionLibrary_{version}_BMF.zip'
(ROOT/'Build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=ROOT/'Build')as tmp:
 stage=Path(tmp);shutil.copytree(source,stage,dirs_exist_ok=True);assets=stage/'assets/logicmods';assets.mkdir(parents=True)
 for suffix in ['pak','ucas','utoc']:
  p=ROOT/'Assets/Cooked'/('PCLAnchor.'+suffix);assert p.is_file(),p;shutil.copyfile(p,assets/p.name)
 shutil.copytree(ROOT/'Assets/LogicMods/PCLAnchor',assets/'PCLAnchor')
 release=package(stage,bmf)
release['repository']='https://github.com/LTR-JT/PreconstructionLibrary'
release['download']={'url':f'https://github.com/LTR-JT/PreconstructionLibrary/releases/download/v{version}/{bmf.name}','sha256':hashlib.sha256(bmf.read_bytes()).hexdigest()}
(OUT/'mod.json').write_text(json.dumps(release,indent=2)+'\n',encoding='utf-8')
with zipfile.ZipFile(bmf)as source_zip,zipfile.ZipFile(manual,'w',zipfile.ZIP_DEFLATED)as z:
 prefix='Bladesong/Binaries/Win64/ue4ss/Mods/PreconstructionLibraryProbe/'
 for name in source_zip.namelist():
  if name=='mod.json':continue
  target='Bladesong/Content/Paks/LogicMods/'+name[17:]if name.startswith('assets/logicmods/')else prefix+name
  z.writestr(target,source_zip.read(name))
 for name in ['mod.json','bmf-installed.json']:z.writestr(prefix+name,json.dumps(release,indent=2)+'\n')
 z.writestr(prefix+'deployment.json',json.dumps({'schema_version':1,'owner':'manual','mod_id':'PreconstructionLibraryProbe'}))
 z.write(ROOT/'LICENSE','LICENSE_PreconstructionLibrary.txt');z.write(ROOT/'THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES_PreconstructionLibrary.md')

for p in [manual,bmf]:
 with zipfile.ZipFile(p)as z:assert z.testzip()is None
(OUT/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n'for p in [manual,bmf]),encoding='utf-8')
print('Prepared PCL runtime, in-game archive, manifest and checksums:',OUT)
