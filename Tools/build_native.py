"""Build PCL's guarded historical Main helpers; BE adapters come from BMF."""
from pathlib import Path
from msvc import build
ROOT=Path(__file__).resolve().parents[1]
for source in sorted((ROOT/'NativeSource').glob('*.cpp')):
 name=source.stem+('b'if source.stem=='pcl_held_upload_151725'else '')+'.dll'
 build(source,ROOT/'Source/PreconstructionLibraryProbe/Scripts'/name,ROOT/'Build/native')
print('Built historical Main helpers from source.')
