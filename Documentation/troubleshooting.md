# Troubleshooting

Close the game fully before updates or branch changes. Confirm the final path is
`Bladesong/Binaries/Win64/ue4ss/Mods/PreconstructionLibraryProbe/Scripts/main.lua`
and the framework's shared modules are alongside its mod directory.

For startup or native helper errors, include the relevant UE4SS log excerpt,
game branch/build and PCL/framework/UE4SS versions in an issue. Unknown native
builds are intentionally refused; never remove the checks to force loading.
The startup log reports `PCL15_18_1_NATIVE_PROBE` results. Status 1 means the
adapter's executable byte guards passed, not that every gameplay action was tested.

Preserve the library and game saves before changes. Do not upload saves, account
details, game executables, full dump trees or other users' creations to issues.
