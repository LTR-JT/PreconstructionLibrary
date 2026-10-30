from pathlib import Path
import argparse,subprocess,tempfile,json,os
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--lua',required=True);a=p.parse_args();lua=str(Path(a.lua).resolve())
with tempfile.TemporaryDirectory(dir=ROOT/'Tests')as temp:
 script=Path(temp)/'syntax.lua'
 script.write_text('\n'.join('assert(loadfile('+json.dumps(p.as_posix())+'))'for p in sorted((ROOT/'Source').rglob('*.lua')))+"\nprint('PASS: complete PCL runtime syntax')\n",encoding='utf-8')
 subprocess.run([lua,str(script)],check=True)
env=os.environ.copy();env['PCL_TEST_ROOT']=str(ROOT)
subprocess.run([lua,str(ROOT/'Tests/forge_modes.lua')],env=env,cwd=ROOT,check=True)
