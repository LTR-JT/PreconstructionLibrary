# Preconstruction Library

Save, reuse and share Bladesong part assemblies and blades with Magic Words.
Manage your library in the Forge or browse it from Creative Mode.

## Requirements and installation

- Bladesong on a supported Main or Bleeding Edge executable.
- A compatible [UE4SS runtime](https://github.com/UE4SS-RE/RE-UE4SS).
- [Bladesong Mod Framework](https://github.com/LTR-JT/BladesongModFramework) 0.1.3+.

Close the game, install the framework, then extract the PCL **runtime ZIP from
Releases** into the outer game folder beside `Bladesong.exe`. GitHub's automatic
Source code ZIP is for development. Keep existing library folders and saves
when updating. The release does not include UE4SS or the game executable.

## Use the library

**Parts:** Open the library, place a cyan anchor and attach the assembly to its
output hardpoint. Upload saves each anchored assembly separately. The camera
symbol shows the preview direction; hold an anchor and press **R** to cycle it.

**Blades:** Select Blades to switch the Forge to blade mode. Upload current blade
saves the blade; placing a saved blade replaces the blade while retaining the
hilt and attached parts. Parts switches the Forge back to Hilt mode.

**Import Magic Word** adds an entry to the library without forcing placement or
adding a Creative Mode sword. Use **Place build** when ready. Hover over a
thumbnail for a larger preview. Rename entries, copy their Magic Words, or hold
to delete. The Creative Mode library screen also supports selection and
multi-delete. Browsing a PCL entry there does not open the Forge.

Game-save backups are kept separately before protected operations. Preserve
your existing saves and `preconstructions`/blade library folders when upgrading.

## Development

The checked-in `Source/PreconstructionLibraryProbe` is the runtime source of
truth. Compatibility adapters for the current Bleeding Edge executable live in
the framework; PCL keeps guarded historical Main helpers for compatibility.
Original menu/anchor assets and their editable Unreal project are under Assets.

```powershell
python Tools/check.py --lua C:/path/to/lua.exe
python Tools/build_native.py
python Tools/package_release.py
```

See [build notes](Documentation/building.md), [troubleshooting](Documentation/troubleshooting.md),
and [contributing](CONTRIBUTING.md). Current runtime: **15.18.1**. This is a community
preview; future game versions may need framework adapter updates.

## License

Original code and project assets are MIT licensed. Bladesong, Unreal Engine and
UE4SS retain their respective licenses. See [third-party notices](THIRD_PARTY_NOTICES.md).
