"""Locate an installed Visual Studio toolchain without a developer shell."""
import os,subprocess,shutil
from pathlib import Path
def environment():
 where=Path(os.environ.get('ProgramFiles(x86)','C:/Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
 installation=subprocess.check_output([str(where),'-latest','-products','*','-requires','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip()
 if not installation:raise SystemExit('Visual Studio C++ build tools are required')
 vcvars=Path(installation)/'VC/Auxiliary/Build/vcvars64.bat'
 wire=subprocess.check_output(f'cmd /d /s /c ""{vcvars}" >nul && set"',text=True)
 env={k.upper():v for k,v in os.environ.items()};env.update((k.upper(),v)for k,v in (line.split('=',1)for line in wire.splitlines()if '='in line and not line.startswith('=')))
 return env

def build(source,destination,workspace):
 env=environment();workspace=Path(workspace).resolve();workspace.mkdir(parents=True,exist_ok=True)
 source=Path(source).resolve();destination=Path(destination).resolve();destination.parent.mkdir(parents=True,exist_ok=True)
 obj=workspace/(source.stem+'.obj')
 compiler=shutil.which('cl.exe',path=env['PATH']);linker=shutil.which('link.exe',path=env['PATH'])
 assert compiler and linker,'MSVC compiler/linker missing from the developer environment'
 subprocess.run([compiler,'/nologo','/c','/O2','/GS-','/GR-','/Zl',f'/Fo:{obj}',str(source)],env=env,cwd=workspace,check=True)
 subprocess.run([linker,'/nologo','/DLL','/NOENTRY','/NODEFAULTLIB',str(obj),'kernel32.lib','user32.lib','vcruntime.lib',f'/OUT:{destination}',f'/IMPLIB:{workspace/source.stem}.lib'],env=env,cwd=workspace,check=True)
