# Building PCL

Install Python 3.12+, Lua 5.4 and Visual Studio C++ build tools on Windows.
`Tools/check.py` parses the complete runtime and exercises native stage routing.
`Tools/build_native.py` builds the historical Main helper DLLs from NativeSource;
it does not patch a running game. Bleeding Edge adapters are supplied by the
framework. `Tools/package_release.py` emits a manual-install ZIP, a separate
in-game mod archive/manifest, and checksums under Releases.

The original own-asset pack under Assets/Cooked is needed for menu and anchor
Blueprint paths. It contains original PCL assets only. For asset edits, use the
Unreal 5.7 mirror project under Assets/Project. Its tiny editor-only class stubs
exist so cooked references resolve to the real game classes at runtime; they
are not replacements for the game. Re-cook only the original PCL content and
check the native class path/socket contract on each supported branch.

Do not package personal library data or game saves. Changing a native helper
requires verifying its exact executable guard, ABI/layout and behavior.
