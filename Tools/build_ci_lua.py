"""Build pinned upstream Lua in CI; not part of player installation."""
import hashlib,os,subprocess,tarfile,urllib.request,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];target=ROOT/'Tests/ci-lua';target.mkdir(exist_ok=True)
archive=target/'lua.tar.gz'
urllib.request.urlretrieve('https://www.lua.org/ftp/lua-5.4.8.tar.gz',archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae'
with tarfile.open(archive)as t:
 for member in t.getmembers():
  dest=(target/member.name).resolve();assert dest.is_relative_to(target.resolve())and not member.issym()and not member.islnk()
 t.extractall(target,filter='data')
from msvc import environment
env=environment()
source=target/'lua-5.4.8/src';files=[str(f)for f in source.glob('*.c')if f.name!='luac.c']
subprocess.run([shutil.which('cl.exe',path=env['PATH']),'/nologo','/O2','/DLUA_USE_WINDOWS',f'/Fe:{target.resolve()}/lua.exe',*files],cwd=source,env=env,check=True)
print(target/'lua.exe')
