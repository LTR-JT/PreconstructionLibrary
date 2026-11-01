-- PCL loads its cooked anchor and UI assets directly from the Lua mod.
-- The empty ModActor is unnecessary and can crash native actor finalization
-- in startup/thumbnail worlds on affected systems. A supported BPModLoader
-- per-package config prevents the default PCLAnchor ModActor spawn.
Mods["PCLAnchor"] = {
    AssetName = "ModActor_C",
    -- AssetPath intentionally absent: skip this package's empty loader actor.
}
print("[PCL] PCL_ASSET_ONLY_PACKAGE unused_mod_actor_spawn=false\n")
