# Releasing

Run the local checks and builds, test on the supported game branches, and update
the root/runtime mod.json version together. Commit the change and create the
matching `vVERSION` tag. Run **Draft release** from Actions with that tag.
The workflow checks the tag's version, builds the code and produces a draft
prerelease containing Runtime/BMF ZIPs, mod.json and SHA256SUMS.txt.

Review the draft assets and release notes before publishing. Do not use the
manual Runtime archive as the in-game installer archive; the release manifest
points to the BMF archive. Cooked asset changes require a manual Runtime update
because the in-game updater intentionally cannot write arbitrary game paths.
