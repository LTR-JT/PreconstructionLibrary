-- PCL 15.18.1: framework-owned native adapters; existing library paths/UI retained.
do
local scripts=assert(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[\\/])'))
local root=scripts..'../../shared/BladesongFramework/'
local framework=assert(loadfile(root..'api.lua'))(root)
BMF_PCL_ROOT=root;BMF_PCL_FRAMEWORK=framework
assert(framework.BindMod('PreconstructionLibraryProbe'))
function BMF_PCL_DIRECT_ANCHOR()
 local profile=framework.GetCompatibilityProfile()
 return profile=='main-26400894-anchor-test' or profile=='main-26433453'
end
function BMF_PCL_NATIVE(path,symbol)
 local name=path:match('([^/\\]+)$')
 local resolved,why=framework.GetNativeHelper(name,scripts)
 if not resolved then return nil,why end
 return package.loadlib(resolved,symbol)
end
print('[PCL] PCL15_18_1_ADAPTER profile='..framework.GetCompatibilityProfile()..'\n')
end
-- Do not run periodic callbacks until all cumulative definitions are ready.
PCL151759_SCRIPT_READY=false
-- ============================================================
-- Phase 15.9 clean-keymap bootstrap
-- Suppress all historical probe bindings while this cumulative helper file
-- loads. The real RegisterKeyBind is restored at the very end and only the
-- Phase 15.9 key is registered.
-- ============================================================
__PCL159_REAL_REGISTER_KEY_BIND = RegisterKeyBind
RegisterKeyBind = function(...)
    return nil
end

-- Preconstruction Library - Phase 2
-- First real prefab operation: export a connected subtree from Bladesong's
-- native AppliedSwordParts graph.
--
-- CTRL+ALT+S  : print current serialized tree
-- CTRL+ALT+F1 : export native part index 0
-- CTRL+ALT+F2 : export native part index 1
-- ...
-- CTRL+ALT+F9 : export native part index 8
--
-- Output:
-- Saved beside this main.lua file as prefab_root_N.pcl

local PREFIX = "[PCL] "
local function get_script_dir()
    local info = debug.getinfo(1, "S")
    if not info or not info.source then
        return "."
    end

    local source = info.source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end

    source = source:gsub("/", "\\")

    local dir = source:match("^(.*)\\[^\\]+$")
    if dir == nil or dir == "" then
        return "."
    end

    return dir
end

local OUTPUT_DIR = get_script_dir() .. "\\"

local function log(msg)
    -- Slot-walker traces are useful during development, but the row monitor
    -- otherwise writes hundreds of these lines per second during play.
    if not PCL151715_SLOT_TRACE and tostring(msg):match('^SLOT_TARGET_') then return end
    print(PREFIX .. tostring(msg) .. "\n")
end

PCL151714_OBJECT_PATHS = setmetatable({}, {__mode="k"})
log('PCL_RUNTIME_VERSION=15.17.62 menu=native_sections_names_and_local_cache import_and_socket=15.17.20')
local function is_valid(obj)
    if obj == nil then return false end
    -- UE4SS IsValid dereferences the GUObjectArray item for the wrapper's
    -- stored pointer. After collection that item can be null, causing a native
    -- crash that pcall cannot catch. Resolve known identities before touching
    -- the old UObject pointer. GetAddress only reads the Lua wrapper itself.
    local address_ok, address = pcall(function() return obj:GetAddress() end)
    if not address_ok or address == nil or address == 0 then return false end
    -- Native GUObjectArray identity checks are safe for expired wrappers and
    -- do not resolve thousands of full object paths on every frame/callback.
    if PCL151731_VALIDATOR then
        local serial=PCL151731_VALIDATOR(address)
        if serial<=0 then return false end
        local previous=PCL151731_SERIALS[obj]
        if previous and previous~=serial then return false end
        PCL151731_SERIALS[obj]=serial
        return true
    end
    local memo = PCL151715_VALIDATION_CACHE
    if memo ~= nil and memo[obj] ~= nil then return memo[obj] end
    local path = PCL151714_OBJECT_PATHS[obj]
    if path ~= nil then
        local found_ok, found = pcall(function() return StaticFindObject(path) end)
        if not found_ok or found == nil then
            if memo ~= nil then memo[obj] = false end
            return false
        end
        local found_address_ok, found_address = pcall(function() return found:GetAddress() end)
        if not found_address_ok or found_address ~= address then
            if memo ~= nil then memo[obj] = false end
            return false
        end
        if memo ~= nil then memo[obj] = true end
        return true
    end
    local ok, result = pcall(function() return obj:IsValid() end)
    if not ok or not result then return false end
    local name_ok, full_name = pcall(function() return obj:GetFullName() end)
    if name_ok and type(full_name) == 'string' then
        local object_path = full_name:match('^[^ ]+ (.+)$')
        if object_path ~= nil then PCL151714_OBJECT_PATHS[obj] = object_path end
    end
    if memo ~= nil then memo[obj] = true end
    return true
end

local function safe_name(value)
    if value == nil then return "None" end
    local ok, result = pcall(function() return value:ToString() end)
    if ok then return result end
    return tostring(value)
end

local function safe_full_name(obj)
    if not is_valid(obj) then return "None" end
    local ok, result = pcall(function() return obj:GetFullName() end)
    if ok then return result end
    return "<valid object>"
end

local function num(v, fallback)
    if v == nil then return fallback or 0 end
    return v
end

local function b(v)
    return v and "true" or "false"
end

local function vec3(v)
    if v == nil then return "0,0,0" end
    local ok, s = pcall(function()
        return string.format("%.9g,%.9g,%.9g", num(v.X), num(v.Y), num(v.Z))
    end)
    return ok and s or "0,0,0"
end

local function vec2(v)
    if v == nil then return "0,0" end
    local ok, s = pcall(function()
        return string.format("%.9g,%.9g", num(v.X), num(v.Y))
    end)
    return ok and s or "0,0"
end

local function quat(v)
    if v == nil then return "0,0,0,1" end
    local ok, s = pcall(function()
        return string.format("%.9g,%.9g,%.9g,%.9g",
            num(v.X), num(v.Y), num(v.Z), num(v.W, 1))
    end)
    return ok and s or "0,0,0,1"
end

local function find_forge()
    local forge = nil
    pcall(function()
        local mode = FindFirstOf('BladesongGameMode')
        if is_valid(mode) and is_valid(mode.ForgeMode) then forge = mode.ForgeMode end
    end)
    if is_valid(forge) then return forge end
    local ok, v = pcall(function() return FindFirstOf("BP_ForgeMode_C") end)
    if ok and is_valid(v) then forge = v end
    if not is_valid(forge) then
        ok, v = pcall(function() return FindFirstOf("ForgeMode") end)
        if ok and is_valid(v) then forge = v end
    end
    return forge
end

local function get_piece_and_design()
    local forge = find_forge()
    if not is_valid(forge) then
        return nil, nil, nil, "No live ForgeMode found."
    end

    local ok, err = pcall(function()
        forge:SerializeSwordPartActorsToData()
    end)
    if not ok then
        log("WARNING serializer call failed: " .. tostring(err))
    end

    local piece = nil
    ok, piece = pcall(function() return forge:GetPiece() end)
    if not ok or not is_valid(piece) then
        return forge, nil, nil, "ForgeMode:GetPiece() failed."
    end

    local design = nil
    ok, design = pcall(function() return piece.WeaponDesignDefinition end)
    if not ok or design == nil then
        return forge, piece, nil, "Could not read WeaponDesignDefinition."
    end

    return forge, piece, design, nil
end

-- Capture the TArray into a Lua table keyed by Bladesong's native zero-based index.
-- UE4SS's Lua ForEach callback is 1-based here, so native index = callback index - 1.
local function capture_parts(design)
    local out = {}
    local parts = design.AppliedSwordParts

    parts:ForEach(function(lua_index, elem)
        local native_index = lua_index - 1
        out[native_index] = elem:get()
    end)

    return out
end

local function read_slot_children(part)
    local out = {}
    if part.SlotChildren == nil then return out end

    part.SlotChildren:ForEach(function(lua_slot, elem)
        out[lua_slot - 1] = elem:get()
    end)

    return out
end

local function read_free_children(part)
    local out = {}
    if part.FreeChildren == nil then return out end

    part.FreeChildren:ForEach(function(lua_index, elem)
        local d = elem:get()
        table.insert(out, {
            idx = d.Idx,
            rel_loc = vec3(d.RelLoc),
            rel_rot = quat(d.RelRot)
        })
    end)

    return out
end

local function collect_subtree(parts, root_index)
    local visited = {}
    local order = {}

    local function visit(idx)
        if idx == nil or idx < 0 then return end
        if visited[idx] then return end
        local part = parts[idx]
        if part == nil then
            log("WARNING child index " .. tostring(idx) .. " is not present in AppliedSwordParts.")
            return
        end

        visited[idx] = true
        table.insert(order, idx)

        local slots = read_slot_children(part)
        for _, child in pairs(slots) do
            if child ~= nil and child >= 0 then visit(child) end
        end

        local frees = read_free_children(part)
        for _, child in ipairs(frees) do
            if child.idx ~= nil and child.idx >= 0 then visit(child.idx) end
        end
    end

    visit(root_index)
    return order
end

local function build_remap(order)
    local remap = {}
    for local_idx, original_idx in ipairs(order) do
        remap[original_idx] = local_idx - 1
    end
    return remap
end

local function remapped_slot_string(part, remap)
    local slots = read_slot_children(part)
    local keys = {}
    for k, _ in pairs(slots) do table.insert(keys, k) end
    table.sort(keys)

    local values = {}
    for _, slot_idx in ipairs(keys) do
        local original_child = slots[slot_idx]
        local local_child = -1
        if original_child ~= nil and original_child >= 0 then
            local_child = remap[original_child]
            if local_child == nil then local_child = -1 end
        end
        table.insert(values, tostring(local_child))
    end
    return table.concat(values, ",")
end


-- Phase 15.11.34: repair legacy export-map holes by SwordPart row.
-- Free-child actors were not always present in older actor maps, which could
-- leave actor_class/render_asset as None even when another instance of the
-- exact same SwordPart row had already resolved correctly.
function PCL151134BackfillExportMaps(parts, actor_class_map, actor_render_asset_map)
    local row_class = {}
    local row_asset = {}
    local class_conflict = {}
    local asset_conflict = {}

    for native_index, part in pairs(parts or {}) do
        if part ~= nil then
            local row = safe_name(part.SwordPart)
            local cls = actor_class_map and actor_class_map[native_index] or nil
            local asset = actor_render_asset_map and actor_render_asset_map[native_index] or nil

            if row ~= nil and row ~= "" and row ~= "None" then
                if cls ~= nil and cls ~= "" and cls ~= "None" then
                    if row_class[row] == nil then
                        row_class[row] = cls
                    elseif row_class[row] ~= cls then
                        class_conflict[row] = true
                    end
                end

                if asset ~= nil and asset ~= "" and asset ~= "None" then
                    if row_asset[row] == nil then
                        row_asset[row] = asset
                    elseif row_asset[row] ~= asset then
                        asset_conflict[row] = true
                    end
                end
            end
        end
    end

    local class_filled = 0
    local asset_filled = 0

    for native_index, part in pairs(parts or {}) do
        if part ~= nil then
            local row = safe_name(part.SwordPart)

            if actor_class_map ~= nil and
               (actor_class_map[native_index] == nil or
                actor_class_map[native_index] == "" or
                actor_class_map[native_index] == "None") and
               not class_conflict[row] and
               row_class[row] ~= nil then
                actor_class_map[native_index] = row_class[row]
                class_filled = class_filled + 1
            end

            if actor_render_asset_map ~= nil and
               (actor_render_asset_map[native_index] == nil or
                actor_render_asset_map[native_index] == "" or
                actor_render_asset_map[native_index] == "None") and
               not asset_conflict[row] and
               row_asset[row] ~= nil then
                actor_render_asset_map[native_index] = row_asset[row]
                asset_filled = asset_filled + 1
            end
        end
    end

    log("PCL15_11_34_EXPORT_ROW_BACKFILL classes=" ..
        tostring(class_filled) .. " assets=" .. tostring(asset_filled))

    return class_filled, asset_filled
end

local function write_prefab(root_index)
    local forge, piece, design, err = get_piece_and_design()
    if err then
        log("EXPORT_ERROR " .. err)
        return
    end

    local parts = capture_parts(design)
    if parts[root_index] == nil then
        log("EXPORT_ERROR no part exists at native index " .. tostring(root_index))
        return
    end

    local order = collect_subtree(parts, root_index)
    local remap = build_remap(order)

    -- Phase 15.2+: persist the exact native actor UClass for every saved
    -- sword part. This removes all load-time guessing and allows a prefab
    -- to be loaded into an empty Forge with no source build present.
    local actor_class_map = {}
    local actor_render_asset_map = {}

    if type(PCLBuildActorClassMapForExport) == "function" then
        local ok, result =
            pcall(function()
                return PCLBuildActorClassMapForExport(design)
            end)

        if ok and type(result) == "table" then
            actor_class_map = result
        else
            log("EXPORT_ACTOR_CLASS_MAP_WARNING " ..
                tostring(result))
        end
    else
        log("EXPORT_ACTOR_CLASS_MAP_WARNING provider unavailable")
    end

    if type(PCLBuildActorRenderAssetMapForExport) == "function" then
        local ok, result =
            pcall(function()
                return PCLBuildActorRenderAssetMapForExport(design)
            end)

        if ok and type(result) == "table" then
            actor_render_asset_map = result
        else
            log("EXPORT_RENDER_ASSET_MAP_WARNING " ..
                tostring(result))
        end
    else
        log("EXPORT_RENDER_ASSET_MAP_WARNING provider unavailable")
    end

    PCL151134BackfillExportMaps(
        parts,
        actor_class_map,
        actor_render_asset_map
    )

    local path = OUTPUT_DIR .. "prefab_root_" .. tostring(root_index) .. ".pcl"
    local file, open_err = io.open(path, "w")
    if not file then
        log("EXPORT_ERROR could not open " .. path .. ": " .. tostring(open_err))
        return
    end

    file:write("PCL_PREFAB_V1\n")
    file:write("game=Bladesong\n")
    file:write("ue_version=5.7\n")
    file:write("root_local_index=0\n")
    file:write("root_original_index=" .. tostring(root_index) .. "\n")
    file:write("part_count=" .. tostring(#order) .. "\n")
    file:write("\n")

    for local_lua_index, original_index in ipairs(order) do
        local local_index = local_lua_index - 1
        local p = parts[original_index]

        file:write("[part " .. tostring(local_index) .. "]\n")
        file:write("original_index=" .. tostring(original_index) .. "\n")
        file:write("sword_part=" .. safe_name(p.SwordPart) .. "\n")

        local actor_class =
            actor_class_map[original_index] or "None"

        file:write("actor_class=" ..
            tostring(actor_class) .. "\n")

        local actor_render_asset =
            actor_render_asset_map[original_index] or "None"

        file:write("actor_render_asset=" ..
            tostring(actor_render_asset) .. "\n")

        file:write("material=" .. safe_name(p.SwordMaterial) .. "\n")

        -- Phase 14.4+: preserve the actual material data row separately from
        -- the display/material-instance name. Pigmented materials such as
        -- LeatherLambRibbed-Black are library variants and are NOT
        -- necessarily DataTable row names.
        local material_data_row = "None"
        local material_data_table = "None"
        pcall(function()
            if p.SwordMaterialData ~= nil then
                material_data_row = safe_name(p.SwordMaterialData.RowName)
                if is_valid(p.SwordMaterialData.DataTable) then
                    material_data_table = safe_full_name(p.SwordMaterialData.DataTable)
                end
            end
        end)

        file:write("material_data_row=" .. tostring(material_data_row) .. "\n")
        file:write("material_data_table=" .. tostring(material_data_table) .. "\n")
        file:write(string.format("polish=%.9g\n", num(p.Polish)))
        file:write(string.format("scale=%.9g\n", num(p.Scale)))
        file:write("rotation=" .. tostring(num(p.Rotation)) .. "\n")
        file:write(string.format("sink=%.9g\n", num(p.Sink)))
        file:write("deflection=" .. quat(p.Deflection) .. "\n")
        file:write("curvature_vals=" .. vec2(p.CurvatureVals) .. "\n")
        file:write("circle_rotations=" .. quat(p.CircleRotations) .. "\n")
        file:write(string.format("stretch=%.9g\n", num(p.Stretch, 1)))
        file:write("flipped_slot=" .. b(p.bIsInFlippedSlot) .. "\n")
        file:write("manual_flip=" .. b(p.bManualFlip) .. "\n")
        file:write(string.format("curvature=%.9g\n", num(p.Curvature)))
        file:write("slots_version=" .. tostring(num(p.SlotsVersion)) .. "\n")
        file:write("slot_children=" .. remapped_slot_string(p, remap) .. "\n")

        local frees = read_free_children(p)
        local free_count = 0
        for _, fc in ipairs(frees) do
            if remap[fc.idx] ~= nil then free_count = free_count + 1 end
        end
        file:write("free_child_count=" .. tostring(free_count) .. "\n")

        local write_idx = 0
        for _, fc in ipairs(frees) do
            local local_child = remap[fc.idx]
            if local_child ~= nil then
                file:write(string.format(
                    "free_child_%d=%d|%s|%s\n",
                    write_idx, local_child, fc.rel_loc, fc.rel_rot
                ))
                write_idx = write_idx + 1
            end
        end

        file:write("\n")
    end

    file:close()

    log("EXPORT_OK root_native=" .. tostring(root_index) ..
        " parts=" .. tostring(#order) ..
        " file=" .. path)

    for local_idx, original_idx in ipairs(order) do
        local p = parts[original_idx]
        log(string.format(
            "EXPORT_PART local=%d original=%d sword_part=%s actor_class=%s render_asset=%s material=%s",
            local_idx - 1, original_idx,
            safe_name(p.SwordPart),
            tostring(actor_class_map[original_idx] or "None"),
            tostring(actor_render_asset_map[original_idx] or "None"),
            safe_name(p.SwordMaterial)
        ))
    end
end

local function snapshot()
    local forge, piece, design, err = get_piece_and_design()
    if err then
        log("SNAPSHOT_ERROR " .. err)
        return
    end

    local parts = capture_parts(design)
    log("SNAPSHOT_BEGIN root_idx=" .. tostring(design.RootSwordPartIdx))

    local idx = 0
    while parts[idx] ~= nil do
        local p = parts[idx]
        log(string.format(
            "PART native=%d sword_part=%s material=%s scale=%.6f rotation=%s stretch=%.6f slots=[%s]",
            idx, safe_name(p.SwordPart), safe_name(p.SwordMaterial),
            num(p.Scale), tostring(num(p.Rotation)), num(p.Stretch, 1),
            remapped_slot_string(p, (function()
                local identity = {}
                for i=0,10000 do identity[i]=i end
                return identity
            end)())
        ))
        idx = idx + 1
    end

    log("SNAPSHOT_END")
end

PCL15179_GAME_CALLBACK_DEPTH = 0
function pcl15179_schedule(delay_ms, fn)
    if type(ExecuteInGameThreadWithDelay) ~= 'function' then
        error('PCL requires UE4SS ExecuteInGameThreadWithDelay; unsafe async timers are disabled.')
    end
    return ExecuteInGameThreadWithDelay(math.max(1, tonumber(delay_ms) or 1), function()
        if not PCL151759_SCRIPT_READY then
            -- Startup folder/asset work can yield while UE4SS begins dispatch.
            -- Keep one pending callback, without touching partially defined globals.
            return pcl15179_schedule(100,fn)
        end
        -- Scope reuse to this synchronous game-thread callback, never across
        -- frames where Unreal may collect or replace objects.
        local previous_cache = PCL151715_VALIDATION_CACHE
        PCL151715_VALIDATION_CACHE = {}
        PCL15179_GAME_CALLBACK_DEPTH = PCL15179_GAME_CALLBACK_DEPTH + 1
        local ok, err = pcall(fn)
        PCL15179_GAME_CALLBACK_DEPTH = PCL15179_GAME_CALLBACK_DEPTH - 1
        PCL151715_VALIDATION_CACHE = previous_cache
        if not ok then log('PCL15_17_9_TIMER_ERROR ' .. tostring(err)) end
    end)
end

local function run_game_thread(fn)
    local function invoke()
        local sequence, source_line = nil, nil
        if PCL15177_TRACE_CALLBACKS then
            PCL15177_CALLBACK_SEQUENCE = (PCL15177_CALLBACK_SEQUENCE or 0) + 1
            sequence = PCL15177_CALLBACK_SEQUENCE
            local info = debug.getinfo(fn, 'S')
            source_line = info and info.linedefined or -1
            log('PCL15_17_7_CALLBACK_BEGIN id=' .. tostring(sequence) .. ' line=' .. tostring(source_line))
        end
        local ok, err = pcall(fn)
        if not ok then log("FATAL " .. tostring(err)) end
        if sequence then
            log('PCL15_17_7_CALLBACK_END id=' .. tostring(sequence) .. ' ok=' .. tostring(ok))
        end
    end
    if PCL15179_GAME_CALLBACK_DEPTH > 0 then
        invoke()
    else
        pcl15179_schedule(1, invoke)
    end
end
log('PCL15_17_9_SCHEDULER game_thread_delay=' .. tostring(type(ExecuteInGameThreadWithDelay) == 'function'))

log("Preconstruction Library Phase 2.2 loaded.")
log("OUTPUT_DIR=" .. OUTPUT_DIR)
log("CTRL+ALT+S = snapshot.")
log("CTRL+ALT+F1..F9 = export native root index 0..8.")

RegisterKeyBind(Key.S, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(snapshot)
end)

local export_keys = {
    {Key.F1, 0}, {Key.F2, 1}, {Key.F3, 2},
    {Key.F4, 3}, {Key.F5, 4}, {Key.F6, 5},
    {Key.F7, 6}, {Key.F8, 7}, {Key.F9, 8},
}

for _, pair in ipairs(export_keys) do
    local key = pair[1]
    local root_index = pair[2]
    RegisterKeyBind(key, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
        run_game_thread(function()
            write_prefab(root_index)
        end)
    end)
end


-- ============================================================
-- Phase 6: first REAL disk -> Piece -> live actors import proof
-- ============================================================
--
-- Reads:
--   scripts\prefab_root_1.pcl
--
-- Applies it to the EXISTING three-part subtree rooted at native index 1,
-- then calls:
--
--   BP_BladesongGameModeCreative_C:EnterForgeMode(Piece)
--
-- IMPORTANT FIRST-PROOF LIMITATION:
-- - current subtree must still have exactly 3 parts
-- - current part IDs must match the saved prefab part IDs
-- - FreeChildren must be zero
-- - SlotChildren array sizes must match
--
-- This lets us prove persistent disk loading without reallocating Unreal
-- TArrays or resolving new part DataTable handles yet.
--
-- CTRL+ALT+L = load prefab_root_1.pcl into native subtree 1
-- CTRL+ALT+U = restore the pre-load subtree captured in memory

local PCL_IMPORT_FILENAME = "prefab_root_1.pcl"
local PCL_IMPORT_TARGET_ROOT = 1
local pcl_import_backup = nil

local function trim(s)
    if s == nil then return "" end
    -- Force gsub's multi-return result down to one plain string.  On a
    -- repeated import UE4SS/Lua exposed the second gsub return to the
    -- table insertion call, producing "wrong number of arguments to 'insert'".
    local cleaned = s:gsub("^%s+", "")
    cleaned = cleaned:gsub("%s+$", "")
    return cleaned
end

local function split_csv(s)
    local out = {}
    if s == nil or s == "" then return out end
    for item in string.gmatch(s, "([^,]+)") do
        -- Do not use table.insert(out, trim(item)) here.  Direct assignment
        -- guarantees exactly one value reaches the table even if a helper
        -- accidentally returns multiple values in this Lua runtime.
        local cleaned = trim(item)
        out[#out + 1] = cleaned
    end
    return out
end

local function parse_bool(s)
    return tostring(s):lower() == "true"
end

local function parse_num_list(s)
    local out = {}
    for _, v in ipairs(split_csv(s)) do
        table.insert(out, tonumber(v) or 0)
    end
    return out
end

local function parse_int_list(s)
    local out = {}
    for _, v in ipairs(split_csv(s)) do
        table.insert(out, tonumber(v) or -1)
    end
    return out
end

local function parse_pcl_file(path)
    local f, err = io.open(path, "r")
    if not f then
        return nil, "could not open " .. path .. ": " .. tostring(err)
    end

    local data = {
        meta = {},
        parts = {}
    }

    local current_part = nil
    local first_line = true

    for raw_line in f:lines() do
        local line = trim(raw_line)

        if first_line then
            first_line = false
            if line ~= "PCL_PREFAB_V1" then
                f:close()
                return nil, "unsupported/missing header: " .. tostring(line)
            end
        elseif line ~= "" then
            local part_index = line:match("^%[part%s+(%d+)%]$")

            if part_index ~= nil then
                local idx = tonumber(part_index)
                current_part = {}
                data.parts[idx] = current_part
            else
                local key, value = line:match("^([^=]+)=(.*)$")

                if key ~= nil then
                    key = trim(key)
                    value = trim(value)

                    if current_part ~= nil then
                        current_part[key] = value
                    else
                        data.meta[key] = value
                    end
                end
            end
        end
    end

    f:close()
    return data, nil
end

local function find_creative_game_mode_6()
    local ok, gm = pcall(function()
        return FindFirstOf("BP_BladesongGameModeCreative_C")
    end)

    if ok and is_valid(gm) then
        return gm
    end

    ok, gm = pcall(function()
        return FindFirstOf("BladesongGameMode")
    end)

    if ok and is_valid(gm) then
        return gm
    end

    return nil
end

local function get_part_native(parts, native_index)
    local found = nil

    parts:ForEach(function(lua_index, elem)
        if found ~= nil then return end
        if (lua_index - 1) == native_index then
            found = elem:get()
        end
    end)

    return found
end

local function read_slot_children_ordered(part)
    local out = {}

    if part == nil or part.SlotChildren == nil then
        return out
    end

    part.SlotChildren:ForEach(function(lua_index, elem)
        out[lua_index] = elem:get()
    end)

    return out
end

local function capture_math2(v)
    if v == nil then return {0, 0} end
    return {num(v.X), num(v.Y)}
end

local function capture_quat(v)
    if v == nil then return {0, 0, 0, 1} end
    return {num(v.X), num(v.Y), num(v.Z), num(v.W, 1)}
end

local function capture_part_state(part)
    return {
        sword_part = safe_name(part.SwordPart),
        material = safe_name(part.SwordMaterial),
        polish = num(part.Polish),
        scale = num(part.Scale),
        rotation = num(part.Rotation),
        sink = num(part.Sink),
        stretch = num(part.Stretch, 1),
        curvature = num(part.Curvature),
        flipped_slot = part.bIsInFlippedSlot and true or false,
        manual_flip = part.bManualFlip and true or false,
        slots_version = num(part.SlotsVersion),
        deflection = capture_quat(part.Deflection),
        curvature_vals = capture_math2(part.CurvatureVals),
        circle_rotations = capture_quat(part.CircleRotations),
        slot_children = read_slot_children_ordered(part),
        free_count = part.FreeChildren and #part.FreeChildren or 0
    }
end

local function copy_num_array(dst, src)
    if dst == nil or src == nil then return end
    if src[1] ~= nil then dst.X = src[1] end
    if src[2] ~= nil then dst.Y = src[2] end
    if src[3] ~= nil then dst.Z = src[3] end
    if src[4] ~= nil then dst.W = src[4] end
end

local function write_slot_children_native(target_part, native_values)
    if target_part.SlotChildren == nil then
        return false, "target SlotChildren is nil"
    end

    if #target_part.SlotChildren ~= #native_values then
        return false, string.format(
            "slot length mismatch target=%d source=%d",
            #target_part.SlotChildren,
            #native_values
        )
    end

    local ok, err = pcall(function()
        target_part.SlotChildren:ForEach(function(lua_index, elem)
            elem:set(native_values[lua_index] or -1)
        end)
    end)

    return ok, err
end

local function apply_state_to_part(target_part, state)
    if target_part == nil or state == nil then
        return false, "nil part/state"
    end

    -- Phase 6 deliberately does not change part/material names or handles.
    -- The current live subtree must use the same IDs as the saved prefab.
    local current_part_name = safe_name(target_part.SwordPart)

    if current_part_name ~= state.sword_part then
        return false, "part ID mismatch current=" ..
            current_part_name .. " saved=" .. tostring(state.sword_part)
    end

    local ok, err = pcall(function()
        target_part.Polish = state.polish
        target_part.Scale = state.scale
        target_part.Rotation = state.rotation
        target_part.Sink = state.sink
        target_part.Stretch = state.stretch
        target_part.Curvature = state.curvature
        target_part.bIsInFlippedSlot = state.flipped_slot
        target_part.bManualFlip = state.manual_flip
        target_part.SlotsVersion = state.slots_version

        copy_num_array(target_part.Deflection, state.deflection)
        copy_num_array(target_part.CurvatureVals, state.curvature_vals)
        copy_num_array(target_part.CircleRotations, state.circle_rotations)
    end)

    if not ok then
        return false, "scalar/math write failed: " .. tostring(err)
    end

    local slots_ok, slots_err = write_slot_children_native(
        target_part,
        state.slot_children
    )

    if not slots_ok then
        return false, "slot write failed: " .. tostring(slots_err)
    end

    return true, nil
end

local function prefab_part_to_state(saved_part, target_order)
    if saved_part == nil then
        return nil, "missing saved part"
    end

    local local_slots = parse_int_list(saved_part.slot_children or "")
    local native_slots = {}

    for i, local_child in ipairs(local_slots) do
        if local_child == nil or local_child < 0 then
            native_slots[i] = -1
        else
            local native_child = target_order[local_child + 1]
            if native_child == nil then
                return nil, "saved child local index " ..
                    tostring(local_child) .. " has no target mapping"
            end
            native_slots[i] = native_child
        end
    end

    local free_count = tonumber(saved_part.free_child_count or "0") or 0
    if free_count ~= 0 then
        return nil, "Phase 6 does not yet import FreeChildren; file has " ..
            tostring(free_count)
    end

    return {
        sword_part = saved_part.sword_part,
        material = saved_part.material,
        polish = tonumber(saved_part.polish) or 0,
        scale = tonumber(saved_part.scale) or 1,
        rotation = tonumber(saved_part.rotation) or 0,
        sink = tonumber(saved_part.sink) or 0,
        stretch = tonumber(saved_part.stretch) or 1,
        curvature = tonumber(saved_part.curvature) or 0,
        flipped_slot = parse_bool(saved_part.flipped_slot),
        manual_flip = parse_bool(saved_part.manual_flip),
        slots_version = tonumber(saved_part.slots_version) or 0,
        deflection = parse_num_list(saved_part.deflection or "0,0,0,1"),
        curvature_vals = parse_num_list(saved_part.curvature_vals or "0,0"),
        circle_rotations = parse_num_list(saved_part.circle_rotations or "0,0,0,1"),
        slot_children = native_slots,
        free_count = 0
    }, nil
end

local function enter_piece_again(piece)
    local gm = find_creative_game_mode_6()

    if not is_valid(gm) then
        return false, "Creative GameMode not found"
    end

    local ok, err = pcall(function()
        gm:EnterForgeMode(piece)
    end)

    if not ok then
        return false, err
    end

    return true, nil
end

local function load_saved_prefab_phase6()
    log("============================================================")
    log("PCL_IMPORT_BEGIN file=" .. PCL_IMPORT_FILENAME ..
        " target_root_native=" .. tostring(PCL_IMPORT_TARGET_ROOT))

    local path = OUTPUT_DIR .. PCL_IMPORT_FILENAME
    log("PCL_IMPORT_PATH=" .. path)

    local prefab, parse_err = parse_pcl_file(path)
    if prefab == nil then
        log("PCL_IMPORT_ERROR " .. tostring(parse_err))
        return
    end

    local saved_count = tonumber(prefab.meta.part_count or "-1") or -1
    log("PCL_IMPORT_FILE_PART_COUNT=" .. tostring(saved_count))

    local forge, piece, design, state_err = get_piece_and_design()

    if state_err then
        log("PCL_IMPORT_ERROR " .. tostring(state_err))
        return
    end

    local live_parts = capture_parts(design)
    local target_order = collect_subtree(live_parts, PCL_IMPORT_TARGET_ROOT)

    log("PCL_IMPORT_TARGET_PART_COUNT=" .. tostring(#target_order))

    if #target_order ~= saved_count then
        log("PCL_IMPORT_ERROR part count mismatch target=" ..
            tostring(#target_order) .. " file=" .. tostring(saved_count))
        return
    end

    -- Capture full scalar/topology backup before mutation.
    pcl_import_backup = {
        piece = piece,
        order = {},
        parts = {}
    }

    for i, native_index in ipairs(target_order) do
        pcl_import_backup.order[i] = native_index
        pcl_import_backup.parts[i] = capture_part_state(live_parts[native_index])
    end

    -- Parse + preflight ALL saved parts before touching the Piece.
    local imported_states = {}

    for local_index = 0, saved_count - 1 do
        local saved_part = prefab.parts[local_index]
        local native_index = target_order[local_index + 1]
        local live_part = live_parts[native_index]

        if saved_part == nil then
            log("PCL_IMPORT_ERROR file missing [part " ..
                tostring(local_index) .. "]")
            return
        end

        if live_part == nil then
            log("PCL_IMPORT_ERROR target missing native part " ..
                tostring(native_index))
            return
        end

        if safe_name(live_part.SwordPart) ~= saved_part.sword_part then
            log("PCL_IMPORT_ERROR part ID mismatch local=" ..
                tostring(local_index) ..
                " current=" .. safe_name(live_part.SwordPart) ..
                " saved=" .. tostring(saved_part.sword_part))
            return
        end

        local state, convert_err = prefab_part_to_state(saved_part, target_order)

        if state == nil then
            log("PCL_IMPORT_ERROR local=" .. tostring(local_index) ..
                " " .. tostring(convert_err))
            return
        end

        if #live_part.SlotChildren ~= #state.slot_children then
            log("PCL_IMPORT_ERROR local=" .. tostring(local_index) ..
                " SlotChildren shape mismatch current=" ..
                tostring(#live_part.SlotChildren) ..
                " saved=" .. tostring(#state.slot_children))
            return
        end

        local live_free = live_part.FreeChildren and #live_part.FreeChildren or 0
        if live_free ~= 0 then
            log("PCL_IMPORT_ERROR local=" .. tostring(local_index) ..
                " current FreeChildren=" .. tostring(live_free) ..
                " (Phase 6 requires 0)")
            return
        end

        imported_states[local_index + 1] = state

        log(string.format(
            "PCL_IMPORT_PREFLIGHT local=%d native=%d part=%s rotation=%s stretch=%.6f slots=%s",
            local_index,
            native_index,
            state.sword_part,
            tostring(state.rotation),
            state.stretch,
            table.concat(state.slot_children, ",")
        ))
    end

    -- Apply in place.
    for i, native_index in ipairs(target_order) do
        local part = live_parts[native_index]
        local ok, err = apply_state_to_part(part, imported_states[i])

        if not ok then
            log("PCL_IMPORT_ERROR write local=" .. tostring(i - 1) ..
                " native=" .. tostring(native_index) ..
                " error=" .. tostring(err))
            log("Use CTRL+ALT+U or restart Bladesong.")
            return
        end
    end

    log("PCL_IMPORT_DATA_WRITTEN")

    local enter_ok, enter_err = enter_piece_again(piece)

    if not enter_ok then
        log("PCL_IMPORT_ERROR EnterForgeMode failed: " .. tostring(enter_err))
        log("Use CTRL+ALT+U or restart Bladesong.")
        return
    end

    log("PCL_IMPORT_ENTERFORGEMODE_CALLED")
    log("PCL_IMPORT_OK")
    log("The live subtree rooted at native index 1 should now match prefab_root_1.pcl.")
    log("CTRL+ALT+U restores the state that existed immediately before import.")
    log("============================================================")
end

local function restore_before_import_phase6()
    log("============================================================")
    log("PCL_IMPORT_RESTORE_BEGIN")

    if pcl_import_backup == nil then
        log("PCL_IMPORT_RESTORE_ERROR no Phase 6 backup exists")
        return
    end

    local forge = find_forge()
    if not is_valid(forge) then
        log("PCL_IMPORT_RESTORE_ERROR no ForgeMode found")
        return
    end

    local piece = forge:GetPiece()
    if not is_valid(piece) then
        log("PCL_IMPORT_RESTORE_ERROR no Piece found")
        return
    end

    -- Serialize current live state first so we operate on the current Piece graph.
    pcall(function()
        forge:SerializeSwordPartActorsToData()
    end)

    local design = piece.WeaponDesignDefinition
    local parts = capture_parts(design)

    for i, native_index in ipairs(pcl_import_backup.order) do
        local target_part = parts[native_index]
        local state = pcl_import_backup.parts[i]

        if target_part == nil then
            log("PCL_IMPORT_RESTORE_ERROR native index " ..
                tostring(native_index) .. " missing")
            return
        end

        local ok, err = apply_state_to_part(target_part, state)
        if not ok then
            log("PCL_IMPORT_RESTORE_ERROR native=" ..
                tostring(native_index) .. " " .. tostring(err))
            return
        end
    end

    local enter_ok, enter_err = enter_piece_again(piece)
    if not enter_ok then
        log("PCL_IMPORT_RESTORE_ERROR EnterForgeMode failed: " ..
            tostring(enter_err))
        return
    end

    log("PCL_IMPORT_RESTORE_OK")
    log("============================================================")
end

RegisterKeyBind(Key.L, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(load_saved_prefab_phase6)
end)

RegisterKeyBind(Key.U, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(restore_before_import_phase6)
end)

log("Phase 6 loaded.")
log("CTRL+ALT+L = load scripts\\prefab_root_1.pcl into native subtree 1.")
log("CTRL+ALT+U = restore the pre-import subtree.")


-- ============================================================
-- Phase 7: saved-name -> native DataTable row-handle resolver
-- ============================================================
--
-- CTRL+ALT+H
--   Reads prefab_root_1.pcl and resolves every saved:
--     sword_part=<row name>
--     material=<row name>
--
--   against BladesongGameModule_Creative / Vanilla's configured
--   SwordPartDataTables and SwordMaterialDataTables.
--
-- This phase is READ-ONLY. It does not mutate the Piece.

local PCL_MODULE_PATHS = {
    "/Game/Modules/BladesongGameModule_Creative.BladesongGameModule_Creative",
    "/Game/Modules/BladesongGameModule_Vanilla.BladesongGameModule_Vanilla"
}

local function find_game_modules_7()
    local modules = {}
    local seen = {}

    for _, path in ipairs(PCL_MODULE_PATHS) do
        local ok, obj = pcall(function()
            return StaticFindObject(path)
        end)

        if ok and is_valid(obj) then
            local full = safe_full_name(obj)
            if not seen[full] then
                seen[full] = true
                table.insert(modules, obj)
            end
        end
    end

    -- Fallback if exact asset paths change but the class still exists.
    if #modules == 0 then
        local ok, obj = pcall(function()
            return FindFirstOf("BladesongGameModule")
        end)

        if ok and is_valid(obj) then
            table.insert(modules, obj)
        end
    end

    return modules
end

local function collect_unique_datatables_7(modules, property_name)
    local tables = {}
    local seen = {}

    for _, module in ipairs(modules) do
        local ok, arr = pcall(function()
            return module[property_name]
        end)

        if ok and arr ~= nil then
            pcall(function()
                arr:ForEach(function(_, elem)
                    local dt = elem:get()

                    if is_valid(dt) then
                        local full = safe_full_name(dt)

                        if not seen[full] then
                            seen[full] = true
                            table.insert(tables, dt)
                        end
                    end
                end)
            end)
        end
    end

    return tables
end

local function get_row_names_7(dt)
    local ok, names = pcall(function()
        return dt:GetRowNames()
    end)

    if ok and names ~= nil then
        return names
    end

    return {}
end

local function find_row_in_tables_7(tables, wanted_name)
    for _, dt in ipairs(tables) do
        local names = get_row_names_7(dt)

        for _, row_name in ipairs(names) do
            if safe_name(row_name) == wanted_name then
                local row = nil

                local ok, result = pcall(function()
                    return dt:FindRow(row_name)
                end)

                if ok then
                    row = result
                end

                return {
                    data_table = dt,
                    row_name = row_name,
                    row = row
                }
            end
        end
    end

    return nil
end

local function safe_len_7(value)
    if value == nil then return -1 end

    local ok, result = pcall(function()
        return #value
    end)

    if ok then return result end
    return -1
end

local function enum_string_7(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function resolve_prefab_handles_7()
    log("============================================================")
    log("HANDLE_RESOLVE_BEGIN file=" .. PCL_IMPORT_FILENAME)

    local path = OUTPUT_DIR .. PCL_IMPORT_FILENAME
    log("HANDLE_RESOLVE_PATH=" .. path)

    local prefab, parse_err = parse_pcl_file(path)

    if prefab == nil then
        log("HANDLE_RESOLVE_ERROR " .. tostring(parse_err))
        return
    end

    local modules = find_game_modules_7()

    log("HANDLE_RESOLVE_MODULE_COUNT=" .. tostring(#modules))

    for i, module in ipairs(modules) do
        log("HANDLE_RESOLVE_MODULE index=" .. tostring(i - 1) ..
            " object=" .. safe_full_name(module))
    end

    if #modules == 0 then
        log("HANDLE_RESOLVE_ERROR no BladesongGameModule assets found")
        return
    end

    local part_tables = collect_unique_datatables_7(
        modules,
        "SwordPartDataTables"
    )

    local material_tables = collect_unique_datatables_7(
        modules,
        "SwordMaterialDataTables"
    )

    log("HANDLE_RESOLVE_PART_TABLE_COUNT=" .. tostring(#part_tables))
    for i, dt in ipairs(part_tables) do
        log("HANDLE_RESOLVE_PART_TABLE index=" .. tostring(i - 1) ..
            " rows=" .. tostring(#get_row_names_7(dt)) ..
            " object=" .. safe_full_name(dt))
    end

    log("HANDLE_RESOLVE_MATERIAL_TABLE_COUNT=" .. tostring(#material_tables))
    for i, dt in ipairs(material_tables) do
        log("HANDLE_RESOLVE_MATERIAL_TABLE index=" .. tostring(i - 1) ..
            " rows=" .. tostring(#get_row_names_7(dt)) ..
            " object=" .. safe_full_name(dt))
    end

    local saved_count = tonumber(prefab.meta.part_count or "-1") or -1

    if saved_count < 0 then
        log("HANDLE_RESOLVE_ERROR invalid prefab part_count")
        return
    end

    local all_ok = true

    for local_index = 0, saved_count - 1 do
        local p = prefab.parts[local_index]

        if p == nil then
            log("HANDLE_RESOLVE_ERROR missing [part " ..
                tostring(local_index) .. "]")
            all_ok = false
        else
            local part_result = find_row_in_tables_7(
                part_tables,
                p.sword_part
            )

            if part_result == nil then
                log("PART_RESOLVE_FAIL local=" .. tostring(local_index) ..
                    " row=" .. tostring(p.sword_part))
                all_ok = false
            else
                local slots = -1
                local ptype = "unknown"
                local display_name = "unknown"

                if part_result.row ~= nil then
                    slots = safe_len_7(part_result.row.Slots)
                    ptype = enum_string_7(part_result.row.Type)

                    local ok_display, display = pcall(function()
                        return part_result.row.DisplayName:ToString()
                    end)

                    if ok_display then
                        display_name = tostring(display)
                    end
                end

                log(
                    "PART_RESOLVE_OK local=" .. tostring(local_index) ..
                    " row=" .. safe_name(part_result.row_name) ..
                    " slots=" .. tostring(slots) ..
                    " type=" .. ptype ..
                    " display=" .. display_name ..
                    " table=" .. safe_full_name(part_result.data_table)
                )
            end

            local material_result = find_row_in_tables_7(
                material_tables,
                p.material
            )

            if material_result == nil then
                log("MATERIAL_RESOLVE_FAIL local=" ..
                    tostring(local_index) ..
                    " row=" .. tostring(p.material))
                all_ok = false
            else
                log(
                    "MATERIAL_RESOLVE_OK local=" .. tostring(local_index) ..
                    " row=" .. safe_name(material_result.row_name) ..
                    " table=" .. safe_full_name(material_result.data_table)
                )
            end
        end
    end

    if all_ok then
        log("HANDLE_RESOLVE_OK all saved part/material rows resolved")
    else
        log("HANDLE_RESOLVE_INCOMPLETE one or more rows did not resolve")
    end

    log("============================================================")
end

RegisterKeyBind(Key.H, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(resolve_prefab_handles_7)
end)

log("Phase 7 handle resolver loaded.")
log("CTRL+ALT+H = resolve saved .pcl part/material names to native DataTable rows.")


-- ============================================================
-- Phase 8.3: combined SAFE prefab importer
-- ============================================================
--
-- Proven-safe pieces combined:
--   - disk .pcl parsing
--   - part row resolution
--   - material row resolution
--   - SwordPart + SwordPartData writes
--   - SwordMaterial + SwordMaterialData writes
--   - geometry/topology writes
--   - EnterForgeMode(Piece)
--   - serialize verification
--   - restore
--
-- The original Phase 8 raw Unreal proxy backup is NOT used.
-- Backup stores strings + plain numbers/booleans/tables only.
--
-- CTRL+ALT+K = full saved prefab import into existing subtree
-- CTRL+ALT+V = verify live actors against prefab_root_1.pcl
-- CTRL+ALT+R = restore pre-import subtree
--
-- Remaining limitation:
--   target subtree must have the same part count and nested array SHAPES.

local pcl_83_backup = nil

local function make_existing_fname_83(name_string)
    local ok, value = pcall(function()
        return FName(name_string, EFindName.FNAME_Find)
    end)

    if not ok then
        return nil, "FName(FNAME_Find) failed: " .. tostring(value)
    end

    return value, nil
end

local function resolve_part_83(part_tables, name)
    local result = find_row_in_tables_7(part_tables, name)
    if result == nil then
        return nil, "part row not found: " .. tostring(name)
    end
    return result, nil
end

local function resolve_material_83(material_tables, name)
    local result = find_row_in_tables_7(material_tables, name)
    if result == nil then
        return nil, "material row not found: " .. tostring(name)
    end
    return result, nil
end

local function write_row_handle_83(handle, data_table, row_name)
    if handle == nil then
        return false, "row handle nil"
    end

    local ok, err = pcall(function()
        handle.DataTable = data_table
        handle.RowName = row_name
    end)

    return ok, err
end

local function write_part_identity_83(target, name, resolved)
    local fname, fname_err = make_existing_fname_83(name)
    if fname == nil then
        return false, fname_err
    end

    local ok, err = pcall(function()
        target.SwordPart = fname
    end)
    if not ok then
        return false, "SwordPart write failed: " .. tostring(err)
    end

    local handle_ok, handle_err = write_row_handle_83(
        target.SwordPartData,
        resolved.data_table,
        fname
    )
    if not handle_ok then
        return false, "SwordPartData write failed: " .. tostring(handle_err)
    end

    return true, nil
end

local function write_material_identity_83(target, name, resolved)
    local fname, fname_err = make_existing_fname_83(name)
    if fname == nil then
        return false, fname_err
    end

    local ok, err = pcall(function()
        target.SwordMaterial = fname
    end)
    if not ok then
        return false, "SwordMaterial write failed: " .. tostring(err)
    end

    local row_name =
        resolved and resolved.row_name or nil

    if row_name == nil then
        row_name = fname
    elseif type(row_name) == "string" then
        local row_fname, row_err =
            make_existing_fname_83(row_name)

        if row_fname == nil then
            return false,
                "material data row FName failed: " ..
                tostring(row_err)
        end

        row_name = row_fname
    end

    local handle_ok, handle_err = write_row_handle_83(
        target.SwordMaterialData,
        resolved.data_table,
        row_name
    )
    if not handle_ok then
        return false, "SwordMaterialData write failed: " .. tostring(handle_err)
    end

    return true, nil
end

local function capture_plain_state_83(part)
    -- IMPORTANT: strings + primitive/plain Lua values only.
    return {
        sword_part = safe_name(part.SwordPart),
        material = safe_name(part.SwordMaterial),
        polish = num(part.Polish),
        scale = num(part.Scale),
        rotation = num(part.Rotation),
        sink = num(part.Sink),
        stretch = num(part.Stretch, 1),
        curvature = num(part.Curvature),
        flipped_slot = part.bIsInFlippedSlot and true or false,
        manual_flip = part.bManualFlip and true or false,
        slots_version = num(part.SlotsVersion),
        deflection = {
            num(part.Deflection and part.Deflection.X),
            num(part.Deflection and part.Deflection.Y),
            num(part.Deflection and part.Deflection.Z),
            num(part.Deflection and part.Deflection.W, 1)
        },
        curvature_vals = {
            num(part.CurvatureVals and part.CurvatureVals.X),
            num(part.CurvatureVals and part.CurvatureVals.Y)
        },
        circle_rotations = {
            num(part.CircleRotations and part.CircleRotations.X),
            num(part.CircleRotations and part.CircleRotations.Y),
            num(part.CircleRotations and part.CircleRotations.Z),
            num(part.CircleRotations and part.CircleRotations.W, 1)
        },
        slot_children = read_slot_children_ordered(part),
        free_count = part.FreeChildren and #part.FreeChildren or 0
    }
end

local function plain_state_from_saved_83(saved, target_order)
    local local_slots = parse_int_list(saved.slot_children or "")
    local native_slots = {}

    for i, local_child in ipairs(local_slots) do
        if local_child < 0 then
            native_slots[i] = -1
        else
            local native_child = target_order[local_child + 1]
            if native_child == nil then
                return nil, "no native mapping for local child " .. tostring(local_child)
            end
            native_slots[i] = native_child
        end
    end

    return {
        sword_part = saved.sword_part,
        material = saved.material,
        polish = tonumber(saved.polish) or 0,
        scale = tonumber(saved.scale) or 1,
        rotation = tonumber(saved.rotation) or 0,
        sink = tonumber(saved.sink) or 0,
        stretch = tonumber(saved.stretch) or 1,
        curvature = tonumber(saved.curvature) or 0,
        flipped_slot = parse_bool(saved.flipped_slot),
        manual_flip = parse_bool(saved.manual_flip),
        slots_version = tonumber(saved.slots_version) or 0,
        deflection = parse_num_list(saved.deflection or "0,0,0,1"),
        curvature_vals = parse_num_list(saved.curvature_vals or "0,0"),
        circle_rotations = parse_num_list(saved.circle_rotations or "0,0,0,1"),
        slot_children = native_slots,
        free_count = tonumber(saved.free_child_count or "0") or 0
    }, nil
end

local function write_plain_geometry_83(target, state)
    local ok, err = pcall(function()
        target.Polish = state.polish
        target.Scale = state.scale
        target.Rotation = state.rotation
        target.Sink = state.sink
        target.Stretch = state.stretch
        target.Curvature = state.curvature
        target.bIsInFlippedSlot = state.flipped_slot
        target.bManualFlip = state.manual_flip
        target.SlotsVersion = state.slots_version

        if target.Deflection then
            target.Deflection.X = state.deflection[1] or 0
            target.Deflection.Y = state.deflection[2] or 0
            target.Deflection.Z = state.deflection[3] or 0
            target.Deflection.W = state.deflection[4] or 1
        end

        if target.CurvatureVals then
            target.CurvatureVals.X = state.curvature_vals[1] or 0
            target.CurvatureVals.Y = state.curvature_vals[2] or 0
        end

        if target.CircleRotations then
            target.CircleRotations.X = state.circle_rotations[1] or 0
            target.CircleRotations.Y = state.circle_rotations[2] or 0
            target.CircleRotations.Z = state.circle_rotations[3] or 0
            target.CircleRotations.W = state.circle_rotations[4] or 1
        end
    end)

    if not ok then
        return false, "geometry scalar write failed: " .. tostring(err)
    end

    local slots_ok, slots_err = write_slot_children_native(
        target,
        state.slot_children
    )

    if not slots_ok then
        return false, "SlotChildren write failed: " .. tostring(slots_err)
    end

    return true, nil
end

local function full_import_83()
    log("============================================================")
    log("FULL_IMPORT_BEGIN file=" .. PCL_IMPORT_FILENAME)

    local path = OUTPUT_DIR .. PCL_IMPORT_FILENAME
    local prefab, parse_err = parse_pcl_file(path)
    if prefab == nil then
        log("FULL_IMPORT_ERROR " .. tostring(parse_err))
        return
    end

    local forge, piece, design, state_err = get_piece_and_design()
    if state_err then
        log("FULL_IMPORT_ERROR " .. tostring(state_err))
        return
    end

    local live_parts = capture_parts(design)
    local order = collect_subtree(live_parts, PCL_IMPORT_TARGET_ROOT)
    local count = tonumber(prefab.meta.part_count or "-1") or -1

    log("FULL_IMPORT_FILE_PART_COUNT=" .. tostring(count))
    log("FULL_IMPORT_TARGET_PART_COUNT=" .. tostring(#order))

    if #order ~= count then
        log("FULL_IMPORT_ERROR part count mismatch")
        return
    end

    local modules = find_game_modules_7()
    local part_tables = collect_unique_datatables_7(
        modules, "SwordPartDataTables"
    )
    local material_tables = collect_unique_datatables_7(
        modules, "SwordMaterialDataTables"
    )

    if #part_tables == 0 or #material_tables == 0 then
        log("FULL_IMPORT_ERROR required DataTables unavailable")
        return
    end

    local saved_states = {}
    local saved_part_rows = {}
    local saved_material_rows = {}
    local backup_parts = {}

    -- FULL read-only preflight and plain backup.
    for local_index = 0, count - 1 do
        local saved = prefab.parts[local_index]
        local native_index = order[local_index + 1]
        local target = live_parts[native_index]

        if saved == nil or target == nil then
            log("FULL_IMPORT_ERROR missing saved/target local=" ..
                tostring(local_index))
            return
        end

        local state, convert_err = plain_state_from_saved_83(saved, order)
        if state == nil then
            log("FULL_IMPORT_ERROR local=" .. tostring(local_index) ..
                " " .. tostring(convert_err))
            return
        end

        local part_row, part_err = resolve_part_83(
            part_tables, saved.sword_part
        )
        if part_row == nil then
            log("FULL_IMPORT_ERROR local=" .. tostring(local_index) ..
                " " .. tostring(part_err))
            return
        end

        local material_row, mat_err = resolve_material_83(
            material_tables, saved.material
        )
        if material_row == nil then
            log("FULL_IMPORT_ERROR local=" .. tostring(local_index) ..
                " " .. tostring(mat_err))
            return
        end

        local target_slots = target.SlotChildren and #target.SlotChildren or 0
        local target_free = target.FreeChildren and #target.FreeChildren or 0

        if target_slots ~= #state.slot_children then
            log("FULL_IMPORT_ERROR local=" .. tostring(local_index) ..
                " SlotChildren shape mismatch current=" ..
                tostring(target_slots) ..
                " saved=" .. tostring(#state.slot_children))
            return
        end

        if target_free ~= state.free_count then
            log("FULL_IMPORT_ERROR local=" .. tostring(local_index) ..
                " FreeChildren shape mismatch current=" ..
                tostring(target_free) ..
                " saved=" .. tostring(state.free_count))
            return
        end

        saved_states[local_index + 1] = state
        saved_part_rows[local_index + 1] = part_row
        saved_material_rows[local_index + 1] = material_row
        backup_parts[local_index + 1] = capture_plain_state_83(target)

        log(
            "FULL_IMPORT_PREFLIGHT local=" .. tostring(local_index) ..
            " native=" .. tostring(native_index) ..
            " current_part=" .. safe_name(target.SwordPart) ..
            " saved_part=" .. tostring(saved.sword_part) ..
            " current_material=" .. safe_name(target.SwordMaterial) ..
            " saved_material=" .. tostring(saved.material) ..
            " slots=" .. tostring(target_slots)
        )
    end

    pcl_83_backup = {
        order = {},
        parts = {}
    }

    for i, native_index in ipairs(order) do
        pcl_83_backup.order[i] = native_index
        pcl_83_backup.parts[i] = backup_parts[i]
    end

    log("FULL_IMPORT_BACKUP_OK plain_lua_only=true")

    -- Apply proven-safe identity + material + geometry writes.
    for i, native_index in ipairs(order) do
        local local_index = i - 1
        local target = live_parts[native_index]
        local state = saved_states[i]

        log("FULL_IMPORT_WRITE_BEGIN local=" .. tostring(local_index))

        if safe_name(target.SwordPart) ~= state.sword_part then
            local ok, err = write_part_identity_83(
                target,
                state.sword_part,
                saved_part_rows[i]
            )
            if not ok then
                log("FULL_IMPORT_ERROR part identity local=" ..
                    tostring(local_index) .. " " .. tostring(err))
                return
            end
        end

        if safe_name(target.SwordMaterial) ~= state.material then
            local ok, err = write_material_identity_83(
                target,
                state.material,
                saved_material_rows[i]
            )
            if not ok then
                log("FULL_IMPORT_ERROR material identity local=" ..
                    tostring(local_index) .. " " .. tostring(err))
                return
            end
        end

        local geom_ok, geom_err = write_plain_geometry_83(target, state)
        if not geom_ok then
            log("FULL_IMPORT_ERROR geometry local=" ..
                tostring(local_index) .. " " .. tostring(geom_err))
            return
        end

        log(
            "FULL_IMPORT_WRITE_OK local=" .. tostring(local_index) ..
            " part=" .. safe_name(target.SwordPart) ..
            " material=" .. safe_name(target.SwordMaterial)
        )
    end

    log("FULL_IMPORT_ALL_WRITES_OK")
    log("FULL_IMPORT_BEFORE_ENTERFORGEMODE")

    local enter_ok, enter_err = enter_piece_again(piece)
    if not enter_ok then
        log("FULL_IMPORT_ERROR EnterForgeMode: " .. tostring(enter_err))
        return
    end

    log("FULL_IMPORT_AFTER_ENTERFORGEMODE")
    log("FULL_IMPORT_OK")
    log("Press CTRL+ALT+V to verify, then CTRL+ALT+R to restore.")
    log("============================================================")
end

local function full_verify_83()
    log("============================================================")
    log("FULL_VERIFY_BEGIN")

    local path = OUTPUT_DIR .. PCL_IMPORT_FILENAME
    local prefab, parse_err = parse_pcl_file(path)
    if prefab == nil then
        log("FULL_VERIFY_ERROR " .. tostring(parse_err))
        return
    end

    local forge = find_forge()
    if not is_valid(forge) then
        log("FULL_VERIFY_ERROR no ForgeMode")
        return
    end

    local ok, err = pcall(function()
        forge:SerializeSwordPartActorsToData()
    end)
    if not ok then
        log("FULL_VERIFY_ERROR serializer: " .. tostring(err))
        return
    end

    local piece = forge:GetPiece()
    local live_parts = capture_parts(piece.WeaponDesignDefinition)
    local order = collect_subtree(live_parts, PCL_IMPORT_TARGET_ROOT)
    local count = tonumber(prefab.meta.part_count or "-1") or -1

    local all_ok = (#order == count)

    for local_index = 0, math.min(#order, count) - 1 do
        local p = live_parts[order[local_index + 1]]
        local saved = prefab.parts[local_index]

        local part_match = safe_name(p.SwordPart) == saved.sword_part
        local material_match = safe_name(p.SwordMaterial) == saved.material
        local rotation_match = num(p.Rotation) == (tonumber(saved.rotation) or 0)
        local stretch_match =
            math.abs(num(p.Stretch, 1) - (tonumber(saved.stretch) or 1)) < 0.0005
        local scale_match =
            math.abs(num(p.Scale, 1) - (tonumber(saved.scale) or 1)) < 0.0005

        local slots_saved_local = parse_int_list(saved.slot_children or "")
        local slots_expected_native = {}
        for i, child in ipairs(slots_saved_local) do
            if child < 0 then
                slots_expected_native[i] = -1
            else
                slots_expected_native[i] = order[child + 1]
            end
        end

        local current_slots = read_slot_children_ordered(p)
        local slots_match = (#current_slots == #slots_expected_native)

        if slots_match then
            for i = 1, #current_slots do
                if current_slots[i] ~= slots_expected_native[i] then
                    slots_match = false
                    break
                end
            end
        end

        local local_ok =
            part_match and material_match and rotation_match and
            stretch_match and scale_match and slots_match

        if not local_ok then all_ok = false end

        log(
            "FULL_VERIFY_PART local=" .. tostring(local_index) ..
            " part=" .. tostring(part_match) ..
            " material=" .. tostring(material_match) ..
            " scale=" .. tostring(scale_match) ..
            " rotation=" .. tostring(rotation_match) ..
            " stretch=" .. tostring(stretch_match) ..
            " slots=" .. tostring(slots_match)
        )
    end

    if all_ok then
        log("FULL_VERIFY_OK live actors match saved prefab")
    else
        log("FULL_VERIFY_MISMATCH")
    end

    log("============================================================")
end

local function full_restore_83()
    log("============================================================")
    log("FULL_RESTORE_BEGIN")

    if pcl_83_backup == nil then
        log("FULL_RESTORE_ERROR no backup")
        return
    end

    local forge = find_forge()
    if not is_valid(forge) then
        log("FULL_RESTORE_ERROR no ForgeMode")
        return
    end

    local serialize_ok, serialize_err = pcall(function()
        forge:SerializeSwordPartActorsToData()
    end)
    if not serialize_ok then
        log("FULL_RESTORE_ERROR serializer: " .. tostring(serialize_err))
        return
    end

    local piece = forge:GetPiece()
    local parts = capture_parts(piece.WeaponDesignDefinition)

    local modules = find_game_modules_7()
    local part_tables = collect_unique_datatables_7(
        modules, "SwordPartDataTables"
    )
    local material_tables = collect_unique_datatables_7(
        modules, "SwordMaterialDataTables"
    )

    -- Pre-resolve all old identities before mutation.
    local old_part_rows = {}
    local old_material_rows = {}

    for i, state in ipairs(pcl_83_backup.parts) do
        local pr, perr = resolve_part_83(part_tables, state.sword_part)
        if pr == nil then
            log("FULL_RESTORE_ERROR backup part resolve local=" ..
                tostring(i - 1) .. " " .. tostring(perr))
            return
        end

        local mr, merr = resolve_material_83(material_tables, state.material)
        if mr == nil then
            log("FULL_RESTORE_ERROR backup material resolve local=" ..
                tostring(i - 1) .. " " .. tostring(merr))
            return
        end

        old_part_rows[i] = pr
        old_material_rows[i] = mr
    end

    for i, native_index in ipairs(pcl_83_backup.order) do
        local local_index = i - 1
        local target = parts[native_index]
        local state = pcl_83_backup.parts[i]

        if target == nil then
            log("FULL_RESTORE_ERROR missing native=" .. tostring(native_index))
            return
        end

        log("FULL_RESTORE_WRITE_BEGIN local=" .. tostring(local_index))

        if safe_name(target.SwordPart) ~= state.sword_part then
            local ok, err = write_part_identity_83(
                target, state.sword_part, old_part_rows[i]
            )
            if not ok then
                log("FULL_RESTORE_ERROR part local=" ..
                    tostring(local_index) .. " " .. tostring(err))
                return
            end
        end

        if safe_name(target.SwordMaterial) ~= state.material then
            local ok, err = write_material_identity_83(
                target, state.material, old_material_rows[i]
            )
            if not ok then
                log("FULL_RESTORE_ERROR material local=" ..
                    tostring(local_index) .. " " .. tostring(err))
                return
            end
        end

        local geom_ok, geom_err = write_plain_geometry_83(target, state)
        if not geom_ok then
            log("FULL_RESTORE_ERROR geometry local=" ..
                tostring(local_index) .. " " .. tostring(geom_err))
            return
        end

        log("FULL_RESTORE_WRITE_OK local=" .. tostring(local_index))
    end

    local enter_ok, enter_err = enter_piece_again(piece)
    if not enter_ok then
        log("FULL_RESTORE_ERROR EnterForgeMode: " .. tostring(enter_err))
        return
    end

    log("FULL_RESTORE_OK")
    log("============================================================")
end

RegisterKeyBind(Key.K, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(full_import_83)
end)

RegisterKeyBind(Key.V, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(full_verify_83)
end)

RegisterKeyBind(Key.R, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(full_restore_83)
end)

log("Phase 8.3 combined safe importer loaded.")
log("CTRL+ALT+K = full prefab import into existing same-shaped subtree.")
log("CTRL+ALT+V = full live verification.")
log("CTRL+ALT+R = full pre-import restore.")


-- ============================================================
-- Phase 9: native catalogue-click / native array-growth proof
-- ============================================================
--
-- Goal:
-- Avoid manually resizing Unreal TArrays.
--
-- We use a REAL live UWSwordPartButton and invoke its contained
-- CommonButtonBase:HandleButtonClicked(), exactly through the catalogue UI path.
--
-- CTRL+ALT+C = enumerate live SwordPart catalogue buttons
-- CTRL+ALT+J = programmatically click saved prefab root part (80_Misc_Cube)
-- CTRL+ALT+N = after manually placing the preview, serialize and report count
--
-- This probe does NOT mutate WeaponDesignDefinition arrays directly.

local PCL_NATIVE_CLICK_TARGET = "80_Misc_Cube"
local pcl9_count_before_click = nil

local function find_live_part_buttons_9()
    local candidates = {}

    local ok, result = pcall(function()
        return FindAllOf("WBP_SwordPartButton_C")
    end)

    if ok and result ~= nil then
        for _, obj in pairs(result) do
            if is_valid(obj) then
                table.insert(candidates, obj)
            end
        end
    end

    if #candidates == 0 then
        ok, result = pcall(function()
            return FindAllOf("UWSwordPartButton")
        end)

        if ok and result ~= nil then
            for _, obj in pairs(result) do
                if is_valid(obj) then
                    table.insert(candidates, obj)
                end
            end
        end
    end

    return candidates
end

local function button_row_name_9(button)
    if not is_valid(button) then return "None" end

    local ok, value = pcall(function()
        local handle = button.SwordPartDataRowHandle
        if handle == nil then return "None" end
        return safe_name(handle.RowName)
    end)

    if ok then return tostring(value) end
    return "ERROR"
end

local function dump_catalogue_buttons_9()
    log("============================================================")
    log("CATALOGUE_BUTTON_SCAN_BEGIN")

    local buttons = find_live_part_buttons_9()
    log("CATALOGUE_BUTTON_COUNT=" .. tostring(#buttons))

    for i, button in ipairs(buttons) do
        local row = button_row_name_9(button)

        local material = "None"
        local scale = "?"
        local stretch = "?"
        local locked = "?"

        pcall(function()
            material = safe_name(button.SwordMaterialName)
        end)

        pcall(function()
            scale = tostring(num(button.Scale, 1))
        end)

        pcall(function()
            stretch = tostring(num(button.Stretch, 1))
        end)

        pcall(function()
            locked = tostring(button.bIsSwordPartLocked)
        end)

        log(
            "CATALOGUE_BUTTON index=" .. tostring(i - 1) ..
            " row=" .. row ..
            " material=" .. material ..
            " scale=" .. scale ..
            " stretch=" .. stretch ..
            " locked=" .. locked ..
            " object=" .. safe_full_name(button)
        )
    end

    log("CATALOGUE_BUTTON_SCAN_END")
    log("============================================================")
end

local function find_button_for_row_9(wanted)
    local buttons = find_live_part_buttons_9()

    for _, button in ipairs(buttons) do
        if button_row_name_9(button) == wanted then
            return button
        end
    end

    return nil
end

local function find_handling_component_9()
    local forge = find_forge()
    if is_valid(forge) then
        local handling = nil
        pcall(function() handling = forge.ForgeModeFrontend.SwordPartHandling end)
        if is_valid(handling) then return handling end
    end
    local ok, obj = pcall(function()
        return FindFirstOf("BP_SwordPartHandlingComponent_C")
    end)

    if ok and is_valid(obj) then
        return obj
    end

    ok, obj = pcall(function()
        return FindFirstOf("SwordPartHandlingComponent")
    end)

    if ok and is_valid(obj) then
        return obj
    end

    return nil
end

local function log_preview_state_9(label)
    local handling = find_handling_component_9()

    if not is_valid(handling) then
        log(label .. "_HANDLING=None")
        return
    end

    log(label .. "_HANDLING=" .. safe_full_name(handling))

    local has_preview = false
    local ok, result = pcall(function()
        return handling:HasPreviewSwordPart()
    end)

    if ok then
        has_preview = result and true or false
    end

    log(label .. "_HAS_PREVIEW=" .. tostring(has_preview))

    local preview = nil
    pcall(function()
        preview = handling.PreviewSwordPartActor
    end)

    if is_valid(preview) then
        local part_name = "None"
        local material_name = "None"

        pcall(function()
            part_name = safe_name(preview.SwordPartDataHandle.RowName)
        end)

        pcall(function()
            material_name = safe_name(preview.SwordMaterialName)
        end)

        log(
            label .. "_PREVIEW_ACTOR=" .. safe_full_name(preview) ..
            " part=" .. part_name ..
            " material=" .. material_name
        )
    else
        log(label .. "_PREVIEW_ACTOR=None")
    end
end

local function get_serialized_part_count_9()
    local forge, piece, design, err = get_piece_and_design()

    if err then
        return nil, err
    end

    if design == nil or design.AppliedSwordParts == nil then
        return nil, "AppliedSwordParts unavailable"
    end

    return #design.AppliedSwordParts, nil
end

local function native_click_probe_9()
    log("============================================================")
    log("NATIVE_CLICK_BEGIN target=" .. PCL_NATIVE_CLICK_TARGET)

    local count, count_err = get_serialized_part_count_9()

    if count == nil then
        log("NATIVE_CLICK_ERROR initial serialize/count: " ..
            tostring(count_err))
        return
    end

    pcl9_count_before_click = count
    log("NATIVE_CLICK_PART_COUNT_BEFORE=" .. tostring(count))

    log_preview_state_9("NATIVE_CLICK_BEFORE")

    local button = find_button_for_row_9(PCL_NATIVE_CLICK_TARGET)

    if not is_valid(button) then
        log("NATIVE_CLICK_ERROR no live catalogue button for " ..
            PCL_NATIVE_CLICK_TARGET)
        log("Open/scroll the part catalogue so that the Cube tile exists,")
        log("then use CTRL+ALT+C to confirm its row is present.")
        return
    end

    log("NATIVE_CLICK_BUTTON=" .. safe_full_name(button))
    log("NATIVE_CLICK_BUTTON_ROW=" .. button_row_name_9(button))

    local common_button = nil
    local ok, err = pcall(function()
        common_button = button.Button
    end)

    if not ok or not is_valid(common_button) then
        log("NATIVE_CLICK_ERROR button.Button unavailable: " .. tostring(err))
        return
    end

    log("NATIVE_CLICK_COMMON_BUTTON=" .. safe_full_name(common_button))
    log("NATIVE_CLICK_BEFORE_HANDLEBUTTONCLICKED")

    local click_ok, click_err = pcall(function()
        common_button:HandleButtonClicked()
    end)

    if not click_ok then
        log("NATIVE_CLICK_ERROR HandleButtonClicked failed: " ..
            tostring(click_err))
        return
    end

    log("NATIVE_CLICK_AFTER_HANDLEBUTTONCLICKED")
    log_preview_state_9("NATIVE_CLICK_AFTER")

    log("NATIVE_CLICK_OK")
    log("If a Cube is now held/previewed, manually LEFT CLICK it onto")
    log("an EMPTY valid hardpoint. Then press CTRL+ALT+N.")
    log("Press X instead if you want to cancel the preview.")
    log("============================================================")
end

local function verify_native_growth_9()
    log("============================================================")
    log("NATIVE_GROWTH_VERIFY_BEGIN")

    local count, err = get_serialized_part_count_9()

    if count == nil then
        log("NATIVE_GROWTH_VERIFY_ERROR " .. tostring(err))
        return
    end

    log("NATIVE_GROWTH_PART_COUNT_NOW=" .. tostring(count))

    if pcl9_count_before_click ~= nil then
        log("NATIVE_GROWTH_PART_COUNT_BEFORE=" ..
            tostring(pcl9_count_before_click))

        local delta = count - pcl9_count_before_click
        log("NATIVE_GROWTH_DELTA=" .. tostring(delta))

        if delta > 0 then
            log("NATIVE_GROWTH_OK Bladesong grew AppliedSwordParts natively")
        else
            log("NATIVE_GROWTH_NO_CHANGE no additional serialized part detected")
        end
    else
        log("NATIVE_GROWTH_WARNING no in-session pre-click count available")
    end

    log_preview_state_9("NATIVE_GROWTH")
    log("============================================================")
end

RegisterKeyBind(Key.C, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(dump_catalogue_buttons_9)
end)

RegisterKeyBind(Key.J, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(native_click_probe_9)
end)

RegisterKeyBind(Key.N, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(verify_native_growth_9)
end)

log("Phase 9 native catalogue-click probe loaded.")
log("CTRL+ALT+C = list live catalogue part buttons.")
log("CTRL+ALT+J = programmatically click 80_Misc_Cube.")
log("CTRL+ALT+N = serialize/count after manually placing preview.")


-- ============================================================
-- Phase 10: exact hardpoint cursor targeting proof
-- ============================================================
--
-- Goal:
-- Automatically target a specific slot on an existing SwordPartActor.
--
-- Proven prerequisites:
--   - catalogue click creates a real preview + provisional AppliedSwordPart
--   - preview snapping stages native parent/slot topology
--   - EnterForgeMode(Piece) finalizes staged topology
--
-- This probe:
--   1. maps serialized native indices -> live SwordPartActors
--   2. targets native parent index 5 (the recently inserted Cube root)
--   3. reads that actor's SwordPartData.Slots
--   4. targets slot index 2 (saved prefab root -> Grip child slot)
--   5. gets slot BoneName
--   6. gets component socket world location
--   7. projects world point to screen
--   8. moves mouse to that screen point
--   9. waits briefly, then reports BestSwordPartSlotParent + staged link
--
-- CTRL+ALT+G = target native 5, slot 2
--
-- READ-ONLY except for moving the mouse cursor.

local PCL10_TARGET_NATIVE = 5
local PCL10_TARGET_SLOT = 2

local function actor_part_name_10(actor)
    if not is_valid(actor) then return "None" end

    local name = "Unknown"

    pcall(function()
        if actor.SwordPartDataHandle ~= nil then
            name = safe_name(actor.SwordPartDataHandle.RowName)
        end
    end)

    return tostring(name)
end

local function get_actor_component_10(actor)
    if not is_valid(actor) then
        log("SLOT_TARGET_COMPONENT_ERROR actor invalid")
        return nil
    end

    -- Preferred safe path: generic reflected Actor API.
    -- The dump exposes K2_GetRootComponent() and returns SceneComponent.
    log("SLOT_TARGET_COMPONENT_ROOT_BEGIN")

    local root_component = nil
    local ok, err = pcall(function()
        root_component = actor:K2_GetRootComponent()
    end)

    if ok and is_valid(root_component) then
        log("SLOT_TARGET_COMPONENT_ROOT_OK=" ..
            safe_full_name(root_component))
        return root_component
    end

    log("SLOT_TARGET_COMPONENT_ROOT_FAIL=" .. tostring(err))

    -- Diagnostic fallback: direct named properties, if this particular actor
    -- class happens to expose them. These are attempted only after the safe
    -- reflected root-component call.
    local names = {
        "StaticMeshComponent",
        "SkeletalMeshComponent",
        "ProceduralMeshComponent",
        "SceneComponent"
    }

    for _, field_name in ipairs(names) do
        local component = nil

        local field_ok, field_err = pcall(function()
            component = actor[field_name]
        end)

        log("SLOT_TARGET_COMPONENT_FIELD name=" .. field_name ..
            " ok=" .. tostring(field_ok) ..
            " valid=" .. tostring(is_valid(component)))

        if field_ok and is_valid(component) then
            log("SLOT_TARGET_COMPONENT_FIELD_OK name=" .. field_name ..
                " object=" .. safe_full_name(component))
            return component
        end
    end

    return nil
end

local function get_root_actor_10(forge)
    local actor = nil

    pcall(function()
        actor = forge:GetRootSwordPartActor()
    end)

    return actor
end

local function collect_live_sword_part_actors_10()
    local actors = {}
    local seen = {}

    local function add_class(class_name)
        local ok, found = pcall(function()
            return FindAllOf(class_name)
        end)

        if not ok or found == nil then
            return
        end

        for _, actor in pairs(found) do
            if is_valid(actor) then
                local full = safe_full_name(actor)

                -- Ignore class defaults / CDOs.
                if not string.find(full, "Default__SwordPart", 1, true) and
                   not seen[full] then
                    seen[full] = true
                    table.insert(actors, actor)
                end
            end
        end
    end

    add_class("SwordPartStaticMeshActor")
    add_class("SwordPartSkeletalMeshActor")
    add_class("SwordPartDeformableStaticMeshActor")
    add_class("SwordPartDecalActor")
    add_class("SwordPartEmptyActor")
    add_class("SwordPartActor")

    return actors
end

local function live_actor_row_10(actor)
    if not is_valid(actor) then
        return "None"
    end

    local row = "None"

    pcall(function()
        if actor.SwordPartDataHandle ~= nil then
            row = safe_name(actor.SwordPartDataHandle.RowName)
        end
    end)

    return tostring(row)
end

local function live_slot_children_10(actor)
    local result = {}

    if not is_valid(actor) then
        return result
    end

    local map = nil
    pcall(function()
        map = actor.SlotChildParts
    end)

    if map == nil then
        return result
    end

    pcall(function()
        map:ForEach(function(kp, vp)
            local key = kp:get()
            local child = vp:get()

            if key ~= nil and is_valid(child) then
                result[key] = child
            end
        end)
    end)

    return result
end

-- Global to avoid consuming another local in the already-full main chunk.
-- FreeChildParts is TMap<SwordPartActor*, FTransform>; preserve its iteration
-- order so it corresponds to FAppliedSwordPart.FreeChildren after serialize.
function PCL151132LiveFreeChildren(actor)
    local result = {}

    if not is_valid(actor) then
        return result
    end

    local map = nil
    pcall(function()
        map = actor.FreeChildParts
    end)

    if map == nil then
        return result
    end

    pcall(function()
        map:ForEach(function(kp, vp)
            local child = kp:get()

            if is_valid(child) then
                table.insert(result, {
                    actor = child
                })
            end
        end)
    end)

    return result
end

local function build_actor_map_10(design, ignored_root_actor)
    local parts = {}
    local actors = {}
    local visited_native = {}
    local visited_actor = {}
    local slot_edges = {}
    local free_edges = {}

    -- Phase 15.11.36: snapshot every reflected child index into plain Lua
    -- tables before doing any recursive matching.  UE4SS 3.0.1 can corrupt
    -- nested TArray::ForEach callback values on very large FreeChildren graphs
    -- (the callback value may arrive as a UScriptStruct instead of int32).
    -- Never recurse while a reflected ForEach callback is active.
    design.AppliedSwordParts:ForEach(function(lua_index, elem)
        parts[lua_index - 1] = elem:get()
    end)

    for native_index, part in pairs(parts) do
        slot_edges[native_index] = {}
        free_edges[native_index] = {}

        if part ~= nil and part.SlotChildren ~= nil then
            pcall(function()
                part.SlotChildren:ForEach(function(lua_slot, elem)
                    local child_native = elem:get()
                    if type(lua_slot) == "number" and
                       type(child_native) == "number" then
                        slot_edges[native_index][lua_slot - 1] = child_native
                    else
                        log("PCL15_11_36_EXPORT_SLOT_VALUE_SKIPPED parent=" ..
                            tostring(native_index) ..
                            " lua_slot_type=" .. tostring(type(lua_slot)) ..
                            " child_type=" .. tostring(type(child_native)))
                    end
                end)
            end)
        end

        if part ~= nil and part.FreeChildren ~= nil then
            pcall(function()
                part.FreeChildren:ForEach(function(lua_free, elem)
                    local data = elem:get()
                    local child_native = data and data.Idx or nil
                    if type(lua_free) == "number" and
                       type(child_native) == "number" then
                        free_edges[native_index][lua_free] = child_native
                    else
                        log("PCL15_11_36_EXPORT_FREE_VALUE_SKIPPED parent=" ..
                            tostring(native_index) ..
                            " lua_free_type=" .. tostring(type(lua_free)) ..
                            " child_type=" .. tostring(type(child_native)))
                    end
                end)
            end)
        end
    end

    local root_native = 0
    pcall(function()
        root_native = design.RootSwordPartIdx
    end)

    local live_actors = collect_live_sword_part_actors_10()

    log("PCL15_11_36_EXPORT_GRAPH_SNAPSHOT parts=" .. tostring(#parts + 1))
    log("SLOT_TARGET_LIVE_ACTOR_COUNT=" .. tostring(#live_actors))
    log("SLOT_TARGET_EXPECTED_ROOT native=" .. tostring(root_native) ..
        " part=" ..
        (parts[root_native] and safe_name(parts[root_native].SwordPart) or "None"))

    -- Score/match a candidate recursively against the complete serialized
    -- SlotChildren + FreeChildren graph.  All serialized edges are plain Lua
    -- values now, so recursive_match never nests UE4SS reflected ForEach calls.
    local function recursive_match(native_index, actor, dry_run, depth)
        depth = depth or 0

        if depth > 64 then
            return false
        end

        local part = parts[native_index]
        if part == nil or not is_valid(actor) then
            return false
        end

        local expected_row = safe_name(part.SwordPart)
        local actual_row = live_actor_row_10(actor)

        if expected_row ~= actual_row then
            return false
        end

        local child_map = live_slot_children_10(actor)
        local free_children = PCL151132LiveFreeChildren(actor)
        local serialized_slots = slot_edges[native_index] or {}
        local serialized_frees = free_edges[native_index] or {}

        for slot_native, child_native in pairs(serialized_slots) do
            if type(child_native) == "number" and child_native >= 0 then
                local child_actor = child_map[slot_native]

                if not is_valid(child_actor) then
                    return false
                end

                if not recursive_match(
                    child_native,
                    child_actor,
                    true,
                    depth + 1
                ) then
                    return false
                end
            end
        end

        for lua_free, child_native in pairs(serialized_frees) do
            if type(child_native) == "number" and child_native >= 0 then
                local live_free = free_children[lua_free]
                local child_actor = live_free and live_free.actor or nil

                if not is_valid(child_actor) then
                    return false
                end

                if not recursive_match(
                    child_native,
                    child_actor,
                    true,
                    depth + 1
                ) then
                    return false
                end
            end
        end

        if not dry_run then
            actors[native_index] = actor

            for slot_native, child_native in pairs(serialized_slots) do
                if type(child_native) == "number" and child_native >= 0 then
                    local child_actor = child_map[slot_native]

                    if is_valid(child_actor) then
                        recursive_match(
                            child_native,
                            child_actor,
                            false,
                            depth + 1
                        )
                    end
                end
            end

            for lua_free, child_native in pairs(serialized_frees) do
                if type(child_native) == "number" and child_native >= 0 then
                    local live_free = free_children[lua_free]
                    local child_actor = live_free and live_free.actor or nil

                    if is_valid(child_actor) then
                        recursive_match(
                            child_native,
                            child_actor,
                            false,
                            depth + 1
                        )
                    end
                end
            end
        end

        return true
    end

    local root_actor = nil

    for _, candidate in ipairs(live_actors) do
        if recursive_match(root_native, candidate, true, 0) then
            root_actor = candidate
            break
        end
    end

    if is_valid(root_actor) then
        log("SLOT_TARGET_MATCHED_ROOT_ACTOR=" ..
            safe_full_name(root_actor) ..
            " part=" .. live_actor_row_10(root_actor))

        recursive_match(root_native, root_actor, false, 0)
    else
        log("SLOT_TARGET_MATCHED_ROOT_ACTOR=None")

        -- Diagnostic dump so a failed match is useful instead of opaque.
        for i, actor in ipairs(live_actors) do
            if i <= 50 then
                local children = live_slot_children_10(actor)
                local child_desc = {}

                for slot, child in pairs(children) do
                    table.insert(
                        child_desc,
                        tostring(slot) .. ":" .. live_actor_row_10(child)
                    )
                end

                table.sort(child_desc)

                log("SLOT_TARGET_ACTOR_DIAG index=" .. tostring(i - 1) ..
                    " row=" .. live_actor_row_10(actor) ..
                    " children=[" .. table.concat(child_desc, ",") .. "]" ..
                    " object=" .. safe_full_name(actor))
            end
        end
    end

    for native_index, actor in pairs(actors) do
        log("SLOT_TARGET_MAP native=" .. tostring(native_index) ..
            " row=" .. live_actor_row_10(actor) ..
            " actor=" .. safe_full_name(actor))
    end

    return parts, actors, root_native
end

local function get_sword_part_row_10(actor)
    if not is_valid(actor) then
        return nil, "actor invalid"
    end

    local row_name = live_actor_row_10(actor)

    log("SLOT_TARGET_ROW_RESOLVE_BEGIN row=" .. tostring(row_name))

    local modules = find_game_modules_7()
    log("SLOT_TARGET_ROW_MODULES=" .. tostring(#modules))

    local part_tables = collect_unique_datatables_7(
        modules,
        "SwordPartDataTables"
    )

    log("SLOT_TARGET_ROW_TABLES=" .. tostring(#part_tables))

    if #part_tables == 0 then
        return nil, "no SwordPartDataTables"
    end

    local resolved = find_row_in_tables_7(part_tables, row_name)

    if resolved == nil then
        return nil, "row not found through configured tables: " ..
            tostring(row_name)
    end

    log("SLOT_TARGET_ROW_RESOLVE_OK row=" .. tostring(row_name) ..
        " table=" .. safe_full_name(resolved.data_table))

    return resolved.row, nil
end

local function get_slot_struct_10(row, slot_native)
    if row == nil then
        return nil, "SwordPartData row nil"
    end

    log("SLOT_TARGET_SLOTS_ACCESS_BEGIN")

    local slots = nil
    local ok, err = pcall(function()
        slots = row.Slots
    end)

    if not ok or slots == nil then
        return nil, "SwordPartData.Slots unavailable: " .. tostring(err)
    end

    local slot_count = -1
    ok, err = pcall(function()
        slot_count = #slots
    end)

    if not ok then
        return nil, "Slots length failed: " .. tostring(err)
    end

    log("SLOT_TARGET_SLOTS_COUNT=" .. tostring(slot_count))

    if slot_native < 0 or slot_native >= slot_count then
        return nil, "slot index out of range: " .. tostring(slot_native) ..
            " count=" .. tostring(slot_count)
    end

    local result = nil

    log("SLOT_TARGET_SLOT_ITERATE_BEGIN wanted_native=" ..
        tostring(slot_native))

    ok, err = pcall(function()
        slots:ForEach(function(lua_index, elem)
            local native_index = lua_index - 1

            if native_index == slot_native then
                log("SLOT_TARGET_SLOT_ELEMENT_MATCH lua=" ..
                    tostring(lua_index) ..
                    " native=" .. tostring(native_index))

                result = elem:get()

                log("SLOT_TARGET_SLOT_ELEMENT_GET_OK")
            end
        end)
    end)

    if not ok then
        return nil, "Slots ForEach/get failed: " .. tostring(err)
    end

    if result == nil then
        return nil, "slot index not found: " .. tostring(slot_native)
    end

    log("SLOT_TARGET_SLOT_STRUCT_OK")

    return result, nil
end

local function get_player_controller_10()
    local pc = nil

    local ok, obj = pcall(function()
        return FindFirstOf("BP_BladesongPlayerController_C")
    end)

    if ok and is_valid(obj) then
        return obj
    end

    ok, obj = pcall(function()
        return FindFirstOf("PlayerController")
    end)

    if ok and is_valid(obj) then
        return obj
    end

    return nil
end

local function find_link_to_candidate_10(design, candidate_index)
    local result_parent = nil
    local result_slot = nil

    design.AppliedSwordParts:ForEach(function(lua_parent, elem)
        local parent_native = lua_parent - 1
        local part = elem:get()

        if part ~= nil and part.SlotChildren ~= nil then
            part.SlotChildren:ForEach(function(lua_slot, child_elem)
                if child_elem:get() == candidate_index then
                    result_parent = parent_native
                    result_slot = lua_slot - 1
                end
            end)
        end
    end)

    return result_parent, result_slot
end

local function report_target_state_10(expected_parent, expected_slot)
    local forge, piece, design, err = get_piece_and_design()

    if err then
        log("SLOT_TARGET_VERIFY_ERROR " .. tostring(err))
        return
    end

    local handling = find_handling_component_9()
    local preview = nil
    local best_parent = nil

    if is_valid(handling) then
        pcall(function() preview = handling.PreviewSwordPartActor end)
        pcall(function() best_parent = handling.BestSwordPartSlotParent end)
    end

    log("SLOT_TARGET_VERIFY_PREVIEW=" ..
        (is_valid(preview) and safe_full_name(preview) or "None"))

    log("SLOT_TARGET_VERIFY_BEST_PARENT=" ..
        (is_valid(best_parent) and safe_full_name(best_parent) or "None") ..
        " part=" .. actor_part_name_10(best_parent))

    local count = #design.AppliedSwordParts
    log("SLOT_TARGET_VERIFY_COUNT=" .. tostring(count))

    if count > 0 then
        local candidate_index = count - 1
        local parent_native, slot_native =
            find_link_to_candidate_10(design, candidate_index)

        if parent_native ~= nil then
            log("SLOT_TARGET_VERIFY_LINK parent_native=" ..
                tostring(parent_native) ..
                " slot_native=" .. tostring(slot_native) ..
                " child_native=" .. tostring(candidate_index))

            local match =
                parent_native == expected_parent and
                slot_native == expected_slot

            log("SLOT_TARGET_VERIFY_MATCH=" .. tostring(match))
        else
            log("SLOT_TARGET_VERIFY_LINK=None")
        end
    end
end

local function target_saved_slot_10()
    log("============================================================")
    log("SLOT_TARGET_BEGIN parent_native=" ..
        tostring(PCL10_TARGET_NATIVE) ..
        " slot_native=" .. tostring(PCL10_TARGET_SLOT))

    local forge, piece, design, state_err = get_piece_and_design()

    if state_err then
        log("SLOT_TARGET_ERROR " .. tostring(state_err))
        return
    end

    local root_actor = get_root_actor_10(forge)

    if not is_valid(root_actor) then
        log("SLOT_TARGET_ERROR root actor unavailable")
        return
    end

    local parts, actors, root_native =
        build_actor_map_10(design, root_actor)

    log("SLOT_TARGET_ROOT_NATIVE=" .. tostring(root_native))

    local target_actor = actors[PCL10_TARGET_NATIVE]

    if not is_valid(target_actor) then
        log("SLOT_TARGET_ERROR could not graph-map native index " ..
            tostring(PCL10_TARGET_NATIVE) .. " to live actor")
        return
    end

    log("SLOT_TARGET_PARENT_ACTOR=" .. safe_full_name(target_actor) ..
        " part=" .. actor_part_name_10(target_actor))

    local row, row_err = get_sword_part_row_10(target_actor)

    if row == nil then
        log("SLOT_TARGET_ERROR " .. tostring(row_err))
        return
    end

    local slot, slot_err =
        get_slot_struct_10(row, PCL10_TARGET_SLOT)

    if slot == nil then
        log("SLOT_TARGET_ERROR " .. tostring(slot_err))
        return
    end

    local bone_name = "None"
    local offset_x, offset_y, offset_z = 0, 0, 0

    log("SLOT_TARGET_BONENAME_READ_BEGIN")

    local bone_ok, bone_err = pcall(function()
        bone_name = safe_name(slot.BoneName)
    end)

    if not bone_ok then
        log("SLOT_TARGET_ERROR BoneName read failed: " .. tostring(bone_err))
        return
    end

    log("SLOT_TARGET_BONENAME_READ_OK bone=" .. tostring(bone_name))

    log("SLOT_TARGET_OFFSET_READ_BEGIN")

    local offset_ok, offset_err = pcall(function()
        local offset = slot.Offset
        offset_x = offset.X
        offset_y = offset.Y
        offset_z = offset.Z
    end)

    if not offset_ok then
        log("SLOT_TARGET_ERROR Offset read failed: " .. tostring(offset_err))
        return
    end

    log("SLOT_TARGET_OFFSET_READ_OK")

    log("SLOT_TARGET_METADATA bone=" .. tostring(bone_name) ..
        " offset=" .. tostring(offset_x) .. "," ..
        tostring(offset_y) .. "," .. tostring(offset_z))

    log("SLOT_TARGET_COMPONENT_LOOKUP_BEGIN")

    local component = get_actor_component_10(target_actor)

    if not is_valid(component) then
        log("SLOT_TARGET_ERROR mesh/scene component unavailable")
        return
    end

    log("SLOT_TARGET_COMPONENT=" .. safe_full_name(component))

    local socket_location = nil

    log("SLOT_TARGET_SOCKET_FNAME_BEGIN bone=" .. tostring(bone_name))

    local socket_fname = nil
    local fname_ok, fname_err = pcall(function()
        socket_fname = FName(bone_name, EFindName.FNAME_Find)
    end)

    if not fname_ok or socket_fname == nil then
        log("SLOT_TARGET_ERROR socket FName failed: " ..
            tostring(fname_err))
        return
    end

    log("SLOT_TARGET_SOCKET_FNAME_OK")

    log("SLOT_TARGET_SOCKET_LOCATION_BEGIN")

    local ok, socket_err = pcall(function()
        socket_location = component:GetSocketLocation(socket_fname)
    end)

    if not ok or socket_location == nil then
        log("SLOT_TARGET_ERROR GetSocketLocation failed: " ..
            tostring(socket_err))
        return
    end

    log("SLOT_TARGET_SOCKET_LOCATION_OK")

    -- First proof deliberately uses the socket anchor itself.
    -- We log the slot.Offset but do not apply it until the coordinate-space
    -- behavior is confirmed. Many Bladesong slot bones are already authored
    -- at the usable snap point.
    local wx = socket_location.X
    local wy = socket_location.Y
    local wz = socket_location.Z

    log("SLOT_TARGET_WORLD socket=" ..
        tostring(wx) .. "," .. tostring(wy) .. "," .. tostring(wz))

    local pc = get_player_controller_10()

    if not is_valid(pc) then
        log("SLOT_TARGET_ERROR PlayerController unavailable")
        return
    end

    local success = false
    local screen = {}

    log("SLOT_TARGET_PROJECT_BEGIN")

    ok, socket_err = pcall(function()
        success = pc:ProjectWorldLocationToScreen(
            socket_location,
            screen,
            false
        )
    end)

    log("SLOT_TARGET_PROJECT_CALL_RETURNED")

    if not ok then
        log("SLOT_TARGET_ERROR ProjectWorldLocationToScreen call failed: " ..
            tostring(socket_err))
        return
    end

    if not success then
        log("SLOT_TARGET_ERROR projection returned false")
        return
    end

    local sx = nil
    local sy = nil

    local screen_ok, screen_err = pcall(function()
        sx = screen.X
        sy = screen.Y
    end)

    if not screen_ok or sx == nil or sy == nil then
        log("SLOT_TARGET_ERROR screen out-param unreadable: " ..
            tostring(screen_err))
        return
    end

    log("SLOT_TARGET_PROJECT_OUT_OK")

    log("SLOT_TARGET_SCREEN=" .. tostring(sx) .. "," .. tostring(sy))

    log("SLOT_TARGET_SET_MOUSE_BEGIN")

    local set_ok, set_err = pcall(function()
        pc:SetMouseLocation(
            math.floor(sx + 0.5),
            math.floor(sy + 0.5)
        )
    end)

    log("SLOT_TARGET_SET_MOUSE_CALL_RETURNED")

    if not set_ok then
        log("SLOT_TARGET_ERROR SetMouseLocation failed: " .. tostring(set_err))
        return
    end

    log("SLOT_TARGET_MOUSE_MOVED")
    log("Waiting 250ms for Bladesong preview snapping...")

    pcl15179_schedule(250, function()
        run_game_thread(function()
            report_target_state_10(
                PCL10_TARGET_NATIVE,
                PCL10_TARGET_SLOT
            )
            log("============================================================")
        end)
    end)
end

RegisterKeyBind(Key.G, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(target_saved_slot_10)
end)

log("Phase 10 exact hardpoint cursor-target probe loaded.")
log("Test setup: finalized prefab-root Cube at native index 5.")
log("Create a Grip preview manually/catalogue if desired, then CTRL+ALT+G.")
log("CTRL+ALT+G targets native 5 slot 2 via socket->screen projection.")


-- ============================================================
-- Phase 11: FIRST WHOLE 3-PART .PCL NATIVE INSERTION
-- ============================================================
--
-- This combines the proven primitives:
--   - real catalogue button activation
--   - native provisional AppliedSwordPart allocation
--   - exact slot targeting via socket -> screen -> cursor
--   - native parent/SlotChildren staging
--   - safe part/material identity + scalar geometry writes
--   - EnterForgeMode(Piece) finalization
--   - live serialization verification
--
-- F6 = insert prefab_root_1.pcl at the hardpoint currently under the cursor.
--
-- First-proof limits:
--   - exactly 3 saved parts
--   - SlotChildren hierarchy only
--   - no FreeChildren
--   - all three saved catalogue tiles must currently exist
--
-- IMPORTANT:
-- Session state stores ONLY plain Lua strings/numbers/tables.
-- No UObject, FName, row-handle or struct proxy is retained across delays.

local pcl11_session = nil

local function state_no_serialize_11()
    local forge = find_forge()

    if not is_valid(forge) then
        return nil, nil, nil, "No live ForgeMode found."
    end

    local piece = nil
    local ok, err = pcall(function()
        piece = forge:GetPiece()
    end)

    if not ok or not is_valid(piece) then
        return forge, nil, nil, "ForgeMode:GetPiece() failed: " ..
            tostring(err)
    end

    local design = nil
    ok, err = pcall(function()
        design = piece.WeaponDesignDefinition
    end)

    if not ok or design == nil then
        return forge, piece, nil,
            "WeaponDesignDefinition unavailable: " .. tostring(err)
    end

    return forge, piece, design, nil
end

local function schedule_game_11(delay_ms, fn)
    pcl15179_schedule(delay_ms, function()
        run_game_thread(fn)
    end)
end

local function has_active_preview_11()
    local handling = find_handling_component_9()

    if not is_valid(handling) then
        return false
    end

    local preview = nil
    pcall(function()
        preview = handling.PreviewSwordPartActor
    end)

    return is_valid(preview)
end

local function click_catalogue_row_11(row_name)
    local button = find_button_for_row_9(row_name)

    if not is_valid(button) then
        return false, "no live catalogue tile for " .. tostring(row_name)
    end

    local common_button = nil
    local ok, err = pcall(function()
        common_button = button.Button
    end)

    if not ok or not is_valid(common_button) then
        return false, "catalogue Button unavailable for " ..
            tostring(row_name) .. ": " .. tostring(err)
    end

    log("PREFAB_INSERT_CLICK row=" .. tostring(row_name) ..
        " widget=" .. safe_full_name(button))

    ok, err = pcall(function()
        common_button:HandleButtonClicked()
    end)

    if not ok then
        return false, "HandleButtonClicked failed for " ..
            tostring(row_name) .. ": " .. tostring(err)
    end

    return true, nil
end

local function parse_saved_scalar_state_11(saved)
    return {
        polish = tonumber(saved.polish) or 0,
        scale = tonumber(saved.scale) or 1,
        rotation = tonumber(saved.rotation) or 0,
        sink = tonumber(saved.sink) or 0,
        stretch = tonumber(saved.stretch) or 1,
        curvature = tonumber(saved.curvature) or 0,
        flipped_slot = parse_bool(saved.flipped_slot),
        manual_flip = parse_bool(saved.manual_flip),
        slots_version = tonumber(saved.slots_version) or 0,
        deflection = parse_num_list(saved.deflection or "0,0,0,1"),
        curvature_vals = parse_num_list(saved.curvature_vals or "0,0"),
        circle_rotations =
            parse_num_list(saved.circle_rotations or "0,0,0,1")
    }
end

local function write_scalar_geometry_only_11(target, saved, preserve_slots_version)
    local state = parse_saved_scalar_state_11(saved)

    local ok, err = pcall(function()
        target.Polish = state.polish
        target.Scale = state.scale
        target.Rotation = state.rotation
        target.Sink = state.sink
        target.Stretch = state.stretch
        target.Curvature = state.curvature
        target.bIsInFlippedSlot = state.flipped_slot
        target.bManualFlip = state.manual_flip

        -- Phase 15.11.7 compatibility rule:
        -- SerializeSwordPartActorsToData() has just created a fresh native
        -- FAppliedSwordPart using the CURRENT game's SwordPart data.  Do not
        -- replace its SlotsVersion with the value captured by an older PCL
        -- export.  The saved slot graph has already been materialized against
        -- the current hardpoints before serialization.
        if not preserve_slots_version then
            target.SlotsVersion = state.slots_version
        end

        if target.Deflection then
            target.Deflection.X = state.deflection[1] or 0
            target.Deflection.Y = state.deflection[2] or 0
            target.Deflection.Z = state.deflection[3] or 0
            target.Deflection.W = state.deflection[4] or 1
        end

        if target.CurvatureVals then
            target.CurvatureVals.X = state.curvature_vals[1] or 0
            target.CurvatureVals.Y = state.curvature_vals[2] or 0
        end

        if target.CircleRotations then
            target.CircleRotations.X = state.circle_rotations[1] or 0
            target.CircleRotations.Y = state.circle_rotations[2] or 0
            target.CircleRotations.Z = state.circle_rotations[3] or 0
            target.CircleRotations.W = state.circle_rotations[4] or 1
        end
    end)

    if not ok then
        return false, tostring(err)
    end

    return true, nil
end

local pcl144_material_resolution_cache = {}

local function find_row_in_one_table_144(dt, candidates)
    if not is_valid(dt) then
        return nil
    end

    local wanted = {}

    for _, name in ipairs(candidates or {}) do
        if name ~= nil and
           name ~= "" and
           name ~= "None" then
            wanted[tostring(name)] = true
        end
    end

    local names = get_row_names_7(dt)

    for _, row_name in ipairs(names) do
        local row_string = safe_name(row_name)

        if wanted[row_string] then
            local row = nil

            pcall(function()
                row = dt:FindRow(row_name)
            end)

            return {
                data_table = dt,
                row_name = row_name,
                row = row,
                source = "datatable"
            }
        end
    end

    return nil
end

local function find_live_material_library_144()
    local libs = {}

    local ok, result = pcall(function()
        return FindAllOf("MaterialLibrary")
    end)

    if ok and result ~= nil then
        libs = result
    end

    local fallback = nil

    for _, lib in ipairs(libs) do
        if is_valid(lib) then
            local full = safe_full_name(lib)

            if not string.find(full, "Default__", 1, true) then
                if string.find(
                    full,
                    "BladesongMaterialLibrary",
                    1,
                    true
                ) then
                    return lib
                end

                fallback = fallback or lib
            end
        end
    end

    return fallback
end

local function find_material_metadata_144(material_name)
    local lib = find_live_material_library_144()

    if not is_valid(lib) then
        return nil, "live MaterialLibrary unavailable"
    end

    local map = nil
    local ok, err = pcall(function()
        map = lib.MaterialMetaData
    end)

    if not ok or map == nil then
        return nil,
            "MaterialLibrary.MaterialMetaData unavailable: " ..
            tostring(err)
    end

    local found = nil

    pcall(function()
        map:ForEach(function(kp, vp)
            if found ~= nil then
                return
            end

            local key = kp:get()
            local meta = vp:get()

            local key_name = safe_name(key)
            local meta_name = "None"

            pcall(function()
                meta_name = safe_name(meta.MaterialName)
            end)

            if key_name == material_name or
               meta_name == material_name then
                found = meta
            end
        end)
    end)

    if found == nil then
        return nil,
            "material metadata not found: " ..
            tostring(material_name)
    end

    return found, nil
end


local function clean_object_path_145(full_name)
    if full_name == nil then
        return nil
    end

    local s = tostring(full_name)

    -- safe_full_name(UObject) normally looks like:
    --   DataTable /Game/.../DT_Name.DT_Name
    -- StaticFindObject wants:
    --   /Game/.../DT_Name.DT_Name
    local stripped =
        s:match("^%S+%s+(.+)$")

    return stripped or s
end

local function find_saved_datatable_145(full_name)
    if full_name == nil or
       full_name == "" or
       full_name == "None" then
        return nil
    end

    local path =
        clean_object_path_145(full_name)

    local obj = nil

    local ok = pcall(function()
        obj = StaticFindObject(path)
    end)

    if ok and is_valid(obj) then
        return obj
    end

    -- Fallback: compare already-loaded DataTable objects by full name.
    local all = nil

    ok = pcall(function()
        all = FindAllOf("DataTable")
    end)

    if ok and all ~= nil then
        for _, candidate in ipairs(all) do
            if is_valid(candidate) then
                local candidate_full =
                    safe_full_name(candidate)

                if candidate_full == full_name or
                   clean_object_path_145(candidate_full) == path then
                    return candidate
                end
            end
        end
    end

    return nil
end

local function exact_material_handle_145(
    row_name,
    table_full_name
)
    if row_name == nil or
       row_name == "" or
       row_name == "None" or
       table_full_name == nil or
       table_full_name == "" or
       table_full_name == "None" then
        return nil, "saved exact material handle incomplete"
    end

    local dt =
        find_saved_datatable_145(
            table_full_name
        )

    if not is_valid(dt) then
        return nil,
            "saved material DataTable unavailable: " ..
            tostring(table_full_name)
    end

    local result =
        find_row_in_one_table_144(
            dt,
            { row_name }
        )

    if result == nil then
        return nil,
            "saved material row not found in exact table: row=" ..
            tostring(row_name) ..
            " table=" .. tostring(table_full_name)
    end

    result.source =
        "saved_exact_material_handle"

    return result, nil
end

local function recover_legacy_material_handle_145(
    saved,
    design
)
    if saved == nil or design == nil then
        return false, "saved/design unavailable"
    end

    if saved.material_data_row ~= nil and
       saved.material_data_row ~= "" and
       saved.material_data_row ~= "None" and
       saved.material_data_table ~= nil and
       saved.material_data_table ~= "" and
       saved.material_data_table ~= "None" then
        return true, nil
    end

    local original_index =
        tonumber(saved.original_index or "-1") or -1

    if original_index < 0 then
        return false,
            "legacy PCL has no usable original_index"
    end

    local parts =
        capture_parts(design)

    local source =
        parts[original_index]

    if source == nil then
        return false,
            "source original native part missing: " ..
            tostring(original_index)
    end

    local source_part =
        safe_name(source.SwordPart)

    local source_material =
        safe_name(source.SwordMaterial)

    if source_part ~= saved.sword_part or
       source_material ~= saved.material then
        return false,
            "source original part no longer matches saved identity: native=" ..
            tostring(original_index) ..
            " source_part=" .. tostring(source_part) ..
            " saved_part=" .. tostring(saved.sword_part) ..
            " source_material=" .. tostring(source_material) ..
            " saved_material=" .. tostring(saved.material)
    end

    local row_name = "None"
    local table_full = "None"

    local ok, err = pcall(function()
        if source.SwordMaterialData ~= nil then
            row_name =
                safe_name(
                    source.SwordMaterialData.RowName
                )

            if is_valid(
                source.SwordMaterialData.DataTable
            ) then
                table_full =
                    safe_full_name(
                        source.SwordMaterialData.DataTable
                    )
            end
        end
    end)

    if not ok then
        return false,
            "source material handle read failed: " ..
            tostring(err)
    end

    if row_name == "None" or
       table_full == "None" then
        return false,
            "source original part has no usable material handle"
    end

    saved.material_data_row =
        row_name

    saved.material_data_table =
        table_full

    log("PREFAB14_LEGACY_MATERIAL_HANDLE_RECOVERED original_native=" ..
        tostring(original_index) ..
        " material=" .. tostring(saved.material) ..
        " row=" .. tostring(row_name) ..
        " table=" .. tostring(table_full))

    return true, nil
end

local function resolve_material_variant_144(
    material_name,
    material_tables,
    preferred_row_name,
    preferred_table_full_name
)
    local cache_key =
        tostring(material_name) .. "|" ..
        tostring(preferred_row_name or "") .. "|" ..
        tostring(preferred_table_full_name or "")

    local cached =
        pcl144_material_resolution_cache[cache_key]

    if cached ~= nil then
        return cached, nil
    end

    -- Strongest source of truth: the exact SwordMaterialData handle saved
    -- from the original AppliedSwordPart.
    if preferred_row_name ~= nil and
       preferred_row_name ~= "" and
       preferred_row_name ~= "None" and
       preferred_table_full_name ~= nil and
       preferred_table_full_name ~= "" and
       preferred_table_full_name ~= "None" then

        local exact_handle, exact_err =
            exact_material_handle_145(
                preferred_row_name,
                preferred_table_full_name
            )

        if exact_handle ~= nil then
            exact_handle.variant_name =
                material_name

            pcl144_material_resolution_cache[
                cache_key
            ] = exact_handle

            return exact_handle, nil
        end

        log("PREFAB14_EXACT_MATERIAL_HANDLE_WARNING " ..
            tostring(exact_err))
    end

    -- Directly named material rows cover SteelDefault, SteelRed, Ice, etc.
    local exact =
        find_row_in_tables_7(
            material_tables,
            material_name
        )

    if exact ~= nil then
        exact.row_name =
            exact.row_name or material_name
        exact.source =
            "exact_datatable"

        pcl144_material_resolution_cache[
            cache_key
        ] = exact

        return exact, nil
    end

    -- A saved row without its table path is still better than guessing.
    if preferred_row_name ~= nil and
       preferred_row_name ~= "" and
       preferred_row_name ~= "None" then

        local preferred =
            find_row_in_tables_7(
                material_tables,
                preferred_row_name
            )

        if preferred ~= nil then
            preferred.row_name =
                preferred.row_name or
                preferred_row_name
            preferred.source =
                "saved_material_data_row"

            pcl144_material_resolution_cache[
                cache_key
            ] = preferred

            return preferred, nil
        end
    end

    -- Legacy fallback for generated/pigmented materials.
    local meta, meta_err =
        find_material_metadata_144(
            material_name
        )

    if meta == nil then
        return nil, meta_err
    end

    local original_dt = nil
    local meta_material_name = "None"
    local template_name = "None"
    local pigment_name = "None"

    pcall(function()
        original_dt =
            meta.OriginalDataTable
    end)

    pcall(function()
        meta_material_name =
            safe_name(meta.MaterialName)
    end)

    pcall(function()
        template_name =
            safe_name(
                meta.MaterialTemplateName
            )
    end)

    pcall(function()
        pigment_name =
            safe_name(meta.PigmentName)
    end)

    local candidates = {
        preferred_row_name,
        template_name,
        meta_material_name,
        material_name
    }

    local resolved = nil

    if is_valid(original_dt) then
        resolved =
            find_row_in_one_table_144(
                original_dt,
                candidates
            )

        if resolved ~= nil then
            resolved.source =
                "material_library_original_table"
        end
    end

    if resolved == nil then
        for _, dt in ipairs(material_tables) do
            resolved =
                find_row_in_one_table_144(
                    dt,
                    candidates
                )

            if resolved ~= nil then
                resolved.source =
                    "material_library_fallback_table"
                break
            end
        end
    end

    if resolved == nil then
        local original_table_name =
            is_valid(original_dt) and
            safe_full_name(original_dt) or
            "None"

        return nil,
            "material library entry exists but backing data row could not be resolved: " ..
            tostring(material_name) ..
            " template=" ..
            tostring(template_name) ..
            " meta_material=" ..
            tostring(meta_material_name) ..
            " pigment=" ..
            tostring(pigment_name) ..
            " original_table=" ..
            tostring(original_table_name)
    end

    resolved.variant_name =
        material_name
    resolved.template_name =
        template_name
    resolved.pigment_name =
        pigment_name

    pcl144_material_resolution_cache[
        cache_key
    ] = resolved

    return resolved, nil
end

local function resolve_identity_rows_fresh_11(
    part_name,
    material_name,
    preferred_material_row,
    preferred_material_table
)
    -- Phase 15.11.17: import-scoped resolution cache.  The active importer
    -- resolves the same configured DataTables and many of the same part/
    -- material identities repeatedly during spawn and apply.  Keep those
    -- handles only for this import; the cache is discarded on success/fail.
    local cache = PCL151117_CACHE
    local key = tostring(part_name) .. "\31" ..
        tostring(material_name) .. "\31" ..
        tostring(preferred_material_row or "") .. "\31" ..
        tostring(preferred_material_table or "")

    if cache ~= nil and cache.identity ~= nil then
        local hit = cache.identity[key]
        if hit ~= nil then
            cache.stats.identity_hits = (cache.stats.identity_hits or 0) + 1
            return hit.part_row, hit.material_row, nil
        end
    end

    local part_tables = nil
    local material_tables = nil

    if cache ~= nil and cache.part_tables ~= nil and cache.material_tables ~= nil then
        part_tables = cache.part_tables
        material_tables = cache.material_tables
    else
        local modules = find_game_modules_7()
        part_tables = collect_unique_datatables_7(modules, "SwordPartDataTables")
        material_tables = collect_unique_datatables_7(modules, "SwordMaterialDataTables")
        if cache ~= nil then
            cache.part_tables = part_tables
            cache.material_tables = material_tables
        end
    end

    local part_row = nil
    if cache ~= nil and cache.part_rows ~= nil then
        part_row = cache.part_rows[tostring(part_name)]
    end
    if part_row == nil then
        part_row = find_row_in_tables_7(part_tables, part_name)
        if part_row ~= nil and cache ~= nil and cache.part_rows ~= nil then
            cache.part_rows[tostring(part_name)] = part_row
        end
    end

    if part_row == nil then
        return nil, nil, "part row not found: " .. tostring(part_name)
    end

    part_row.row_name = part_row.row_name or part_name

    local material_row, material_err = resolve_material_variant_144(
        material_name,
        material_tables,
        preferred_material_row,
        preferred_material_table
    )

    if material_row == nil then
        return nil, nil, material_err
    end

    if cache ~= nil and cache.identity ~= nil then
        cache.identity[key] = { part_row = part_row, material_row = material_row }
        cache.stats.identity_misses = (cache.stats.identity_misses or 0) + 1
    end

    return part_row, material_row, nil
end

local function apply_saved_part_11(local_index, native_index, target_override)
    if pcl11_session == nil then
        return false, "no insertion session"
    end

    local saved = pcl11_session.parts[local_index + 1]
    local target = target_override

    -- Phase 15.11.62 hot path: target_override is the ephemeral wrapper from
    -- the current AppliedSwordParts:ForEach callback. Do not retain thousands
    -- of FAppliedSwordPart wrappers across the whole import.
    if target == nil then
        if pcl11_session.native_parts ~= nil then
            target = pcl11_session.native_parts[native_index]
        else
            local forge, piece, design, err = state_no_serialize_11()
            if err then return false, err end
            local parts = capture_parts(design)
            target = parts[native_index]
        end
    end

    if target == nil then
        return false, "native part missing: " .. tostring(native_index)
    end

    local part_resolved = nil
    local material_resolved = nil
    local cached = pcl11_session.resolved_by_local and
        pcl11_session.resolved_by_local[local_index + 1] or nil

    if cached ~= nil then
        part_resolved = cached.part_resolved
        material_resolved = cached.material_resolved
        if PCL151117_CACHE ~= nil then
            PCL151117_CACHE.stats.apply_cache_hits =
                (PCL151117_CACHE.stats.apply_cache_hits or 0) + 1
        end
    else
        local resolve_err = nil
        part_resolved, material_resolved, resolve_err = resolve_identity_rows_fresh_11(
            saved.sword_part,
            saved.material,
            saved.material_data_row,
            saved.material_data_table
        )
        if resolve_err then return false, resolve_err end
    end

    if safe_name(target.SwordPart) ~= saved.sword_part then
        local part_ok, part_err = write_part_identity_83(target, saved.sword_part, part_resolved)
        if not part_ok then return false, "part identity: " .. tostring(part_err) end
    end

    if safe_name(target.SwordMaterial) ~= saved.material then
        local mat_ok, mat_err = write_material_identity_83(target, saved.material, material_resolved)
        if not mat_ok then return false, "material identity: " .. tostring(mat_err) end
    end

    local serialized_slots_version = nil
    pcall(function() serialized_slots_version = target.SlotsVersion end)

    local geom_ok, geom_err = write_scalar_geometry_only_11(target, saved, true)
    if not geom_ok then return false, "geometry: " .. tostring(geom_err) end

    local final_slots_version = nil
    pcall(function() final_slots_version = target.SlotsVersion end)

    if serialized_slots_version ~= nil and
       final_slots_version ~= serialized_slots_version then
        return false,
            "SlotsVersion changed unexpectedly native=" .. tostring(native_index) ..
            " before=" .. tostring(serialized_slots_version) ..
            " after=" .. tostring(final_slots_version)
    end

    -- Per-part diagnostic logging intentionally removed from the fast path.
    -- Progress/error markers remain in phase1510_begin.
    return true, nil
end


-- Phase 15.11.7: PCL stores already-resolved geometry/flip state rather than
-- an historical FWeaponDesignDefinition migration snapshot.  Mark the
-- reconstructed design as the current enum version before calling the native
-- InitInEditor rebuild.  EWeaponDesignDefinitionVersion::LatestVersion is
-- ManualFlipPropagates, numeric value 3 in the current headers.
PCL15117_LATEST_DESIGN_VERSION = 3

function pcl15117_force_latest_design_version(design)
    if design == nil then
        return false, "design unavailable"
    end

    local before = "<unreadable>"
    pcall(function()
        before = tostring(design.Version)
    end)

    local ok, err = pcall(function()
        design.Version = PCL15117_LATEST_DESIGN_VERSION
    end)

    if not ok then
        return false, "Version write failed: " .. tostring(err)
    end

    local after = "<unreadable>"
    pcall(function()
        after = tostring(design.Version)
    end)

    log("PCL15_11_7_DESIGN_VERSION before=" .. tostring(before) ..
        " target=" .. tostring(PCL15117_LATEST_DESIGN_VERSION) ..
        " after=" .. tostring(after) ..
        " enum_latest=ManualFlipPropagates")

    return true, nil
end


local function fail_insert_111(message)
    log("PREFAB_INSERT_ERROR " .. tostring(message))
    log("PREFAB_INSERT_SESSION_CLEARED_AFTER_ERROR=true")
    pcl11_session = nil
end

local function get_kismet_math_111()
    local lib = nil

    local ok, obj = pcall(function()
        return FindFirstOf("KismetMathLibrary")
    end)

    if ok and is_valid(obj) then
        return obj
    end

    return nil
end

local function rotate_vector_by_quat_13(vx, vy, vz, qx, qy, qz, qw)
    -- Unreal FQuat vector rotation:
    -- v' = v + 2 * (w * (q.xyz x v) + q.xyz x (q.xyz x v))
    local uvx = qy * vz - qz * vy
    local uvy = qz * vx - qx * vz
    local uvz = qx * vy - qy * vx

    local uuvx = qy * uvz - qz * uvy
    local uuvy = qz * uvx - qx * uvz
    local uuvz = qx * uvy - qy * uvx

    return
        vx + 2.0 * (qw * uvx + uuvx),
        vy + 2.0 * (qw * uvy + uuvy),
        vz + 2.0 * (qw * uvz + uuvz)
end

local function transform_local_point_13(transform, local_point)
    if transform == nil or local_point == nil then
        return nil, "transform/local point unavailable"
    end

    local tx, ty, tz = 0, 0, 0
    local sx, sy, sz = 1, 1, 1
    local qx, qy, qz, qw = 0, 0, 0, 1
    local lx, ly, lz = 0, 0, 0

    local ok, err = pcall(function()
        tx = transform.Translation.X
        ty = transform.Translation.Y
        tz = transform.Translation.Z

        sx = transform.Scale3D.X
        sy = transform.Scale3D.Y
        sz = transform.Scale3D.Z

        qx = transform.Rotation.X
        qy = transform.Rotation.Y
        qz = transform.Rotation.Z
        qw = transform.Rotation.W

        lx = local_point.X
        ly = local_point.Y
        lz = local_point.Z
    end)

    if not ok then
        return nil, "FTransform field read failed: " .. tostring(err)
    end

    local vx = lx * sx
    local vy = ly * sy
    local vz = lz * sz

    local rx, ry, rz =
        rotate_vector_by_quat_13(
            vx, vy, vz,
            qx, qy, qz, qw
        )

    return {
        X = tx + rx,
        Y = ty + ry,
        Z = tz + rz
    }, nil
end

local function world_target_from_slot_111(component, slot, bone_name)
    if not is_valid(component) then
        return nil, "component invalid"
    end

    local offset = nil
    local ox, oy, oz = 0, 0, 0

    local ok, err = pcall(function()
        offset = slot.Offset
        ox = offset.X
        oy = offset.Y
        oz = offset.Z
    end)

    if not ok or offset == nil then
        return nil, "slot Offset unavailable: " .. tostring(err)
    end

    local has_offset =
        math.abs(ox) > 0.0001 or
        math.abs(oy) > 0.0001 or
        math.abs(oz) > 0.0001

    local has_bone =
        bone_name ~= nil and
        bone_name ~= "" and
        bone_name ~= "None"

    log("PREFAB_INSERT_TARGET_MODE bone=" .. tostring(bone_name) ..
        " has_bone=" .. tostring(has_bone) ..
        " has_offset=" .. tostring(has_offset))

    local target_transform = nil

    if has_bone then
        local socket_fname = nil

        ok, err = pcall(function()
            socket_fname = FName(bone_name, EFindName.FNAME_Find)
        end)

        if not ok or socket_fname == nil then
            return nil, "slot FName failed: " .. tostring(err)
        end

        if not has_offset then
            local socket_location = nil

            ok, err = pcall(function()
                socket_location = component:GetSocketLocation(socket_fname)
            end)

            if not ok or socket_location == nil then
                return nil, "GetSocketLocation failed: " .. tostring(err)
            end

            return socket_location, nil
        end

        log("PREFAB_INSERT_SOCKET_TRANSFORM_BEGIN bone=" ..
            tostring(bone_name))

        ok, err = pcall(function()
            -- ERelativeTransformSpace::RTS_World = 0
            target_transform =
                component:GetSocketTransform(socket_fname, 0)
        end)

        if not ok or target_transform == nil then
            return nil, "GetSocketTransform failed: " .. tostring(err)
        end

        log("PREFAB_INSERT_SOCKET_TRANSFORM_OK")
    else
        log("PREFAB_INSERT_COMPONENT_TRANSFORM_BEGIN")

        ok, err = pcall(function()
            target_transform = component:K2_GetComponentToWorld()
        end)

        if not ok or target_transform == nil then
            return nil, "K2_GetComponentToWorld failed: " ..
                tostring(err)
        end

        log("PREFAB_INSERT_COMPONENT_TRANSFORM_OK")

        if not has_offset then
            local loc = nil

            ok, err = pcall(function()
                loc = component:K2_GetComponentLocation()
            end)

            if not ok or loc == nil then
                return nil, "K2_GetComponentLocation failed: " ..
                    tostring(err)
            end

            return loc, nil
        end
    end

    log("PREFAB_INSERT_TRANSFORM_OFFSET_BEGIN local=" ..
        tostring(ox) .. "," ..
        tostring(oy) .. "," ..
        tostring(oz))

    local world, transform_err =
        transform_local_point_13(target_transform, offset)

    if world == nil then
        return nil, transform_err
    end

    log("PREFAB_INSERT_TRANSFORM_OFFSET_OK world=" ..
        tostring(world.X) .. "," ..
        tostring(world.Y) .. "," ..
        tostring(world.Z))

    return world, nil
end

local function target_native_slot_11(parent_native, slot_native)
    local forge, piece, design, state_err = state_no_serialize_11()

    if state_err then
        return false, state_err
    end

    local _, actors, _ = build_actor_map_10(design, nil)
    local target_actor = actors[parent_native]

    if not is_valid(target_actor) then
        return false, "could not graph-map parent native " ..
            tostring(parent_native)
    end

    log("PREFAB_INSERT_TARGET_PARENT native=" ..
        tostring(parent_native) ..
        " slot=" .. tostring(slot_native) ..
        " actor=" .. safe_full_name(target_actor) ..
        " part=" .. actor_part_name_10(target_actor))

    local row, row_err = get_sword_part_row_10(target_actor)
    if row == nil then
        return false, row_err
    end

    local slot, slot_err = get_slot_struct_10(row, slot_native)
    if slot == nil then
        return false, slot_err
    end

    local bone_name = "None"
    local ox, oy, oz = 0, 0, 0

    local ok, read_err = pcall(function()
        bone_name = safe_name(slot.BoneName)
        ox = slot.Offset.X
        oy = slot.Offset.Y
        oz = slot.Offset.Z
    end)

    if not ok then
        return false, "slot metadata read failed: " .. tostring(read_err)
    end

    local component = get_actor_component_10(target_actor)
    if not is_valid(component) then
        return false, "parent root component unavailable"
    end

    log("PREFAB_INSERT_TARGET_SLOT bone=" .. tostring(bone_name) ..
        " offset=" .. tostring(ox) .. "," ..
        tostring(oy) .. "," .. tostring(oz))

    local world_target, world_err =
        world_target_from_slot_111(
            component,
            slot,
            bone_name
        )

    if world_target == nil then
        return false, world_err
    end

    log("PREFAB_INSERT_TARGET_WORLD=" ..
        tostring(world_target.X) .. "," ..
        tostring(world_target.Y) .. "," ..
        tostring(world_target.Z))

    local pc = get_player_controller_10()
    if not is_valid(pc) then
        return false, "PlayerController unavailable"
    end

    local screen = {}
    local success = false

    ok, read_err = pcall(function()
        success = pc:ProjectWorldLocationToScreen(
            world_target,
            screen,
            false
        )
    end)

    if not ok then
        return false, "projection call failed: " .. tostring(read_err)
    end

    if not success or screen.X == nil or screen.Y == nil then
        return false, "projection returned no screen point"
    end

    log("PREFAB_INSERT_TARGET_SCREEN x=" ..
        tostring(screen.X) .. " y=" .. tostring(screen.Y))

    ok, read_err = pcall(function()
        pc:SetMouseLocation(
            math.floor(screen.X + 0.5),
            math.floor(screen.Y + 0.5)
        )
    end)

    if not ok then
        return false, "SetMouseLocation failed: " .. tostring(read_err)
    end

    return true, nil
end

local function candidate_link_11(candidate_native)
    local forge, piece, design, err = state_no_serialize_11()
    if err then
        return nil, nil, nil, err
    end

    local parent_native, slot_native =
        find_link_to_candidate_10(design, candidate_native)

    return parent_native, slot_native, #design.AppliedSwordParts, nil
end

local function finalize_then_11(next_fn)
    local forge, piece, design, err = state_no_serialize_11()

    if err then
        fail_insert_111("finalize acquire: " .. tostring(err))
        return
    end

    log("PREFAB_INSERT_BEFORE_ENTERFORGEMODE count=" ..
        tostring(#design.AppliedSwordParts))

    local enter_ok, enter_err = enter_piece_again(piece)

    if not enter_ok then
        fail_insert_111("EnterForgeMode: " .. tostring(enter_err))
        return
    end

    log("PREFAB_INSERT_AFTER_ENTERFORGEMODE")

    schedule_game_11(300, next_fn)
end


local function hand_finished_prefab_to_cursor_13(design)
    if pcl11_session == nil then
        return false, "no insertion session"
    end

    local root_native =
        pcl11_session.local_to_native[1]

    if root_native == nil then
        return false, "root native index unavailable"
    end

    log("PREFAB_HELD_ASSIGN_BEGIN root_native=" ..
        tostring(root_native))

    local _, actors, _ =
        build_actor_map_10(design, nil)

    local root_actor = actors[root_native]

    if not is_valid(root_actor) then
        return false,
            "could not graph-map finished prefab root native " ..
            tostring(root_native)
    end

    local handling =
        find_handling_component_9()

    if not is_valid(handling) then
        return false, "SwordPartHandlingComponent unavailable"
    end

    local active_preview = nil

    pcall(function()
        active_preview = handling.PreviewSwordPartActor
    end)

    if is_valid(active_preview) and
       safe_full_name(active_preview) ~= safe_full_name(root_actor) then
        return false,
            "another preview is already active: " ..
            safe_full_name(active_preview)
    end

    log("PREFAB_HELD_ROOT_ACTOR=" ..
        safe_full_name(root_actor) ..
        " part=" .. actor_part_name_10(root_actor))

    local ok, err = pcall(function()
        handling.PreviewSwordPartActor = root_actor
    end)

    if not ok then
        return false,
            "PreviewSwordPartActor assignment failed: " ..
            tostring(err)
    end

    log("PREFAB_HELD_ASSIGN_WRITE_RETURNED=true")

    -- Return the cursor to where the player had it before the mod performed
    -- its internal staging movements. The newly assigned preview root then
    -- follows that restored cursor normally.
    restore_mouse_position_131()

    return true, nil
end

local function verify_finished_11()
    if pcl11_session == nil then
        log("PREFAB_INSERT_VERIFY_ERROR no session")
        return
    end

    log("============================================================")
    log("PREFAB_INSERT_VERIFY_BEGIN")

    local forge = find_forge()

    if not is_valid(forge) then
        log("PREFAB_INSERT_VERIFY_ERROR no ForgeMode")
        return
    end

    local ok, err = pcall(function()
        forge:SerializeSwordPartActorsToData()
    end)

    if not ok then
        log("PREFAB_INSERT_VERIFY_ERROR serializer: " .. tostring(err))
        return
    end

    local piece = nil
    ok, err = pcall(function()
        piece = forge:GetPiece()
    end)

    if not ok or not is_valid(piece) then
        log("PREFAB_INSERT_VERIFY_ERROR GetPiece: " .. tostring(err))
        return
    end

    local design = piece.WeaponDesignDefinition
    local parts = capture_parts(design)

    local all_ok = true

    for local_index = 0, 2 do
        local native_index =
            pcl11_session.local_to_native[local_index + 1]
        local saved = pcl11_session.parts[local_index + 1]
        local part = parts[native_index]

        if part == nil then
            all_ok = false
            log("PREFAB_INSERT_VERIFY_PART local=" ..
                tostring(local_index) .. " missing=true")
        else
            local part_match =
                safe_name(part.SwordPart) == saved.sword_part
            local material_match =
                safe_name(part.SwordMaterial) == saved.material
            local scale_match =
                math.abs(
                    num(part.Scale, 1) -
                    (tonumber(saved.scale) or 1)
                ) < 0.0005
            local rotation_match =
                num(part.Rotation) ==
                (tonumber(saved.rotation) or 0)
            local stretch_match =
                math.abs(
                    num(part.Stretch, 1) -
                    (tonumber(saved.stretch) or 1)
                ) < 0.0005

            local local_ok =
                part_match and material_match and
                scale_match and rotation_match and stretch_match

            if not local_ok then
                all_ok = false
            end

            log("PREFAB_INSERT_VERIFY_PART local=" ..
                tostring(local_index) ..
                " native=" .. tostring(native_index) ..
                " part=" .. tostring(part_match) ..
                " material=" .. tostring(material_match) ..
                " scale=" .. tostring(scale_match) ..
                " rotation=" .. tostring(rotation_match) ..
                " stretch=" .. tostring(stretch_match))
        end
    end

    for child_local = 1, 2 do
        local relation = pcl11_session.relations[child_local + 1]
        local expected_parent =
            pcl11_session.local_to_native[relation.parent_local + 1]
        local expected_child =
            pcl11_session.local_to_native[child_local + 1]

        local parent_native, slot_native =
            find_link_to_candidate_10(design, expected_child)

        local link_ok =
            parent_native == expected_parent and
            slot_native == relation.slot_native

        if not link_ok then
            all_ok = false
        end

        log("PREFAB_INSERT_VERIFY_LINK child_local=" ..
            tostring(child_local) ..
            " parent_native=" .. tostring(parent_native) ..
            " expected_parent=" .. tostring(expected_parent) ..
            " slot_native=" .. tostring(slot_native) ..
            " expected_slot=" .. tostring(relation.slot_native) ..
            " match=" .. tostring(link_ok))
    end

    local expected_count =
        pcl11_session.base_count + 3
    local count_ok =
        #design.AppliedSwordParts == expected_count

    if not count_ok then
        all_ok = false
    end

    log("PREFAB_INSERT_VERIFY_COUNT current=" ..
        tostring(#design.AppliedSwordParts) ..
        " expected=" .. tostring(expected_count) ..
        " match=" .. tostring(count_ok))

    if all_ok then
        log("PREFAB_INSERT_OK whole 3-part prefab assembled natively")

        local held_ok, held_err =
            hand_finished_prefab_to_cursor_13(design)

        if held_ok then
            log("PREFAB_HELD_PENDING_VERIFY=true")

            schedule_game_11(300, function()
                local handling =
                    find_handling_component_9()

                if not is_valid(handling) then
                    log("PREFAB_HELD_VERIFY_ERROR handling unavailable")
                    pcl11_session = nil
                    return
                end

                local preview = nil
                local has_preview = false

                pcall(function()
                    preview = handling.PreviewSwordPartActor
                end)

                pcall(function()
                    has_preview =
                        handling:HasPreviewSwordPart() and true or false
                end)

                local expected_root_native =
                    pcl11_session and
                    pcl11_session.local_to_native[1] or nil

                local forge2 = find_forge()
                local tree_count = 0
                local preview_matches = false

                if is_valid(preview) then
                    local seen = {}

                    local function walk_held_tree_13(actor)
                        if not is_valid(actor) then return end

                        local full = safe_full_name(actor)
                        if seen[full] then return end
                        seen[full] = true
                        tree_count = tree_count + 1

                        local slots = nil
                        pcall(function()
                            slots = actor.SlotChildParts
                        end)

                        if slots ~= nil then
                            pcall(function()
                                slots:ForEach(function(_, vp)
                                    local child = vp:get()
                                    if is_valid(child) then
                                        walk_held_tree_13(child)
                                    end
                                end)
                            end)
                        end

                        local free = nil
                        pcall(function()
                            free = actor.FreeChildParts
                        end)

                        if free ~= nil then
                            pcall(function()
                                free:ForEach(function(kp, _)
                                    local child = kp:get()
                                    if is_valid(child) then
                                        walk_held_tree_13(child)
                                    end
                                end)
                            end)
                        end
                    end

                    walk_held_tree_13(preview)

                    if expected_root_native ~= nil and is_valid(forge2) then
                        local piece2 = nil
                        pcall(function()
                            piece2 = forge2:GetPiece()
                        end)

                        if is_valid(piece2) then
                            local design2 =
                                piece2.WeaponDesignDefinition

                            local _, actors2, _ =
                                build_actor_map_10(design2, nil)

                            local expected_actor =
                                actors2[expected_root_native]

                            if is_valid(expected_actor) then
                                preview_matches =
                                    safe_full_name(expected_actor) ==
                                    safe_full_name(preview)
                            end
                        end
                    end
                end

                log("PREFAB_HELD_VERIFY_HAS_PREVIEW=" ..
                    tostring(has_preview))
                log("PREFAB_HELD_VERIFY_PREVIEW=" ..
                    (is_valid(preview) and
                        safe_full_name(preview) or "None"))
                log("PREFAB_HELD_VERIFY_TREE_COUNT=" ..
                    tostring(tree_count))
                log("PREFAB_HELD_VERIFY_ROOT_MATCH=" ..
                    tostring(preview_matches))

                if has_preview and
                   is_valid(preview) and
                   tree_count >= 3 then
                    log("PREFAB_HELD_OK finished prefab is now in cursor hand")
                    log("Move it normally and LEFT CLICK once to place it.")
                else
                    log("PREFAB_HELD_NOT_CONFIRMED")
                end

                pcl11_session = nil
                log("PREFAB_INSERT_SESSION_CLEARED_AFTER_HELD_VERIFY=true")
                log("============================================================")
            end)
        else
            log("PREFAB_HELD_ERROR " .. tostring(held_err))
            pcl11_session = nil
            log("PREFAB_INSERT_SESSION_CLEARED_AFTER_HELD_ERROR=true")
            log("============================================================")
        end

        return
    else
        log("PREFAB_INSERT_VERIFY_MISMATCH")
        pcl11_session = nil
        log("PREFAB_INSERT_SESSION_CLEARED_AFTER_MISMATCH=true")
    end

    log("============================================================")
end

local function insert_child_after_finalize_11(child_local)

    if child_local > 2 then
        verify_finished_11()
        return
    end

    local relation = pcl11_session.relations[child_local + 1]
    local parent_native =
        pcl11_session.local_to_native[relation.parent_local + 1]
    local saved = pcl11_session.parts[child_local + 1]

    log("============================================================")
    log("PREFAB_INSERT_CHILD_BEGIN local=" ..
        tostring(child_local) ..
        " part=" .. tostring(saved.sword_part) ..
        " parent_local=" .. tostring(relation.parent_local) ..
        " parent_native=" .. tostring(parent_native) ..
        " slot_native=" .. tostring(relation.slot_native))

    -- Phase 13.2 runtime hardpoint diagnostics. This helper is now called
    -- from a scope where it is actually defined, avoiding the Phase 13.1
    -- nil-global crash.
    dump_slot_actor_pool_131(
        "PREFAB_RUNTIME_BEFORE_CHILD_" .. tostring(child_local)
    )

    local forge, piece, design, err = state_no_serialize_11()

    if err then
        fail_insert_111("child acquire: " .. tostring(err))
        return
    end

    local before_count = #design.AppliedSwordParts

    local click_ok, click_err =
        click_catalogue_row_11(saved.sword_part)

    if not click_ok then
        fail_insert_111(tostring(click_err))
        return
    end

    local candidate_native = before_count
    pcl11_session.local_to_native[child_local + 1] =
        candidate_native

    log("PREFAB_INSERT_CHILD_ALLOC_EXPECTED local=" ..
        tostring(child_local) ..
        " native=" .. tostring(candidate_native))

    -- Give the preview one frame to exist, then drive the cursor to the
    -- exact saved parent slot.
    schedule_game_11(75, function()
        local target_ok, target_err =
            target_native_slot_11(
                parent_native,
                relation.slot_native
            )

        dump_slot_actor_pool_131(
            "PREFAB_RUNTIME_AFTER_TARGET_CHILD_" ..
            tostring(child_local)
        )

        if not target_ok then
            fail_insert_111("target child local=" ..
                tostring(child_local) .. ": " ..
                tostring(target_err))
            return
        end

        schedule_game_11(300, function()
            local actual_parent, actual_slot, count, link_err =
                candidate_link_11(candidate_native)

            if link_err then
                fail_insert_111("child link check: " ..
                    tostring(link_err))
                return
            end

            log("PREFAB_INSERT_CHILD_STAGE local=" ..
                tostring(child_local) ..
                " native=" .. tostring(candidate_native) ..
                " count=" .. tostring(count) ..
                " parent_native=" .. tostring(actual_parent) ..
                " slot_native=" .. tostring(actual_slot))

            if actual_parent ~= parent_native or
               actual_slot ~= relation.slot_native then
                fail_insert_111("wrong staged slot local=" ..
                    tostring(child_local) ..
                    " expected_parent=" .. tostring(parent_native) ..
                    " expected_slot=" .. tostring(relation.slot_native))
                return
            end

            local apply_ok, apply_err =
                apply_saved_part_11(
                    child_local,
                    candidate_native
                )

            if not apply_ok then
                fail_insert_111("apply local=" ..
                    tostring(child_local) .. ": " ..
                    tostring(apply_err))
                return
            end

            finalize_then_11(function()
                insert_child_after_finalize_11(
                    child_local + 1
                )
            end)
        end)
    end)
end


-- ============================================================
-- Phase 13.1: no-user-aim automatic staging
-- ============================================================

local function scalar_out_value_132(t, preferred_key)
    if type(t) ~= "table" then
        return nil
    end

    if preferred_key ~= nil and type(t[preferred_key]) == "number" then
        return t[preferred_key]
    end

    if type(t[1]) == "number" then
        return t[1]
    end

    if type(t.Value) == "number" then
        return t.Value
    end

    if type(t.value) == "number" then
        return t.value
    end

    for _, v in pairs(t) do
        if type(v) == "number" then
            return v
        end
    end

    return nil
end

local function capture_mouse_position_131()
    local pc = get_player_controller_10()

    if not is_valid(pc) then
        return nil, nil
    end

    local xout = {}
    local yout = {}
    local success = false

    local ok, err = pcall(function()
        success = pc:GetMousePosition(xout, yout)
    end)

    if not ok or not success then
        log("PREFAB_AUTO_MOUSE_CAPTURE_FAILED=" .. tostring(err))
        return nil, nil
    end

    local x =
        scalar_out_value_132(xout, "LocationX")

    local y =
        scalar_out_value_132(yout, "LocationY")

    if x == nil or y == nil then
        local xkeys = {}
        local ykeys = {}

        for k, v in pairs(xout) do
            table.insert(xkeys, tostring(k) .. "=" .. tostring(v))
        end

        for k, v in pairs(yout) do
            table.insert(ykeys, tostring(k) .. "=" .. tostring(v))
        end

        log("PREFAB_AUTO_MOUSE_CAPTURE_FAILED=out params unreadable" ..
            " xout={" .. table.concat(xkeys, ",") .. "}" ..
            " yout={" .. table.concat(ykeys, ",") .. "}")

        return nil, nil
    end

    log("PREFAB_AUTO_MOUSE_CAPTURE x=" ..
        tostring(x) .. " y=" .. tostring(y))

    return math.floor(x + 0.5), math.floor(y + 0.5)
end

local function restore_mouse_position_131()
    if pcl11_session == nil then
        return false
    end

    local x = pcl11_session.original_mouse_x
    local y = pcl11_session.original_mouse_y

    if x == nil or y == nil then
        log("PREFAB_AUTO_MOUSE_RESTORE_SKIPPED=no captured mouse")
        return false
    end

    local pc = get_player_controller_10()

    if not is_valid(pc) then
        log("PREFAB_AUTO_MOUSE_RESTORE_SKIPPED=no PlayerController")
        return false
    end

    local ok, err = pcall(function()
        pc:SetMouseLocation(x, y)
    end)

    if not ok then
        log("PREFAB_AUTO_MOUSE_RESTORE_ERROR=" .. tostring(err))
        return false
    end

    log("PREFAB_AUTO_MOUSE_RESTORED x=" ..
        tostring(x) .. " y=" .. tostring(y))

    return true
end

local function collect_design_parts_131(design)
    local parts = {}

    design.AppliedSwordParts:ForEach(function(lua_index, elem)
        parts[lua_index - 1] = elem:get()
    end)

    return parts
end

local function collect_empty_staging_slots_131(design)
    local result = {}
    local parts = collect_design_parts_131(design)
    local _, actors, _ = build_actor_map_10(design, nil)

    local count = #design.AppliedSwordParts

    -- Prefer earlier/rootward parts because they tend to be stable,
    -- easy-to-project staging locations.
    for native_index = 0, count - 1 do
        local part = parts[native_index]
        local actor = actors[native_index]

        if part ~= nil and is_valid(actor) then
            local row = nil
            local row_err = nil

            row, row_err = get_sword_part_row_10(actor)

            if row ~= nil then
                local slots = nil
                local ok = pcall(function()
                    slots = row.Slots
                end)

                if ok and slots ~= nil then
                    local slot_count = #slots
                    local occupied = {}

                    if part.SlotChildren ~= nil then
                        part.SlotChildren:ForEach(function(lua_slot, elem)
                            local child = elem:get()
                            occupied[lua_slot - 1] =
                                child ~= nil and child >= 0
                        end)
                    end

                    for slot_native = 0, slot_count - 1 do
                        if not occupied[slot_native] then
                            local slot_struct = nil

                            slots:ForEach(function(lua_slot, elem)
                                if lua_slot - 1 == slot_native then
                                    slot_struct = elem:get()
                                end
                            end)

                            local special = false

                            if slot_struct ~= nil then
                                pcall(function()
                                    special =
                                        slot_struct.bSpecial and true or false
                                end)
                            end

                            table.insert(result, {
                                parent_native = native_index,
                                slot_native = slot_native,
                                special = special
                            })
                        end
                    end
                end
            else
                log("PREFAB_AUTO_STAGE_ROW_SKIP native=" ..
                    tostring(native_index) ..
                    " error=" .. tostring(row_err))
            end
        end
    end

    -- Stable sort: normal slots before special slots.
    table.sort(result, function(a, b)
        if a.special ~= b.special then
            return not a.special
        end

        if a.parent_native ~= b.parent_native then
            return a.parent_native < b.parent_native
        end

        return a.slot_native < b.slot_native
    end)

    log("PREFAB_AUTO_STAGE_CANDIDATE_COUNT=" ..
        tostring(#result))

    for i, target in ipairs(result) do
        log("PREFAB_AUTO_STAGE_CANDIDATE index=" ..
            tostring(i) ..
            " parent_native=" .. tostring(target.parent_native) ..
            " slot_native=" .. tostring(target.slot_native) ..
            " special=" .. tostring(target.special))
    end

    return result
end

local function dump_slot_actor_pool_131(label)
    local handling = find_handling_component_9()

    if not is_valid(handling) then
        log(label .. "_SLOT_POOL_ERROR=no handling")
        return
    end

    local pool = nil
    local in_use = -1
    local visible = -1

    local ok, err = pcall(function()
        pool = handling.SwordPartSlotActorPool
        in_use = handling.SwordPartSlotActorsInUse
        visible = handling.SwordPartSlotActorsVisible
    end)

    if not ok or pool == nil then
        log(label .. "_SLOT_POOL_ERROR=" .. tostring(err))
        return
    end

    log(label .. "_SLOT_POOL count=" .. tostring(#pool) ..
        " in_use=" .. tostring(in_use) ..
        " visible=" .. tostring(visible))

    pool:ForEach(function(lua_index, elem)
        local actor = elem:get()

        if is_valid(actor) and lua_index <= math.max(in_use, visible, 0) then
            local location = nil
            local attach_parent = nil
            local owner = nil
            local root = nil
            local comp_parent = nil

            pcall(function()
                location = actor:K2_GetActorLocation()
            end)

            pcall(function()
                attach_parent = actor:GetAttachParentActor()
            end)

            pcall(function()
                owner = actor:GetOwner()
            end)

            pcall(function()
                root = actor:K2_GetRootComponent()
            end)

            if is_valid(root) then
                pcall(function()
                    comp_parent = root:GetAttachParent()
                end)
            end

            log(label .. "_SLOT_ACTOR pool_native=" ..
                tostring(lua_index - 1) ..
                " actor=" .. safe_full_name(actor) ..
                " loc=" ..
                (location and
                    (tostring(location.X) .. "," ..
                     tostring(location.Y) .. "," ..
                     tostring(location.Z))
                    or "None") ..
                " attach_parent=" ..
                (is_valid(attach_parent) and
                    safe_full_name(attach_parent) or "None") ..
                " owner=" ..
                (is_valid(owner) and safe_full_name(owner) or "None") ..
                " comp_parent=" ..
                (is_valid(comp_parent) and
                    safe_full_name(comp_parent) or "None"))
        end
    end)
end

local function continue_root_after_stage_131(parent_native, slot_native)
    if pcl11_session == nil then
        return
    end

    local root_native = pcl11_session.local_to_native[1]

    pcl11_session.external_parent_native = parent_native
    pcl11_session.external_parent_slot = slot_native

    log("PREFAB_AUTO_STAGE_OK root_native=" ..
        tostring(root_native) ..
        " parent_native=" .. tostring(parent_native) ..
        " slot_native=" .. tostring(slot_native))

    local apply_ok, apply_err =
        apply_saved_part_11(0, root_native)

    if not apply_ok then
        fail_insert_111("root apply: " .. tostring(apply_err))
        return
    end

    finalize_then_11(function()
        insert_child_after_finalize_11(1)
    end)
end

local function try_auto_stage_root_131(candidate_index)
    if pcl11_session == nil then
        return
    end

    local targets = pcl11_session.staging_targets or {}

    if candidate_index > #targets then
        fail_insert_111(
            "could not automatically find a compatible temporary hardpoint"
        )
        return
    end

    local target = targets[candidate_index]
    local root_native = pcl11_session.local_to_native[1]

    log("PREFAB_AUTO_STAGE_TRY index=" ..
        tostring(candidate_index) ..
        " parent_native=" .. tostring(target.parent_native) ..
        " slot_native=" .. tostring(target.slot_native))

    local target_ok, target_err =
        target_native_slot_11(
            target.parent_native,
            target.slot_native
        )

    if not target_ok then
        log("PREFAB_AUTO_STAGE_TARGET_FAIL index=" ..
            tostring(candidate_index) ..
            " error=" .. tostring(target_err))

        schedule_game_11(75, function()
            try_auto_stage_root_131(candidate_index + 1)
        end)

        return
    end

    schedule_game_11(250, function()
        if pcl11_session == nil then
            return
        end

        local actual_parent, actual_slot, count, link_err =
            candidate_link_11(root_native)

        log("PREFAB_AUTO_STAGE_CHECK index=" ..
            tostring(candidate_index) ..
            " root_native=" .. tostring(root_native) ..
            " count=" .. tostring(count) ..
            " actual_parent=" .. tostring(actual_parent) ..
            " actual_slot=" .. tostring(actual_slot))

        if not link_err and
           actual_parent == target.parent_native and
           actual_slot == target.slot_native then

            continue_root_after_stage_131(
                actual_parent,
                actual_slot
            )
            return
        end

        schedule_game_11(75, function()
            try_auto_stage_root_131(candidate_index + 1)
        end)
    end)
end

local function verify_root_staged_11(attempt)
    if pcl11_session == nil then
        return
    end

    local root_native = pcl11_session.local_to_native[1]

    local parent_native, slot_native, count, err =
        candidate_link_11(root_native)

    if err then
        log("PREFAB_INSERT_ROOT_WAIT attempt=" ..
            tostring(attempt) .. " error=" .. tostring(err))
    else
        log("PREFAB_INSERT_ROOT_STAGE attempt=" ..
            tostring(attempt) ..
            " native=" .. tostring(root_native) ..
            " count=" .. tostring(count) ..
            " parent_native=" .. tostring(parent_native) ..
            " slot_native=" .. tostring(slot_native))

        if parent_native ~= nil then
            pcl11_session.external_parent_native =
                parent_native
            pcl11_session.external_parent_slot =
                slot_native

            local apply_ok, apply_err =
                apply_saved_part_11(0, root_native)

            if not apply_ok then
                fail_insert_111("root apply: " ..
                    tostring(apply_err))
                return
            end

            finalize_then_11(function()
                insert_child_after_finalize_11(1)
            end)

            return
        end
    end

    if attempt >= 6 then
        fail_insert_111("root never staged to a hardpoint; press X if preview remains")
        return
    end

    schedule_game_11(150, function()
        verify_root_staged_11(attempt + 1)
    end)
end

local function build_relations_11(prefab)
    local relations = {}

    local count =
        tonumber(prefab.meta.part_count or "-1") or -1

    if count < 1 then
        return nil, "invalid prefab part_count=" .. tostring(count)
    end

    for parent_local = 0, count - 1 do
        local saved = prefab.parts[parent_local]

        if saved == nil then
            return nil, "missing saved local " .. tostring(parent_local)
        end

        local free_count =
            tonumber(saved.free_child_count or "0") or 0

        if free_count < 0 or free_count % 1 ~= 0 then
            return nil,
                "invalid free_child_count at local=" ..
                tostring(parent_local) ..
                " free_count=" .. tostring(free_count)
        end

        local slots =
            parse_int_list(saved.slot_children or "")

        for i, child_local in ipairs(slots) do
            if child_local >= 0 then
                if child_local >= count then
                    return nil,
                        "saved child index out of range: parent=" ..
                        tostring(parent_local) ..
                        " child=" .. tostring(child_local) ..
                        " count=" .. tostring(count)
                end

                if child_local == 0 then
                    return nil, "saved root cannot be a child"
                end

                if relations[child_local + 1] ~= nil then
                    return nil,
                        "saved child has multiple slot parents: " ..
                        tostring(child_local)
                end

                relations[child_local + 1] = {
                    attachment = "slot",
                    parent_local = parent_local,
                    slot_native = i - 1
                }
            end
        end


        for free_i = 0, free_count - 1 do
            local raw =
                saved["free_child_" .. tostring(free_i)]

            if raw == nil then
                return nil,
                    "missing free child record: parent=" ..
                    tostring(parent_local) ..
                    " ordinal=" .. tostring(free_i)
            end

            local child_text, location_text, rotation_text =
                string.match(
                    tostring(raw),
                    "^([^|]+)|([^|]+)|([^|]+)$"
                )

            if child_text == nil then
                return nil,
                    "invalid free child record: parent=" ..
                    tostring(parent_local) ..
                    " ordinal=" .. tostring(free_i)
            end

            local child_local = tonumber(child_text)

            if child_local == nil or
               child_local % 1 ~= 0 or
               child_local < 0 or
               child_local >= count then
                return nil,
                    "saved free child index out of range: parent=" ..
                    tostring(parent_local) ..
                    " child=" .. tostring(child_text) ..
                    " count=" .. tostring(count)
            end

            if child_local == 0 then
                return nil, "saved root cannot be a child"
            end

            if relations[child_local + 1] ~= nil then
                return nil,
                    "saved child has multiple parents: " ..
                    tostring(child_local)
            end

            local location = parse_num_list(location_text)
            local rotation = parse_num_list(rotation_text)

            if #location ~= 3 or #rotation ~= 4 then
                return nil,
                    "invalid free child transform: parent=" ..
                    tostring(parent_local) ..
                    " child=" .. tostring(child_local)
            end

            relations[child_local + 1] = {
                attachment = "free",
                parent_local = parent_local,
                free_ordinal = free_i,
                free_location = location,
                free_rotation = rotation
            }
        end
    end

    -- The Phase 2 exporter writes DFS parent-before-child order.
    -- Require that property so construction can remain deterministic.
    for child_local = 1, count - 1 do
        local rel =
            relations[child_local + 1]

        if rel == nil then
            return nil,
                "no saved parent relation for local " ..
                tostring(child_local)
        end

        if rel.parent_local >= child_local then
            return nil,
                "prefab local order is not parent-before-child: parent=" ..
                tostring(rel.parent_local) ..
                " child=" .. tostring(child_local)
        end
    end

    return relations, nil
end

local function start_whole_prefab_insert_11()
    log("============================================================")
    log("PREFAB_INSERT_BEGIN file=" .. PCL_IMPORT_FILENAME)
    log("PREFAB_NO_AIM_MODE=true")

    if pcl11_session ~= nil then
        log("PREFAB_INSERT_ERROR session already exists; restart/reload mod")
        return
    end

    if has_active_preview_11() then
        log("PREFAB_INSERT_ERROR an active preview already exists")
        log("Press X to cancel the current preview, then press F6 again.")
        return
    end

    local path = OUTPUT_DIR .. PCL_IMPORT_FILENAME
    local prefab, parse_err = parse_pcl_file(path)

    if prefab == nil then
        log("PREFAB_INSERT_ERROR " .. tostring(parse_err))
        return
    end

    local count =
        tonumber(prefab.meta.part_count or "-1") or -1

    if count ~= 3 then
        log("PREFAB_INSERT_ERROR Phase 13.2 requires exactly 3 parts, got " ..
            tostring(count))
        return
    end

    local relations, relation_err =
        build_relations_11(prefab)

    if relations == nil then
        log("PREFAB_INSERT_ERROR " .. tostring(relation_err))
        return
    end

    for local_index = 0, 2 do
        local saved = prefab.parts[local_index]

        local button = find_button_for_row_9(saved.sword_part)
        if not is_valid(button) then
            log("PREFAB_INSERT_ERROR catalogue tile missing for local=" ..
                tostring(local_index) .. " row=" ..
                tostring(saved.sword_part))
            return
        end

        local pr, mr, resolve_err =
            resolve_identity_rows_fresh_11(
                saved.sword_part,
                saved.material
            )

        if resolve_err then
            log("PREFAB_INSERT_ERROR preflight local=" ..
                tostring(local_index) .. ": " ..
                tostring(resolve_err))
            return
        end

        log("PREFAB_INSERT_PREFLIGHT local=" ..
            tostring(local_index) ..
            " part=" .. tostring(saved.sword_part) ..
            " material=" .. tostring(saved.material))
    end

    local forge, piece, design, state_err =
        state_no_serialize_11()

    if state_err then
        log("PREFAB_INSERT_ERROR " .. tostring(state_err))
        return
    end

    local base_count = #design.AppliedSwordParts
    local mouse_x, mouse_y = capture_mouse_position_131()
    local staging_targets = collect_empty_staging_slots_131(design)

    if #staging_targets == 0 then
        log("PREFAB_INSERT_ERROR no empty staging hardpoints exist")
        return
    end

    pcl11_session = {
        base_count = base_count,
        parts = {
            prefab.parts[0],
            prefab.parts[1],
            prefab.parts[2]
        },
        relations = {
            relations[1],
            relations[2],
            relations[3]
        },
        local_to_native = {},
        staging_targets = staging_targets,
        original_mouse_x = mouse_x,
        original_mouse_y = mouse_y
    }

    log("PREFAB_INSERT_BASE_COUNT=" .. tostring(base_count))
    log("PREFAB_AUTO_STAGE=mod chooses temporary hardpoint automatically")

    local root_saved = pcl11_session.parts[1]

    -- Create the root preview first. It does NOT need the user to be aiming
    -- at a hardpoint. We then move the cursor internally over candidate
    -- staging slots until Bladesong natively stages the root.
    local click_ok, click_err =
        click_catalogue_row_11(root_saved.sword_part)

    if not click_ok then
        log("PREFAB_INSERT_ERROR " .. tostring(click_err))
        pcl11_session = nil
        return
    end

    local root_native = base_count
    pcl11_session.local_to_native[1] = root_native

    log("PREFAB_INSERT_ROOT_ALLOC_EXPECTED native=" ..
        tostring(root_native))

    schedule_game_11(100, function()
        try_auto_stage_root_131(1)
    end)
end



-- ============================================================
-- Phase 14: TRUE ZERO-CURSOR PREFAB-TO-HAND
-- ============================================================
--
-- IMPORTANT:
-- This F6 pipeline NEVER calls target_native_slot_11(),
-- ProjectWorldLocationToScreen(), or SetMouseLocation().
--
-- It uses:
--   catalogue click -> native actor allocation
--   raw PreviewSwordPartActor=nil -> keep allocated actor without cancelling
--   SwordPartActor:DissolveFromParent() -> remove any accidental live snap
--   SwordPartActor.SlotChildParts:TMap:Add() -> direct live topology
--   Actor:K2_AttachToComponent() -> direct live attachment
--   ForgeMode:SerializeSwordPartActorsToData() -> native data reconstruction
--   saved .pcl field writes
--   EnterForgeMode(Piece) -> correct material/geometry rebuild
--   PreviewSwordPartActor = rebuilt prefab root
--
-- User interaction:
--   F6 -> complete prefab appears in hand
--   move normally
--   Left Click once to place
--

local pcl14_session = nil
local pcl142_visual_state = nil

local function stop_all_camera_shakes_142()
    local pc = nil
    pcall(function()
        pc = get_player_controller_10()
    end)

    if not is_valid(pc) then
        return false
    end

    local pcm = nil
    pcall(function()
        pcm = pc.PlayerCameraManager
    end)

    if not is_valid(pcm) then
        return false
    end

    local ok = pcall(function()
        pcm:StopAllCameraShakes(true)
    end)

    return ok
end

local function begin_smooth_visual_142()
    if pcl142_visual_state ~= nil then
        return true
    end

    local forge = find_forge()
    if not is_valid(forge) then
        return false, "ForgeMode unavailable"
    end

    local frontend = nil
    pcall(function()
        frontend = forge:GetFrontend()
    end)

    local camera = nil
    if is_valid(frontend) then
        pcall(function()
            camera = frontend.CameraHandling
        end)
    end

    local state = {
        suppress = false,
        suppress_known = false,
        camera_tick = true,
        camera_tick_known = false,
        use_auto_cam = false,
        use_auto_cam_known = false,
        use_auto_focus = false,
        use_auto_focus_known = false,
        use_auto_focus_edit = false,
        use_auto_focus_edit_known = false
    }

    pcall(function()
        state.suppress = forge.bSupressFrontendUpdate and true or false
        state.suppress_known = true
    end)

    if is_valid(camera) then
        pcall(function()
            state.camera_tick = camera:IsComponentTickEnabled() and true or false
            state.camera_tick_known = true
        end)
        pcall(function()
            state.use_auto_cam = camera.bUseAutoCam and true or false
            state.use_auto_cam_known = true
        end)
        pcall(function()
            state.use_auto_focus = camera.bUseAutoFocus and true or false
            state.use_auto_focus_known = true
        end)
        pcall(function()
            state.use_auto_focus_edit = camera.bUseAutoFocusInEditMode and true or false
            state.use_auto_focus_edit_known = true
        end)
    end

    pcl142_visual_state = state

    -- Do not suppress the Forge frontend during catalogue actor allocation;
    -- the catalogue path itself may rely on frontend state. We only enable
    -- bSupressFrontendUpdate immediately around the final rebuild.

    if is_valid(camera) then
        pcall(function() camera.bUseAutoCam = false end)
        pcall(function() camera.bUseAutoFocus = false end)
        pcall(function() camera.bUseAutoFocusInEditMode = false end)
        pcall(function() camera:SetComponentTickEnabled(false) end)
    end

    stop_all_camera_shakes_142()

    log("PREFAB14_SMOOTH_BEGIN=true")
    log("PREFAB14_SMOOTH_FRONTEND_SUPPRESS=deferred_until_rebuild")
    log("PREFAB14_SMOOTH_CAMERA_TICK=false")
    log("PREFAB14_SMOOTH_AUTOCAM=false")
    log("PREFAB14_SMOOTH_AUTOFOCUS=false")

    return true, nil
end

local function end_smooth_visual_142()
    local state = pcl142_visual_state
    if state == nil then
        return
    end

    local forge = find_forge()
    local frontend = nil
    local camera = nil

    if is_valid(forge) then
        pcall(function()
            frontend = forge:GetFrontend()
        end)

        if state.suppress_known then
            pcall(function()
                forge.bSupressFrontendUpdate = state.suppress
            end)
        else
            pcall(function()
                forge.bSupressFrontendUpdate = false
            end)
        end
    end

    if is_valid(frontend) then
        pcall(function()
            camera = frontend.CameraHandling
        end)
    end

    if is_valid(camera) then
        if state.use_auto_cam_known then
            pcall(function() camera.bUseAutoCam = state.use_auto_cam end)
        end
        if state.use_auto_focus_known then
            pcall(function() camera.bUseAutoFocus = state.use_auto_focus end)
        end
        if state.use_auto_focus_edit_known then
            pcall(function()
                camera.bUseAutoFocusInEditMode = state.use_auto_focus_edit
            end)
        end

        if state.camera_tick_known then
            pcall(function()
                camera:SetComponentTickEnabled(state.camera_tick)
            end)
        else
            pcall(function()
                camera:SetComponentTickEnabled(true)
            end)
        end
    end

    stop_all_camera_shakes_142()
    pcl142_visual_state = nil
    log("PREFAB14_SMOOTH_END=true")
end

local function hide_temp_actor_142(actor, local_index, where)
    if not is_valid(actor) then
        return false
    end

    local hidden_ok = pcall(function()
        actor:SetActorHiddenInGame(true)
    end)

    pcall(function()
        actor:SetActorEnableCollision(false)
    end)

    if hidden_ok then
        log("PREFAB14_TEMP_HIDDEN local=" .. tostring(local_index) ..
            " where=" .. tostring(where) ..
            " actor=" .. safe_full_name(actor))
    end

    stop_all_camera_shakes_142()
    return hidden_ok
end

local function fail_14(message)
    log("PREFAB14_ERROR " .. tostring(message))

    -- Before native serialization, all prefab actors are temporary and
    -- should be destroyed on failure. This prevents a failed pre-commit
    -- import from reappearing when Forge is reloaded.
    if pcl14_session ~= nil and
       not pcl14_session.serialized_into_piece then

        local wanted = {}

        for _, full in pairs(
            pcl14_session.actor_names or {}
        ) do
            if full ~= nil then
                wanted[full] = true
            end
        end

        local destroyed = 0
        local live =
            collect_live_sword_part_actors_10()

        for _, actor in ipairs(live) do
            if is_valid(actor) and
               wanted[safe_full_name(actor)] then

                local ok = pcall(function()
                    actor:K2_DestroyActor()
                end)

                if ok then
                    destroyed =
                        destroyed + 1
                end
            end
        end

        local handling =
            find_handling_component_9()

        if is_valid(handling) then
            pcall(function()
                handling.PreviewSwordPartActor = nil
                handling.BestSwordPartSlotParent = nil
            end)
        end

        log("PREFAB14_ABORT_TEMP_CLEANUP destroyed=" ..
            tostring(destroyed))
    elseif pcl14_session ~= nil and
           pcl14_session.serialized_into_piece then

        log("PREFAB14_ABORT_WARNING real Piece was already serialized")
        log("PREFAB14_ABORT_WARNING use Ctrl+Z or reload the clean test save before saving")
    end

    end_smooth_visual_142()
    pcl11_session = nil
    pcl14_session = nil
end

local function live_actor_by_full_name_14(full_name)
    if full_name == nil then
        return nil
    end

    local actors = collect_live_sword_part_actors_10()

    for _, actor in ipairs(actors) do
        if is_valid(actor) and safe_full_name(actor) == full_name then
            return actor
        end
    end

    return nil
end

local function current_preview_14()
    local handling = find_handling_component_9()

    if not is_valid(handling) then
        return nil, nil
    end

    local preview = nil
    pcall(function()
        preview = handling.PreviewSwordPartActor
    end)

    return handling, preview
end

local function clear_preview_pointer_14()
    local handling, preview = current_preview_14()

    if not is_valid(handling) then
        return false, "handling component unavailable"
    end

    local ok, err = pcall(function()
        handling.PreviewSwordPartActor = nil
        handling.BestSwordPartSlotParent = nil
    end)

    if not ok then
        return false, tostring(err)
    end

    return true, nil
end

local function detach_live_actor_14(actor)
    if not is_valid(actor) then
        return false, "actor invalid"
    end

    local result = false
    local ok, err = pcall(function()
        result = actor:DissolveFromParent()
    end)

    if not ok then
        return false, tostring(err)
    end

    log("PREFAB14_DISSOLVE actor=" ..
        safe_full_name(actor) ..
        " result=" .. tostring(result))

    -- false is allowed here: it means it was already unattached.
    return true, nil
end

local function live_tree_count_14(root)
    if not is_valid(root) then
        return 0
    end

    local seen = {}
    local count = 0

    local function walk(actor)
        if not is_valid(actor) then
            return
        end

        local full = safe_full_name(actor)
        if seen[full] then
            return
        end

        seen[full] = true
        count = count + 1

        local slots = nil
        pcall(function()
            slots = actor.SlotChildParts
        end)

        if slots ~= nil then
            pcall(function()
                slots:ForEach(function(_, vp)
                    local child = vp:get()
                    if is_valid(child) then
                        walk(child)
                    end
                end)
            end)
        end

        local free = nil
        pcall(function()
            free = actor.FreeChildParts
        end)

        if free ~= nil then
            pcall(function()
                free:ForEach(function(kp, _)
                    local child = kp:get()
                    if is_valid(child) then
                        walk(child)
                    end
                end)
            end)
        end
    end

    walk(root)
    return count
end


-- Phase 15.2 export helper.
-- Global on purpose: write_prefab() is defined much earlier in this file.
-- Phase 15.11.36 also shares one live actor map across class + render export
-- so a large build is never recursively scanned twice in the same hotkey run.
PCL151136ExportActorMapCache = nil
function PCLBuildActorClassMapForExport(design)
    local result = {}

    if design == nil then
        return result
    end

    PCL151136ExportActorMapCache = nil

    local _, actors, err =
        build_actor_map_10(design, nil)

    if actors ~= nil then
        PCL151136ExportActorMapCache = actors
    end

    if actors == nil then
        log("EXPORT_ACTOR_CLASS_MAP_ERROR " ..
            tostring(err))
        return result
    end

    for native_index, actor in pairs(actors) do
        if is_valid(actor) then
            local cls = nil

            local ok = pcall(function()
                cls = actor:GetClass()
            end)

            if ok and is_valid(cls) then
                result[native_index] =
                    safe_full_name(cls)
            end
        end
    end

    local count = 0
    for _, _ in pairs(result) do
        count = count + 1
    end

    log("EXPORT_ACTOR_CLASS_MAP_OK count=" ..
        tostring(count))

    return result
end


function PCLBuildActorRenderAssetMapForExport(design)
    local result = {}

    if design == nil then
        return result
    end

    local actors = PCL151136ExportActorMapCache
    local err = nil

    if type(actors) ~= "table" then
        local _
        _, actors, err = build_actor_map_10(design, nil)
        log("PCL15_11_36_EXPORT_MAP_CACHE=miss")
    else
        log("PCL15_11_36_EXPORT_MAP_CACHE=hit")
    end

    -- This cache is deliberately one-shot; never retain live actor wrappers
    -- beyond the current export pipeline.
    PCL151136ExportActorMapCache = nil

    if actors == nil then
        log("EXPORT_RENDER_ASSET_MAP_ERROR " ..
            tostring(err))
        return result
    end

    for native_index, actor in pairs(actors) do
        if is_valid(actor) then
            local asset = nil

            -- Static sword parts: the actor RootComponent is the actual
            -- StaticMeshComponent, even though actor.StaticMeshComponent is
            -- not exposed through this UE4SS build.
            pcall(function()
                local root = actor.RootComponent

                if is_valid(root) and
                   is_valid(root.StaticMesh) then
                    asset = root.StaticMesh
                end
            end)

            -- Deformable sword parts retain their source UStaticMesh in Mesh.
            if not is_valid(asset) then
                pcall(function()
                    if is_valid(actor.Mesh) then
                        asset = actor.Mesh
                    end
                end)
            end

            -- Skeletal fallback when present.
            if not is_valid(asset) then
                pcall(function()
                    local root = actor.RootComponent

                    if is_valid(root) and
                       is_valid(root.SkeletalMesh) then
                        asset = root.SkeletalMesh
                    end
                end)
            end

            if not is_valid(asset) then
                pcall(function()
                    local root = actor.RootComponent

                    if is_valid(root) and
                       is_valid(root.SkeletalMeshAsset) then
                        asset = root.SkeletalMeshAsset
                    end
                end)
            end

            if is_valid(asset) then
                result[native_index] =
                    safe_full_name(asset)
            else
                result[native_index] = "None"
            end
        end
    end

    local count = 0
    local resolved = 0

    for _, value in pairs(result) do
        count = count + 1
        if value ~= nil and value ~= "None" then
            resolved = resolved + 1
        end
    end

    log("EXPORT_RENDER_ASSET_MAP_OK count=" ..
        tostring(count) ..
        " resolved=" .. tostring(resolved))

    return result
end

local function find_empty_live_slot_14(design)
    local _, actors, _ = build_actor_map_10(design, nil)
    local parts = capture_parts(design)
    local design_count = #design.AppliedSwordParts

    for native_index = 0, design_count - 1 do
        local actor = actors[native_index]
        local applied = parts[native_index]

        if is_valid(actor) and applied ~= nil then
            local row = nil
            local row_err = nil
            row, row_err = get_sword_part_row_10(actor)

            if row ~= nil then
                local slots = row.Slots
                local live_map = nil

                pcall(function()
                    live_map = actor.SlotChildParts
                end)

                if slots ~= nil and live_map ~= nil then
                    local candidates = {}

                    slots:ForEach(function(lua_slot, elem)
                        local slot_native = lua_slot - 1
                        local slot = elem:get()

                        local occupied = false

                        pcall(function()
                            occupied = live_map:Contains(slot_native)
                        end)

                        if not occupied then
                            local special = false
                            local bone = "None"
                            local ox, oy, oz = 0, 0, 0

                            pcall(function()
                                special = slot.bSpecial and true or false
                                bone = safe_name(slot.BoneName)
                                ox = slot.Offset.X
                                oy = slot.Offset.Y
                                oz = slot.Offset.Z
                            end)

                            table.insert(candidates, {
                                native = native_index,
                                actor = actor,
                                slot = slot_native,
                                special = special,
                                bone = bone,
                                ox = ox,
                                oy = oy,
                                oz = oz
                            })
                        end
                    end)

                    table.sort(candidates, function(a, b)
                        if a.special ~= b.special then
                            return not a.special
                        end

                        local az =
                            math.abs(a.ox) +
                            math.abs(a.oy) +
                            math.abs(a.oz)

                        local bz =
                            math.abs(b.ox) +
                            math.abs(b.oy) +
                            math.abs(b.oz)

                        return az < bz
                    end)

                    if #candidates > 0 then
                        local c = candidates[1]

                        return {
                            parent_native = c.native,
                            parent_full_name = safe_full_name(c.actor),
                            slot_native = c.slot,
                            bone = c.bone,
                            ox = c.ox,
                            oy = c.oy,
                            oz = c.oz
                        }, nil
                    end
                end
            else
                log("PREFAB14_STAGE_ROW_SKIP native=" ..
                    tostring(native_index) ..
                    " error=" .. tostring(row_err))
            end
        end
    end

    return nil, "no empty live sword-part slot available"
end

local function attach_child_live_14(parent, slot_native, child)
    if not is_valid(parent) or not is_valid(child) then
        return false, "parent/child invalid"
    end

    local cache = PCL151117_CACHE

    -- Phase 15.11.18 true data-only link fast path.  Slot metadata, sockets,
    -- components and relative offsets are irrelevant to the serializer once the
    -- explicit SlotChildParts relation is present.
    if cache ~= nil and cache.data_only_staging then
        local map = nil
        pcall(function() map = parent.SlotChildParts end)
        if map == nil then return false, "parent SlotChildParts unavailable" end
        local ok, err = pcall(function() map:Add(slot_native, child) end)
        if not ok then return false, "SlotChildParts:Add failed: " .. tostring(err) end
        cache.stats.data_only_links = (cache.stats.data_only_links or 0) + 1
        return true, nil
    end

    local row_name = live_actor_row_10(parent)
    local meta_key = tostring(row_name) .. "\31" .. tostring(slot_native)
    local meta = cache and cache.slot_meta and cache.slot_meta[meta_key] or nil

    if meta ~= nil then
        cache.stats.slot_hits = (cache.stats.slot_hits or 0) + 1
    else
        local row = nil
        if cache ~= nil and cache.part_rows ~= nil then
            local resolved = cache.part_rows[tostring(row_name)]
            if resolved ~= nil then row = resolved.row end
        end

        local slot = nil
        if row ~= nil then
            local slots = nil
            local ok, err = pcall(function() slots = row.Slots end)
            if not ok or slots == nil then
                return false, "SwordPartData.Slots unavailable: " .. tostring(err)
            end
            ok, err = pcall(function()
                slots:ForEach(function(lua_index, elem)
                    if lua_index - 1 == slot_native then slot = elem:get() end
                end)
            end)
            if not ok then return false, "Slots ForEach/get failed: " .. tostring(err) end
            if slot == nil then return false, "slot index not found: " .. tostring(slot_native) end
        else
            local row_err = nil
            row, row_err = get_sword_part_row_10(parent)
            if row == nil then return false, row_err end
            local slot_err = nil
            slot, slot_err = get_slot_struct_10(row, slot_native)
            if slot == nil then return false, slot_err end
        end

        local bone_name = "None"
        local offset = nil
        local ox, oy, oz = 0, 0, 0
        local ok, err = pcall(function()
            bone_name = safe_name(slot.BoneName)
            offset = slot.Offset
            ox = offset.X
            oy = offset.Y
            oz = offset.Z
        end)
        if not ok then return false, "slot metadata: " .. tostring(err) end

        local socket_name = nil
        ok, err = pcall(function()
            socket_name = FName(
                (bone_name ~= nil and bone_name ~= "") and bone_name or "None",
                EFindName.FNAME_Find
            )
        end)
        if not ok or socket_name == nil then
            return false, "socket FName failed: " .. tostring(err)
        end

        meta = {
            bone_name = bone_name,
            socket_name = socket_name,
            offset = offset,
            ox = ox, oy = oy, oz = oz
        }
        if cache ~= nil and cache.slot_meta ~= nil then
            cache.slot_meta[meta_key] = meta
            cache.stats.slot_misses = (cache.stats.slot_misses or 0) + 1
        end
    end

    local map = nil
    pcall(function() map = parent.SlotChildParts end)
    if map == nil then return false, "parent SlotChildParts unavailable" end

    local ok, err = pcall(function() map:Add(slot_native, child) end)
    if not ok then return false, "SlotChildParts:Add failed: " .. tostring(err) end

    local parent_component = get_actor_component_10(parent)
    if not is_valid(parent_component) then return false, "parent root component unavailable" end

    local attached = false
    ok, err = pcall(function()
        attached = child:K2_AttachToComponent(
            parent_component,
            meta.socket_name,
            2, 2, 2,
            false
        )
    end)
    if not ok then return false, "K2_AttachToComponent failed: " .. tostring(err) end
    if not attached then return false, "K2_AttachToComponent returned false" end

    local has_offset = math.abs(meta.ox) > 0.0001 or
        math.abs(meta.oy) > 0.0001 or math.abs(meta.oz) > 0.0001

    if has_offset then
        local child_root = nil
        pcall(function() child_root = child:K2_GetRootComponent() end)
        if not is_valid(child_root) then return false, "child root component unavailable" end
        local hit = {}
        ok, err = pcall(function()
            child_root:K2_SetRelativeLocation(meta.offset, false, hit, true)
        end)
        if not ok then
            return false, "K2_SetRelativeLocation(offset) failed: " .. tostring(err)
        end
    end

    return true, nil
end

-- Phase 15.11.32: materialize an exported free-child relation directly into
-- SwordPartActor.FreeChildParts.  The reflected map value is FTransform and
-- UE4SS accepts the same Lua-table struct shape used by actor spawn calls.
function PCL151132FreeTransform(relation)
    local location = relation and relation.free_location or {}
    local rotation = relation and relation.free_rotation or {}

    return {
        Rotation = {
            X = rotation[1] or 0.0,
            Y = rotation[2] or 0.0,
            Z = rotation[3] or 0.0,
            W = rotation[4] or 1.0
        },
        Translation = {
            X = location[1] or 0.0,
            Y = location[2] or 0.0,
            Z = location[3] or 0.0
        },
        Scale3D = {
            X = 1.0,
            Y = 1.0,
            Z = 1.0
        }
    }
end

function PCL151132AttachFreeChild(parent, child, relation)
    if not is_valid(parent) or not is_valid(child) then
        return false, "free parent/child invalid"
    end

    local map = nil
    pcall(function()
        map = parent.FreeChildParts
    end)

    if map == nil then
        return false, "parent FreeChildParts unavailable"
    end

    local transform = PCL151132FreeTransform(relation)
    local ok, err = pcall(function()
        map:Add(child, transform)
    end)

    if not ok then
        return false, "FreeChildParts:Add failed: " .. tostring(err)
    end

    if PCL151117_CACHE ~= nil then
        PCL151117_CACHE.stats.data_only_free_links =
            (PCL151117_CACHE.stats.data_only_free_links or 0) + 1
    end

    return true, nil
end

local function native_index_for_actor_name_14(design, full_name)
    local _, actors, _ = build_actor_map_10(design, nil)

    for native_index, actor in pairs(actors) do
        if is_valid(actor) and
           safe_full_name(actor) == full_name then
            return native_index
        end
    end

    return nil
end

local function allocate_part_14(local_index)
    if pcl14_session == nil then
        return
    end

    local part_count =
        pcl14_session.part_count or 0

    if local_index >= part_count then
        -- Every prefab actor now exists as a hidden live actor.
        local actors = {}

        for local_i = 0, part_count - 1 do
            local full =
                pcl14_session.actor_names[local_i + 1]

            local actor =
                live_actor_by_full_name_14(full)

            if not is_valid(actor) then
                fail_14(
                    "allocated actor disappeared before linking local=" ..
                    tostring(local_i) ..
                    " actor=" .. tostring(full)
                )
                return
            end

            actors[local_i + 1] = actor
        end

        local root =
            actors[1]

        local stage_parent =
            live_actor_by_full_name_14(
                pcl14_session.stage_parent_full_name
            )

        if not is_valid(root) or
           not is_valid(stage_parent) then
            fail_14(
                "root or internal staging parent disappeared before linking"
            )
            return
        end

        log("PREFAB14_LINK_BEGIN part_count=" ..
            tostring(part_count))

        -- Make the prefab tree temporarily reachable from the current Forge
        -- root so Bladesong's native serializer discovers it.
        local ok, err =
            attach_child_live_14(
                stage_parent,
                pcl14_session.stage_slot_native,
                root
            )

        if not ok then
            fail_14(
                "stage-root live attach: " ..
                tostring(err)
            )
            return
        end

        -- Link every saved SlotChildren relation.
        for child_local = 1, part_count - 1 do
            local relation =
                pcl14_session.relations[
                    child_local + 1
                ]

            if relation == nil then
                fail_14(
                    "missing relation while linking local=" ..
                    tostring(child_local)
                )
                return
            end

            local parent =
                actors[
                    relation.parent_local + 1
                ]

            local child =
                actors[
                    child_local + 1
                ]

            if not is_valid(parent) or
               not is_valid(child) then
                fail_14(
                    "invalid actor while linking parent_local=" ..
                    tostring(relation.parent_local) ..
                    " child_local=" ..
                    tostring(child_local)
                )
                return
            end

            ok, err =
                attach_child_live_14(
                    parent,
                    relation.slot_native,
                    child
                )

            if not ok then
                fail_14(
                    "live attach parent_local=" ..
                    tostring(relation.parent_local) ..
                    " child_local=" ..
                    tostring(child_local) ..
                    " slot=" ..
                    tostring(relation.slot_native) ..
                    ": " .. tostring(err)
                )
                return
            end

            if child_local % 10 == 0 or
               child_local == part_count - 1 then
                log("PREFAB14_LINK_PROGRESS=" ..
                    tostring(child_local + 1) ..
                    "/" .. tostring(part_count))
            end
        end

        local live_count =
            live_tree_count_14(root)

        log("PREFAB14_LIVE_TREE_COUNT=" ..
            tostring(live_count) ..
            " expected=" .. tostring(part_count))

        if live_count ~= part_count then
            fail_14(
                "live tree count mismatch expected=" ..
                tostring(part_count) ..
                " actual=" .. tostring(live_count)
            )
            return
        end

        local forge, piece, design, state_err =
            state_no_serialize_11()

        if state_err then
            fail_14(state_err)
            return
        end

        log("PREFAB14_SERIALIZE_BEGIN")

        local serialize_ok, serialize_err =
            pcall(function()
                forge:SerializeSwordPartActorsToData()
            end)

        if not serialize_ok then
            fail_14(
                "SerializeSwordPartActorsToData: " ..
                tostring(serialize_err)
            )
            return
        end

        log("PREFAB14_SERIALIZE_OK")
        pcl14_session.serialized_into_piece = true
        log("PREFAB14_COMMIT_POINT_REACHED=true")

        local forge2, piece2, design2, state_err2 =
            state_no_serialize_11()

        if state_err2 then
            fail_14(state_err2)
            return
        end

        -- Build the graph mapping ONCE and reverse it by full actor name.
        -- The 3-part proof rebuilt the graph for every local part; that would
        -- be unnecessarily expensive for a 50+ part prefab.
        local _, mapped_actors, map_err =
            build_actor_map_10(design2, nil)

        if mapped_actors == nil then
            fail_14(
                "post-serialize actor map failed: " ..
                tostring(map_err)
            )
            return
        end

        local native_by_actor_name = {}

        for native_index, actor in pairs(mapped_actors) do
            if is_valid(actor) then
                native_by_actor_name[
                    safe_full_name(actor)
                ] = native_index
            end
        end

        local local_to_native = {}

        for local_i = 0, part_count - 1 do
            local full =
                pcl14_session.actor_names[
                    local_i + 1
                ]

            local native =
                native_by_actor_name[full]

            if native == nil then
                fail_14(
                    "could not map serialized prefab actor local=" ..
                    tostring(local_i) ..
                    " actor=" .. tostring(full)
                )
                return
            end

            local_to_native[
                local_i + 1
            ] = native

            if local_i < 5 or
               local_i % 10 == 0 or
               local_i == part_count - 1 then
                log("PREFAB14_SERIALIZED_MAP local=" ..
                    tostring(local_i) ..
                    " native=" .. tostring(native) ..
                    " actor=" .. tostring(full))
            end
        end

        -- Reuse the proven AppliedSwordPart identity/material/geometry writer.
        pcl11_session = {
            base_count =
                pcl14_session.base_count,
            parts =
                pcl14_session.parts,
            relations =
                pcl14_session.relations,
            local_to_native =
                local_to_native
        }

        for local_i = 0, part_count - 1 do
            local apply_ok, apply_err =
                apply_saved_part_11(
                    local_i,
                    local_to_native[
                        local_i + 1
                    ]
                )

            if not apply_ok then
                pcl11_session = nil
                fail_14(
                    "saved data apply local=" ..
                    tostring(local_i) ..
                    ": " .. tostring(apply_err)
                )
                return
            end

            if local_i % 10 == 0 or
               local_i == part_count - 1 then
                log("PREFAB14_APPLY_PROGRESS=" ..
                    tostring(local_i + 1) ..
                    "/" .. tostring(part_count))
            end
        end

        -- One hidden/suppressed rebuild applies the exact saved material,
        -- scale, stretch, rotation, sink and other AppliedSwordPart state.
        local forge3, piece3, design3, state_err3 =
            state_no_serialize_11()

        if state_err3 then
            pcl11_session = nil
            fail_14(state_err3)
            return
        end

        stop_all_camera_shakes_142()

        do
            local forge_for_rebuild =
                find_forge()

            if is_valid(forge_for_rebuild) then
                pcall(function()
                    forge_for_rebuild.bSupressFrontendUpdate =
                        true
                end)
            end
        end

        log("PREFAB14_SMOOTH_FRONTEND_SUPPRESS=true")
        log("PREFAB14_SMOOTH_CAMERA_LOCKED_FOR_REBUILD=true")
        log("PREFAB14_REBUILD_BEGIN part_count=" ..
            tostring(part_count))

        local rebuild_ok, rebuild_err =
            enter_piece_again(piece3)

        if not rebuild_ok then
            pcl11_session = nil
            fail_14(
                "EnterForgeMode: " ..
                tostring(rebuild_err)
            )
            return
        end

        -- Larger trees can take a little longer to recreate. Keep the delay
        -- short but scale it modestly for complex prefabs.
        local rebuild_delay =
            120 + math.min(380, part_count * 4)

        schedule_game_11(rebuild_delay, function()
            if pcl14_session == nil then
                pcl11_session = nil
                return
            end

            local forge4, piece4, design4, state_err4 =
                state_no_serialize_11()

            if state_err4 then
                pcl11_session = nil
                fail_14(state_err4)
                return
            end

            local root_native =
                local_to_native[1]

            local _, actors4, rebuild_map_err =
                build_actor_map_10(
                    design4,
                    nil
                )

            if actors4 == nil then
                pcl11_session = nil
                fail_14(
                    "rebuilt actor map failed: " ..
                    tostring(rebuild_map_err)
                )
                return
            end

            local rebuilt_root =
                actors4[root_native]

            if not is_valid(rebuilt_root) then
                pcl11_session = nil
                fail_14(
                    "rebuilt prefab root unavailable native=" ..
                    tostring(root_native)
                )
                return
            end

            local handling =
                find_handling_component_9()

            if not is_valid(handling) then
                pcl11_session = nil
                fail_14(
                    "handling component unavailable"
                )
                return
            end

            log("PREFAB14_HAND_ASSIGN_BEGIN root_native=" ..
                tostring(root_native) ..
                " actor=" ..
                safe_full_name(rebuilt_root))

            local assign_ok, assign_err =
                pcall(function()
                    handling.PreviewSwordPartActor =
                        rebuilt_root
                end)

            if not assign_ok then
                pcl11_session = nil
                fail_14(
                    "PreviewSwordPartActor write: " ..
                    tostring(assign_err)
                )
                return
            end

            -- Finished tree is already held. Restore the Forge camera only now.
            end_smooth_visual_142()

            schedule_game_11(250, function()
                local handling2 =
                    find_handling_component_9()

                if not is_valid(handling2) then
                    pcl11_session = nil
                    fail_14(
                        "handling disappeared during verify"
                    )
                    return
                end

                local preview = nil
                local has_preview = false

                pcall(function()
                    preview =
                        handling2.PreviewSwordPartActor
                end)

                pcall(function()
                    has_preview =
                        handling2:HasPreviewSwordPart() and
                        true or false
                end)

                local tree_count =
                    live_tree_count_14(preview)

                log("PREFAB14_VERIFY_HAS_PREVIEW=" ..
                    tostring(has_preview))

                log("PREFAB14_VERIFY_PREVIEW=" ..
                    (is_valid(preview) and
                        safe_full_name(preview) or
                        "None"))

                log("PREFAB14_VERIFY_TREE_COUNT=" ..
                    tostring(tree_count) ..
                    " expected=" ..
                    tostring(part_count))

                if has_preview and
                   is_valid(preview) and
                   tree_count == part_count then

                    log("PREFAB14_OK complete prefab spawned directly into hand")
                    log("PREFAB14_GENERALIZED_PART_COUNT=" ..
                        tostring(part_count))
                    log("PREFAB14_CURSOR_MOVED=false")
                    log("Move normally and LEFT CLICK once to place.")
                else
                    log("PREFAB14_NOT_CONFIRMED")
                end

                end_smooth_visual_142()
                pcl11_session = nil
                pcl14_session = nil
                log("============================================================")
            end)
        end)

        return
    end

    local saved =
        pcl14_session.parts[
            local_index + 1
        ]

    if saved == nil then
        fail_14(
            "missing saved part during allocation local=" ..
            tostring(local_index)
        )
        return
    end

    log("PREFAB14_ALLOC_BEGIN local=" ..
        tostring(local_index) ..
        "/" .. tostring(part_count - 1) ..
        " part=" .. tostring(saved.sword_part))

    local before_count = nil

    do
        local _, _, design, err =
            state_no_serialize_11()

        if err then
            fail_14(err)
            return
        end

        before_count =
            #design.AppliedSwordParts
    end

    local click_ok, click_err =
        click_catalogue_row_11(
            saved.sword_part
        )

    if not click_ok then
        fail_14(click_err)
        return
    end

    -- Hide the temporary catalogue actor immediately. The user sees only
    -- the final rebuilt tree.
    do
        local _, immediate_preview =
            current_preview_14()

        if is_valid(immediate_preview) then
            hide_temp_actor_142(
                immediate_preview,
                local_index,
                "immediate"
            )
        end
    end

    schedule_game_11(120, function()
        if pcl14_session == nil then
            return
        end

        local handling, preview =
            current_preview_14()

        if not is_valid(handling) or
           not is_valid(preview) then
            fail_14(
                "catalogue allocation produced no preview local=" ..
                tostring(local_index)
            )
            return
        end

        hide_temp_actor_142(
            preview,
            local_index,
            "delayed"
        )

        local _, _, design, state_err =
            state_no_serialize_11()

        if state_err then
            fail_14(state_err)
            return
        end

        local after_count =
            #design.AppliedSwordParts

        log("PREFAB14_ALLOC_PREVIEW local=" ..
            tostring(local_index) ..
            " actor=" ..
            safe_full_name(preview) ..
            " row=" ..
            live_actor_row_10(preview) ..
            " count_before=" ..
            tostring(before_count) ..
            " count_after=" ..
            tostring(after_count))

        if after_count == before_count then
            log("PREFAB14_ALLOC_LIVE_ONLY local=" ..
                tostring(local_index) ..
                " design_append_deferred=true")
        elseif after_count > before_count then
            log("PREFAB14_ALLOC_DESIGN_GREW local=" ..
                tostring(local_index) ..
                " delta=" ..
                tostring(after_count - before_count))
        else
            fail_14(
                "design count unexpectedly decreased during allocation local=" ..
                tostring(local_index)
            )
            return
        end

        pcl14_session.actor_names[
            local_index + 1
        ] = safe_full_name(preview)

        local detach_ok, detach_err =
            detach_live_actor_14(preview)

        if not detach_ok then
            fail_14(
                "live detach local=" ..
                tostring(local_index) ..
                ": " .. tostring(detach_err)
            )
            return
        end

        local clear_ok, clear_err =
            clear_preview_pointer_14()

        if not clear_ok then
            fail_14(
                "preview clear local=" ..
                tostring(local_index) ..
                ": " .. tostring(clear_err)
            )
            return
        end

        schedule_game_11(80, function()
            if pcl14_session == nil then
                return
            end

            local actor =
                live_actor_by_full_name_14(
                    pcl14_session.actor_names[
                        local_index + 1
                    ]
                )

            local _, _, design2, state_err2 =
                state_no_serialize_11()

            if state_err2 then
                fail_14(state_err2)
                return
            end

            local retained_count =
                #design2.AppliedSwordParts

            log("PREFAB14_ALLOC_RETAIN local=" ..
                tostring(local_index) ..
                " actor_alive=" ..
                tostring(is_valid(actor)) ..
                " design_count=" ..
                tostring(retained_count) ..
                " design_append_required_now=false")

            if not is_valid(actor) then
                fail_14(
                    "allocated actor was destroyed after preview clear local=" ..
                    tostring(local_index)
                )
                return
            end

            if local_index % 10 == 0 or
               local_index == part_count - 1 then
                log("PREFAB14_ALLOC_PROGRESS=" ..
                    tostring(local_index + 1) ..
                    "/" .. tostring(part_count))
            end

            allocate_part_14(
                local_index + 1
            )
        end)
    end)
end


local function allocate_all_parts_fast_144()
    if pcl14_session == nil then
        return
    end

    local part_count =
        pcl14_session.part_count or 0

    log("PREFAB14_FAST_BATCH_ALLOC_BEGIN count=" ..
        tostring(part_count))

    local batch_start =
        os.clock()

    for local_index = 0, part_count - 1 do
        local saved =
            pcl14_session.parts[
                local_index + 1
            ]

        if saved == nil then
            fail_14(
                "fast batch missing saved local=" ..
                tostring(local_index)
            )
            return
        end

        local click_ok, click_err =
            click_catalogue_row_11(
                saved.sword_part
            )

        if not click_ok then
            fail_14(
                "fast batch click local=" ..
                tostring(local_index) ..
                ": " .. tostring(click_err)
            )
            return
        end

        local handling, preview =
            current_preview_14()

        if not is_valid(handling) or
           not is_valid(preview) then
            fail_14(
                "fast batch produced no immediate preview local=" ..
                tostring(local_index)
            )
            return
        end

        hide_temp_actor_142(
            preview,
            local_index,
            "fast_batch"
        )

        pcl14_session.actor_names[
            local_index + 1
        ] =
            safe_full_name(preview)

        local detach_ok, detach_err =
            detach_live_actor_14(preview)

        if not detach_ok then
            fail_14(
                "fast batch detach local=" ..
                tostring(local_index) ..
                ": " .. tostring(detach_err)
            )
            return
        end

        local clear_ok, clear_err =
            clear_preview_pointer_14()

        if not clear_ok then
            fail_14(
                "fast batch preview clear local=" ..
                tostring(local_index) ..
                ": " .. tostring(clear_err)
            )
            return
        end

        -- The catalogue click is synchronous in the proven path. Verify the
        -- actor remained alive immediately, rather than waiting ~200ms for
        -- every single part.
        local actor =
            nil

        local live =
            collect_live_sword_part_actors_10()

        local wanted_name =
            pcl14_session.actor_names[
                local_index + 1
            ]

        for _, candidate in ipairs(live) do
            if is_valid(candidate) and
               safe_full_name(candidate) ==
               wanted_name then
                actor = candidate
                break
            end
        end

        if not is_valid(actor) then
            fail_14(
                "fast batch actor did not survive preview clear local=" ..
                tostring(local_index)
            )
            return
        end

        if local_index < 5 or
           local_index % 10 == 0 or
           local_index == part_count - 1 then

            log("PREFAB14_FAST_BATCH_PROGRESS=" ..
                tostring(local_index + 1) ..
                "/" .. tostring(part_count))
        end
    end

    local elapsed_ms =
        (os.clock() - batch_start) *
        1000.0

    log(string.format(
        "PREFAB14_FAST_BATCH_ALLOC_OK count=%d elapsed_ms=%.3f",
        part_count,
        elapsed_ms
    ))

    -- Give the engine one tick boundary after the tight synchronous batch,
    -- then reuse the proven generalized link/serialize/apply/rebuild path.
    schedule_game_11(1, function()
        allocate_part_14(part_count)
    end)
end

local function start_true_no_cursor_14()
    log("============================================================")
    log("PREFAB14_5_BEGIN exact_material_handles=true fast_batch=true generalized_slot_tree=true zero_cursor=true")
    log("PREFAB14_SET_MOUSE_LOCATION_CALLS=0")

    if pcl14_session ~= nil then
        log("PREFAB14_ERROR session already active")
        return
    end

    local handling, preview =
        current_preview_14()

    if is_valid(preview) then
        log("PREFAB14_ERROR another preview is already active; press X first")
        return
    end

    local path =
        OUTPUT_DIR .. PCL_IMPORT_FILENAME

    local prefab, parse_err =
        parse_pcl_file(path)

    if prefab == nil then
        log("PREFAB14_ERROR " .. tostring(parse_err))
        return
    end

    local count =
        tonumber(prefab.meta.part_count or "-1") or -1

    if count < 1 then
        log("PREFAB14_ERROR invalid part_count=" ..
            tostring(count))
        return
    end

    -- Safety cap for this experimental implementation.
    if count > 250 then
        log("PREFAB14_ERROR experimental generalized loader cap is 250 parts; got " ..
            tostring(count))
        return
    end

    log("PREFAB14_GENERALIZED_PART_COUNT=" ..
        tostring(count))

    local relations, relation_err =
        build_relations_11(prefab)

    if relations == nil then
        log("PREFAB14_ERROR " ..
            tostring(relation_err))
        return
    end

    local forge, piece, design, state_err =
        state_no_serialize_11()

    if state_err then
        log("PREFAB14_ERROR " ..
            tostring(state_err))
        return
    end

    -- Preflight every part before creating any actors.
    for local_index = 0, count - 1 do
        local saved =
            prefab.parts[local_index]

        if saved == nil then
            log("PREFAB14_ERROR missing prefab part local=" ..
                tostring(local_index))
            return
        end

        local button =
            find_button_for_row_9(
                saved.sword_part
            )

        if not is_valid(button) then
            log("PREFAB14_ERROR catalogue tile missing local=" ..
                tostring(local_index) ..
                " row=" ..
                tostring(saved.sword_part))
            return
        end

        -- Legacy PCL compatibility:
        -- The user's current 50-part file was exported before exact
        -- material_data_row/material_data_table fields were added. While
        -- the original source sword is still present, recover those exact
        -- handles from original_index instead of guessing generated
        -- material naming.
        local recovered_ok, recovered_err =
            recover_legacy_material_handle_145(
                saved,
                design
            )

        if not recovered_ok and
           (saved.material_data_row == nil or
            saved.material_data_row == "" or
            saved.material_data_row == "None") then

            log("PREFAB14_LEGACY_MATERIAL_HANDLE_UNAVAILABLE local=" ..
                tostring(local_index) ..
                " reason=" .. tostring(recovered_err))
        end

        -- Full identity preflight BEFORE any preview actor is created.
        local part_resolved, material_resolved, identity_err =
            resolve_identity_rows_fresh_11(
                saved.sword_part,
                saved.material,
                saved.material_data_row,
                saved.material_data_table
            )

        if identity_err then
            log("PREFAB14_PREFLIGHT_IDENTITY_ERROR local=" ..
                tostring(local_index) ..
                " part=" .. tostring(saved.sword_part) ..
                " material=" .. tostring(saved.material) ..
                " error=" .. tostring(identity_err))
            log("PREFAB14_PREFLIGHT_ABORTED_BEFORE_MUTATION=true")
            return
        end

        if local_index < 5 or
           local_index % 10 == 0 or
           local_index == count - 1 then
            log("PREFAB14_PREFLIGHT_PROGRESS=" ..
                tostring(local_index + 1) ..
                "/" .. tostring(count) ..
                " row=" ..
                tostring(saved.sword_part) ..
                " material=" .. tostring(saved.material) ..
                " material_row=" ..
                tostring(
                    material_resolved and
                    safe_name(material_resolved.row_name) or
                    "None"
                ) ..
                " source=" ..
                tostring(
                    material_resolved and
                    material_resolved.source or
                    "None"
                ) ..
                " table=" ..
                tostring(
                    material_resolved and
                    is_valid(material_resolved.data_table) and
                    safe_full_name(material_resolved.data_table) or
                    "None"
                ))
        end
    end

    local staging, staging_err =
        find_empty_live_slot_14(design)

    if staging == nil then
        log("PREFAB14_ERROR " ..
            tostring(staging_err))
        return
    end

    log("PREFAB14_INTERNAL_STAGE parent_native=" ..
        tostring(staging.parent_native) ..
        " slot_native=" ..
        tostring(staging.slot_native) ..
        " parent_actor=" ..
        tostring(staging.parent_full_name))

    local parts = {}
    for local_index = 0, count - 1 do
        parts[local_index + 1] =
            prefab.parts[local_index]
    end

    pcl14_session = {
        part_count = count,
        base_count =
            #design.AppliedSwordParts,
        parts = parts,
        relations = relations,
        actor_names = {},
        stage_parent_full_name =
            staging.parent_full_name,
        stage_slot_native =
            staging.slot_native,
        serialized_into_piece = false
    }

    local smooth_ok, smooth_err =
        begin_smooth_visual_142()

    if not smooth_ok then
        pcl14_session = nil
        log("PREFAB14_ERROR smooth visual setup: " ..
            tostring(smooth_err))
        return
    end

    log("PREFAB14_BATCH_BUILD_BEGIN count=" ..
        tostring(count))
    log("PREFAB14_BATCH_MODE=fast_same_frame")

    allocate_all_parts_fast_144()
end

RegisterKeyBind(Key.F6, function()
    run_game_thread(start_true_no_cursor_14)
end)

log("Phase 14.5 EXACT MATERIAL HANDLE prefab-to-hand loaded.")
log("F6 = exact material-handle preflight + fast hidden batch + complete tree into hand.")
log("F6 pipeline never calls SetMouseLocation.")


-- ============================================================
-- Phase 15: DIRECT DEFERRED SPAWN PROOF
-- ============================================================
--
-- F7 = spawn ONLY saved local-0 directly from SwordPartData.Blueprint.
--
-- This path deliberately does NOT:
--   - click a catalogue button
--   - move the cursor
--   - stage on a hardpoint
--   - call EnterForgeMode()
--   - serialize into the Piece
--
-- It is a performance/initialization proof for the next full batch loader.
--
-- F8 = destroy the last Phase15 proof actor / clear preview pointer.
--

local pcl15_last_actor_name = nil

local function gameplay_statics_15()
    local obj = nil

    local ok = pcall(function()
        obj = StaticFindObject(
            "/Script/Engine.Default__GameplayStatics"
        )
    end)

    if ok and is_valid(obj) then
        return obj
    end

    ok = pcall(function()
        obj = FindFirstOf("GameplayStatics")
    end)

    if ok and is_valid(obj) then
        return obj
    end

    return nil
end

local function actor_by_full_name_15(full_name)
    if full_name == nil then
        return nil
    end

    local actors =
        collect_live_sword_part_actors_10()

    for _, actor in ipairs(actors) do
        if is_valid(actor) and
           safe_full_name(actor) == full_name then
            return actor
        end
    end

    return nil
end

local function neutral_spawn_transform_153()
    -- No live sword actor is needed. UE4SS accepts a Lua table for Unreal
    -- struct parameters, so use the FTransform identity directly.
    --
    -- UE5 FTransform fields:
    --   Rotation    = FQuat
    --   Translation = FVector
    --   Scale3D     = FVector
    return {
        Rotation = {
            X = 0.0,
            Y = 0.0,
            Z = 0.0,
            W = 1.0
        },
        Translation = {
            X = 0.0,
            Y = 0.0,
            Z = 0.0
        },
        Scale3D = {
            X = 1.0,
            Y = 1.0,
            Z = 1.0
        }
    }
end

local function world_context_153()
    -- Any live UObject belonging to the Forge world is a valid
    -- WorldContextObject for GameplayStatics. ForgeMode exists even when
    -- the actual sword contains zero parts.
    local forge = find_forge()

    if is_valid(forge) then
        return forge, "ForgeMode"
    end

    local frontend = nil

    pcall(function()
        frontend = FindFirstOf("BP_ForgeModeFrontend_C")
    end)

    if is_valid(frontend) then
        return frontend, "ForgeModeFrontend"
    end

    return nil, nil
end

local function copy_material_handle_15(
    target_actor,
    material_name
)
    -- Phase 15.11.18: cache the three SwordMaterialHandle fields by material.
    -- The old path walked MaterialLibrary.Materials for every staging actor.
    local cache = PCL151117_CACHE
    local cache_key = tostring(material_name)
    local cached = cache and cache.material_handles and cache.material_handles[cache_key] or nil

    if cached ~= nil then
        local ok, err = pcall(function()
            target_actor.SwordMaterialHandle.Name = cached.Name
            target_actor.SwordMaterialHandle.Type = cached.Type
            target_actor.SwordMaterialHandle.UVType = cached.UVType
        end)
        if ok then
            cache.stats.material_handle_hits =
                (cache.stats.material_handle_hits or 0) + 1
            return true, nil
        end
        return false, "cached material handle write failed: " .. tostring(err)
    end

    local lib = find_live_material_library_144()
    if not is_valid(lib) then
        return false, "MaterialLibrary unavailable"
    end

    local materials = nil
    local ok, err = pcall(function() materials = lib.Materials end)
    if not ok or materials == nil then
        return false, "MaterialLibrary.Materials unavailable: " .. tostring(err)
    end

    local found = false
    local copy_err = nil
    local resolved_handle = nil

    pcall(function()
        materials:ForEach(function(kp, vp)
            if found then return end
            local key = kp:get()
            local entry = vp:get()
            local key_name = "None"
            local entry_name = "None"
            pcall(function() key_name = safe_name(key.Name) end)
            pcall(function() entry_name = safe_name(entry.MaterialName) end)

            if key_name == material_name or entry_name == material_name then
                local inner_ok, inner_err = pcall(function()
                    resolved_handle = {
                        Name = key.Name,
                        Type = key.Type,
                        UVType = key.UVType
                    }
                    target_actor.SwordMaterialHandle.Name = resolved_handle.Name
                    target_actor.SwordMaterialHandle.Type = resolved_handle.Type
                    target_actor.SwordMaterialHandle.UVType = resolved_handle.UVType
                end)
                if inner_ok then
                    found = true
                else
                    copy_err = tostring(inner_err)
                end
            end
        end)
    end)

    if found then
        if cache ~= nil and cache.material_handles ~= nil then
            cache.material_handles[cache_key] = resolved_handle
            cache.stats.material_handle_misses =
                (cache.stats.material_handle_misses or 0) + 1
        end
        return true, nil
    end

    return false, copy_err or
        ("material handle not found: " .. tostring(material_name))
end

local function setup_deferred_actor_identity_15(
    actor,
    saved,
    part_resolved,
    material_resolved
)
    if not is_valid(actor) then
        return false,
            "deferred actor invalid"
    end

    local cache = PCL151117_CACHE
    local part_fname = cache and cache.fnames and cache.fnames[tostring(saved.sword_part)] or nil
    local part_fname_err = nil
    if part_fname == nil then
        part_fname, part_fname_err = make_existing_fname_83(saved.sword_part)
        if part_fname ~= nil and cache and cache.fnames then
            cache.fnames[tostring(saved.sword_part)] = part_fname
        end
    end
    if part_fname == nil then return false, part_fname_err end

    local material_fname = cache and cache.fnames and cache.fnames[tostring(saved.material)] or nil
    local material_fname_err = nil
    if material_fname == nil then
        material_fname, material_fname_err = make_existing_fname_83(saved.material)
        if material_fname ~= nil and cache and cache.fnames then
            cache.fnames[tostring(saved.material)] = material_fname
        end
    end
    if material_fname == nil then return false, material_fname_err end

    local material_row_name =
        material_resolved.row_name

    if type(material_row_name) == "string" then
        local row_key = tostring(material_row_name)
        local converted = cache and cache.fnames and cache.fnames[row_key] or nil
        local converted_err = nil
        if converted == nil then
            converted, converted_err = make_existing_fname_83(material_row_name)
            if converted ~= nil and cache and cache.fnames then
                cache.fnames[row_key] = converted
            end
        end
        if converted == nil then
            return false, "material row FName: " .. tostring(converted_err)
        end
        material_row_name = converted
    end

    local ok, err =
        pcall(function()
            actor.SwordPartDataHandle.DataTable =
                part_resolved.data_table

            actor.SwordPartDataHandle.RowName =
                part_fname

            actor.SwordMaterialName =
                material_fname

            actor.SwordMaterialDataHandle.DataTable =
                material_resolved.data_table

            actor.SwordMaterialDataHandle.RowName =
                material_row_name

            actor.bPending = false

            actor.Scale =
                tonumber(saved.scale) or 1

            actor.Rotation =
                tonumber(saved.rotation) or 0

            actor.Sink =
                tonumber(saved.sink) or 0

            actor.Polish =
                tonumber(saved.polish) or 0

            actor.bIsInFlippedSlot =
                parse_bool(saved.flipped_slot)

            actor.bManualFlip =
                parse_bool(saved.manual_flip)

            local deflection =
                parse_num_list(
                    saved.deflection or
                    "0,0,0,1"
                )

            if actor.Deflection ~= nil then
                actor.Deflection.X =
                    deflection[1] or 0
                actor.Deflection.Y =
                    deflection[2] or 0
                actor.Deflection.Z =
                    deflection[3] or 0
                actor.Deflection.W =
                    deflection[4] or 1
            end
        end)

    if not ok then
        return false,
            "deferred identity/state write failed: " ..
            tostring(err)
    end

    local material_ok, material_err =
        copy_material_handle_15(
            actor,
            saved.material
        )

    if not material_ok then
        log("PREFAB15_MATERIAL_HANDLE_WARNING " .. tostring(material_err))
    end

    return true, nil
end



local function class_from_saved_string_152(saved_class)
    if saved_class == nil or
       saved_class == "" or
       saved_class == "None" then
        return nil, "saved actor_class missing"
    end

    local path =
        tostring(saved_class):match("^%S+%s+(.+)$") or
        tostring(saved_class)

    local cls = nil

    local ok, err =
        pcall(function()
            cls = StaticFindObject(path)
        end)

    if ok and is_valid(cls) then
        return cls, nil
    end

    -- Native classes can also be recovered from their CDO if a particular
    -- UE4SS build does not return the UClass directly by path.
    local class_name =
        path:match("%.([^%.]+)$") or
        path:match("/([^/]+)$")

    if class_name ~= nil then
        local cdo_path =
            "/Script/Bladesong.Default__" ..
            tostring(class_name)

        local cdo = nil

        pcall(function()
            cdo = StaticFindObject(cdo_path)
        end)

        if is_valid(cdo) then
            pcall(function()
                cls = cdo:GetClass()
            end)

            if is_valid(cls) then
                return cls, nil
            end
        end
    end

    return nil,
        "saved actor_class could not be resolved: " ..
        tostring(saved_class) ..
        " error=" .. tostring(err)
end


-- Phase 15.11.34: build a prefab-local SwordPart-row -> saved actor_class map.
-- This recovers old exports where some free-child records have actor_class=None
-- while another occurrence of the same SwordPart row in the same prefab has
-- the exact native class persisted.
function PCL151134SeedSavedRowClasses(parts, part_count)
    if PCL151117_CACHE == nil then
        return 0, 0
    end

    PCL151117_CACHE.saved_actor_class_by_row = {}
    PCL151117_CACHE.saved_actor_class_conflict = {}

    local seeded = 0
    local conflicts = 0

    for i = 1, tonumber(part_count or 0) do
        local saved = parts and parts[i] or nil
        if saved ~= nil then
            local row = tostring(saved.sword_part or "")
            local cls = tostring(saved.actor_class or "")

            if row ~= "" and row ~= "None" and
               cls ~= "" and cls ~= "None" then
                local prior = PCL151117_CACHE.saved_actor_class_by_row[row]

                if prior == nil then
                    PCL151117_CACHE.saved_actor_class_by_row[row] = cls
                    seeded = seeded + 1
                elseif prior ~= cls and
                       not PCL151117_CACHE.saved_actor_class_conflict[row] then
                    PCL151117_CACHE.saved_actor_class_conflict[row] = true
                    conflicts = conflicts + 1
                end
            end
        end
    end

    for row, _ in pairs(PCL151117_CACHE.saved_actor_class_conflict) do
        PCL151117_CACHE.saved_actor_class_by_row[row] = nil
    end

    log("PCL15_11_34_SAVED_ROW_CLASS_SEED rows=" ..
        tostring(seeded) .. " conflicts=" .. tostring(conflicts))

    return seeded, conflicts
end

local function resolve_actor_class_151(saved, design, part_resolved)
    -- Phase 15.11.33: legacy row-class cache. Canonical saved actor_class still
    -- wins; this cache only avoids repeating expensive fallback scans for
    -- legacy prefab records that do not carry a usable actor_class.
    local row_cache_key = "legacy_row_class:" .. tostring(saved.sword_part)

    -- 1. Phase 15.2+ canonical source: exact class persisted in the prefab.
    if saved.actor_class ~= nil and
       saved.actor_class ~= "" and
       saved.actor_class ~= "None" then

        local saved_cls = nil
        local saved_err = nil
        if PCL151117_CACHE ~= nil and PCL151117_CACHE.classes ~= nil then
            saved_cls = PCL151117_CACHE.classes[tostring(saved.actor_class)]
            if is_valid(saved_cls) then
                PCL151117_CACHE.stats.class_hits =
                    (PCL151117_CACHE.stats.class_hits or 0) + 1
            else
                saved_cls = nil
            end
        end

        if not is_valid(saved_cls) then
            saved_cls, saved_err = class_from_saved_string_152(saved.actor_class)
            if is_valid(saved_cls) and PCL151117_CACHE ~= nil and PCL151117_CACHE.classes ~= nil then
                PCL151117_CACHE.classes[tostring(saved.actor_class)] = saved_cls
                PCL151117_CACHE.stats.class_misses =
                    (PCL151117_CACHE.stats.class_misses or 0) + 1
            end
        end

        if is_valid(saved_cls) then
            return saved_cls, "saved_actor_class", nil
        end

        log("PREFAB15_2_SAVED_CLASS_WARNING " ..
            tostring(saved_err))
    end

    if PCL151117_CACHE ~= nil and PCL151117_CACHE.classes ~= nil then
        local cached_row_class = PCL151117_CACHE.classes[row_cache_key]
        if is_valid(cached_row_class) then
            PCL151117_CACHE.stats.legacy_row_class_hits =
                (PCL151117_CACHE.stats.legacy_row_class_hits or 0) + 1
            return cached_row_class, "legacy_row_class_cache", nil
        end
    end

    -- Phase 15.11.34: old free-child exports can have actor_class=None for
    -- one instance even though the same SwordPart row is correctly persisted
    -- elsewhere in the prefab. Prefer that prefab-local exact class string
    -- over any live UObject scan.
    if PCL151117_CACHE ~= nil and
       PCL151117_CACHE.saved_actor_class_by_row ~= nil then
        local seeded_class =
            PCL151117_CACHE.saved_actor_class_by_row[tostring(saved.sword_part)]

        if seeded_class ~= nil then
            local seeded_cls, seeded_err =
                class_from_saved_string_152(seeded_class)

            if is_valid(seeded_cls) then
                if PCL151117_CACHE.classes ~= nil then
                    PCL151117_CACHE.classes[row_cache_key] = seeded_cls
                end
                PCL151117_CACHE.stats.saved_row_class_hits =
                    (PCL151117_CACHE.stats.saved_row_class_hits or 0) + 1
                return seeded_cls, "saved_prefab_row_class", nil
            else
                log("PCL15_11_34_SAVED_ROW_CLASS_WARNING row=" ..
                    tostring(saved.sword_part) ..
                    " class=" .. tostring(seeded_class) ..
                    " error=" .. tostring(seeded_err))
            end
        end
    end

    -- Phase 15.11.35: targeted legacy FreeChild class recovery for the chain
    -- element.  The 2,403-part legacy export contains six of these records
    -- with actor_class=None/render_asset=None.  Unlike 693_Dome there is no
    -- second correctly-mapped occurrence to seed from, because all six are
    -- FreeChildren and the old slot-only actor map never saw them.
    --
    -- Resolve the known native actor class BEFORE touching reflected row
    -- Blueprint/RenderAsset fields.  UE4SS 3.0.1 can null-deref while reading
    -- those fields for this row during the empty-Forge staging pass.
    if tostring(saved.sword_part or "") == "455_MiscAttachment_ChainElement" then
        local chain_cls = nil

        pcall(function()
            chain_cls =
                StaticFindObject(
                    "/Script/Bladesong.SwordPartDeformableStaticMeshActor"
                )
        end)

        if not is_valid(chain_cls) then
            local chain_cdo = nil
            pcall(function()
                chain_cdo =
                    StaticFindObject(
                        "/Script/Bladesong.Default__SwordPartDeformableStaticMeshActor"
                    )
            end)

            if is_valid(chain_cdo) then
                pcall(function()
                    chain_cls = chain_cdo:GetClass()
                end)
            end
        end

        if is_valid(chain_cls) then
            if PCL151117_CACHE ~= nil and PCL151117_CACHE.classes ~= nil then
                PCL151117_CACHE.classes[row_cache_key] = chain_cls
                PCL151117_CACHE.stats.legacy_chain_class_hits =
                    (PCL151117_CACHE.stats.legacy_chain_class_hits or 0) + 1
            end
            return chain_cls,
                "legacy_chain_native_fallback",
                nil
        end

        return nil, nil,
            "455_MiscAttachment_ChainElement native deformable class unavailable"
    end

    -- 2. Optional per-row Blueprint override.
    local blueprint_class = nil

    pcall(function()
        blueprint_class =
            part_resolved.row.Blueprint
    end)

    if is_valid(blueprint_class) then
        if PCL151117_CACHE ~= nil and PCL151117_CACHE.classes ~= nil then
            PCL151117_CACHE.classes[row_cache_key] = blueprint_class
        end
        return blueprint_class,
            "SwordPartData.Blueprint",
            nil
    end

    -- 3. Narrow portable fallback for the current legacy root proof.
    -- Put this BEFORE any live-actor lookup so orphan actors from previous
    -- crash tests cannot contaminate class resolution.
    if saved.sword_part == "80_Misc_Cube" then
        local static_cls = nil

        pcall(function()
            static_cls =
                StaticFindObject(
                    "/Script/Bladesong.SwordPartStaticMeshActor"
                )
        end)

        if not is_valid(static_cls) then
            local cdo = nil

            pcall(function()
                cdo =
                    StaticFindObject(
                        "/Script/Bladesong.Default__SwordPartStaticMeshActor"
                    )
            end)

            if is_valid(cdo) then
                pcall(function()
                    static_cls =
                        cdo:GetClass()
                end)
            end
        end

        if is_valid(static_cls) then
            if PCL151117_CACHE ~= nil and PCL151117_CACHE.classes ~= nil then
                PCL151117_CACHE.classes[row_cache_key] = static_cls
            end
            return static_cls,
                "legacy_cube_native_fallback",
                nil
        end
    end

    -- 4. Fallback for a legacy prefab whose source build is still
    -- loaded: use the exact class of the original live actor.
    local original_index =
        tonumber(saved.original_index or "-1") or -1

    -- Phase 15.11.33: during the current direct importer the active design is
    -- intentionally empty until all actors are spawned/linked/serialized.
    -- Calling build_actor_map_10 against that empty design yields root=-1,
    -- dumps up to 50 live actors, and repeats the scan for legacy records. On
    -- multi-thousand-part prefabs this can make the game appear hard-frozen.
    local graph_fallback_allowed = false
    pcall(function()
        graph_fallback_allowed =
            (tonumber(design.RootSwordPartIdx) or -1) >= 0 and
            #design.AppliedSwordParts > 0
    end)

    if original_index >= 0 and graph_fallback_allowed then
        local _, source_actors, map_err =
            build_actor_map_10(design, nil)

        if source_actors ~= nil then
            local source_actor =
                source_actors[original_index]

            if is_valid(source_actor) and
               live_actor_row_10(source_actor) ==
               saved.sword_part then

                local cls = nil
                local ok, class_err =
                    pcall(function()
                        cls =
                            source_actor:GetClass()
                    end)

                if ok and is_valid(cls) then
                    if PCL151117_CACHE ~= nil and PCL151117_CACHE.classes ~= nil then
                        PCL151117_CACHE.classes[row_cache_key] = cls
                    end
                    return cls,
                        "original_live_actor",
                        nil
                end
            end
        else
            log("PREFAB15_1_SOURCE_MAP_WARNING " ..
                tostring(map_err))
        end
    end

    -- 5. Any currently-live actor using this same SwordPart row can identify
    -- the class, but never run this fallback during the direct empty-Forge
    -- staging pass. UE4SS crashed in this scan on the first legacy free-child
    -- hole (2,403-part test, between progress 30 and 40).
    if graph_fallback_allowed then
        local live =
            collect_live_sword_part_actors_10()

        for _, actor in ipairs(live) do
            if is_valid(actor) and
               live_actor_row_10(actor) ==
               saved.sword_part then

                local cls = nil
                local ok = pcall(function()
                    cls = actor:GetClass()
                end)

                if ok and is_valid(cls) then
                    if PCL151117_CACHE ~= nil and PCL151117_CACHE.classes ~= nil then
                        PCL151117_CACHE.classes[row_cache_key] = cls
                        PCL151117_CACHE.stats.legacy_row_class_misses =
                            (PCL151117_CACHE.stats.legacy_row_class_misses or 0) + 1
                    end
                    return cls,
                        "matching_live_actor",
                        nil
                end
            end
        end
    end

    -- 6. Diagnostic only for legacy prefabs: inspect RenderAsset so the next
    -- portable fallback can classify rows even when no source actor exists.
    local render_desc = "None"
    local render_class = "None"

    pcall(function()
        local render_asset =
            part_resolved.row.RenderAsset

        if is_valid(render_asset) then
            render_desc =
                safe_full_name(render_asset)

            local rc =
                render_asset:GetClass()

            if is_valid(rc) then
                render_class =
                    safe_full_name(rc)
            end
        else
            render_desc =
                tostring(render_asset)
        end
    end)

    return nil,
        nil,
        "no actor class source; Blueprint=nil RenderAsset=" ..
        tostring(render_desc) ..
        " RenderAssetClass=" ..
        tostring(render_class)
end



local function object_path_from_full_name_155(full_name)
    if full_name == nil then
        return nil
    end

    local s = tostring(full_name)

    if s == "" or s == "None" then
        return nil
    end

    return s:match("^%S+%s+(.+)$") or s
end

local function load_saved_render_asset_155(saved)
    local full = saved and saved.actor_render_asset or nil
    local path = object_path_from_full_name_155(full)

    if path == nil then
        return nil, "prefab has no actor_render_asset; re-export with Phase 15.5"
    end

    local cache = PCL151117_CACHE
    if cache ~= nil and cache.assets ~= nil then
        local cached = cache.assets[path]
        if is_valid(cached) then
            cache.stats.asset_hits = (cache.stats.asset_hits or 0) + 1
            return cached, nil
        end
    end

    -- A large fraction of render assets are already resident after the DataTable
    -- lookup/catalogue initialization.  Avoid an unnecessary synchronous
    -- LoadAsset when StaticFindObject can return the live asset immediately.
    local asset = nil
    pcall(function() asset = StaticFindObject(path) end)

    if not is_valid(asset) then
        local load_ok, load_err = pcall(function() LoadAsset(path) end)
        if not load_ok then
            return nil, "LoadAsset failed for " .. tostring(path) .. ": " .. tostring(load_err)
        end

        local find_ok, find_err = pcall(function() asset = StaticFindObject(path) end)
        if not find_ok or not is_valid(asset) then
            return nil,
                "StaticFindObject failed after LoadAsset for " ..
                tostring(path) .. ": " .. tostring(find_err)
        end
        if cache ~= nil then
            cache.stats.assets_loaded = (cache.stats.assets_loaded or 0) + 1
        end
    else
        if cache ~= nil then
            cache.stats.assets_already_resident =
                (cache.stats.assets_already_resident or 0) + 1
        end
    end

    if cache ~= nil and cache.assets ~= nil then cache.assets[path] = asset end
    return asset, nil
end

local function initialize_render_asset_155(actor, saved)
    if not is_valid(actor) then
        return false, "actor invalid"
    end

    local asset, asset_err =
        load_saved_render_asset_155(saved)

    if not is_valid(asset) then
        return false, asset_err
    end

    local actor_class = "None"
    local asset_class = "None"

    pcall(function()
        actor_class =
            safe_full_name(actor:GetClass())
    end)

    pcall(function()
        asset_class =
            safe_full_name(asset:GetClass())
    end)

    log("PREFAB15_5_RENDER_ASSET_LOADED=" ..
        safe_full_name(asset))
    log("PREFAB15_5_RENDER_ASSET_CLASS=" ..
        tostring(asset_class))

    local root = nil

    pcall(function()
        root = actor.RootComponent
    end)

    if not is_valid(root) then
        return false, "actor RootComponent invalid"
    end

    if string.find(
        tostring(actor_class),
        "SwordPartStaticMeshActor",
        1,
        true
    ) then
        local set_result = nil
        local ok, err =
            pcall(function()
                set_result =
                    root:SetStaticMesh(asset)
            end)

        if not ok then
            return false,
                "RootComponent:SetStaticMesh failed: " ..
                tostring(err)
        end

        log("PREFAB15_5_SET_STATIC_MESH_RESULT=" ..
            tostring(set_result))

        local verify = nil

        pcall(function()
            verify = root.StaticMesh
        end)

        if not is_valid(verify) then
            return false,
                "SetStaticMesh returned but RootComponent.StaticMesh is invalid"
        end

        log("PREFAB15_5_STATIC_MESH_VERIFY=" ..
            safe_full_name(verify))

        return true, nil
    end

    -- For deformable actors, persist the source Mesh now. Procedural mesh
    -- generation is a separate initialization problem and will be tested
    -- after the static root proof succeeds.
    if string.find(
        tostring(actor_class),
        "SwordPartDeformableStaticMeshActor",
        1,
        true
    ) then
        local ok, err =
            pcall(function()
                actor.Mesh = asset
            end)

        if not ok then
            return false,
                "deformable Mesh write failed: " ..
                tostring(err)
        end

        log("PREFAB15_5_DEFORMABLE_SOURCE_MESH_WRITTEN=true")
        return true, nil
    end

    return false,
        "Phase15.5 render initializer unsupported actor class: " ..
        tostring(actor_class)
end

local pcl154_last_saved_row = nil

local function audit_direct_actor_154(actor, label)
    if not is_valid(actor) then
        log("PREFAB15_5_AUDIT " ..
            tostring(label) ..
            " actor_invalid=true")
        return
    end

    local cls = "None"
    local row = "None"
    local material = "None"
    local material_row = "None"
    local material_table = "None"
    local pending = "?"
    local scale = "?"
    local rotation = "?"
    local sink = "?"
    local polish = "?"
    local inventory = "None"
    local root_component = "None"
    local static_mesh_component = "None"
    local static_mesh = "None"
    local proc_component = "None"
    local deform_mesh = "None"

    pcall(function()
        local c = actor:GetClass()
        if is_valid(c) then
            cls = safe_full_name(c)
        end
    end)

    pcall(function()
        row =
            safe_name(
                actor.SwordPartDataHandle.RowName
            )
    end)

    pcall(function()
        material =
            safe_name(
                actor.SwordMaterialName
            )
    end)

    pcall(function()
        material_row =
            safe_name(
                actor.SwordMaterialDataHandle.RowName
            )

        if is_valid(
            actor.SwordMaterialDataHandle.DataTable
        ) then
            material_table =
                safe_full_name(
                    actor.SwordMaterialDataHandle.DataTable
                )
        end
    end)

    pcall(function()
        pending = tostring(actor.bPending)
        scale = tostring(actor.Scale)
        rotation = tostring(actor.Rotation)
        sink = tostring(actor.Sink)
        polish = tostring(actor.Polish)
    end)

    pcall(function()
        if is_valid(actor.InventorySwordPart) then
            inventory =
                safe_full_name(
                    actor.InventorySwordPart
                )
        end
    end)

    pcall(function()
        if is_valid(actor.RootComponent) then
            root_component =
                safe_full_name(
                    actor.RootComponent
                )
        end
    end)

    pcall(function()
        local root = actor.RootComponent

        if is_valid(root) then
            local root_class = root:GetClass()

            if is_valid(root_class) and
               string.find(
                   safe_full_name(root_class),
                   "StaticMeshComponent",
                   1,
                   true
               ) then

                static_mesh_component =
                    safe_full_name(root)

                if is_valid(root.StaticMesh) then
                    static_mesh =
                        safe_full_name(root.StaticMesh)
                else
                    static_mesh =
                        tostring(root.StaticMesh)
                end
            end
        end
    end)

    pcall(function()
        if is_valid(actor.ProceduralMeshComponent) then
            proc_component =
                safe_full_name(
                    actor.ProceduralMeshComponent
                )
        end

        if is_valid(actor.Mesh) then
            deform_mesh =
                safe_full_name(actor.Mesh)
        else
            deform_mesh =
                tostring(actor.Mesh)
        end
    end)

    log("PREFAB15_5_AUDIT label=" ..
        tostring(label) ..
        " actor=" .. safe_full_name(actor))

    log("PREFAB15_5_AUDIT class=" ..
        tostring(cls) ..
        " row=" .. tostring(row) ..
        " material=" .. tostring(material))

    log("PREFAB15_5_AUDIT material_row=" ..
        tostring(material_row) ..
        " material_table=" ..
        tostring(material_table))

    log("PREFAB15_5_AUDIT pending=" ..
        tostring(pending) ..
        " scale=" .. tostring(scale) ..
        " rotation=" .. tostring(rotation) ..
        " sink=" .. tostring(sink) ..
        " polish=" .. tostring(polish))

    log("PREFAB15_5_AUDIT inventory=" ..
        tostring(inventory) ..
        " root_component=" ..
        tostring(root_component))

    log("PREFAB15_5_AUDIT static_mesh_component=" ..
        tostring(static_mesh_component) ..
        " static_mesh=" ..
        tostring(static_mesh))

    log("PREFAB15_5_AUDIT proc_component=" ..
        tostring(proc_component) ..
        " deform_mesh=" ..
        tostring(deform_mesh))
end

local function handoff_direct_actor_154()
    log("============================================================")
    log("PREFAB15_4_HANDOFF_BEGIN")

    local actor =
        actor_by_full_name_15(
            pcl15_last_actor_name
        )

    if not is_valid(actor) then
        log("PREFAB15_4_HANDOFF_ERROR direct actor missing")
        return
    end

    audit_direct_actor_154(
        actor,
        "before_manual_handoff"
    )

    local handling =
        find_handling_component_9()

    if not is_valid(handling) then
        log("PREFAB15_4_HANDOFF_ERROR handling unavailable")
        return
    end

    -- Remove hidden-state as a variable. If the handoff still crashes, the
    -- issue is preview/handling initialization rather than visibility.
    local reveal_ok, reveal_err =
        pcall(function()
            actor:SetActorHiddenInGame(false)
        end)

    log("PREFAB15_4_HANDOFF_REVEAL ok=" ..
        tostring(reveal_ok) ..
        " error=" .. tostring(reveal_err))

    local assign_ok, assign_err =
        pcall(function()
            handling.PreviewSwordPartActor =
                actor
        end)

    log("PREFAB15_4_HANDOFF_WRITE_RETURNED=" ..
        tostring(assign_ok) ..
        " error=" .. tostring(assign_err))

    if not assign_ok then
        return
    end

    log("PREFAB15_4_HANDOFF_POINTER_ASSIGNED=true")
    log("If the game now fatals, the crash boundary is the handling/preview tick.")
    log("============================================================")
end

local function direct_spawn_root_15()
    log("============================================================")
    log("PREFAB15_DIRECT_ROOT_BEGIN")
    log("PREFAB15_CATALOGUE_CLICKS=0")
    log("PREFAB15_ENTER_FORGE_MODE_CALLS=0")
    log("PREFAB15_SET_MOUSE_LOCATION_CALLS=0")

    local handling =
        find_handling_component_9()

    if not is_valid(handling) then
        log("PREFAB15_ERROR handling component unavailable")
        return
    end

    local existing_preview = nil

    pcall(function()
        existing_preview =
            handling.PreviewSwordPartActor
    end)

    if is_valid(existing_preview) then
        log("PREFAB15_ERROR another preview is already active; press X first")
        return
    end

    local path =
        OUTPUT_DIR .. PCL_IMPORT_FILENAME

    local prefab, parse_err =
        parse_pcl_file(path)

    if prefab == nil then
        log("PREFAB15_ERROR " ..
            tostring(parse_err))
        return
    end

    local saved =
        prefab.parts[0]

    if saved == nil then
        log("PREFAB15_ERROR prefab local 0 missing")
        return
    end

    local forge, piece, design, state_err =
        state_no_serialize_11()

    if state_err then
        log("PREFAB15_ERROR " ..
            tostring(state_err))
        return
    end

    -- Recover exact legacy material handle when the source tree is still
    -- present. New exports already contain these fields.
    recover_legacy_material_handle_145(
        saved,
        design
    )

    local part_resolved,
          material_resolved,
          resolve_err =
        resolve_identity_rows_fresh_11(
            saved.sword_part,
            saved.material,
            saved.material_data_row,
            saved.material_data_table
        )

    if resolve_err then
        log("PREFAB15_ERROR preflight " ..
            tostring(resolve_err))
        return
    end

    local actor_class,
          actor_class_source,
          actor_class_err =
        resolve_actor_class_151(
            saved,
            design,
            part_resolved
        )

    if not is_valid(actor_class) then
        log("PREFAB15_ERROR actor class resolution failed: " ..
            tostring(actor_class_err))
        return
    end

    log("PREFAB15_ACTOR_CLASS_SOURCE=" ..
        tostring(actor_class_source))

    log("PREFAB15_PART=" ..
        tostring(saved.sword_part))

    log("PREFAB15_MATERIAL=" ..
        tostring(saved.material))

    log("PREFAB15_RESOLVED_ACTOR_CLASS=" ..
        safe_full_name(actor_class))

    -- Phase 15.3: direct spawning is completely independent of an
    -- existing sword part. Spawn hidden at identity and let the normal
    -- preview system take ownership/position it afterwards.
    local transform =
        neutral_spawn_transform_153()

    local world_context,
          world_context_source =
        world_context_153()

    if not is_valid(world_context) then
        log("PREFAB15_ERROR no Forge world context available")
        return
    end

    log("PREFAB15_SPAWN_TRANSFORM_SOURCE=identity")
    log("PREFAB15_WORLD_CONTEXT_SOURCE=" ..
        tostring(world_context_source))
    log("PREFAB15_EXISTING_SWORD_PART_REQUIRED=false")

    local gameplay =
        gameplay_statics_15()

    if not is_valid(gameplay) then
        log("PREFAB15_ERROR GameplayStatics unavailable")
        return
    end

    local start_clock =
        os.clock()

    local deferred = nil
    local ok = false
    local class_err = nil

    log("PREFAB15_BEGIN_DEFERRED_CALL")

    ok, class_err =
        pcall(function()
            deferred =
                gameplay:BeginDeferredActorSpawnFromClass(
                    world_context,
                    actor_class,
                    transform,
                    1,      -- AlwaysSpawn
                    nil,    -- Owner
                    2       -- SelectDefaultAtRuntime
                )
        end)

    if not ok or not is_valid(deferred) then
        log("PREFAB15_ERROR BeginDeferredActorSpawnFromClass failed: " ..
            tostring(class_err))
        return
    end

    log("PREFAB15_DEFERRED_ACTOR=" ..
        safe_full_name(deferred))

    -- Try to keep the proof visually invisible until the actor is handed to
    -- the preview system.
    pcall(function()
        deferred:SetActorHiddenInGame(true)
    end)

    local setup_ok, setup_err =
        setup_deferred_actor_identity_15(
            deferred,
            saved,
            part_resolved,
            material_resolved
        )

    if not setup_ok then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        log("PREFAB15_ERROR setup before FinishSpawningActor: " ..
            tostring(setup_err))
        return
    end

    log("PREFAB15_PRE_FINISH_STATE_WRITTEN=true")

    local render_ok, render_err =
        initialize_render_asset_155(
            deferred,
            saved
        )

    if not render_ok then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        pcl15_last_actor_name = nil

        log("PREFAB15_5_RENDER_INIT_ERROR " ..
            tostring(render_err))
        log("PREFAB15_5_REEXPORT_REQUIRED=" ..
            tostring(
                saved.actor_render_asset == nil or
                saved.actor_render_asset == "" or
                saved.actor_render_asset == "None"
            ))
        return
    end

    log("PREFAB15_5_RENDER_INIT_OK=true")

    local finished = nil

    log("PREFAB15_FINISH_SPAWN_CALL")

    ok, class_err =
        pcall(function()
            finished =
                gameplay:FinishSpawningActor(
                    deferred,
                    transform,
                    2
                )
        end)

    if not ok or not is_valid(finished) then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        log("PREFAB15_ERROR FinishSpawningActor failed: " ..
            tostring(class_err))
        return
    end

    local elapsed_ms =
        (os.clock() - start_clock) *
        1000.0

    pcl15_last_actor_name =
        safe_full_name(finished)

    log(string.format(
        "PREFAB15_DIRECT_SPAWN_OK elapsed_ms=%.3f actor=%s",
        elapsed_ms,
        pcl15_last_actor_name
    ))

    local live_row = "None"
    local live_material = "None"
    local live_scale = 0
    local live_rotation = 0
    local live_sink = 0
    local live_polish = 0

    pcall(function()
        live_row =
            safe_name(
                finished.SwordPartDataHandle.RowName
            )

        live_material =
            safe_name(
                finished.SwordMaterialName
            )

        live_scale =
            finished.Scale

        live_rotation =
            finished.Rotation

        live_sink =
            finished.Sink

        live_polish =
            finished.Polish
    end)

    log("PREFAB15_POST_FINISH row=" ..
        tostring(live_row) ..
        " material=" ..
        tostring(live_material) ..
        " scale=" ..
        tostring(live_scale) ..
        " rotation=" ..
        tostring(live_rotation) ..
        " sink=" ..
        tostring(live_sink) ..
        " polish=" ..
        tostring(live_polish))

    -- Phase 15.4 intentionally STOPS HERE.
    -- Do not assign this actor to PreviewSwordPartActor automatically.
    -- The previous test proved the fatal occurs after that boundary.

    pcall(function()
        finished:SetActorHiddenInGame(true)
        finished:SetActorEnableCollision(false)
    end)

    pcl154_last_saved_row =
        tostring(saved.sword_part)

    audit_direct_actor_154(
        finished,
        "immediate_after_finish"
    )

    local spawned_name =
        tostring(pcl15_last_actor_name)

    schedule_game_11(500, function()
        local actor =
            actor_by_full_name_15(
                spawned_name
            )

        if is_valid(actor) then
            log("PREFAB15_5_SURVIVED_500MS=true actor=" ..
                safe_full_name(actor))

            audit_direct_actor_154(
                actor,
                "after_500ms_no_handoff"
            )

            log("PREFAB15_5_DIRECT_ACTOR_STABLE_WITH_RENDER=true")
            log("Press F9 ONLY when ready to test the PreviewSwordPartActor boundary.")
        else
            log("PREFAB15_5_SURVIVED_500MS=false")
            log("PREFAB15_4_DIRECT_ACTOR_DIED_BEFORE_HANDOFF=true")
        end

        log("============================================================")
    end)

end

local function cleanup_direct_spawn_15()
    log("============================================================")
    log("PREFAB15_CLEANUP_BEGIN")

    local handling =
        find_handling_component_9()

    if is_valid(handling) then
        pcall(function()
            handling.PreviewSwordPartActor = nil
            handling.BestSwordPartSlotParent = nil
        end)
    end

    local actor =
        actor_by_full_name_15(
            pcl15_last_actor_name
        )

    if is_valid(actor) then
        local ok, err =
            pcall(function()
                actor:K2_DestroyActor()
            end)

        log("PREFAB15_CLEANUP_DESTROY ok=" ..
            tostring(ok) ..
            " error=" .. tostring(err))
    else
        log("PREFAB15_CLEANUP_ACTOR=None")
    end

    pcl15_last_actor_name = nil

    log("PREFAB15_CLEANUP_OK")
    log("============================================================")
end

RegisterKeyBind(Key.F7, function()
    run_game_thread(
        direct_spawn_root_15
    )
end)

RegisterKeyBind(Key.F8, function()
    run_game_thread(
        cleanup_direct_spawn_15
    )
end)

RegisterKeyBind(Key.F9, function()
    run_game_thread(
        handoff_direct_actor_154
    )
end)

log("Phase 15.5 DIRECT SPAWN + SAVED RENDER ASSET proof loaded.")
log("F7 = direct-spawn saved local-0 + initialize saved render asset; no Forge handoff.")
log("F8 = cleanup direct-spawn test actor.")
log("F9 = manually hand render-initialized direct actor to PreviewSwordPartActor (diagnostic).")


-- ============================================================
-- Phase 15.6: DIRECT DEFORMABLE PART PROOF
-- ============================================================
--
-- F10 = directly spawn the first saved deformable part in prefab_root_1.pcl.
--       No catalogue click, no Forge rebuild, no preview handoff.
--
-- F11 = reveal + hand the surviving deformable proof actor to
--       PreviewSwordPartActor.
--
-- F12 = cleanup deformable proof actor.
--
-- This isolates whether SwordPartDeformableStaticMeshActor can be initialized
-- portably from:
--   actor_class
--   actor_render_asset
--   SwordPartData/material/state
--
-- If this succeeds, the next phase can direct-spawn the entire 50-part tree.
--

local pcl156_actor_name = nil
local pcl156_saved_local = nil

local function class_name_156(obj)
    if not is_valid(obj) then
        return "None"
    end

    local cls = nil
    pcall(function()
        cls = obj:GetClass()
    end)

    if is_valid(cls) then
        return safe_full_name(cls)
    end

    return "None"
end

local function proc_section_count_156(proc)
    if not is_valid(proc) then
        return -1
    end

    local count = -1

    pcall(function()
        if proc.ProcMeshSections ~= nil then
            count = #proc.ProcMeshSections
        end
    end)

    return count
end

local function audit_deformable_156(actor, label)
    if not is_valid(actor) then
        log("PREFAB15_6_AUDIT label=" ..
            tostring(label) ..
            " actor_invalid=true")
        return
    end

    local actor_class = class_name_156(actor)
    local row = "None"
    local material = "None"
    local mesh = "None"
    local root = "None"
    local root_class = "None"
    local proc = "None"
    local proc_sections = -1
    local hidden = "?"
    local collision = "?"

    pcall(function()
        row =
            safe_name(
                actor.SwordPartDataHandle.RowName
            )
    end)

    pcall(function()
        material =
            safe_name(
                actor.SwordMaterialName
            )
    end)

    pcall(function()
        if is_valid(actor.Mesh) then
            mesh = safe_full_name(actor.Mesh)
        else
            mesh = tostring(actor.Mesh)
        end
    end)

    pcall(function()
        if is_valid(actor.RootComponent) then
            root =
                safe_full_name(
                    actor.RootComponent
                )

            root_class =
                class_name_156(
                    actor.RootComponent
                )
        end
    end)

    pcall(function()
        if is_valid(actor.ProceduralMeshComponent) then
            proc =
                safe_full_name(
                    actor.ProceduralMeshComponent
                )

            proc_sections =
                proc_section_count_156(
                    actor.ProceduralMeshComponent
                )
        end
    end)

    pcall(function()
        hidden = tostring(actor.bHidden)
    end)

    pcall(function()
        collision =
            tostring(
                actor:GetActorEnableCollision()
            )
    end)

    log("PREFAB15_6_AUDIT label=" ..
        tostring(label) ..
        " actor=" ..
        safe_full_name(actor))

    log("PREFAB15_6_AUDIT class=" ..
        tostring(actor_class) ..
        " row=" .. tostring(row) ..
        " material=" .. tostring(material))

    log("PREFAB15_6_AUDIT mesh=" ..
        tostring(mesh))

    log("PREFAB15_6_AUDIT root=" ..
        tostring(root) ..
        " root_class=" ..
        tostring(root_class))

    log("PREFAB15_6_AUDIT proc=" ..
        tostring(proc) ..
        " proc_sections=" ..
        tostring(proc_sections))

    log("PREFAB15_6_AUDIT hidden=" ..
        tostring(hidden) ..
        " collision=" ..
        tostring(collision))
end

local function find_first_deformable_saved_156(prefab)
    if prefab == nil or prefab.parts == nil then
        return nil, nil
    end

    local max_index = -1

    for idx, _ in pairs(prefab.parts) do
        if type(idx) == "number" and idx > max_index then
            max_index = idx
        end
    end

    for local_index = 0, max_index do
        local saved =
            prefab.parts[local_index]

        if saved ~= nil then
            local cls =
                tostring(saved.actor_class or "")

            if cls:find(
                "SwordPartDeformableStaticMeshActor",
                1,
                true
            ) ~= nil then
                return local_index, saved
            end
        end
    end

    return nil, nil
end

local function setup_deformable_render_156(
    actor,
    saved
)
    if not is_valid(actor) then
        return false, "actor invalid"
    end

    if saved.actor_render_asset == nil or
       saved.actor_render_asset == "" or
       saved.actor_render_asset == "None" then
        return false,
            "saved actor_render_asset missing"
    end

    local render_path =
        tostring(saved.actor_render_asset):match(
            "^%S+%s+(.+)$"
        ) or
        tostring(saved.actor_render_asset)

    local mesh = nil

    local ok, err =
        pcall(function()
            mesh =
                LoadAsset(render_path)
        end)

    if not ok or not is_valid(mesh) then
        return false,
            "LoadAsset failed for deformable mesh: " ..
            tostring(render_path) ..
            " error=" .. tostring(err)
    end

    log("PREFAB15_6_RENDER_ASSET_LOADED=" ..
        safe_full_name(mesh))

    log("PREFAB15_6_RENDER_ASSET_CLASS=" ..
        class_name_156(mesh))

    -- SwordPartDeformableStaticMeshActor exposes Mesh directly.
    local write_ok, write_err =
        pcall(function()
            actor.Mesh = mesh
        end)

    log("PREFAB15_6_MESH_WRITE_RETURNED=" ..
        tostring(write_ok) ..
        " error=" .. tostring(write_err))

    if not write_ok then
        return false,
            "actor.Mesh write failed: " ..
            tostring(write_err)
    end

    local verify = "None"

    pcall(function()
        if is_valid(actor.Mesh) then
            verify =
                safe_full_name(actor.Mesh)
        else
            verify =
                tostring(actor.Mesh)
        end
    end)

    log("PREFAB15_6_MESH_VERIFY=" ..
        tostring(verify))

    if verify == "None" or
       verify == "nil" then
        return false,
            "deformable Mesh did not persist"
    end

    return true, nil
end

local function direct_spawn_deformable_156()
    log("============================================================")
    log("PREFAB15_6_DEFORMABLE_BEGIN")
    log("PREFAB15_6_CATALOGUE_CLICKS=0")
    log("PREFAB15_6_ENTER_FORGE_MODE_CALLS=0")
    log("PREFAB15_6_EXISTING_SWORD_PART_REQUIRED=false")

    if pcl156_actor_name ~= nil then
        local existing =
            actor_by_full_name_15(
                pcl156_actor_name
            )

        if is_valid(existing) then
            log("PREFAB15_6_ERROR previous deformable proof still exists; press CTRL+ALT+Q")
            return
        end

        pcl156_actor_name = nil
    end

    local path =
        OUTPUT_DIR .. PCL_IMPORT_FILENAME

    local prefab, parse_err =
        parse_pcl_file(path)

    if prefab == nil then
        log("PREFAB15_6_ERROR " ..
            tostring(parse_err))
        return
    end

    local local_index, saved =
        find_first_deformable_saved_156(
            prefab
        )

    if saved == nil then
        log("PREFAB15_6_ERROR no saved deformable actor_class found")
        return
    end

    pcl156_saved_local = local_index

    log("PREFAB15_6_LOCAL=" ..
        tostring(local_index) ..
        " part=" ..
        tostring(saved.sword_part))

    log("PREFAB15_6_SAVED_CLASS=" ..
        tostring(saved.actor_class))

    log("PREFAB15_6_SAVED_RENDER_ASSET=" ..
        tostring(saved.actor_render_asset))

    local forge, piece, design, state_err =
        state_no_serialize_11()

    if state_err then
        log("PREFAB15_6_ERROR state " ..
            tostring(state_err))
        return
    end

    local part_resolved,
          material_resolved,
          resolve_err =
        resolve_identity_rows_fresh_11(
            saved.sword_part,
            saved.material,
            saved.material_data_row,
            saved.material_data_table
        )

    if resolve_err then
        log("PREFAB15_6_ERROR preflight " ..
            tostring(resolve_err))
        return
    end

    local actor_class,
          actor_class_source,
          actor_class_err =
        resolve_actor_class_151(
            saved,
            design,
            part_resolved
        )

    if not is_valid(actor_class) then
        log("PREFAB15_6_ERROR class " ..
            tostring(actor_class_err))
        return
    end

    log("PREFAB15_6_ACTOR_CLASS_SOURCE=" ..
        tostring(actor_class_source))

    log("PREFAB15_6_RESOLVED_CLASS=" ..
        safe_full_name(actor_class))

    local gameplay =
        gameplay_statics_15()

    if not is_valid(gameplay) then
        log("PREFAB15_6_ERROR GameplayStatics unavailable")
        return
    end

    local transform =
        neutral_spawn_transform_153()

    local world_context = forge

    local deferred = nil
    local ok, spawn_err =
        pcall(function()
            deferred =
                gameplay:BeginDeferredActorSpawnFromClass(
                    world_context,
                    actor_class,
                    transform,
                    1,
                    nil,
                    2
                )
        end)

    if not ok or not is_valid(deferred) then
        log("PREFAB15_6_ERROR BeginDeferredActorSpawnFromClass " ..
            tostring(spawn_err))
        return
    end

    log("PREFAB15_6_DEFERRED_ACTOR=" ..
        safe_full_name(deferred))

    pcall(function()
        deferred:SetActorHiddenInGame(true)
        deferred:SetActorEnableCollision(false)
    end)

    local setup_ok, setup_err =
        setup_deferred_actor_identity_15(
            deferred,
            saved,
            part_resolved,
            material_resolved
        )

    if not setup_ok then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        log("PREFAB15_6_ERROR identity " ..
            tostring(setup_err))
        return
    end

    local render_ok, render_err =
        setup_deformable_render_156(
            deferred,
            saved
        )

    if not render_ok then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        log("PREFAB15_6_ERROR render " ..
            tostring(render_err))
        return
    end

    audit_deformable_156(
        deferred,
        "before_finish"
    )

    local start_clock = os.clock()
    local finished = nil

    ok, spawn_err =
        pcall(function()
            finished =
                gameplay:FinishSpawningActor(
                    deferred,
                    transform,
                    2
                )
        end)

    if not ok or not is_valid(finished) then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        log("PREFAB15_6_ERROR FinishSpawningActor " ..
            tostring(spawn_err))
        return
    end

    local elapsed_ms =
        (os.clock() - start_clock) *
        1000.0

    pcl156_actor_name =
        safe_full_name(finished)

    log(string.format(
        "PREFAB15_6_DIRECT_SPAWN_OK finish_ms=%.3f actor=%s",
        elapsed_ms,
        pcl156_actor_name
    ))

    audit_deformable_156(
        finished,
        "immediate_after_finish"
    )

    local name_copy =
        tostring(pcl156_actor_name)

    schedule_game_11(500, function()
        local actor =
            actor_by_full_name_15(
                name_copy
            )

        if not is_valid(actor) then
            log("PREFAB15_6_SURVIVED_500MS=false")
            log("============================================================")
            return
        end

        log("PREFAB15_6_SURVIVED_500MS=true")

        audit_deformable_156(
            actor,
            "after_500ms"
        )

        local sections = -1

        pcall(function()
            if is_valid(
                actor.ProceduralMeshComponent
            ) then
                sections =
                    proc_section_count_156(
                        actor.ProceduralMeshComponent
                    )
            end
        end)

        if sections > 0 then
            log("PREFAB15_6_PROCEDURAL_MESH_BUILT=true sections=" ..
                tostring(sections))

            log("PREFAB15_6_DIRECT_DEFORMABLE_READY_FOR_HANDOFF=true")
            log("Press CTRL+ALT+T to test handing this deformable actor to Forge.")
        else
            log("PREFAB15_6_PROCEDURAL_MESH_BUILT=false sections=" ..
                tostring(sections))

            log("PREFAB15_6_NEEDS_DEFORMATION_BUILD_STEP=true")
            log("Do NOT press CTRL+ALT+T yet.")
        end

        log("============================================================")
    end)
end

local function handoff_deformable_156()
    log("============================================================")
    log("PREFAB15_6_HANDOFF_BEGIN")

    local actor =
        actor_by_full_name_15(
            pcl156_actor_name
        )

    if not is_valid(actor) then
        log("PREFAB15_6_HANDOFF_ERROR actor missing")
        return
    end

    audit_deformable_156(
        actor,
        "before_handoff"
    )

    local handling =
        find_handling_component_9()

    if not is_valid(handling) then
        log("PREFAB15_6_HANDOFF_ERROR handling unavailable")
        return
    end

    pcall(function()
        actor:SetActorHiddenInGame(false)
    end)

    local ok, err =
        pcall(function()
            handling.PreviewSwordPartActor =
                actor
        end)

    log("PREFAB15_6_HANDOFF_WRITE_RETURNED=" ..
        tostring(ok) ..
        " error=" .. tostring(err))

    if ok then
        log("PREFAB15_6_HANDOFF_POINTER_ASSIGNED=true")
    end

    log("============================================================")
end

local function cleanup_deformable_156()
    log("============================================================")
    log("PREFAB15_6_CLEANUP_BEGIN")

    local handling =
        find_handling_component_9()

    if is_valid(handling) then
        pcall(function()
            if is_valid(
                handling.PreviewSwordPartActor
            ) and
               safe_full_name(
                   handling.PreviewSwordPartActor
               ) == pcl156_actor_name then
                handling.PreviewSwordPartActor = nil
            end
        end)
    end

    local actor =
        actor_by_full_name_15(
            pcl156_actor_name
        )

    if is_valid(actor) then
        local ok, err =
            pcall(function()
                actor:K2_DestroyActor()
            end)

        log("PREFAB15_6_CLEANUP_DESTROY ok=" ..
            tostring(ok) ..
            " error=" .. tostring(err))
    else
        log("PREFAB15_6_CLEANUP_ACTOR=None")
    end

    pcl156_actor_name = nil
    pcl156_saved_local = nil

    log("PREFAB15_6_CLEANUP_OK")
    log("============================================================")
end

-- Phase 15.8: old 15.6.1 D/T/Q bindings intentionally disabled.

log("Phase 15.6.1 DIRECT DEFORMABLE proof loaded.")
log("CTRL+ALT+D = direct-spawn first saved deformable part, hidden, no handoff.")
log("CTRL+ALT+T = reveal/hand surviving deformable actor to Forge.")
log("CTRL+ALT+Q = cleanup deformable proof actor.")
log("F10/F11/F12 are intentionally NOT registered.")


-- ============================================================
-- Phase 15.7: NATIVE DEFORMABLE PREVIEW STATE PROBE
-- ============================================================
--
-- CTRL+ALT+B
--   Uses Bladesong's NORMAL catalogue button path to create the first saved
--   deformable prefab part as a native preview, then dumps the resulting actor
--   at ~50 ms and ~250 ms.
--
-- CTRL+ALT+Y
--   Dumps whatever native preview actor is currently held.
--
-- Cleanup is deliberately left to Bladesong's normal X/cancel control.
--
-- NO F10/F11/F12 bindings are used.
--

local function fmt_vec3_157(v)
    if v == nil then
        return "nil"
    end

    local x, y, z = "?", "?", "?"

    pcall(function() x = tostring(v.X) end)
    pcall(function() y = tostring(v.Y) end)
    pcall(function() z = tostring(v.Z) end)

    return "(" .. x .. "," .. y .. "," .. z .. ")"
end

local function fmt_rotator_157(v)
    if v == nil then
        return "nil"
    end

    local p, y, r = "?", "?", "?"

    pcall(function() p = tostring(v.Pitch) end)
    pcall(function() y = tostring(v.Yaw) end)
    pcall(function() r = tostring(v.Roll) end)

    return "(" .. p .. "," .. y .. "," .. r .. ")"
end

local function native_proc_sections_157(proc)
    if not is_valid(proc) then
        return -1, -1
    end

    local reflected = -1
    local raw = -1

    pcall(function()
        reflected =
            proc:GetNumSections()
    end)

    pcall(function()
        if proc.ProcMeshSections ~= nil then
            raw = #proc.ProcMeshSections
        end
    end)

    return reflected, raw
end

local function dump_component_materials_157(component, label)
    if not is_valid(component) then
        log(label .. "_MATERIAL_COMPONENT=None")
        return
    end

    local count = -1

    pcall(function()
        count =
            component:GetNumMaterials()
    end)

    log(label .. "_MATERIAL_COUNT=" ..
        tostring(count))

    if type(count) == "number" and count > 0 then
        local max_i = math.min(count - 1, 5)

        for i = 0, max_i do
            local mat = nil

            pcall(function()
                mat =
                    component:GetMaterial(i)
            end)

            log(label ..
                "_MATERIAL index=" ..
                tostring(i) ..
                " object=" ..
                (is_valid(mat) and
                 safe_full_name(mat) or
                 tostring(mat)))
        end
    end
end

local function dump_handling_state_157(label)
    local handling =
        find_handling_component_9()

    if not is_valid(handling) then
        log(label .. "_HANDLING=None")
        return nil
    end

    local preview = nil
    local has_preview = false
    local best_parent = nil
    local interacting = nil
    local preview_material_last = nil
    local material_to_assign = "None"

    pcall(function()
        preview =
            handling.PreviewSwordPartActor
    end)

    pcall(function()
        has_preview =
            handling:HasPreviewSwordPart()
            and true or false
    end)

    pcall(function()
        best_parent =
            handling.BestSwordPartSlotParent
    end)

    pcall(function()
        interacting =
            handling.InteractingSwordPartActor
    end)

    pcall(function()
        preview_material_last =
            handling.ActorPreviewMaterialSetLastFrame
    end)

    pcall(function()
        material_to_assign =
            safe_name(
                handling.SwordMaterialToAssign
            )
    end)

    log(label ..
        "_HANDLING=" ..
        safe_full_name(handling))

    log(label ..
        "_HAS_PREVIEW=" ..
        tostring(has_preview))

    log(label ..
        "_PREVIEW=" ..
        (is_valid(preview) and
         safe_full_name(preview) or
         "None"))

    log(label ..
        "_BEST_PARENT=" ..
        (is_valid(best_parent) and
         safe_full_name(best_parent) or
         "None"))

    log(label ..
        "_INTERACTING=" ..
        (is_valid(interacting) and
         safe_full_name(interacting) or
         "None"))

    log(label ..
        "_PREVIEW_MATERIAL_LAST=" ..
        (is_valid(preview_material_last) and
         safe_full_name(preview_material_last) or
         "None"))

    log(label ..
        "_MATERIAL_TO_ASSIGN=" ..
        tostring(material_to_assign))

    return preview
end

local function dump_native_deformable_actor_157(actor, label)
    log("------------------------------------------------------------")
    log("PREFAB15_7_DUMP_BEGIN label=" ..
        tostring(label))

    if not is_valid(actor) then
        log("PREFAB15_7_DUMP_ACTOR=None")
        log("PREFAB15_7_DUMP_END")
        return
    end

    local class_name = "None"
    local row = "None"
    local material = "None"
    local material_row = "None"
    local material_table = "None"
    local material_handle_name = "None"
    local material_handle_type = "?"
    local material_handle_uv = "?"
    local mesh = "None"
    local proc = nil
    local root = nil
    local inventory = nil
    local b_pending = "?"
    local scale = "?"
    local rotation = "?"
    local sink = "?"
    local polish = "?"
    local flipped = "?"
    local manual_flip = "?"
    local collision = "?"
    local hidden = "?"
    local rel_loc = nil
    local rel_rot = nil
    local rel_scale = nil

    pcall(function()
        local cls = actor:GetClass()
        if is_valid(cls) then
            class_name = safe_full_name(cls)
        end
    end)

    pcall(function()
        row =
            safe_name(
                actor.SwordPartDataHandle.RowName
            )
    end)

    pcall(function()
        material =
            safe_name(
                actor.SwordMaterialName
            )
    end)

    pcall(function()
        material_row =
            safe_name(
                actor.SwordMaterialDataHandle.RowName
            )

        if is_valid(
            actor.SwordMaterialDataHandle.DataTable
        ) then
            material_table =
                safe_full_name(
                    actor.SwordMaterialDataHandle.DataTable
                )
        end
    end)

    pcall(function()
        material_handle_name =
            safe_name(
                actor.SwordMaterialHandle.Name
            )

        material_handle_type =
            tostring(
                actor.SwordMaterialHandle.Type
            )

        material_handle_uv =
            tostring(
                actor.SwordMaterialHandle.UVType
            )
    end)

    pcall(function()
        if is_valid(actor.Mesh) then
            mesh =
                safe_full_name(actor.Mesh)
        else
            mesh =
                tostring(actor.Mesh)
        end
    end)

    pcall(function()
        proc =
            actor.ProceduralMeshComponent
    end)

    pcall(function()
        root =
            actor.RootComponent
    end)

    pcall(function()
        inventory =
            actor.InventorySwordPart
    end)

    pcall(function()
        b_pending = tostring(actor.bPending)
        scale = tostring(actor.Scale)
        rotation = tostring(actor.Rotation)
        sink = tostring(actor.Sink)
        polish = tostring(actor.Polish)
        flipped = tostring(actor.bIsInFlippedSlot)
        manual_flip = tostring(actor.bManualFlip)
    end)

    pcall(function()
        collision =
            tostring(
                actor:GetActorEnableCollision()
            )
    end)

    pcall(function()
        hidden =
            tostring(actor.bHidden)
    end)

    if is_valid(root) then
        pcall(function()
            rel_loc =
                root.RelativeLocation
        end)

        pcall(function()
            rel_rot =
                root.RelativeRotation
        end)

        pcall(function()
            rel_scale =
                root.RelativeScale3D
        end)
    end

    local section_count, raw_section_count =
        native_proc_sections_157(proc)

    log("PREFAB15_7_ACTOR=" ..
        safe_full_name(actor))

    log("PREFAB15_7_CLASS=" ..
        tostring(class_name))

    log("PREFAB15_7_IDENTITY row=" ..
        tostring(row) ..
        " material=" ..
        tostring(material))

    log("PREFAB15_7_MATERIAL_DATA row=" ..
        tostring(material_row) ..
        " table=" ..
        tostring(material_table))

    log("PREFAB15_7_MATERIAL_HANDLE name=" ..
        tostring(material_handle_name) ..
        " type=" ..
        tostring(material_handle_type) ..
        " uv=" ..
        tostring(material_handle_uv))

    log("PREFAB15_7_STATE pending=" ..
        tostring(b_pending) ..
        " scale=" ..
        tostring(scale) ..
        " rotation=" ..
        tostring(rotation) ..
        " sink=" ..
        tostring(sink) ..
        " polish=" ..
        tostring(polish) ..
        " flipped=" ..
        tostring(flipped) ..
        " manual_flip=" ..
        tostring(manual_flip))

    log("PREFAB15_7_MESH=" ..
        tostring(mesh))

    log("PREFAB15_7_ROOT=" ..
        (is_valid(root) and
         safe_full_name(root) or
         "None"))

    log("PREFAB15_7_PROC=" ..
        (is_valid(proc) and
         safe_full_name(proc) or
         "None"))

    log("PREFAB15_7_PROC_SECTIONS reflected=" ..
        tostring(section_count) ..
        " raw=" ..
        tostring(raw_section_count))

    log("PREFAB15_7_INVENTORY=" ..
        (is_valid(inventory) and
         safe_full_name(inventory) or
         "None"))

    log("PREFAB15_7_VIS hidden=" ..
        tostring(hidden) ..
        " collision=" ..
        tostring(collision))

    log("PREFAB15_7_ROOT_RELATIVE location=" ..
        fmt_vec3_157(rel_loc) ..
        " rotation=" ..
        fmt_rotator_157(rel_rot) ..
        " scale=" ..
        fmt_vec3_157(rel_scale))

    dump_component_materials_157(
        proc,
        "PREFAB15_7_PROC"
    )

    if pcl151160_presentation_audit ~= nil then
        pcl151160_presentation_audit(actor, 'native_catalogue_' .. tostring(label))
    end

    log("PREFAB15_7_DUMP_END")
    log("------------------------------------------------------------")
end

local function dump_current_native_preview_157(label)
    local preview =
        dump_handling_state_157(
            "PREFAB15_7_" .. tostring(label)
        )

    if not is_valid(preview) then
        log("PREFAB15_7_ERROR no native preview actor")
        return
    end

    dump_native_deformable_actor_157(
        preview,
        label
    )
end

local function native_deformable_preview_probe_157()
    log("============================================================")
    log("PREFAB15_7_NATIVE_PREVIEW_BEGIN")
    log("PREFAB15_7_USES_NORMAL_CATALOGUE_PATH=true")
    log("PREFAB15_7_CURSOR_TELEPORT=false")
    log("PREFAB15_7_DESIGN_MUTATION_REQUESTED=false")

    local handling =
        find_handling_component_9()

    if not is_valid(handling) then
        log("PREFAB15_7_ERROR handling unavailable")
        return
    end

    local has_preview = false

    pcall(function()
        has_preview =
            handling:HasPreviewSwordPart()
            and true or false
    end)

    if has_preview then
        log("PREFAB15_7_ERROR another preview is already active; press X first")
        return
    end

    local path =
        OUTPUT_DIR .. PCL_IMPORT_FILENAME

    local prefab, parse_err =
        parse_pcl_file(path)

    if prefab == nil then
        log("PREFAB15_7_ERROR " ..
            tostring(parse_err))
        return
    end

    local local_index, saved =
        find_first_deformable_saved_156(
            prefab
        )

    if saved == nil then
        log("PREFAB15_7_ERROR no saved deformable part")
        return
    end

    log("PREFAB15_7_TARGET local=" ..
        tostring(local_index) ..
        " part=" ..
        tostring(saved.sword_part) ..
        " saved_material=" ..
        tostring(saved.material))

    local button =
        find_button_for_row_9(
            saved.sword_part
        )

    if not is_valid(button) then
        log("PREFAB15_7_ERROR no live catalogue button for " ..
            tostring(saved.sword_part))
        return
    end

    log("PREFAB15_7_BUTTON=" ..
        safe_full_name(button))

    local click_ok, click_err =
        click_catalogue_row_11(
            saved.sword_part
        )

    if not click_ok then
        log("PREFAB15_7_ERROR catalogue click " ..
            tostring(click_err))
        return
    end

    log("PREFAB15_7_NATIVE_CLICK_RETURNED=true")

    schedule_game_11(50, function()
        log("PREFAB15_7_SAMPLE_MS=50")
        dump_current_native_preview_157(
            "NATIVE_50MS"
        )
    end)

    schedule_game_11(250, function()
        log("PREFAB15_7_SAMPLE_MS=250")
        dump_current_native_preview_157(
            "NATIVE_250MS"
        )

        log("PREFAB15_7_PROBE_COMPLETE=true")
        log("Use Bladesong's normal X key now to cancel the preview.")
        log("============================================================")
    end)
end

local function dump_active_preview_157()
    log("============================================================")
    log("PREFAB15_7_MANUAL_DUMP_BEGIN")

    dump_current_native_preview_157(
        "MANUAL"
    )

    log("============================================================")
end

RegisterKeyBind(Key.B, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(
        native_deformable_preview_probe_157
    )
end)

RegisterKeyBind(Key.Y, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(
        dump_active_preview_157
    )
end)

log("Phase 15.7.1 NATIVE DEFORMABLE PREVIEW STATE probe loaded.")
log("CTRL+ALT+B = create normal native deformable preview + dump at 50/250 ms (15.7.1 fixed).")
log("CTRL+ALT+Y = dump currently active preview without creating anything.")
log("Cancel native previews with Bladesong's normal X key.")
log("F10/F11/F12 remain unused.")


-- ============================================================
-- Phase 15.8: DIRECT DEFORMABLE PROCEDURAL-COPY PROOF
-- ============================================================
--
-- CTRL+ALT+G
--   Direct-spawns the first saved deformable prefab part.
--   Before FinishSpawningActor, builds its ProceduralMeshComponent by using
--   Unreal's reflected:
--
--     KismetProceduralMeshLibrary:
--       CopyProceduralMeshFromStaticMeshComponent
--
--   A temporary hidden SwordPartStaticMeshActor is used only as a source
--   StaticMeshComponent for the saved render asset.
--
--   No catalogue click.
--   No EnterForgeMode.
--   No cursor teleport.
--   No PreviewSwordPartActor handoff.
--
-- CTRL+ALT+K
--   Cleanup the surviving Phase 15.8 proof actor.
--
-- F10/F11/F12 remain unused.
--

local pcl158_actor_name = nil
local pcl158_helper_name = nil

local function proc_lib_158()
    local lib = nil

    pcall(function()
        lib =
            StaticFindObject(
                "/Script/ProceduralMeshComponent.Default__KismetProceduralMeshLibrary"
            )
    end)

    return lib
end

local function static_sword_part_class_158()
    local cls = nil

    pcall(function()
        cls =
            StaticFindObject(
                "/Script/Bladesong.SwordPartStaticMeshActor"
            )
    end)

    if is_valid(cls) then
        return cls
    end

    local cdo = nil

    pcall(function()
        cdo =
            StaticFindObject(
                "/Script/Bladesong.Default__SwordPartStaticMeshActor"
            )
    end)

    if is_valid(cdo) then
        pcall(function()
            cls = cdo:GetClass()
        end)
    end

    return cls
end

local function reflected_proc_sections_158(proc)
    if not is_valid(proc) then
        return -1, -1
    end

    local reflected = -1
    local raw = -1

    pcall(function()
        reflected =
            proc:GetNumSections()
    end)

    pcall(function()
        if proc.ProcMeshSections ~= nil then
            raw = #proc.ProcMeshSections
        end
    end)

    return reflected, raw
end

local function material_summary_158(component)
    if not is_valid(component) then
        return "component=None"
    end

    local count = -1
    pcall(function()
        count = component:GetNumMaterials()
    end)

    local parts = {
        "count=" .. tostring(count)
    }

    if type(count) == "number" and count > 0 then
        for i = 0, math.min(count - 1, 3) do
            local mat = nil
            pcall(function()
                mat = component:GetMaterial(i)
            end)

            table.insert(
                parts,
                "m" .. tostring(i) .. "=" ..
                (is_valid(mat) and
                 safe_full_name(mat) or
                 tostring(mat))
            )
        end
    end

    return table.concat(parts, " ")
end

local function audit_158(actor, label)
    if not is_valid(actor) then
        log("PREFAB15_8_AUDIT label=" ..
            tostring(label) ..
            " actor_invalid=true")
        return
    end

    local proc = nil
    local mesh = nil
    local row = "None"
    local material = "None"
    local pending = "?"
    local hidden = "?"
    local collision = "?"

    pcall(function()
        proc = actor.ProceduralMeshComponent
    end)

    pcall(function()
        mesh = actor.Mesh
    end)

    pcall(function()
        row =
            safe_name(
                actor.SwordPartDataHandle.RowName
            )
    end)

    pcall(function()
        material =
            safe_name(
                actor.SwordMaterialName
            )
    end)

    pcall(function()
        pending = tostring(actor.bPending)
    end)

    pcall(function()
        hidden = tostring(actor.bHidden)
    end)

    pcall(function()
        collision =
            tostring(
                actor:GetActorEnableCollision()
            )
    end)

    local reflected, raw =
        reflected_proc_sections_158(proc)

    log("PREFAB15_8_AUDIT label=" ..
        tostring(label) ..
        " actor=" ..
        safe_full_name(actor))

    log("PREFAB15_8_AUDIT row=" ..
        tostring(row) ..
        " material=" ..
        tostring(material) ..
        " pending=" ..
        tostring(pending))

    log("PREFAB15_8_AUDIT mesh=" ..
        (is_valid(mesh) and
         safe_full_name(mesh) or
         tostring(mesh)))

    log("PREFAB15_8_AUDIT proc=" ..
        (is_valid(proc) and
         safe_full_name(proc) or
         "None") ..
        " sections_reflected=" ..
        tostring(reflected) ..
        " sections_raw=" ..
        tostring(raw))

    log("PREFAB15_8_AUDIT proc_materials " ..
        material_summary_158(proc))

    log("PREFAB15_8_AUDIT hidden=" ..
        tostring(hidden) ..
        " collision=" ..
        tostring(collision))

    local tick_enabled = "?"
    pcall(function()
        tick_enabled =
            tostring(actor:IsActorTickEnabled())
    end)

    log("PREFAB15_8_1_AUDIT tick_enabled=" ..
        tostring(tick_enabled))
end

local function cleanup_158_internal()
    if pcl158_actor_name ~= nil then
        local actor =
            actor_by_full_name_15(
                pcl158_actor_name
            )

        if is_valid(actor) then
            pcall(function()
                actor:K2_DestroyActor()
            end)
        end
    end

    if pcl158_helper_name ~= nil then
        local helper =
            actor_by_full_name_15(
                pcl158_helper_name
            )

        if is_valid(helper) then
            pcall(function()
                helper:K2_DestroyActor()
            end)
        end
    end

    pcl158_actor_name = nil
    pcl158_helper_name = nil
end

local function direct_proc_copy_158()
    log("============================================================")
    log("PREFAB15_8_1_BEGIN")
    log("PREFAB15_8_CATALOGUE_CLICKS=0")
    log("PREFAB15_8_ENTER_FORGE_MODE_CALLS=0")
    log("PREFAB15_8_SET_MOUSE_LOCATION_CALLS=0")
    log("PREFAB15_8_PREVIEW_HANDOFF=false")

    cleanup_158_internal()

    local path =
        OUTPUT_DIR .. PCL_IMPORT_FILENAME

    local prefab, parse_err =
        parse_pcl_file(path)

    if prefab == nil then
        log("PREFAB15_8_ERROR parse " ..
            tostring(parse_err))
        return
    end

    local local_index, saved =
        find_first_deformable_saved_156(
            prefab
        )

    if saved == nil then
        log("PREFAB15_8_ERROR no deformable saved part")
        return
    end

    log("PREFAB15_8_TARGET local=" ..
        tostring(local_index) ..
        " part=" ..
        tostring(saved.sword_part))

    local forge, piece, design, state_err =
        state_no_serialize_11()

    if state_err then
        log("PREFAB15_8_ERROR state " ..
            tostring(state_err))
        return
    end

    local part_resolved,
          material_resolved,
          resolve_err =
        resolve_identity_rows_fresh_11(
            saved.sword_part,
            saved.material,
            saved.material_data_row,
            saved.material_data_table
        )

    if resolve_err then
        log("PREFAB15_8_ERROR identity preflight " ..
            tostring(resolve_err))
        return
    end

    local deform_class,
          deform_class_source,
          class_err =
        resolve_actor_class_151(
            saved,
            design,
            part_resolved
        )

    if not is_valid(deform_class) then
        log("PREFAB15_8_ERROR deform class " ..
            tostring(class_err))
        return
    end

    local static_class =
        static_sword_part_class_158()

    if not is_valid(static_class) then
        log("PREFAB15_8_ERROR static helper class unavailable")
        return
    end

    local proc_lib =
        proc_lib_158()

    if not is_valid(proc_lib) then
        log("PREFAB15_8_ERROR KismetProceduralMeshLibrary CDO unavailable")
        return
    end

    log("PREFAB15_8_PROC_LIB=" ..
        safe_full_name(proc_lib))

    local asset, asset_err =
        load_saved_render_asset_155(
            saved
        )

    if not is_valid(asset) then
        log("PREFAB15_8_ERROR render asset " ..
            tostring(asset_err))
        return
    end

    log("PREFAB15_8_RENDER_ASSET=" ..
        safe_full_name(asset))

    local gameplay =
        gameplay_statics_15()

    if not is_valid(gameplay) then
        log("PREFAB15_8_ERROR GameplayStatics unavailable")
        return
    end

    local transform =
        neutral_spawn_transform_153()

    -- --------------------------------------------------------
    -- 1. Spawn a hidden STATIC helper carrying the source mesh.
    -- --------------------------------------------------------
    local helper_deferred = nil
    local ok, err =
        pcall(function()
            helper_deferred =
                gameplay:BeginDeferredActorSpawnFromClass(
                    forge,
                    static_class,
                    transform,
                    1,
                    nil,
                    2
                )
        end)

    if not ok or not is_valid(helper_deferred) then
        log("PREFAB15_8_ERROR helper BeginDeferred " ..
            tostring(err))
        return
    end

    pcall(function()
        helper_deferred:SetActorHiddenInGame(true)
        helper_deferred:SetActorEnableCollision(false)
    end)

    local helper_root = nil
    pcall(function()
        helper_root = helper_deferred.RootComponent
    end)

    if not is_valid(helper_root) then
        pcall(function()
            helper_deferred:K2_DestroyActor()
        end)

        log("PREFAB15_8_ERROR helper RootComponent invalid")
        return
    end

    local set_mesh_result = nil

    ok, err =
        pcall(function()
            set_mesh_result =
                helper_root:SetStaticMesh(asset)
        end)

    if not ok then
        pcall(function()
            helper_deferred:K2_DestroyActor()
        end)

        log("PREFAB15_8_ERROR helper SetStaticMesh " ..
            tostring(err))
        return
    end

    log("PREFAB15_8_HELPER_SET_STATIC_MESH=" ..
        tostring(set_mesh_result))

    local helper = nil

    ok, err =
        pcall(function()
            helper =
                gameplay:FinishSpawningActor(
                    helper_deferred,
                    transform,
                    2
                )
        end)

    if not ok or not is_valid(helper) then
        pcall(function()
            helper_deferred:K2_DestroyActor()
        end)

        log("PREFAB15_8_ERROR helper FinishSpawning " ..
            tostring(err))
        return
    end

    pcl158_helper_name =
        safe_full_name(helper)

    pcall(function()
        helper_root = helper.RootComponent
    end)

    log("PREFAB15_8_HELPER_READY=" ..
        tostring(is_valid(helper_root)) ..
        " actor=" ..
        tostring(pcl158_helper_name))

    -- --------------------------------------------------------
    -- 2. Begin the target DEFORMABLE actor but do not finish it.
    -- --------------------------------------------------------
    local deferred = nil

    ok, err =
        pcall(function()
            deferred =
                gameplay:BeginDeferredActorSpawnFromClass(
                    forge,
                    deform_class,
                    transform,
                    1,
                    nil,
                    2
                )
        end)

    if not ok or not is_valid(deferred) then
        cleanup_158_internal()
        log("PREFAB15_8_ERROR target BeginDeferred " ..
            tostring(err))
        return
    end

    pcall(function()
        deferred:SetActorHiddenInGame(true)
        deferred:SetActorEnableCollision(false)
    end)

    local setup_ok, setup_err =
        setup_deferred_actor_identity_15(
            deferred,
            saved,
            part_resolved,
            material_resolved
        )

    if not setup_ok then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        cleanup_158_internal()
        log("PREFAB15_8_ERROR target identity " ..
            tostring(setup_err))
        return
    end

    -- Native catalogue previews are pending=true.
    pcall(function()
        deferred.bPending = true
    end)

    local mesh_write_ok, mesh_write_err =
        pcall(function()
            deferred.Mesh = asset
        end)

    if not mesh_write_ok then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        cleanup_158_internal()
        log("PREFAB15_8_ERROR target Mesh write " ..
            tostring(mesh_write_err))
        return
    end

    local proc = nil
    pcall(function()
        proc =
            deferred.ProceduralMeshComponent
    end)

    if not is_valid(proc) then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        cleanup_158_internal()
        log("PREFAB15_8_ERROR target ProceduralMeshComponent invalid")
        return
    end

    local before_ref, before_raw =
        reflected_proc_sections_158(proc)

    log("PREFAB15_8_BEFORE_COPY sections_reflected=" ..
        tostring(before_ref) ..
        " sections_raw=" ..
        tostring(before_raw))

    -- --------------------------------------------------------
    -- 3. Copy LOD0 geometry into the empty procedural component.
    -- --------------------------------------------------------
    local copy_ok, copy_err =
        pcall(function()
            proc_lib:CopyProceduralMeshFromStaticMeshComponent(
                helper_root,
                0,
                proc,
                false
            )
        end)

    log("PREFAB15_8_COPY_CALL_RETURNED=" ..
        tostring(copy_ok) ..
        " error=" ..
        tostring(copy_err))

    if not copy_ok then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        cleanup_158_internal()
        log("PREFAB15_8_ERROR procedural copy failed")
        return
    end

    local copied_ref, copied_raw =
        reflected_proc_sections_158(proc)

    log("PREFAB15_8_AFTER_COPY sections_reflected=" ..
        tostring(copied_ref) ..
        " sections_raw=" ..
        tostring(copied_raw))

    log("PREFAB15_8_AFTER_COPY_MATERIALS " ..
        material_summary_158(proc))

    if copied_ref <= 0 and copied_raw <= 0 then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        cleanup_158_internal()
        log("PREFAB15_8_ERROR copy returned but no procedural section exists")
        return
    end

    log("PREFAB15_8_PROCEDURAL_SECTION_READY_BEFORE_FINISH=true")

    -- Phase 15.8.1 isolation:
    -- The native deformable class starts with actor ticking enabled.
    -- Disable it BEFORE FinishSpawning so any Bladesong deformable tick/update
    -- cannot run against partially reconstructed native state.
    local tick_pre_ok, tick_pre_err =
        pcall(function()
            deferred:SetActorTickEnabled(false)
        end)

    log("PREFAB15_8_1_TICK_DISABLE_PRE_FINISH ok=" ..
        tostring(tick_pre_ok) ..
        " error=" .. tostring(tick_pre_err))

    -- Static helper is no longer required once section data is copied.
    if is_valid(helper) then
        pcall(function()
            helper:K2_DestroyActor()
        end)
    end
    pcl158_helper_name = nil

    -- --------------------------------------------------------
    -- 4. Finish only after procedural geometry is valid.
    -- --------------------------------------------------------
    local finished = nil
    local start_clock = os.clock()

    ok, err =
        pcall(function()
            finished =
                gameplay:FinishSpawningActor(
                    deferred,
                    transform,
                    2
                )
        end)

    if not ok or not is_valid(finished) then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        log("PREFAB15_8_ERROR target FinishSpawning " ..
            tostring(err))
        return
    end

    local elapsed_ms =
        (os.clock() - start_clock) *
        1000.0

    pcl158_actor_name =
        safe_full_name(finished)

    local tick_post_ok, tick_post_err =
        pcall(function()
            finished:SetActorTickEnabled(false)
        end)

    log("PREFAB15_8_1_TICK_DISABLE_POST_FINISH ok=" ..
        tostring(tick_post_ok) ..
        " error=" .. tostring(tick_post_err))

    log(string.format(
        "PREFAB15_8_DIRECT_SPAWN_OK finish_ms=%.3f actor=%s",
        elapsed_ms,
        tostring(pcl158_actor_name)
    ))

    audit_158(
        finished,
        "immediate_after_finish"
    )

    local name_copy =
        tostring(pcl158_actor_name)

    schedule_game_11(500, function()
        local actor =
            actor_by_full_name_15(
                name_copy
            )

        if not is_valid(actor) then
            log("PREFAB15_8_SURVIVED_500MS=false")
            log("============================================================")
            return
        end

        log("PREFAB15_8_SURVIVED_500MS=true")

        audit_158(
            actor,
            "after_500ms"
        )

        local proc_after = nil
        pcall(function()
            proc_after =
                actor.ProceduralMeshComponent
        end)

        local final_ref, final_raw =
            reflected_proc_sections_158(
                proc_after
            )

        if final_ref > 0 or final_raw > 0 then
            log("PREFAB15_8_DIRECT_DEFORMABLE_STABLE_WITH_PROCEDURAL_MESH=true")
            log("PREFAB15_8_NEXT_STEP=material_and_held_preview_state")
        else
            log("PREFAB15_8_PROCEDURAL_MESH_LOST_AFTER_FINISH=true")
        end

        log("Use CTRL+ALT+K to cleanup.")
        log("============================================================")
    end)
end

local function cleanup_158()
    log("============================================================")
    log("PREFAB15_8_CLEANUP_BEGIN")

    cleanup_158_internal()

    log("PREFAB15_8_CLEANUP_OK")
    log("============================================================")
end

-- Phase 15.8.1 uses fresh bindings to avoid collisions with old probes.
RegisterKeyBind(Key.M, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(
        direct_proc_copy_158
    )
end)

RegisterKeyBind(Key.P, {ModifierKey.CONTROL, ModifierKey.ALT}, function()
    run_game_thread(
        cleanup_158
    )
end)

log("Phase 15.8.1 TICK ISOLATION proof loaded.")
log("CTRL+ALT+M = direct deformable procedural-copy proof with actor tick disabled.")
log("CTRL+ALT+P = cleanup Phase 15.8.1 actor.")
log("CTRL+ALT+G is NOT used by Phase 15.8.1.")
log("No preview handoff key exists.")
log("F10/F11/F12 remain unused.")


-- ============================================================
-- Phase 15.9: DIRECT -> SERIALIZE -> NATIVE REBUILD ROUNDTRIP
-- ============================================================
--
-- CTRL+ALT+I
--
-- Empty Forge only.
--
-- 1. Reuses the proven Phase 15.8.1 direct deformable constructor:
--      saved class/render asset
--      procedural section copy
--      bPending=true
--      actor tick disabled
--
-- 2. Makes that direct actor ForgeMode.RootSwordPartActor.
--
-- 3. Calls ForgeMode:SerializeSwordPartActorsToData().
--
-- 4. Re-applies the exact saved AppliedSwordPart identity/material/geometry.
--
-- 5. Calls EnterForgeMode(Piece) ONCE.
--
-- 6. Reacquires the rebuilt native root and audits:
--      tick enabled
--      procedural sections
--      material/MID
--      row/material/state
--
-- No catalogue clicks.
-- No cursor teleport.
-- No PreviewSwordPartActor handoff in this proof.
--
-- This tests whether one native rebuild can populate all of the private
-- deformable state that direct Lua construction cannot access.
--

pcl159_running = false

function audit_rebuilt_159(actor, label)
    log("------------------------------------------------------------")
    log("PREFAB15_9_AUDIT_BEGIN label=" .. tostring(label))

    if not is_valid(actor) then
        log("PREFAB15_9_AUDIT actor=None")
        log("PREFAB15_9_AUDIT_END")
        return
    end

    local cls = "None"
    local row = "None"
    local material = "None"
    local pending = "?"
    local tick_enabled = "?"
    local hidden = "?"
    local collision = "?"
    local mesh = "None"
    local proc = nil
    local sections_reflected = -1
    local sections_raw = -1
    local material_count = -1

    pcall(function()
        local c = actor:GetClass()
        if is_valid(c) then
            cls = safe_full_name(c)
        end
    end)

    pcall(function()
        row = safe_name(actor.SwordPartDataHandle.RowName)
    end)

    pcall(function()
        material = safe_name(actor.SwordMaterialName)
    end)

    pcall(function()
        pending = tostring(actor.bPending)
    end)

    pcall(function()
        tick_enabled = tostring(actor:IsActorTickEnabled())
    end)

    pcall(function()
        hidden = tostring(actor.bHidden)
    end)

    pcall(function()
        collision = tostring(actor:GetActorEnableCollision())
    end)

    pcall(function()
        if is_valid(actor.Mesh) then
            mesh = safe_full_name(actor.Mesh)
        else
            mesh = tostring(actor.Mesh)
        end
    end)

    pcall(function()
        proc = actor.ProceduralMeshComponent
    end)

    if is_valid(proc) then
        pcall(function()
            sections_reflected = proc:GetNumSections()
        end)

        pcall(function()
            if proc.ProcMeshSections ~= nil then
                sections_raw = #proc.ProcMeshSections
            end
        end)

        pcall(function()
            material_count = proc:GetNumMaterials()
        end)
    end

    log("PREFAB15_9_AUDIT actor=" .. safe_full_name(actor))
    log("PREFAB15_9_AUDIT class=" .. tostring(cls))
    log("PREFAB15_9_AUDIT row=" .. tostring(row) ..
        " material=" .. tostring(material) ..
        " pending=" .. tostring(pending))
    log("PREFAB15_9_AUDIT tick_enabled=" .. tostring(tick_enabled) ..
        " hidden=" .. tostring(hidden) ..
        " collision=" .. tostring(collision))
    log("PREFAB15_9_AUDIT mesh=" .. tostring(mesh))
    log("PREFAB15_9_AUDIT proc=" ..
        (is_valid(proc) and safe_full_name(proc) or "None") ..
        " sections_reflected=" .. tostring(sections_reflected) ..
        " sections_raw=" .. tostring(sections_raw))
    log("PREFAB15_9_AUDIT material_count=" .. tostring(material_count))

    if is_valid(proc) and type(material_count) == "number" and material_count > 0 then
        for i = 0, math.min(material_count - 1, 3) do
            local mat = nil
            pcall(function()
                mat = proc:GetMaterial(i)
            end)

            log("PREFAB15_9_AUDIT material_index=" .. tostring(i) ..
                " object=" ..
                (is_valid(mat) and safe_full_name(mat) or tostring(mat)))
        end
    end

    log("PREFAB15_9_AUDIT_END")
    log("------------------------------------------------------------")
end

function phase159_roundtrip_after_direct()
    if not pcl159_running then
        return
    end

    local direct_actor =
        actor_by_full_name_15(
            pcl158_actor_name
        )

    if not is_valid(direct_actor) then
        pcl159_running = false
        log("PREFAB15_9_ERROR direct actor unavailable before serialize")
        return
    end

    local tick_before = "?"
    pcall(function()
        tick_before =
            tostring(
                direct_actor:IsActorTickEnabled()
            )
    end)

    local proc = nil
    local sections = -1

    pcall(function()
        proc =
            direct_actor.ProceduralMeshComponent
    end)

    if is_valid(proc) then
        pcall(function()
            sections =
                proc:GetNumSections()
        end)
    end

    log("PREFAB15_9_DIRECT_READY actor=" ..
        safe_full_name(direct_actor) ..
        " tick_enabled=" ..
        tostring(tick_before) ..
        " sections=" ..
        tostring(sections))

    if sections <= 0 then
        pcl159_running = false
        log("PREFAB15_9_ERROR direct actor has no procedural section")
        return
    end

    local path =
        OUTPUT_DIR .. PCL_IMPORT_FILENAME

    local prefab, parse_err =
        parse_pcl_file(path)

    if prefab == nil then
        pcl159_running = false
        log("PREFAB15_9_ERROR parse " ..
            tostring(parse_err))
        return
    end

    local saved_local, saved =
        find_first_deformable_saved_156(
            prefab
        )

    if saved == nil then
        pcl159_running = false
        log("PREFAB15_9_ERROR no saved deformable part")
        return
    end

    local forge, piece, design, state_err =
        state_no_serialize_11()

    if state_err then
        pcl159_running = false
        log("PREFAB15_9_ERROR state " ..
            tostring(state_err))
        return
    end

    local before_count = -1
    pcall(function()
        before_count =
            #design.AppliedSwordParts
    end)

    log("PREFAB15_9_DESIGN_BEFORE count=" ..
        tostring(before_count))

    -- Phase 15.9.2 discriminator:
    -- A normal catalogue preview is bPending=true, but
    -- SerializeSwordPartActorsToData() serializes the committed sword.
    -- Commit ONLY this state bit before serialization while leaving actor
    -- tick disabled and all other direct-spawn state unchanged.
    local commit_pending_ok, commit_pending_err =
        pcall(function()
            direct_actor.bPending = false
        end)

    local pending_after_commit = "?"
    pcall(function()
        pending_after_commit =
            tostring(direct_actor.bPending)
    end)

    log("PREFAB15_9_2_PENDING_COMMIT ok=" ..
        tostring(commit_pending_ok) ..
        " error=" ..
        tostring(commit_pending_err) ..
        " pending_now=" ..
        tostring(pending_after_commit))

    if not commit_pending_ok or
       pending_after_commit ~= "false" then
        pcl159_running = false
        log("PREFAB15_9_2_ERROR could not clear bPending")
        return
    end

    -- This proof is intentionally EMPTY-FORGE only.
    if before_count ~= 0 then
        pcl159_running = false
        log("PREFAB15_9_ERROR test requires empty Forge design count=0")
        return
    end

    -- Phase 15.9.3 correction:
    --
    -- ForgeMode.RootSwordPartActor is the permanent SwordPartEmptyActor
    -- sentinel/container. SerializeSwordPartActorsToData() intentionally
    -- does NOT serialize that actor; it recursively serializes the
    -- sentinel's SlotChildParts / FreeChildParts.
    --
    -- Therefore do NOT replace Forge.RootSwordPartActor with our real part.
    -- Put the real part under the existing sentinel in its normal slot 0.
    local sentinel = nil

    pcall(function()
        sentinel =
            forge:GetRootSwordPartActor()
    end)

    if not is_valid(sentinel) then
        pcl159_running = false
        log("PREFAB15_9_3_ERROR root sentinel unavailable")
        return
    end

    if safe_full_name(sentinel) ==
       safe_full_name(direct_actor) then
        pcl159_running = false
        log("PREFAB15_9_3_ERROR root sentinel unexpectedly equals direct actor")
        return
    end

    local sentinel_class = "None"
    local sentinel_row = "None"

    pcall(function()
        local cls = sentinel:GetClass()
        if is_valid(cls) then
            sentinel_class = safe_full_name(cls)
        end
    end)

    pcall(function()
        sentinel_row =
            safe_name(
                sentinel.SwordPartDataHandle.RowName
            )
    end)

    log("PREFAB15_9_3_SENTINEL=" ..
        safe_full_name(sentinel))

    log("PREFAB15_9_3_SENTINEL_CLASS=" ..
        tostring(sentinel_class) ..
        " row=" ..
        tostring(sentinel_row))

    local sentinel_children_before = 0
    local sentinel_child_desc = {}

    pcall(function()
        sentinel.SlotChildParts:ForEach(
            function(key, value)
                sentinel_children_before =
                    sentinel_children_before + 1

                table.insert(
                    sentinel_child_desc,
                    tostring(key) ..
                    ":" ..
                    (is_valid(value) and
                     safe_full_name(value) or
                     tostring(value))
                )

                return false
            end
        )
    end)

    log("PREFAB15_9_3_SENTINEL_CHILDREN_BEFORE count=" ..
        tostring(sentinel_children_before) ..
        " children=[" ..
        table.concat(sentinel_child_desc, ",") ..
        "]")

    -- Empty-Forge proof only. Do not overwrite an existing sword.
    if sentinel_children_before ~= 0 then
        pcl159_running = false
        log("PREFAB15_9_3_ERROR sentinel already has real sword children")
        return
    end

    local attach_ok, attach_err =
        pcall(function()
            sentinel.SlotChildParts:Add(
                0,
                direct_actor
            )
        end)

    log("PREFAB15_9_3_SENTINEL_SLOT0_ADD ok=" ..
        tostring(attach_ok) ..
        " error=" ..
        tostring(attach_err))

    if not attach_ok then
        pcl159_running = false
        return
    end

    local slot0_verify = nil

    pcall(function()
        slot0_verify =
            sentinel.SlotChildParts:Find(0)
    end)

    log("PREFAB15_9_3_SENTINEL_SLOT0_VERIFY=" ..
        (is_valid(slot0_verify) and
         safe_full_name(slot0_verify) or
         tostring(slot0_verify)))

    local serialize_ok, serialize_err =
        pcall(function()
            forge:SerializeSwordPartActorsToData()
        end)

    log("PREFAB15_9_SERIALIZE_RETURNED ok=" ..
        tostring(serialize_ok) ..
        " error=" ..
        tostring(serialize_err))

    if not serialize_ok then
        pcl159_running = false
        return
    end

    local forge2, piece2, design2, state_err2 =
        state_no_serialize_11()

    if state_err2 then
        pcl159_running = false
        log("PREFAB15_9_ERROR post-serialize state " ..
            tostring(state_err2))
        return
    end

    local serialized_count = -1
    local root_native = -1

    pcall(function()
        serialized_count =
            #design2.AppliedSwordParts
    end)

    pcall(function()
        root_native =
            design2.RootSwordPartIdx
    end)

    log("PREFAB15_9_SERIALIZED count=" ..
        tostring(serialized_count) ..
        " root_native=" ..
        tostring(root_native))

    if serialized_count ~= 1 or
       type(root_native) ~= "number" or
       root_native < 0 then
        pcl159_running = false
        log("PREFAB15_9_3_ERROR serializer did not produce one valid real part from sentinel slot 0")
        return
    end

    -- Replace whatever scalar/deformation values the raw direct actor
    -- serialized with the exact values from the saved prefab part.
    local previous_session =
        pcl11_session

    pcl11_session = {
        base_count = 0,
        parts = {
            [1] = saved
        },
        relations = {},
        local_to_native = {
            [1] = root_native
        }
    }

    local apply_ok, apply_err =
        apply_saved_part_11(
            0,
            root_native
        )

    pcl11_session =
        previous_session

    log("PREFAB15_9_APPLY_SAVED_RETURNED ok=" ..
        tostring(apply_ok) ..
        " error=" ..
        tostring(apply_err))

    if not apply_ok then
        pcl159_running = false
        return
    end

    -- Suppress visible frontend churn just like the proven Phase 14 path.
    pcall(function()
        forge2.bSupressFrontendUpdate =
            true
    end)

    log("PREFAB15_9_ENTER_FORGE_MODE_BEGIN")

    local rebuild_ok, rebuild_err =
        enter_piece_again(
            piece2
        )

    log("PREFAB15_9_ENTER_FORGE_MODE_RETURNED ok=" ..
        tostring(rebuild_ok) ..
        " error=" ..
        tostring(rebuild_err))

    if not rebuild_ok then
        pcl159_running = false
        return
    end

    schedule_game_11(300, function()
        if not pcl159_running then
            return
        end

        local forge3, piece3, design3, err3 =
            state_no_serialize_11()

        if err3 then
            pcl159_running = false
            log("PREFAB15_9_ERROR rebuilt state " ..
                tostring(err3))
            return
        end

        local rebuilt_sentinel = nil

        pcall(function()
            rebuilt_sentinel =
                forge3:GetRootSwordPartActor()
        end)

        log("PREFAB15_9_REBUILT_SENTINEL=" ..
            (is_valid(rebuilt_sentinel) and
             safe_full_name(rebuilt_sentinel) or
             "None"))

        if not is_valid(rebuilt_sentinel) then
            pcl159_running = false
            log("PREFAB15_9_ERROR rebuilt sentinel unavailable")
            return
        end

        local rebuilt_root = nil

        pcall(function()
            rebuilt_root =
                rebuilt_sentinel.SlotChildParts:Find(0)
        end)

        log("PREFAB15_9_REBUILT_ROOT_SLOT0=" ..
            (is_valid(rebuilt_root) and
             safe_full_name(rebuilt_root) or
             tostring(rebuilt_root)))

        audit_rebuilt_159(
            rebuilt_root,
            "after_300ms_native_rebuild_slot0"
        )

        if not is_valid(rebuilt_root) then
            pcl159_running = false
            log("PREFAB15_9_ERROR rebuilt real root unavailable in sentinel slot 0")
            return
        end

        local rebuilt_name =
            safe_full_name(rebuilt_root)

        schedule_game_11(500, function()
            if not pcl159_running then
                return
            end

            local actor =
                actor_by_full_name_15(
                    rebuilt_name
                )

            if not is_valid(actor) then
                pcl159_running = false
                log("PREFAB15_9_NATIVE_REBUILD_SURVIVED_500MS=false")
                log("============================================================")
                return
            end

            log("PREFAB15_9_NATIVE_REBUILD_SURVIVED_500MS=true")

            audit_rebuilt_159(
                actor,
                "after_800ms_native_rebuild"
            )

            local tick_ok = false
            local section_ok = false

            pcall(function()
                tick_ok =
                    actor:IsActorTickEnabled()
                    and true or false
            end)

            pcall(function()
                section_ok =
                    is_valid(actor.ProceduralMeshComponent) and
                    actor.ProceduralMeshComponent:GetNumSections() > 0
            end)

            log("PREFAB15_9_NATIVE_PRIVATE_STATE_PROVEN=" ..
                tostring(tick_ok and section_ok))

            if tick_ok and section_ok then
                log("PREFAB15_9_NEXT_STEP=direct_batch_then_one_native_rebuild")
            end

            pcl159_running = false
            log("============================================================")
        end)
    end)
end

function phase159_begin()
    if pcl159_running then
        log("PREFAB15_9_ERROR test already running")
        return
    end

    log("============================================================")
    log("PREFAB15_9_BEGIN")
    log("PREFAB15_9_CLEAN_KEYMAP=true")
    log("PREFAB15_9_CATALOGUE_CLICKS=0")
    log("PREFAB15_9_CURSOR_TELEPORT=false")
    log("PREFAB15_9_EXPECTED_ENTER_FORGE_MODE_CALLS=1")
    log("PREFAB15_9_PREVIEW_HANDOFF=false")

    pcl159_running = true

    -- Phase 15.8.1's direct builder is already patched in this file to:
    --   copy one procedural section
    --   bPending=true
    --   disable actor tick before and after FinishSpawningActor
    direct_proc_copy_158()

    -- Give the direct builder enough time to finish but stay well inside the
    -- proven tick-disabled stability window.
    schedule_game_11(
        100,
        phase159_roundtrip_after_direct
    )
end



-- ============================================================
-- Phase 15.10: FULL DIRECT PREFAB -> ONE NATIVE REBUILD -> HAND
-- ============================================================
--
-- This is the first full-prefab version of the direct-spawn architecture.
--
-- Empty Forge only.
--
-- Pipeline:
--   PCL all parts
--   -> direct-spawn every actor hidden/tick-disabled
--   -> initialize static/deformable render geometry
--   -> link saved SlotChildren tree
--   -> sentinel.SlotChildParts[0] = prefab root
--   -> SerializeSwordPartActorsToData() ONCE
--   -> map every direct actor to its new native AppliedSwordPart index
--   -> apply exact saved identity/material/deformation state to every part
--   -> EnterForgeMode(Piece) ONCE
--   -> rebuild actor map
--   -> assign complete rebuilt root to PreviewSwordPartActor
--
-- No catalogue clicks.
-- No mouse movement.
-- Historical keybinds remain suppressed by the Phase 15.9 bootstrap.
--

pcl1510_running = false

function pcl1510_fail(message)
    log("PREFAB15_10_ERROR " .. tostring(message))
    pcl1510_running = false
    pcl11_session = nil
    PCL151117_CACHE = nil
    log("============================================================")
end

function pcl1510_spawn_helper(forge, gameplay, transform)
    local static_class =
        static_sword_part_class_158()

    if not is_valid(static_class) then
        return nil, nil,
            "SwordPartStaticMeshActor class unavailable for deformable helper"
    end

    local deferred = nil
    local ok, err =
        pcall(function()
            deferred =
                gameplay:BeginDeferredActorSpawnFromClass(
                    forge,
                    static_class,
                    transform,
                    1,
                    nil,
                    2
                )
        end)

    if not ok or not is_valid(deferred) then
        return nil, nil,
            "helper BeginDeferred failed: " .. tostring(err)
    end

    pcall(function()
        deferred:SetActorHiddenInGame(true)
        deferred:SetActorEnableCollision(false)
        deferred:SetActorTickEnabled(false)
    end)

    local finished = nil

    ok, err =
        pcall(function()
            finished =
                gameplay:FinishSpawningActor(
                    deferred,
                    transform,
                    2
                )
        end)

    if not ok or not is_valid(finished) then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        return nil, nil,
            "helper FinishSpawning failed: " .. tostring(err)
    end

    pcall(function()
        finished:SetActorTickEnabled(false)
    end)

    local root = nil
    pcall(function()
        root = finished.RootComponent
    end)

    if not is_valid(root) then
        pcall(function()
            finished:K2_DestroyActor()
        end)

        return nil, nil,
            "helper RootComponent unavailable"
    end

    return finished, root, nil
end

function pcl1510_spawn_one(
    forge,
    gameplay,
    transform,
    design,
    proc_lib,
    helper_root,
    saved,
    local_index
)
    local part_resolved,
          material_resolved,
          resolve_err =
        resolve_identity_rows_fresh_11(
            saved.sword_part,
            saved.material,
            saved.material_data_row,
            saved.material_data_table
        )

    if resolve_err then
        return nil,
            "identity preflight local=" ..
            tostring(local_index) ..
            ": " .. tostring(resolve_err)
    end

    local actor_class,
          class_source,
          class_err =
        resolve_actor_class_151(
            saved,
            design,
            part_resolved
        )

    if not is_valid(actor_class) then
        return nil,
            "actor class local=" ..
            tostring(local_index) ..
            ": " .. tostring(class_err)
    end

    local class_name = "None"

    pcall(function()
        class_name =
            safe_full_name(actor_class)
    end)

    local is_deform =
        string.find(
            class_name,
            "SwordPartDeformableStaticMeshActor",
            1,
            true
        ) ~= nil

    local is_static =
        string.find(
            class_name,
            "SwordPartStaticMeshActor",
            1,
            true
        ) ~= nil

    local is_skeletal =
        string.find(
            class_name,
            "SwordPartSkeletalMeshActor",
            1,
            true
        ) ~= nil

    local is_empty =
        string.find(
            class_name,
            "SwordPartEmptyActor",
            1,
            true
        ) ~= nil

    if not is_deform and
       not is_static and
       not is_skeletal and
       not is_empty then

        return nil,
            "unsupported direct actor class local=" ..
            tostring(local_index) ..
            " class=" .. tostring(class_name)
    end

    local data_only = PCL151117_CACHE ~= nil and
        PCL151117_CACHE.data_only_staging and true or false
    local asset = nil

    if not is_empty and not data_only then
        local asset_err = nil
        asset, asset_err = load_saved_render_asset_155(saved)
        if not is_valid(asset) then
            return nil, "render asset local=" .. tostring(local_index) ..
                ": " .. tostring(asset_err)
        end
    elseif data_only and PCL151117_CACHE ~= nil then
        PCL151117_CACHE.stats.render_assets_skipped =
            (PCL151117_CACHE.stats.render_assets_skipped or 0) + 1
    end

    if PCL151117_CACHE ~= nil and PCL151117_CACHE.resolved_by_local ~= nil then
        PCL151117_CACHE.resolved_by_local[local_index + 1] = {
            part_resolved = part_resolved,
            material_resolved = material_resolved,
            actor_class = actor_class,
            asset = asset
        }
    end

    local deferred = nil
    local ok, err =
        pcall(function()
            deferred =
                gameplay:BeginDeferredActorSpawnFromClass(
                    forge,
                    actor_class,
                    transform,
                    1,
                    nil,
                    2
                )
        end)

    if not ok or not is_valid(deferred) then
        return nil,
            "BeginDeferred local=" ..
            tostring(local_index) ..
            ": " .. tostring(err)
    end

    pcall(function()
        deferred:SetActorHiddenInGame(true)
        deferred:SetActorEnableCollision(false)
        deferred:SetActorTickEnabled(false)
    end)

    local identity_ok, identity_err =
        setup_deferred_actor_identity_15(
            deferred,
            saved,
            part_resolved,
            material_resolved
        )

    if not identity_ok then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        return nil,
            "identity local=" ..
            tostring(local_index) ..
            ": " .. tostring(identity_err)
    end

    -- Serializer wants committed real parts, not catalogue-style pending ones.
    pcall(function()
        deferred.bPending = false
    end)

    local root = nil
    pcall(function()
        root = deferred.RootComponent
    end)

    if not is_valid(root) then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        return nil,
            "RootComponent unavailable local=" ..
            tostring(local_index)
    end

    if not data_only and is_deform then
        if not is_valid(proc_lib) or
           not is_valid(helper_root) then

            pcall(function()
                deferred:K2_DestroyActor()
            end)

            return nil,
                "deformable helper unavailable local=" ..
                tostring(local_index)
        end

        ok, err =
            pcall(function()
                deferred.Mesh = asset
                helper_root:SetStaticMesh(asset)

                proc_lib:
                    CopyProceduralMeshFromStaticMeshComponent(
                        helper_root,
                        0,
                        deferred.ProceduralMeshComponent,
                        false
                    )
            end)

        if not ok then
            pcall(function()
                deferred:K2_DestroyActor()
            end)

            return nil,
                "deformable procedural copy local=" ..
                tostring(local_index) ..
                ": " .. tostring(err)
        end

        local section_count = -1

        pcall(function()
            section_count =
                deferred.ProceduralMeshComponent:
                    GetNumSections()
        end)

        if section_count <= 0 then
            pcall(function()
                deferred:K2_DestroyActor()
            end)

            return nil,
                "deformable produced no procedural sections local=" ..
                tostring(local_index)
        end

    elseif not data_only and is_static then
        ok, err =
            pcall(function()
                root:SetStaticMesh(asset)
            end)

        if not ok then
            pcall(function()
                deferred:K2_DestroyActor()
            end)

            return nil,
                "SetStaticMesh local=" ..
                tostring(local_index) ..
                ": " .. tostring(err)
        end

    elseif not data_only and is_skeletal then
        ok, err =
            pcall(function()
                root:SetSkeletalMeshAsset(asset)
            end)

        if not ok then
            pcall(function()
                deferred:K2_DestroyActor()
            end)

            return nil,
                "SetSkeletalMeshAsset local=" ..
                tostring(local_index) ..
                ": " .. tostring(err)
        end
    end

    local finished = nil

    ok, err =
        pcall(function()
            finished =
                gameplay:FinishSpawningActor(
                    deferred,
                    transform,
                    2
                )
        end)

    if not ok or not is_valid(finished) then
        pcall(function()
            deferred:K2_DestroyActor()
        end)

        return nil,
            "FinishSpawning local=" ..
            tostring(local_index) ..
            ": " .. tostring(err)
    end

    pcall(function()
        finished:SetActorTickEnabled(false)
        finished:SetActorHiddenInGame(true)
        finished:SetActorEnableCollision(false)
        finished.bPending = false
    end)

    return finished, nil
end


pcl15104_context = nil

function pcl15104_hide_live_rebuild()
    local live = collect_live_sword_part_actors_10()
    local hidden_count = 0
    for _, actor in ipairs(live) do
        if is_valid(actor) then
            local ok = pcall(function()
                actor:SetActorHiddenInGame(true)
            end)
            if ok then hidden_count = hidden_count + 1 end
        end
    end
    log("PREFAB15_10_4_HIDE_WHILE_NOT_READY count=" .. tostring(hidden_count))
end

function pcl15104_finish_handoff(forge3, design3, source_label)
    local ctx = pcl15104_context
    if ctx == nil or not pcl1510_running then return false, "context unavailable" end
    if not is_valid(forge3) then return false, "ForgeMode unavailable" end
    if design3 == nil then return false, "WeaponDesignDefinition unavailable" end

    local _, rebuilt_actors, rebuilt_map_err = build_actor_map_10(design3, nil)
    if rebuilt_actors == nil then
        return false, "rebuilt actor map not ready: " .. tostring(rebuilt_map_err)
    end

    local rebuilt_root_native = ctx.local_to_native[1]
    local rebuilt_root = rebuilt_actors[rebuilt_root_native]
    if not is_valid(rebuilt_root) then
        return false, "rebuilt root not ready native=" .. tostring(rebuilt_root_native)
    end

    local rebuilt_tree_count = live_tree_count_14(rebuilt_root)
    log("PREFAB15_10_REBUILT_TREE_COUNT=" .. tostring(rebuilt_tree_count) ..
        " expected=" .. tostring(ctx.part_count) .. " source=" .. tostring(source_label))
    if rebuilt_tree_count ~= ctx.part_count then
        return false, "rebuilt tree not ready count=" .. tostring(rebuilt_tree_count)
    end

    local handling3 = find_handling_component_9()
    if not is_valid(handling3) then return false, "handling component unavailable" end

    local sentinel_for_unlink = nil
    pcall(function() sentinel_for_unlink = forge3:GetRootSwordPartActor() end)
    if not is_valid(sentinel_for_unlink) then return false, "sentinel unavailable" end

    log("PREFAB15_10_HANDOFF_BEGIN actor=" .. safe_full_name(rebuilt_root))
    local pre_unlink_count = live_tree_count_14(rebuilt_root)
    log("PREFAB15_10_4_PRE_UNLINK_TREE_COUNT=" .. tostring(pre_unlink_count) ..
        " expected=" .. tostring(ctx.part_count))
    if pre_unlink_count ~= ctx.part_count then return false, "tree changed before unlink" end

    local remove_result = nil
    local unlink_ok, unlink_err = pcall(function()
        remove_result = sentinel_for_unlink.SlotChildParts:Remove(0)
    end)
    log("PREFAB15_10_4_SENTINEL_SLOT0_REMOVE ok=" .. tostring(unlink_ok) ..
        " result=" .. tostring(remove_result) .. " error=" .. tostring(unlink_err))
    if not unlink_ok then return false, "sentinel unlink failed: " .. tostring(unlink_err) end

    local post_unlink_count = live_tree_count_14(rebuilt_root)
    log("PREFAB15_10_4_POST_UNLINK_TREE_COUNT=" .. tostring(post_unlink_count) ..
        " expected=" .. tostring(ctx.part_count))
    if post_unlink_count ~= ctx.part_count then
        return false, "sentinel unlink changed tree count"
    end

    for _, actor in pairs(rebuilt_actors) do
        if is_valid(actor) then
            pcall(function() actor:SetActorHiddenInGame(false) end)
        end
    end

    local hand_ok, hand_err = pcall(function()
        handling3.PreviewSwordPartActor = rebuilt_root
    end)
    if not hand_ok then
        return false, "PreviewSwordPartActor write failed: " .. tostring(hand_err)
    end

    local preview = nil
    local has_preview = false
    pcall(function()
        preview = handling3.PreviewSwordPartActor
        has_preview = handling3:HasPreviewSwordPart() and true or false
    end)
    local held_count = live_tree_count_14(preview)
    log("PREFAB15_10_VERIFY_HAS_PREVIEW=" .. tostring(has_preview))
    log("PREFAB15_10_VERIFY_HELD_TREE_COUNT=" .. tostring(held_count) ..
        " expected=" .. tostring(ctx.part_count))
    log("PREFAB15_10_4_HANDOFF_SOURCE=" .. tostring(source_label))

    if has_preview and is_valid(preview) and held_count == ctx.part_count then
        log("PREFAB15_11_OK FULL DIRECT PREFAB HELD WITHOUT ENTERFORGEMODE")
    else
        log("PREFAB15_10_4_HANDOFF_WRITE_DONE_VERIFY_INCOMPLETE")
    end

    log("PREFAB15_10_CATALOGUE_CLICKS=0")
    log("PREFAB15_10_ENTER_FORGE_MODE_CALLS=0")
    log("PREFAB15_10_CURSOR_MOVED=false")
    log("PREFAB15_10_4_FIXED_DELAY_MS=0")
    log("Move normally and LEFT CLICK once to place.")
    pcl15104_context = nil
    pcl1510_running = false
    log("============================================================")
    return true, nil
end

function pcl15104_retry_ready_state()
    if not pcl1510_running or pcl15104_context == nil then return end
    pcl15104_context.attempt = pcl15104_context.attempt + 1

    local forge3, piece3, design3, state_err3 = state_no_serialize_11()
    if state_err3 then
        log("PREFAB15_10_4_NOT_READY attempt=" .. tostring(pcl15104_context.attempt) ..
            " reason=" .. tostring(state_err3))
        if pcl15104_context.attempt >= 120 then
            pcl1510_fail("rebuilt Forge state never became ready")
            pcl15104_context = nil
            return
        end
        schedule_game_11(0, pcl15104_retry_ready_state)
        return
    end

    local done, reason = pcl15104_finish_handoff(
        forge3, design3, "readiness_retry_" .. tostring(pcl15104_context.attempt))
    if done then return end

    log("PREFAB15_10_4_NOT_READY attempt=" .. tostring(pcl15104_context.attempt) ..
        " reason=" .. tostring(reason))
    if pcl15104_context.attempt >= 120 then
        pcl1510_fail("rebuilt actors never became ready: " .. tostring(reason))
        pcl15104_context = nil
        return
    end
    schedule_game_11(0, pcl15104_retry_ready_state)
end


-- ============================================================
-- Phase 15.11.6: STABLE REFLECTED-ALIAS NATIVE REBUILD
-- ============================================================
--
-- Proven working path from Phase 15.11.5:
--
--   /Script/Bladesong.ForgeMode_TechDemoTeaserAnim:InitInEditor
--
-- is a reflected native UFunction inherited from ForgeMode. Calling the
-- unbound UFunction with the existing live ForgeMode as its context performs
-- the native rebuild we need without calling BladesongGameMode:EnterForgeMode.
--
-- IMPORTANT:
--   * no PCLBridge DLL
--   * no BridgeSource project
--   * no RegisterCustomProperty
--   * no UFunction pointer patch
--   * no EXE byte patch
--   * no camera fade workaround
--   * no fixed post-rebuild delay
--
-- The current Bladesong build used for this proof is the 147,934,792-byte EXE.

PCL15116_ALIAS_PATH =
    '/Script/Bladesong.ForgeMode_TechDemoTeaserAnim:InitInEditor'

function pcl15116_object_identity(obj)
    if not is_valid(obj) then
        return 'None'
    end

    local full = '<valid object>'
    pcall(function()
        full = obj:GetFullName()
    end)

    return tostring(full)
end

function pcl151112_script_dir()
    local source = nil
    pcall(function()
        source = debug.getinfo(1, 'S').source
    end)
    source = tostring(source or '')
    if source:sub(1, 1) == '@' then
        source = source:sub(2)
    end
    local dir = source:match('^(.*[\\/])')
    if dir == nil then
        return ''
    end
    return dir
end

PCL151112_NATIVE_CALL = nil
PCL151112_NATIVE_LOAD_ERROR = nil
PCL151112_BRIDGE_FILENAME = 'pcl_native_seam.dll'
PCL151112_RUNTIME_SEAM_RVA = '0x45AF640'

function pcl151112_get_native_call()
    if type(PCL151112_NATIVE_CALL) == 'function' then
        return PCL151112_NATIVE_CALL, nil
    end
    if PCL151112_NATIVE_LOAD_ERROR ~= nil then
        return nil, PCL151112_NATIVE_LOAD_ERROR
    end

    local dll_path = pcl151112_script_dir() .. PCL151112_BRIDGE_FILENAME
    local fn, err, where = BMF_PCL_NATIVE(dll_path, 'pcl_native_rebuild')
    if type(fn) ~= 'function' then
        PCL151112_NATIVE_LOAD_ERROR =
            'package.loadlib failed path=' .. tostring(dll_path) ..
            ' error=' .. tostring(err) .. ' where=' .. tostring(where)
        return nil, PCL151112_NATIVE_LOAD_ERROR
    end

    PCL151112_NATIVE_CALL = fn
    log('PCL15_11_12_BRIDGE_LOADED path=' .. tostring(dll_path) ..
        ' seam_rva=' .. tostring(PCL151112_RUNTIME_SEAM_RVA))
    return fn, nil
end

-- 15.11.73: selective stable-source H4 vertex-cache telemetry. The entry detour
-- classifies/proves sources and a second seam-scoped mid-H4 detour skips only the
-- source->vertex conversion loop after eight identical stock outputs.
PCL151169_H4_STATS_CALL = nil
PCL151169_H4_STATS_LOAD_ERROR = nil

function pcl151169_get_h4_stats_call()
    if type(PCL151169_H4_STATS_CALL) == 'function' then
        return PCL151169_H4_STATS_CALL, nil
    end
    if PCL151169_H4_STATS_LOAD_ERROR ~= nil then
        return nil, PCL151169_H4_STATS_LOAD_ERROR
    end
    local dll_path = pcl151112_script_dir() .. PCL151112_BRIDGE_FILENAME
    local fn, err, where = BMF_PCL_NATIVE(dll_path, 'pcl_native_h4_scope_stats')
    if type(fn) ~= 'function' then
        PCL151169_H4_STATS_LOAD_ERROR =
            'package.loadlib failed path=' .. tostring(dll_path) ..
            ' error=' .. tostring(err) .. ' where=' .. tostring(where)
        return nil, PCL151169_H4_STATS_LOAD_ERROR
    end
    PCL151169_H4_STATS_CALL = fn
    return fn, nil
end

function pcl151112_first_slot_child(sentinel)
    if not is_valid(sentinel) then return nil end
    local child = nil
    pcall(function()
        sentinel.SlotChildParts:ForEach(function(kp, vp)
            local v = vp:get()
            if is_valid(v) and child == nil then child = v end
            return child ~= nil
        end)
    end)
    return child
end

function pcl151112_addr(obj)
    if not is_valid(obj) then return 0 end
    local a = 0
    pcall(function() a = obj:GetAddress() end)
    return tonumber(a) or 0
end

function pcl1511_private_rebuild(forge)
    if not is_valid(forge) then
        return false, 'ForgeMode invalid'
    end

    local piece_before = nil
    local sentinel_before = nil
    pcall(function() piece_before = forge:GetPiece() end)
    pcall(function() sentinel_before = forge:GetRootSwordPartActor() end)
    if not is_valid(piece_before) then
        return false, 'current Piece invalid before direct native seam'
    end
    if not is_valid(sentinel_before) then
        return false, 'current sentinel invalid before direct native seam'
    end

    local direct_root_before = pcl151112_first_slot_child(sentinel_before)
    if not is_valid(direct_root_before) then
        return false, 'direct prefab root unavailable below pre-seam sentinel'
    end

    local forge_addr = pcl151112_addr(forge)
    local piece_addr = pcl151112_addr(piece_before)
    local sentinel_before_addr = pcl151112_addr(sentinel_before)
    local direct_before_addr = pcl151112_addr(direct_root_before)
    if forge_addr == 0 or piece_addr == 0 then
        return false, 'UE4SS GetAddress unavailable for ForgeMode/Piece'
    end

    local before_root = -1
    local before_count = -1
    local before_getnum = -1
    local stage_before = -1
    local side_before = -1
    local read_before_ok, read_before_err = pcall(function()
        local d = piece_before.WeaponDesignDefinition
        before_root = tonumber(d.RootSwordPartIdx) or -1
        before_count = #d.AppliedSwordParts
        before_getnum = piece_before:GetNumSwordParts()
        stage_before = tonumber(piece_before.CurrentSwordmakingStage) or -1
        side_before = tonumber(piece_before.CurrentSideEditingMode) or -1
    end)
    if not read_before_ok or before_root < 0 or before_count < 1 then
        return false, 'pre-seam Piece state invalid: ' .. tostring(read_before_err)
    end

    local native_call, load_err = pcl151112_get_native_call()
    if native_call == nil then
        return false, 'native bridge unavailable: ' .. tostring(load_err)
    end

    log(string.format(
        'PCL15_11_12_DIRECT_SEAM_BEGIN forge=0x%X piece=0x%X sentinel_before=0x%X direct_root_before=0x%X root=%d parts=%d get_num=%d stage=%d side=%d enter_forge_mode_calls=0 init_in_editor_calls=0',
        forge_addr, piece_addr, sentinel_before_addr, direct_before_addr,
        before_root, before_count, before_getnum, stage_before, side_before))

    local call_ok, status_or_err = pcall(function()
        return native_call(forge_addr, piece_addr)
    end)
    if not call_ok then
        return false, 'native seam bridge invocation failed: ' .. tostring(status_or_err)
    end

    local status = tonumber(status_or_err) or -999
    log('PCL15_11_12_BRIDGE_RETURN status=' .. tostring(status) ..
        ' meaning=' .. ({
            [1]='native_seam_called',[-1]='lua_arguments_invalid',[-2]='main_module_base_failed',
            [-3]='exe_guard_failed',[-4]='seam_signature_failed',[-5]='pointer_guard_failed',
            [-6]='forge_piece_pointer_mismatch'
        })[status])
    if status ~= 1 then
        return false, 'native bridge refused call status=' .. tostring(status)
    end

    local piece_after = nil
    local sentinel_after = nil
    pcall(function() piece_after = forge:GetPiece() end)
    pcall(function() sentinel_after = forge:GetRootSwordPartActor() end)
    if not is_valid(piece_after) then
        return false, 'Piece invalid after direct native seam'
    end
    if not is_valid(sentinel_after) then
        return false, 'sentinel invalid after direct native seam'
    end

    local piece_after_addr = pcl151112_addr(piece_after)
    local sentinel_after_addr = pcl151112_addr(sentinel_after)
    local rebuilt_root = pcl151112_first_slot_child(sentinel_after)
    local rebuilt_addr = pcl151112_addr(rebuilt_root)

    local after_root = -1
    local after_count = -1
    local after_getnum = -1
    local stage_after = -1
    local side_after = -1
    local read_after_ok, read_after_err = pcall(function()
        local d = piece_after.WeaponDesignDefinition
        after_root = tonumber(d.RootSwordPartIdx) or -1
        after_count = #d.AppliedSwordParts
        after_getnum = piece_after:GetNumSwordParts()
        stage_after = tonumber(piece_after.CurrentSwordmakingStage) or -1
        side_after = tonumber(piece_after.CurrentSideEditingMode) or -1
    end)

    local rebuilt_tree_count = live_tree_count_14(rebuilt_root)
    log(string.format(
        'PCL15_11_12_DIRECT_SEAM_RETURN piece_same=%s sentinel_before=0x%X sentinel_after=0x%X direct_before=0x%X rebuilt_root=0x%X rebuilt_tree=%d root=%d parts=%d get_num=%d stage_before=%d stage_after=%d side_before=%d side_after=%d read_ok=%s error=%s',
        tostring(piece_after_addr == piece_addr), sentinel_before_addr, sentinel_after_addr,
        direct_before_addr, rebuilt_addr, rebuilt_tree_count, after_root, after_count,
        after_getnum, stage_before, stage_after, side_before, side_after,
        tostring(read_after_ok), tostring(read_after_err)))

    if not read_after_ok then
        return false, 'post-seam Piece read failed: ' .. tostring(read_after_err)
    end
    if piece_after_addr ~= piece_addr then
        return false, 'direct seam unexpectedly replaced Piece'
    end
    if after_root ~= before_root or after_count ~= before_count or after_getnum ~= before_count then
        return false, 'direct seam Piece design mismatch root=' .. tostring(after_root) ..
            ' count=' .. tostring(after_count) .. ' get_num=' .. tostring(after_getnum)
    end
    if not is_valid(rebuilt_root) then
        return false, 'native rebuilt root unavailable below post-seam sentinel'
    end
    if rebuilt_addr == direct_before_addr then
        return false, 'native seam did not replace direct-spawn root actor'
    end
    if rebuilt_tree_count ~= before_count then
        return false, 'native rebuilt tree count mismatch expected=' .. tostring(before_count) ..
            ' actual=' .. tostring(rebuilt_tree_count)
    end

    if stage_after ~= stage_before or side_after ~= side_before then
        local restore_ok, restore_err = pcall(function()
            piece_after.CurrentSwordmakingStage = stage_before
            piece_after.CurrentSideEditingMode = side_before
        end)
        log('PCL15_11_12_STAGE_RESTORE changed=true ok=' .. tostring(restore_ok) ..
            ' error=' .. tostring(restore_err))
        if not restore_ok then
            return false, 'stage/side restore failed after native seam: ' .. tostring(restore_err)
        end
    else
        log('PCL15_11_12_STAGE_RESTORE changed=false')
    end

    return true, nil
end

function phase1510_begin()
    if pcl1510_running then
        log("PREFAB15_10_ERROR already running")
        return
    end

    log("============================================================")
    log("PREFAB15_10_BEGIN")
    log("PREFAB15_10_MODE=full_direct_prefab_native_runtime_seam_bridge")
    log("PREFAB15_10_CATALOGUE_CLICKS=0")
    log("PREFAB15_10_CURSOR_MOVED=false")
    log("PREFAB15_11_EXPECTED_ENTER_FORGE_MODE_CALLS=0")

    pcl1510_running = true

    PCL151117_CACHE = {
        identity = {}, part_rows = {}, classes = {}, assets = {},
        slot_meta = {}, material_handles = {}, fnames = {},
        resolved_by_local = {}, stats = {},
        data_only_staging = true,
        started_clock = os.clock()
    }
    log("PCL15_11_17_FAST_CACHE_INIT=true")
    log("PCL15_11_18_DATA_ONLY_STAGING=true")

    local path =
        OUTPUT_DIR .. PCL_IMPORT_FILENAME

    local prefab, parse_err =
        parse_pcl_file(path)

    if prefab == nil then
        pcl1510_fail(parse_err)
        return
    end

    local part_count =
        tonumber(
            prefab.meta.part_count or "-1"
        ) or -1

    if part_count < 1 then
        pcl1510_fail(
            "invalid part_count=" ..
            tostring(part_count)
        )
        return
    end

    log("PREFAB15_10_PART_COUNT=" ..
        tostring(part_count))

    local relations, relation_err =
        build_relations_11(prefab)

    if relations == nil then
        pcl1510_fail(relation_err)
        return
    end

    local forge, piece, design, state_err =
        state_no_serialize_11()

    if state_err then
        pcl1510_fail(state_err)
        return
    end

    local design_count = -1

    pcall(function()
        design_count =
            #design.AppliedSwordParts
    end)

    if design_count ~= 0 then
        pcl1510_fail(
            "Phase 15.10 requires empty Forge; design count=" ..
            tostring(design_count)
        )
        return
    end

    local handling =
        find_handling_component_9()

    if is_valid(handling) then
        local active_preview = false

        pcall(function()
            active_preview =
                handling:HasPreviewSwordPart()
                and true or false
        end)

        if active_preview then
            pcl1510_fail(
                "another preview is active; cancel it with X first"
            )
            return
        end
    end

    local sentinel = nil

    pcall(function()
        sentinel =
            forge:GetRootSwordPartActor()
    end)

    if not is_valid(sentinel) then
        pcl1510_fail(
            "SwordPartEmptyActor sentinel unavailable"
        )
        return
    end

    local sentinel_children = 0

    pcall(function()
        sentinel.SlotChildParts:ForEach(
            function(kp, vp)
                local child = vp:get()

                if is_valid(child) then
                    sentinel_children =
                        sentinel_children + 1
                end

                return false
            end
        )
    end)

    if sentinel_children ~= 0 then
        pcl1510_fail(
            "sentinel already has slot children; empty Forge required"
        )
        return
    end

    local gameplay =
        gameplay_statics_15()

    if not is_valid(gameplay) then
        pcl1510_fail(
            "GameplayStatics unavailable"
        )
        return
    end

    local data_only = PCL151117_CACHE ~= nil and
        PCL151117_CACHE.data_only_staging and true or false
    local proc_lib = nil
    local transform = neutral_spawn_transform_153()
    local helper = nil
    local helper_root = nil

    if not data_only then
        proc_lib = proc_lib_158()
        if not is_valid(proc_lib) then
            pcl1510_fail("KismetProceduralMeshLibrary unavailable")
            return
        end

        local helper_err = nil
        helper, helper_root, helper_err = pcl1510_spawn_helper(forge, gameplay, transform)
        if not is_valid(helper) or not is_valid(helper_root) then
            pcl1510_fail(helper_err)
            return
        end
    else
        log("PCL15_11_18_RENDER_HELPER_SKIPPED=true")
    end

    local actors = {}
    local actor_names = {}
    local parts = {}

    -- Preflight/save into the same 1-based shape used by Phase 14's proven
    -- AppliedSwordPart writer.
    for local_i = 0, part_count - 1 do
        local saved =
            prefab.parts[local_i]

        if saved == nil then
            pcall(function()
                helper:K2_DestroyActor()
            end)

            pcl1510_fail(
                "missing saved part local=" ..
                tostring(local_i)
            )
            return
        end

        parts[local_i + 1] =
            saved
    end

    PCL151134SeedSavedRowClasses(parts, part_count)

    log("PREFAB15_10_DIRECT_SPAWN_BEGIN")

    for local_i = 0, part_count - 1 do
        local actor, spawn_err =
            pcl1510_spawn_one(
                forge,
                gameplay,
                transform,
                design,
                proc_lib,
                helper_root,
                parts[local_i + 1],
                local_i
            )

        if not is_valid(actor) then
            for _, prior in ipairs(actors) do
                if is_valid(prior) then
                    pcall(function()
                        prior:K2_DestroyActor()
                    end)
                end
            end

            pcall(function()
                helper:K2_DestroyActor()
            end)

            pcl1510_fail(spawn_err)
            return
        end

        actors[local_i + 1] =
            actor

        -- Names are only needed if the graph mapper falls back.
        actor_names[local_i + 1] = nil

        if local_i == part_count - 1 or
           (local_i + 1) % 10 == 0 then
            log("PREFAB15_10_SPAWN_PROGRESS=" ..
                tostring(local_i + 1) ..
                "/" ..
                tostring(part_count))
        end
    end

    pcall(function()
        helper:K2_DestroyActor()
    end)

    helper = nil
    helper_root = nil

    log("PREFAB15_10_DIRECT_SPAWN_COMPLETE count=" ..
        tostring(#actors))

    -- Build exact saved live topology before the native serializer sees it.
    log("PREFAB15_10_LINK_BEGIN")

    for child_local = 1, part_count - 1 do
        local relation =
            relations[child_local + 1]

        if relation == nil then
            pcl1510_fail(
                "missing relation local=" ..
                tostring(child_local)
            )
            return
        end

        local parent =
            actors[
                relation.parent_local + 1
            ]

        local child =
            actors[
                child_local + 1
            ]

        local link_ok = false
        local link_err = nil

        if relation.attachment == "free" then
            link_ok, link_err =
                PCL151132AttachFreeChild(
                    parent,
                    child,
                    relation
                )
        else
            link_ok, link_err =
                attach_child_live_14(
                    parent,
                    relation.slot_native,
                    child
                )
        end

        if not link_ok then
            pcl1510_fail(
                "link local=" ..
                tostring(child_local) ..
                " parent=" ..
                tostring(relation.parent_local) ..
                " attachment=" ..
                tostring(relation.attachment) ..
                " slot=" ..
                tostring(relation.slot_native) ..
                ": " .. tostring(link_err)
            )
            return
        end

        if child_local == part_count - 1 or
           child_local % 10 == 0 then
            log("PREFAB15_10_LINK_PROGRESS=" ..
                tostring(child_local + 1) ..
                "/" ..
                tostring(part_count))
        end
    end

    local tree_count =
        live_tree_count_14(
            actors[1]
        )

    log("PREFAB15_10_DIRECT_TREE_COUNT=" ..
        tostring(tree_count) ..
        " expected=" ..
        tostring(part_count))

    if tree_count ~= part_count then
        pcl1510_fail(
            "direct live tree count mismatch"
        )
        return
    end

    -- Attach the real prefab root below the permanent EmptyActor sentinel.
    local sentinel_add_ok,
          sentinel_add_err =
        pcall(function()
            sentinel.SlotChildParts:Add(
                0,
                actors[1]
            )
        end)

    if not sentinel_add_ok then
        pcl1510_fail(
            "sentinel slot0 add: " ..
            tostring(sentinel_add_err)
        )
        return
    end

    log("PREFAB15_10_SENTINEL_SLOT0_ADDED=true")

    -- This is the native allocator. The Phase 15.9.3 one-part proof proved
    -- that real children below the sentinel are appended to AppliedSwordParts.
    local serialize_ok,
          serialize_err =
        pcall(function()
            forge:SerializeSwordPartActorsToData()
        end)

    if not serialize_ok then
        pcl1510_fail(
            "SerializeSwordPartActorsToData: " ..
            tostring(serialize_err)
        )
        return
    end

    local forge2,
          piece2,
          design2,
          state_err2 =
        state_no_serialize_11()

    if state_err2 then
        pcl1510_fail(state_err2)
        return
    end

    local serialized_count = -1
    local root_native = -1

    pcall(function()
        serialized_count =
            #design2.AppliedSwordParts

        root_native =
            design2.RootSwordPartIdx
    end)

    log("PREFAB15_10_SERIALIZED count=" ..
        tostring(serialized_count) ..
        " root_native=" ..
        tostring(root_native))

    if serialized_count ~= part_count then
        pcl1510_fail(
            "serialized part count mismatch expected=" ..
            tostring(part_count) ..
            " actual=" ..
            tostring(serialized_count)
        )
        return
    end

    -- Phase 15.11.62 wrapper-lifetime hardening. 15.11.61 died immediately
    -- after PREFAB15_10_SERIALIZED, before the first native-map marker. The
    -- old path captured all 3316 FAppliedSwordPart wrappers into a long-lived
    -- Lua table. Snapshot only integer child indices into plain Lua tables,
    -- then stream actual struct wrappers exactly once for saved-field apply.
    log("PCL15_11_62_GRAPH_SNAPSHOT_BEGIN count=" .. tostring(serialized_count))

    local serialized_graph = {}
    local graph_nodes = 0
    local graph_ok, graph_err = pcall(function()
        design2.AppliedSwordParts:ForEach(function(lua_index, elem)
            local native_index = lua_index - 1
            local part = elem:get()
            local node = { slots = {}, free = {} }

            if part ~= nil and part.SlotChildren ~= nil then
                part.SlotChildren:ForEach(function(lua_slot, child_elem)
                    local v = child_elem:get()
                    if v ~= nil and tonumber(v) ~= nil and tonumber(v) >= 0 then
                        node.slots[lua_slot - 1] = tonumber(v)
                    end
                end)
            end

            if part ~= nil and part.FreeChildren ~= nil then
                part.FreeChildren:ForEach(function(lua_free, child_elem)
                    local data = child_elem:get()
                    local v = data and data.Idx or nil
                    if v ~= nil and tonumber(v) ~= nil and tonumber(v) >= 0 then
                        node.free[lua_free - 1] = tonumber(v)
                    end
                end)
            end

            serialized_graph[native_index] = node
            graph_nodes = graph_nodes + 1
        end)
    end)

    if not graph_ok then
        pcl1510_fail("15.11.62 graph snapshot: " .. tostring(graph_err))
        return
    end

    log("PCL15_11_62_GRAPH_SNAPSHOT_END nodes=" .. tostring(graph_nodes) ..
        " expected=" .. tostring(part_count))

    if graph_nodes ~= part_count then
        pcl1510_fail("15.11.62 graph snapshot count mismatch expected=" ..
            tostring(part_count) .. " actual=" .. tostring(graph_nodes))
        return
    end

    local local_to_native = {}
    local_to_native[1] = root_native
    local pending = part_count - 1
    local passes = 0
    while pending > 0 and passes < part_count do
        passes = passes + 1
        local progressed = false
        for child_local = 1, part_count - 1 do
            if local_to_native[child_local + 1] == nil then
                local relation = relations[child_local + 1]
                local parent_native = relation and local_to_native[relation.parent_local + 1] or nil
                if parent_native ~= nil then
                    local parent_node = serialized_graph[parent_native]
                    local child_native = nil
                    if parent_node ~= nil and relation.attachment == "free" then
                        child_native = parent_node.free[relation.free_ordinal]
                    elseif parent_node ~= nil then
                        child_native = parent_node.slots[relation.slot_native]
                    end
                    if child_native ~= nil then
                        local_to_native[child_local + 1] = child_native
                        pending = pending - 1
                        progressed = true
                    end
                end
            end
        end
        if not progressed then break end
    end

    local map_source = "serialized_mixed_graph_plain_snapshot"
    if pending > 0 then
        map_source = "actor_match_fallback"
        local _, mapped_actors, map_err = build_actor_map_10(design2, nil)
        if mapped_actors == nil then
            pcl1510_fail("post-serialize actor map: " .. tostring(map_err))
            return
        end
        local native_by_name = {}
        for native_i, actor in pairs(mapped_actors) do
            if is_valid(actor) then native_by_name[safe_full_name(actor)] = native_i end
        end
        for local_i = 0, part_count - 1 do
            local native = native_by_name[safe_full_name(actors[local_i + 1])]
            if native == nil then
                pcl1510_fail("could not map serialized direct actor local=" .. tostring(local_i))
                return
            end
            local_to_native[local_i + 1] = native
        end
    end

    log("PCL15_11_17_NATIVE_MAP_SOURCE=" .. tostring(map_source) ..
        " passes=" .. tostring(passes) .. " pending=" .. tostring(pending))

    pcl11_session = {
        base_count = 0,
        parts = parts,
        relations = relations,
        local_to_native = local_to_native,
        native_parts = nil,
        resolved_by_local = PCL151117_CACHE and PCL151117_CACHE.resolved_by_local or nil
    }

    local native_to_local = {}
    local validate_unique = {}
    local validate_unique_count = 0
    for local_i = 0, part_count - 1 do
        local native_i = local_to_native[local_i + 1]
        if native_i ~= nil then
            native_to_local[native_i] = local_i
            if validate_unique[native_i] == nil then
                validate_unique[native_i] = true
                validate_unique_count = validate_unique_count + 1
            end
        end
    end

    log("PREFAB15_10_APPLY_BEGIN")
    log("PCL15_11_62_APPLY_STREAM_BEGIN expected=" .. tostring(part_count))

    local applied_count = 0
    local validate_identity_count = 0
    local validate_edge_count = 0
    local apply_all_ok, apply_all_err = pcall(function()
        design2.AppliedSwordParts:ForEach(function(lua_index, elem)
            local native_i = lua_index - 1
            local local_i = native_to_local[native_i]
            if local_i ~= nil then
                local target = elem:get()
                local apply_ok, apply_err = apply_saved_part_11(local_i, native_i, target)
                if not apply_ok then
                    error("apply local=" .. tostring(local_i) .. " native=" .. tostring(native_i) .. ": " .. tostring(apply_err))
                end

                applied_count = applied_count + 1
                local saved = parts[local_i + 1]
                if safe_name(target.SwordPart) == tostring(saved.sword_part) and
                   safe_name(target.SwordMaterial) == tostring(saved.material) then
                    validate_identity_count = validate_identity_count + 1
                end

                if target.SlotChildren ~= nil then
                    target.SlotChildren:ForEach(function(kp, vp)
                        local v = vp:get()
                        if v ~= nil and tonumber(v) ~= nil and tonumber(v) >= 0 then
                            validate_edge_count = validate_edge_count + 1
                        end
                    end)
                end
                if target.FreeChildren ~= nil then
                    target.FreeChildren:ForEach(function(kp, vp)
                        local data = vp:get()
                        local v = data and data.Idx or nil
                        if v ~= nil and tonumber(v) ~= nil and tonumber(v) >= 0 then
                            validate_edge_count = validate_edge_count + 1
                        end
                    end)
                end

                if local_i == part_count - 1 or (local_i + 1) % 10 == 0 then
                    log("PREFAB15_10_APPLY_PROGRESS=" .. tostring(local_i + 1) .. "/" .. tostring(part_count))
                end
            end
        end)
    end)

    if not apply_all_ok then
        pcl11_session = nil
        pcl1510_fail("15.11.62 streamed apply: " .. tostring(apply_all_err))
        return
    end

    log("PCL15_11_62_APPLY_STREAM_END applied=" .. tostring(applied_count) ..
        " expected=" .. tostring(part_count))

    log('PCL15_11_18_PRESEAM_VALIDATE unique=' .. tostring(validate_unique_count) ..
        ' identities=' .. tostring(validate_identity_count) ..
        ' edges=' .. tostring(validate_edge_count) ..
        ' expected_parts=' .. tostring(part_count) ..
        ' expected_edges=' .. tostring(part_count - 1))

    if applied_count ~= part_count or
       validate_unique_count ~= part_count or
       validate_identity_count ~= part_count or
       validate_edge_count ~= part_count - 1 then
        pcl11_session = nil
        pcl1510_fail('15.11.62 streamed data-only design validation failed')
        return
    end

    pcl11_session = nil

    -- The serializer created this design in the current build, while the PCL
    -- payload may have been exported before a game data update.  Prevent the
    -- native rebuild from treating our already-resolved state as a legacy
    -- WeaponDesignDefinition and running migrations over it.
    local version_ok, version_err =
        pcl15117_force_latest_design_version(design2)

    if not version_ok then
        pcl1510_fail(
            "design version compatibility: " ..
            tostring(version_err)
        )
        return
    end

    stop_all_camera_shakes_142()

    -- 15.11.60: 15.11.59 proved that calling the reflected AForgeMode:SetStage
    -- transition here is unsafe in this fully populated data-only staging state:
    -- UE4SS AV'd immediately after PRESEAM_VALIDATE, before the native seam.
    -- Do not call SetStage/NextStage here.  Keep the proven no-side-effect seam
    -- entry and diagnose the rebuilt actor's actual presentation attachment.
    log('PCL15_11_60_STAGE_TRANSITION_SKIPPED reason=15.11.59_reflected_SetStage_native_AV')

    pcall(function()
        forge2.bSupressFrontendUpdate =
            true
    end)

    log("PREFAB15_11_NATIVE_REBUILD_BEGIN mode=temp_forge_native_runtime_seam_bridge")

    local rebuild_start = os.clock()
    local rebuild_ok, rebuild_err =
        pcl1511_private_rebuild(
            forge2
        )
    local rebuild_ms =
        (os.clock() - rebuild_start) * 1000.0

    log(string.format(
        "PREFAB15_11_NATIVE_REBUILD_RETURNED ok=%s elapsed_ms=%.3f error=%s",
        tostring(rebuild_ok),
        rebuild_ms,
        tostring(rebuild_err)))

    if not rebuild_ok then
        pcl1510_fail(
            "private native rebuild: " ..
            tostring(rebuild_err)
        )
        return
    end

    -- The ForgeMode object itself was never replaced, so the rebuilt sword
    -- should normally be available immediately. Keep the existing zero-delay
    -- readiness retry only as a safety net; no fixed wait is introduced.
    pcl15104_context = {
        part_count = part_count,
        local_to_native = local_to_native,
        attempt = 0
    }

    local immediate_forge = find_forge()
    local immediate_done, immediate_reason =
        pcl15104_finish_handoff(immediate_forge, design2, "immediate")

    if immediate_done then
        return
    end

    log("PREFAB15_10_4_IMMEDIATE_NOT_READY reason=" .. tostring(immediate_reason))

    -- Only if required native objects are genuinely unavailable do we yield.
    -- Hide rebuilt sword actors before yielding so no hardpoint flash is visible.
    pcl15104_hide_live_rebuild()
    schedule_game_11(0, pcl15104_retry_ready_state)
end



-- ============================================================
-- Phase 15.11.13: TEMP FORGEMODE NATIVE REBUILD HOST
-- ============================================================
--
-- Phase 15.11.12 proved the current runtime seam at RVA 0x45B02F0 can
-- rebuild the complete prefab synchronously, but calling it on the already
-- active ForgeMode replaces/rebinds that ForgeMode's lifecycle objects.
-- The resulting tree was correct (50/50) yet a later native callback crashed.
--
-- This build keeps the player's active ForgeMode/frontend/handling untouched.
-- A second hidden ForgeMode of the exact same class is spawned only as a
-- native reconstruction host.  The populated live Piece is assigned to that
-- host, the proven seam is called there, and only the rebuilt sword tree is
-- transferred to the ORIGINAL active handling component.
--
-- The temporary ForgeMode is deliberately retained alive and inert after
-- handoff.  Destroying it could invalidate delegates registered by the native
-- seam; lifetime cleanup is deferred until this architecture is proven.

PCL151113_TEMP_FORGE = nil
PCL151113_TEMP_SENTINEL = nil
PCL151113_TEMP_FRONTEND = nil
PCL151113_ACTIVE_FORGE = nil
PCL151113_ACTIVE_SENTINEL = nil
PCL151113_ACTIVE_FRONTEND = nil
PCL151113_ACTIVE_HANDLING = nil
PCL151113_SOURCE_ROOT = nil
PCL151113_REBUILT_ROOT = nil
PCL151113_GAME_MODE = nil

function pcl151113_obj_addr(obj)
    return pcl151112_addr(obj)
end

function pcl151113_get_frontend(forge)
    if not is_valid(forge) then return nil end
    local frontend = nil
    pcall(function() frontend = forge.ForgeModeFrontend end)
    return frontend
end

function pcl151113_set_actor_inert(actor, hidden)
    if not is_valid(actor) then return end
    pcall(function() actor:SetActorHiddenInGame(hidden and true or false) end)
    pcall(function() actor:SetActorTickEnabled(false) end)
    pcall(function() actor:SetActorEnableCollision(false) end)
end

function pcl151113_disable_component(component)
    if not is_valid(component) then return end
    pcall(function() component:SetComponentTickEnabled(false) end)
    pcall(function() component:SetActive(false, false) end)
end

function pcl151113_set_tree_hidden(root, hidden)
    if not is_valid(root) then return 0 end
    local seen = {}
    local count = 0

    local function walk(actor)
        if not is_valid(actor) then return end
        local key = safe_full_name(actor)
        if seen[key] then return end
        seen[key] = true
        count = count + 1
        pcall(function() actor:SetActorHiddenInGame(hidden and true or false) end)

        local slots = nil
        pcall(function() slots = actor.SlotChildParts end)
        if slots ~= nil then
            pcall(function()
                slots:ForEach(function(_, vp)
                    local child = vp:get()
                    if is_valid(child) then walk(child) end
                end)
            end)
        end

        local free = nil
        pcall(function() free = actor.FreeChildParts end)
        if free ~= nil then
            pcall(function()
                free:ForEach(function(kp, _)
                    local child = kp:get()
                    if is_valid(child) then walk(child) end
                end)
            end)
        end
    end

    walk(root)
    return count
end

function pcl151113_restore_game_mode_forge(gm, active_forge, label)
    if not is_valid(gm) or not is_valid(active_forge) then return end
    local before = nil
    pcall(function() before = gm.ForgeMode end)
    local before_addr = pcl151113_obj_addr(before)
    local active_addr = pcl151113_obj_addr(active_forge)
    local restored = false
    local restore_err = nil
    if before_addr ~= active_addr then
        local ok, err = pcall(function() gm.ForgeMode = active_forge end)
        restored = ok
        restore_err = err
    end
    local after = nil
    pcall(function() after = gm.ForgeMode end)
    log(string.format(
        'PCL15_11_13_GAMEMODE_FORGE_%s before=0x%X active=0x%X after=0x%X restored=%s error=%s',
        tostring(label), before_addr, active_addr, pcl151113_obj_addr(after),
        tostring(restored), tostring(restore_err)))
end

function pcl151113_spawn_temp_forge(active_forge, piece)
    local gameplay = gameplay_statics_15()
    if not is_valid(gameplay) then
        return nil, nil, 'GameplayStatics unavailable'
    end

    local gm = find_creative_game_mode_6()
    if not is_valid(gm) then
        return nil, nil, 'Creative GameMode unavailable'
    end

    local forge_class = nil
    pcall(function() forge_class = active_forge:GetClass() end)
    if not is_valid(forge_class) then
        pcall(function() forge_class = gm.ForgeModeClass end)
    end
    if not is_valid(forge_class) then
        return nil, gm, 'ForgeMode class unavailable'
    end

    local transform = neutral_spawn_transform_153()
    pcall(function()
        local current = active_forge:GetActorTransform()
        if current ~= nil then transform = current end
    end)

    local deferred = nil
    local begin_ok, begin_err = pcall(function()
        deferred = gameplay:BeginDeferredActorSpawnFromClass(
            active_forge,
            forge_class,
            transform,
            1,
            nil,
            2
        )
    end)
    pcl151731_fresh(deferred)
    if not begin_ok or not is_valid(deferred) then
        return nil, gm, 'temp ForgeMode BeginDeferred failed: ' .. tostring(begin_err)
    end

    -- Suppress/disable before construction finishes so the temporary host has
    -- the least possible visible/frontend impact.
    pcall(function() deferred.bSupressFrontendUpdate = true end)
    pcl151113_set_actor_inert(deferred, true)

    pcl151757_track_temp(deferred,active_forge)
    local temp = nil
    local finish_ok, finish_err = pcall(function()
        temp = gameplay:FinishSpawningActor(deferred, transform, 2)
    end)
    if not finish_ok or not is_valid(temp) then
        pcall(function() deferred:K2_DestroyActor() end)
        return nil, gm, 'temp ForgeMode FinishSpawning failed: ' .. tostring(finish_err)
    end

    pcall(function() temp.bSupressFrontendUpdate = true end)
    pcl151113_set_actor_inert(temp, true)

    -- If the Blueprint's BeginPlay registered itself as the GameMode's active
    -- ForgeMode, immediately restore the real player ForgeMode.
    pcl151113_restore_game_mode_forge(gm, active_forge, 'AFTER_SPAWN')

    -- Match the normal precondition seen at the native seam call-site.
    local piece_write_ok, piece_write_err = pcall(function() temp.Piece = piece end)
    local temp_piece = nil
    pcall(function() temp_piece = temp:GetPiece() end)
    if not piece_write_ok or pcl151113_obj_addr(temp_piece) ~= pcl151113_obj_addr(piece) then
        return nil, gm, 'temp ForgeMode Piece bind failed: ' .. tostring(piece_write_err)
    end

    PCL151730_HOST_REGISTRY=PCL151730_HOST_REGISTRY or {}
    PCL151730_HOST_REGISTRY[temp:GetAddress()]=temp
    log(string.format(
        'PCL15_11_13_TEMP_FORGE_SPAWNED active=0x%X temp=0x%X class=%s piece=0x%X same=false suppressed=true hidden=true',
        pcl151113_obj_addr(active_forge), pcl151113_obj_addr(temp),
        safe_full_name(forge_class), pcl151113_obj_addr(piece)))

    return temp, gm, nil
end

function pcl151113_make_temp_inert(temp)
    if not is_valid(temp) then return end
    pcall(function() temp.bSupressFrontendUpdate = true end)
    pcl151113_set_actor_inert(temp, true)

    local sentinel = nil
    local frontend = nil
    pcall(function() sentinel = temp:GetRootSwordPartActor() end)
    pcall(function() frontend = temp.ForgeModeFrontend end)
    pcl151113_set_actor_inert(sentinel, true)
    pcl151113_set_actor_inert(frontend, true)

    local handling = nil
    local camera = nil
    if is_valid(frontend) then
        pcall(function() handling = frontend.SwordPartHandling end)
        pcall(function() camera = frontend.CameraHandling end)
    end
    pcl151113_disable_component(handling)
    pcl151113_disable_component(camera)

    log(string.format(
        'PCL15_11_13_TEMP_INERT temp=0x%X sentinel=0x%X frontend=0x%X handling=0x%X camera=0x%X retained=true',
        pcl151113_obj_addr(temp), pcl151113_obj_addr(sentinel),
        pcl151113_obj_addr(frontend), pcl151113_obj_addr(handling),
        pcl151113_obj_addr(camera)))
end

-- Phase 15.11.38: PCL direct-seam optimization activation + profiling.
-- The 15.11.27 native profiler already contains the proven >=512-part child
-- transform refresh deferral. Magic Word DownloadPiece arms that profiler, but
-- the PCL direct bridge previously did not, so direct imports paid the stock
-- per-link recursive refresh cost. Arm only around the synchronous PCL seam;
-- this both enables the existing optimization and records its native timings.
function pcl151138_direct_native_arm(part_count)
    part_count = tonumber(part_count) or 0
    if part_count < 512 then
        log('PCL15_11_38_DIRECT_NATIVE_ARM skipped=true reason=below_threshold parts=' .. tostring(part_count))
        return false
    end
    if PCLMWNATIVE == nil or not PCLMWNATIVE.installed or
       type(PCLMWNATIVE.arm) ~= 'function' or type(PCLMWNATIVE.read) ~= 'function' then
        log('PCL15_11_38_DIRECT_NATIVE_ARM skipped=true reason=profiler_unavailable parts=' .. tostring(part_count))
        return false
    end
    if PCLMWNATIVE.active then
        log('PCL15_11_38_DIRECT_NATIVE_ARM skipped=true reason=profiler_busy parts=' .. tostring(part_count))
        return false
    end

    -- Phase 15.11.40/43: explicit PCL direct seams still request the borrowed-array
    -- walker here because they intentionally bypass EnterForgeMode. Normal Creative
    -- and Magic Word loads now activate the same fast path just-in-time inside the
    -- native EnterForgeMode hook.
    local alias_ok, alias_status = false, -998
    if type(PCLMWNATIVE.alias_on) == 'function' then
        alias_ok, alias_status = pcall(PCLMWNATIVE.alias_on)
        alias_status = tonumber(alias_status) or -999
    end
    log(string.format(
        'PCL15_11_40_ARRAY_ALIAS_REQUEST parts=%d eligible=true ok=%s status=%d exact_byte_guarded=true scope=pcl_direct_seam',
        part_count, tostring(alias_ok), alias_status))

    PCLMWNATIVE.run = (PCLMWNATIVE.run or 0) + 1
    local ok, status = pcall(PCLMWNATIVE.arm)
    status = tonumber(status) or -999
    local armed = ok and status == 1
    if not armed and type(PCLMWNATIVE.alias_off) == 'function' then
        pcall(PCLMWNATIVE.alias_off)
    end
    log(string.format(
        'PCL15_11_38_DIRECT_NATIVE_ARM run=%d parts=%d threshold=512 ok=%s status=%d deferred_refresh_enabled=%s',
        PCLMWNATIVE.run, part_count, tostring(ok), status, tostring(armed)))
    return armed
end

function pcl151138_direct_native_finish(part_count, armed)
    if not armed then return end
    local r = {pcall(PCLMWNATIVE.read)}
    local disarm_ok, disarm_status = pcall(PCLMWNATIVE.disarm)
    disarm_status = tonumber(disarm_status) or -999
    log(string.format(
        'PCL15_11_40_ARRAY_ALIAS_RESTORE ok=%s status=%d restored=%s',
        tostring(disarm_ok), disarm_status, tostring(disarm_ok and disarm_status == 1)))
    if not r[1] then
        log('PCL15_11_38_DIRECT_NATIVE_PROFILE_ERROR=' .. tostring(r[2]))
        return
    end

    local seam_count = tonumber(r[5]) or 0
    local seam_us = tonumber(r[8]) or 0
    local child_a_count, child_a_us = tonumber(r[10]) or 0, tonumber(r[11]) or 0
    local child_b_count, child_b_us = tonumber(r[12]) or 0, tonumber(r[13]) or 0
    local child_c_count, child_c_us = tonumber(r[14]) or 0, tonumber(r[15]) or 0
    local child_d_count, child_d_us = tonumber(r[16]) or 0, tonumber(r[17]) or 0
    local child_e_count, child_e_us = tonumber(r[18]) or 0, tonumber(r[19]) or 0
    local applied_count = tonumber(r[20]) or 0
    local copy_calls, copy_elements, copy_us = tonumber(r[22]) or 0, tonumber(r[23]) or 0, tonumber(r[24]) or 0
    local clone_alloc_calls, clone_alloc_us = tonumber(r[25]) or 0, tonumber(r[26]) or 0
    local clone_destroy_calls, clone_destroy_us = tonumber(r[27]) or 0, tonumber(r[28]) or 0
    local actor_make_calls, actor_make_us = tonumber(r[29]) or 0, tonumber(r[30]) or 0
    local actor_link_calls, actor_link_us = tonumber(r[31]) or 0, tonumber(r[32]) or 0
    local threshold = tonumber(r[33]) or 0
    local deferred_calls, final_calls, final_us = tonumber(r[34]) or 0, tonumber(r[35]) or 0, tonumber(r[36]) or 0
    local notify_calls, notify_us = tonumber(r[38]) or 0, tonumber(r[39]) or 0
    local map_calls, map_us = tonumber(r[40]) or 0, tonumber(r[41]) or 0
    local spawn_calls, spawn_us = tonumber(r[42]) or 0, tonumber(r[43]) or 0
    local resolve_calls, resolve_us = tonumber(r[44]) or 0, tonumber(r[45]) or 0
    local data_calls, data_us = tonumber(r[46]) or 0, tonumber(r[47]) or 0
    local alias_requested = tonumber(r[48]) or 0
    local alias_active = tonumber(r[49]) or 0
    local alias_patch_status = tonumber(r[50]) or 0
    local alias_enable_count = tonumber(r[51]) or 0
    -- 15.11.49 append-only actor_make helper fields from native read().
    local make_h1_calls, make_h1_us = tonumber(r[65]) or 0, tonumber(r[66]) or 0
    local make_h2_calls, make_h2_us = tonumber(r[67]) or 0, tonumber(r[68]) or 0
    local make_h3_calls, make_h3_us = tonumber(r[69]) or 0, tonumber(r[70]) or 0
    local make_h4_calls, make_h4_us = tonumber(r[71]) or 0, tonumber(r[72]) or 0
    local make_params_calls, make_params_us = tonumber(r[73]) or 0, tonumber(r[74]) or 0
    local known_us = child_a_us + child_b_us + child_c_us + child_d_us + child_e_us
    local unclassified_us = seam_us - known_us
    if unclassified_us < 0 then unclassified_us = 0 end

    log(string.format(
        'PCL15_11_40_ARRAY_ALIAS_RESULT requested=%d active=%d patch_status=%d enable_count=%d copy_calls=%d copy_elements=%d clone_destroy_calls=%d',
        alias_requested, alias_active, alias_patch_status, alias_enable_count,
        copy_calls, copy_elements, clone_destroy_calls))
    log(string.format(
        'PCL15_11_38_NATIVE_PROFILE parts=%d applied=%d seam_count=%d seam_us=%d childA[count=%d us=%d] childB[count=%d us=%d] childC[count=%d us=%d] childD[count=%d us=%d] childE[count=%d us=%d] known_us=%d unclassified_us=%d',
        tonumber(part_count) or 0, applied_count, seam_count, seam_us,
        child_a_count, child_a_us, child_b_count, child_b_us,
        child_c_count, child_c_us, child_d_count, child_d_us,
        child_e_count, child_e_us, known_us, unclassified_us))
    log(string.format(
        'PCL15_11_38_DEFER_RESULT threshold=%d eligible=%s deferred_refresh_calls=%d final_refresh_calls=%d final_refresh_us=%d',
        threshold, tostring(applied_count >= threshold and threshold > 0), deferred_calls, final_calls, final_us))
    log(string.format(
        'PCL15_11_38_COST_PROFILE copy[count=%d elements=%d us=%d] clone_alloc[count=%d us=%d] clone_destroy[count=%d us=%d] actor_make[count=%d us=%d] actor_link[count=%d us=%d]',
        copy_calls, copy_elements, copy_us, clone_alloc_calls, clone_alloc_us,
        clone_destroy_calls, clone_destroy_us, actor_make_calls, actor_make_us,
        actor_link_calls, actor_link_us))
    log(string.format(
        'PCL15_11_38_DEEP_PROFILE link_notify[count=%d us=%d] link_map[count=%d us=%d] actor_spawn[count=%d us=%d] actor_resolve[count=%d us=%d] actor_data[count=%d us=%d]',
        notify_calls, notify_us, map_calls, map_us, spawn_calls, spawn_us,
        resolve_calls, resolve_us, data_calls, data_us))
    local make_known_us = spawn_us + resolve_us + data_us + make_h1_us + make_h2_us + make_h3_us + make_h4_us + make_params_us
    local make_residual_us = actor_make_us - make_known_us
    if make_residual_us < 0 then make_residual_us = 0 end
    log(string.format(
        'PCL15_11_49_ACTOR_MAKE_PROFILE scope=pcl_direct actor_make[count=%d us=%d] spawn_us=%d resolve_us=%d data_us=%d H1[rva=0x45F9759 count=%d us=%d] H2[rva=0x45F8720 count=%d us=%d] H3[rva=0x45F8770 count=%d us=%d] H4[rva=0x45F8080 count=%d us=%d] PARAMS[rva=0x3EEC910 count=%d us=%d] known_nonoverlap_us=%d residual_us=%d',
        actor_make_calls, actor_make_us, spawn_us, resolve_us, data_us,
        make_h1_calls, make_h1_us, make_h2_calls, make_h2_us,
        make_h3_calls, make_h3_us, make_h4_calls, make_h4_us,
        make_params_calls, make_params_us, make_known_us, make_residual_us))
end

-- ============================================================================
-- Phase 15.11.60 - PASSIVE PRESENTATION / ATTACHMENT AUDIT
--
-- No reflected Forge state-machine calls are made here.  This only reads the
-- rebuilt actor/component state so a real native catalogue preview can be
-- compared against the PCL result without another blind pickup/stage mutation.
-- ============================================================================

function pcl151160_presentation_audit(actor, label)
    label = tostring(label or 'unknown')
    if not is_valid(actor) then
        log('PCL15_11_60_PRESENTATION_AUDIT label=' .. label .. ' actor=None')
        return
    end

    local pending, actor_hidden = '?', '?'
    local root, root_parent, proc, proc_parent = nil, nil, nil, nil
    local root_visible, root_hidden = '?', '?'
    local proc_visible, proc_hidden = '?', '?'
    local rel_loc, rel_rot, rel_scale = nil, nil, nil

    pcall(function() pending = tostring(actor.bPending) end)
    pcall(function() actor_hidden = tostring(actor.bHidden) end)
    pcall(function() root = actor.RootComponent end)
    pcall(function() proc = actor.ProceduralMeshComponent end)

    if is_valid(root) then
        pcall(function() root_parent = root.AttachParent end)
        pcall(function() root_visible = tostring(root.bVisible) end)
        pcall(function() root_hidden = tostring(root.bHiddenInGame) end)
        pcall(function() rel_loc = root.RelativeLocation end)
        pcall(function() rel_rot = root.RelativeRotation end)
        pcall(function() rel_scale = root.RelativeScale3D end)
    end
    if is_valid(proc) then
        pcall(function() proc_parent = proc.AttachParent end)
        pcall(function() proc_visible = tostring(proc.bVisible) end)
        pcall(function() proc_hidden = tostring(proc.bHiddenInGame) end)
    end

    log('PCL15_11_60_PRESENTATION_AUDIT' ..
        ' label=' .. label ..
        ' actor=0x' .. string.format('%X', pcl151113_obj_addr(actor)) ..
        ' pending=' .. tostring(pending) ..
        ' actor_hidden=' .. tostring(actor_hidden) ..
        ' root=0x' .. string.format('%X', pcl151113_obj_addr(root)) ..
        ' root_parent=' .. (is_valid(root_parent) and safe_full_name(root_parent) or 'None') ..
        ' root_visible=' .. tostring(root_visible) ..
        ' root_hidden=' .. tostring(root_hidden) ..
        ' proc=0x' .. string.format('%X', pcl151113_obj_addr(proc)) ..
        ' proc_parent=' .. (is_valid(proc_parent) and safe_full_name(proc_parent) or 'None') ..
        ' proc_visible=' .. tostring(proc_visible) ..
        ' proc_hidden=' .. tostring(proc_hidden) ..
        ' root_rel_loc=' .. fmt_vec3_157(rel_loc) ..
        ' root_rel_rot=' .. fmt_rotator_157(rel_rot) ..
        ' root_rel_scale=' .. fmt_vec3_157(rel_scale))

end

-- ============================================================================
-- Phase 15.11.61 - DETACH REBUILT ROOT FROM TEMP SENTINEL SCENE HIERARCHY
--
-- 15.11.60 proved that removing temp_sentinel.SlotChildParts[0] only unlinks
-- Bladesong's logical construction relation. The rebuilt actor's RootComponent
-- remains attached to the temporary SwordPartEmptyActor SceneComponent, which
-- is subsequently hidden/quarantined. Detach the ACTOR scene root with
-- KeepWorld rules before handing the full tree to the live SwordPartHandling.
-- ============================================================================

function pcl151161_detach_rebuilt_root_scene(actor)
    if not is_valid(actor) then
        return false, 'rebuilt actor invalid for scene detach'
    end

    local root = nil
    local parent_before = nil
    pcall(function() root = actor.RootComponent end)
    if not is_valid(root) then
        return false, 'rebuilt actor RootComponent unavailable for scene detach'
    end
    pcall(function() parent_before = root.AttachParent end)

    if not is_valid(parent_before) then
        log('PCL15_11_61_TEMP_SCENE_DETACH ok=true method=already_detached keep_world=true parent_before=None parent_after=None')
        return true, nil
    end

    local method = 'K2_DetachFromActor'
    local detach_ok, detach_err = pcall(function()
        -- EDetachmentRule::KeepWorld = 1 for location/rotation/scale.
        actor:K2_DetachFromActor(1, 1, 1)
    end)

    -- Engine-level fallback only if the Actor wrapper is unavailable. This is
    -- still a pure scene detach; it never calls SwordPart reset/dissolve logic.
    if not detach_ok then
        method = 'K2_DetachFromComponent'
        detach_ok, detach_err = pcall(function()
            root:K2_DetachFromComponent(1, 1, 1, false)
        end)
    end

    local parent_after = nil
    pcall(function() parent_after = root.AttachParent end)

    log('PCL15_11_61_TEMP_SCENE_DETACH' ..
        ' ok=' .. tostring(detach_ok and not is_valid(parent_after)) ..
        ' method=' .. tostring(method) ..
        ' keep_world=true' ..
        ' parent_before=' .. (is_valid(parent_before) and safe_full_name(parent_before) or 'None') ..
        ' parent_after=' .. (is_valid(parent_after) and safe_full_name(parent_after) or 'None') ..
        ' error=' .. tostring(detach_err))

    if not detach_ok then
        return false, 'scene detach call failed: ' .. tostring(detach_err)
    end
    if is_valid(parent_after) then
        return false, 'scene detach returned but rebuilt root is still attached to ' .. safe_full_name(parent_after)
    end

    return true, nil
end

-- ============================================================================
-- Phase 15.11.59 - REAL Forge stage transition before private rebuild
--
-- 15.11.58 proved that a full 3316-part root can be written to the correct
-- active SwordPartHandling and still be invisible/not actually held when the
-- Piece began in stage 0.  The older visually-working 15.11.42 run entered the
-- seam already in stage 1.  Do not emulate that state by poking the enum.
-- Drive AForgeMode through its reflected SetStage/NextStage transition so the
-- frontend/handling state associated with stage 1 is initialized by Bladesong.
-- ============================================================================

function pcl151159_real_stage_transition(forge, expected_parts)
    if not is_valid(forge) then return false, 'active ForgeMode invalid for real stage transition', forge end

    local forge_before_addr = pcl151113_obj_addr(forge)
    local piece_before = nil
    local stage_before = -1
    pcall(function() piece_before = forge:GetPiece() end)
    pcall(function()
        if is_valid(piece_before) then
            stage_before = tonumber(piece_before.CurrentSwordmakingStage) or -1
        end
    end)

    local method = 'already_stage1'
    local call_ok = true
    local call_err = nil

    if stage_before == 0 then
        method = 'SetStage'
        call_ok, call_err = pcall(function() forge:SetStage(1) end)
    elseif stage_before ~= 1 then
        call_ok = false
        call_err = 'unexpected starting stage ' .. tostring(stage_before)
    end

    -- SetStage is synchronous in the reflected Forge API, but it is allowed to
    -- replace GameMode.ForgeMode. Always resolve the authoritative player Forge
    -- again before checking the result.
    local authoritative = find_forge()
    if not is_valid(authoritative) then authoritative = forge end

    local piece_after = nil
    local stage_after = -1
    pcall(function() piece_after = authoritative:GetPiece() end)
    pcall(function()
        if is_valid(piece_after) then
            stage_after = tonumber(piece_after.CurrentSwordmakingStage) or -1
        end
    end)

    -- Fail over to Bladesong's own NextStage transition only when SetStage was
    -- unavailable/refused or did not actually enter stage 1. Never raw-write
    -- CurrentSwordmakingStage in this path.
    local next_ok = nil
    local next_err = nil
    if stage_before == 0 and (not call_ok or stage_after ~= 1) then
        method = 'NextStage'
        next_ok, next_err = pcall(function() authoritative:NextStage() end)
        call_ok = next_ok
        call_err = next_err
        local refreshed = find_forge()
        if is_valid(refreshed) then authoritative = refreshed end
        pcall(function() piece_after = authoritative:GetPiece() end)
        pcall(function()
            if is_valid(piece_after) then
                stage_after = tonumber(piece_after.CurrentSwordmakingStage) or -1
            end
        end)
    end

    local frontend_after = pcl151113_get_frontend(authoritative)
    local handling_after = nil
    if is_valid(frontend_after) then
        pcall(function() handling_after = frontend_after.SwordPartHandling end)
    end

    local design_parts = -1
    local source_tree = -1
    local sentinel_after = nil
    pcall(function()
        if is_valid(piece_after) then
            design_parts = #piece_after.WeaponDesignDefinition.AppliedSwordParts
        end
    end)
    pcall(function() sentinel_after = authoritative:GetRootSwordPartActor() end)
    if is_valid(sentinel_after) then
        source_tree = live_tree_count_14(pcl151112_first_slot_child(sentinel_after))
    end

    log(string.format(
        'PCL15_11_59_REAL_STAGE_TRANSITION before=%d method=%s call_ok=%s after=%d forge_before=0x%X forge_after=0x%X forge_same=%s piece_before=0x%X piece_after=0x%X frontend=0x%X handling=0x%X design_parts=%d source_tree=%d expected=%d error=%s',
        stage_before, tostring(method), tostring(call_ok), stage_after,
        forge_before_addr, pcl151113_obj_addr(authoritative),
        tostring(forge_before_addr == pcl151113_obj_addr(authoritative)),
        pcl151113_obj_addr(piece_before), pcl151113_obj_addr(piece_after),
        pcl151113_obj_addr(frontend_after), pcl151113_obj_addr(handling_after),
        design_parts, source_tree, tonumber(expected_parts) or -1, tostring(call_err)))

    if not call_ok or stage_after ~= 1 then
        return false, 'Bladesong real stage transition did not reach stage 1: ' .. tostring(call_err), authoritative
    end
    if not is_valid(frontend_after) or not is_valid(handling_after) then
        return false, 'active frontend/handling invalid after real stage transition', authoritative
    end
    if tonumber(expected_parts) and expected_parts > 0 then
        if design_parts ~= expected_parts or source_tree ~= expected_parts then
            return false, 'real stage transition changed staged prefab design/tree', authoritative
        end
    end

    return true, nil, authoritative
end

-- Override Phase 15.11.12's active-Forge seam call.  The native bridge is the
-- same guarded bridge; only its ForgeMode argument changes to a fresh host.
function pcl1511_private_rebuild(forge)
    if not is_valid(forge) then
        return false, 'active ForgeMode invalid'
    end

    local piece = nil
    local active_sentinel = nil
    local active_frontend = pcl151113_get_frontend(forge)
    local active_handling = nil
    pcall(function() piece = forge:GetPiece() end)
    pcall(function() active_sentinel = forge:GetRootSwordPartActor() end)
    if is_valid(active_frontend) then
        pcall(function() active_handling = active_frontend.SwordPartHandling end)
    end

    if not is_valid(piece) then return false, 'active Piece invalid' end
    if not is_valid(active_sentinel) then return false, 'active sentinel invalid' end
    if not is_valid(active_frontend) then return false, 'active frontend invalid before temp spawn' end
    if not is_valid(active_handling) then
        return false, 'active frontend SwordPartHandling invalid before temp spawn'
    end

    log(string.format(
        'PCL15_11_58_ACTIVE_HANDLING_OWNERSHIP forge=0x%X frontend=0x%X handling=0x%X source=active_frontend retained_temp_hosts=%d',
        pcl151113_obj_addr(forge), pcl151113_obj_addr(active_frontend),
        pcl151113_obj_addr(active_handling),
        (PCL151114_TEMP_HOSTS ~= nil and #PCL151114_TEMP_HOSTS or 0)))

    local source_root = pcl151112_first_slot_child(active_sentinel)
    local direct_json_mode = (PCL151165_DIRECT_JSON_MODE == true)
    if not is_valid(source_root) and not direct_json_mode then
        return false, 'direct prefab root unavailable below active sentinel'
    end
    if direct_json_mode then
        log('PCL15_11_65_SOURCELESS_REBUILD source_root=' ..
            (is_valid(source_root) and safe_full_name(source_root) or 'None') ..
            ' expected=None')
        if is_valid(source_root) then
            return false, 'direct JSON import requires empty active sentinel'
        end
    end

    local active_addr = pcl151113_obj_addr(forge)
    local piece_addr = pcl151113_obj_addr(piece)
    local active_sentinel_addr = pcl151113_obj_addr(active_sentinel)
    local active_frontend_addr = pcl151113_obj_addr(active_frontend)
    local active_handling_addr = pcl151113_obj_addr(active_handling)
    if active_addr == 0 or piece_addr == 0 then
        return false, 'UE4SS GetAddress unavailable for active ForgeMode/Piece'
    end

    local root_idx = -1
    local part_count = -1
    local blade_count = 0
    local get_num = -1
    local stage_before = -1
    local side_before = -1
    local read_ok, read_err = pcall(function()
        local d = piece.WeaponDesignDefinition
        root_idx = tonumber(d.RootSwordPartIdx) or -1
        part_count = #d.AppliedSwordParts
        blade_count = #d.BladeSwordParts
        get_num = piece:GetNumSwordParts()
        stage_before = tonumber(piece.CurrentSwordmakingStage) or -1
        side_before = tonumber(piece.CurrentSideEditingMode) or -1
    end)
    if not read_ok or root_idx < 0 or part_count < 1 or get_num ~= part_count then
        return false, 'active Piece state invalid before temp seam: ' .. tostring(read_err)
    end

    local temp, gm, spawn_err = pcl151113_spawn_temp_forge(forge, piece)
    if not is_valid(temp) then
        return false, 'temp ForgeMode spawn failed: ' .. tostring(spawn_err)
    end

    local native_call, load_err = pcl151112_get_native_call()
    if native_call == nil then
        return false, 'native bridge unavailable: ' .. tostring(load_err)
    end

    log(string.format(
        'PCL15_11_13_TEMP_DIRECT_SEAM_BEGIN active=0x%X temp=0x%X piece=0x%X source_root=0x%X root=%d parts=%d blade_parts=%d get_num=%d stage=%d side=%d active_frontend=0x%X active_handling=0x%X enter_forge_mode_calls=0 init_in_editor_calls=0',
        active_addr, pcl151113_obj_addr(temp), piece_addr,
        pcl151113_obj_addr(source_root), root_idx, part_count, blade_count, get_num,
        stage_before, side_before, active_frontend_addr, active_handling_addr))

    local direct_native_armed = pcl151138_direct_native_arm(part_count)
    local call_ok, status_or_err = pcall(function()
        return native_call(pcl151113_obj_addr(temp), piece_addr)
    end)
    pcl151138_direct_native_finish(part_count, direct_native_armed)

    local h4_scope = {
        install=-999, restore=-999, calls=-1, active=-1, stock=-1,
        unique=-1, repeats=-1, first_us=-1, repeat_us=-1,
        max_calls=-1, max_source=0, max_source_us=-1, null_sources=-1, overflow=-1,
        hot_source=0, hot_calls=-1, hot_us=-1, cap=-1, total_us=-1, qpc_ready=-1,
        profile_calls=-1, other_thread_calls=-1, fp_captured=-1, fp_validated=-1,
        fp_mismatch=-1, fp_guard_fail=-1, fp_checks=-1, fp_hash_us=-1,
        fp_index_bytes=-1, fp_vertex_bytes=-1, fp_mismatch_source=0, fp_mismatch_code=0,
        fp_geometry_validated=-1, fp_geometry_mismatch=-1, fp_bounds_only_mismatch=-1,
        fp_bounds_mismatch=-1, fp_index_num_mismatch=-1, fp_vertex_num_mismatch=-1,
        fp_index_hash_mismatch=-1, fp_vertex_hash_mismatch=-1,
        fp_geometry_mismatch_source=0, fp_geometry_mismatch_code=0,
        stable_sources=-1, unstable_sources=-1, unresolved_sources=-1,
        stable_post_calls=-1, stable_post_us=-1, unstable_post_calls=-1, unstable_post_us=-1,
        unresolved_repeat_calls=-1, unresolved_repeat_us=-1, hot_geometry_state=-1, max_geometry_state=-1,
        loop_install=-999, loop_restore=-999, loop_active=-1, loop_stock=-1,
        cache_promoted=-1, cache_rejected=-1, cache_late_demotions=-1,
        cache_fast_calls=-1, cache_fast_bytes=-1, cache_copy_us=-1, cache_mid_guard_fail=-1,
        cache_canary_calls=-1, cache_canary_mismatch=-1, cache_proof_checks=-1, cache_proof_us=-1,
        cache_arena_used=-1, cache_arena_cap=-1, cache_arena_rejects=-1,
        hot_cache_state=-1, max_cache_state=-1,
        post_install=-999, post_restore=-999, post_active=-1, post_stock=-1,
        post_vertex_copy_calls=-1, post_vertex_copy_us=-1, post_index_copy_calls=-1, post_index_copy_us=-1,
        post_component_build_calls=-1, post_component_build_us=-1, post_component_final_calls=-1, post_component_final_us=-1,
        post_profiled_us=-1,
        ut_tail_calls=-1, ut_tail_us=-1, ut_pre_calls=-1, ut_pre_us=-1,
        ut_dirty_calls=-1, ut_dirty_us=-1, ut_dispatch_calls=-1, ut_dispatch_us=-1,
        error=nil
    }
    pcall(function()
        local stats_fn, stats_err = pcl151169_get_h4_stats_call()
        if type(stats_fn) ~= 'function' then
            h4_scope.error = tostring(stats_err)
            return
        end
        local vals = {stats_fn()}
        h4_scope.install = tonumber(vals[1]) or -999
        h4_scope.restore = tonumber(vals[2]) or -999
        h4_scope.calls = tonumber(vals[3]) or -1
        h4_scope.active = tonumber(vals[4]) or -1
        h4_scope.stock = tonumber(vals[5]) or -1
        h4_scope.unique = tonumber(vals[6]) or -1
        h4_scope.repeats = tonumber(vals[7]) or -1
        h4_scope.first_us = tonumber(vals[8]) or -1
        h4_scope.repeat_us = tonumber(vals[9]) or -1
        h4_scope.max_calls = tonumber(vals[10]) or -1
        h4_scope.max_source = tonumber(vals[11]) or 0
        h4_scope.max_source_us = tonumber(vals[12]) or -1
        h4_scope.null_sources = tonumber(vals[13]) or -1
        h4_scope.overflow = tonumber(vals[14]) or -1
        h4_scope.hot_source = tonumber(vals[15]) or 0
        h4_scope.hot_calls = tonumber(vals[16]) or -1
        h4_scope.hot_us = tonumber(vals[17]) or -1
        h4_scope.cap = tonumber(vals[18]) or -1
        h4_scope.total_us = tonumber(vals[19]) or -1
        h4_scope.qpc_ready = tonumber(vals[20]) or -1
        h4_scope.profile_calls = tonumber(vals[21]) or -1
        h4_scope.other_thread_calls = tonumber(vals[22]) or -1
        h4_scope.fp_captured = tonumber(vals[23]) or -1
        h4_scope.fp_validated = tonumber(vals[24]) or -1
        h4_scope.fp_mismatch = tonumber(vals[25]) or -1
        h4_scope.fp_guard_fail = tonumber(vals[26]) or -1
        h4_scope.fp_checks = tonumber(vals[27]) or -1
        h4_scope.fp_hash_us = tonumber(vals[28]) or -1
        h4_scope.fp_index_bytes = tonumber(vals[29]) or -1
        h4_scope.fp_vertex_bytes = tonumber(vals[30]) or -1
        h4_scope.fp_mismatch_source = tonumber(vals[31]) or 0
        h4_scope.fp_mismatch_code = tonumber(vals[32]) or 0
        h4_scope.fp_geometry_validated = tonumber(vals[33]) or -1
        h4_scope.fp_geometry_mismatch = tonumber(vals[34]) or -1
        h4_scope.fp_bounds_only_mismatch = tonumber(vals[35]) or -1
        h4_scope.fp_bounds_mismatch = tonumber(vals[36]) or -1
        h4_scope.fp_index_num_mismatch = tonumber(vals[37]) or -1
        h4_scope.fp_vertex_num_mismatch = tonumber(vals[38]) or -1
        h4_scope.fp_index_hash_mismatch = tonumber(vals[39]) or -1
        h4_scope.fp_vertex_hash_mismatch = tonumber(vals[40]) or -1
        h4_scope.fp_geometry_mismatch_source = tonumber(vals[41]) or 0
        h4_scope.fp_geometry_mismatch_code = tonumber(vals[42]) or 0
        h4_scope.stable_sources = tonumber(vals[43]) or -1
        h4_scope.unstable_sources = tonumber(vals[44]) or -1
        h4_scope.unresolved_sources = tonumber(vals[45]) or -1
        h4_scope.stable_post_calls = tonumber(vals[46]) or -1
        h4_scope.stable_post_us = tonumber(vals[47]) or -1
        h4_scope.unstable_post_calls = tonumber(vals[48]) or -1
        h4_scope.unstable_post_us = tonumber(vals[49]) or -1
        h4_scope.unresolved_repeat_calls = tonumber(vals[50]) or -1
        h4_scope.unresolved_repeat_us = tonumber(vals[51]) or -1
        h4_scope.hot_geometry_state = tonumber(vals[52]) or -1
        h4_scope.max_geometry_state = tonumber(vals[53]) or -1
        h4_scope.loop_install = tonumber(vals[54]) or -999
        h4_scope.loop_restore = tonumber(vals[55]) or -999
        h4_scope.loop_active = tonumber(vals[56]) or -1
        h4_scope.loop_stock = tonumber(vals[57]) or -1
        h4_scope.cache_promoted = tonumber(vals[58]) or -1
        h4_scope.cache_rejected = tonumber(vals[59]) or -1
        h4_scope.cache_late_demotions = tonumber(vals[60]) or -1
        h4_scope.cache_fast_calls = tonumber(vals[61]) or -1
        h4_scope.cache_fast_bytes = tonumber(vals[62]) or -1
        h4_scope.cache_copy_us = tonumber(vals[63]) or -1
        h4_scope.cache_mid_guard_fail = tonumber(vals[64]) or -1
        h4_scope.cache_canary_calls = tonumber(vals[65]) or -1
        h4_scope.cache_canary_mismatch = tonumber(vals[66]) or -1
        h4_scope.cache_proof_checks = tonumber(vals[67]) or -1
        h4_scope.cache_proof_us = tonumber(vals[68]) or -1
        h4_scope.cache_arena_used = tonumber(vals[69]) or -1
        h4_scope.cache_arena_cap = tonumber(vals[70]) or -1
        h4_scope.cache_arena_rejects = tonumber(vals[71]) or -1
        h4_scope.hot_cache_state = tonumber(vals[72]) or -1
        h4_scope.max_cache_state = tonumber(vals[73]) or -1
        h4_scope.post_install = tonumber(vals[74]) or -999
        h4_scope.post_restore = tonumber(vals[75]) or -999
        h4_scope.post_active = tonumber(vals[76]) or -1
        h4_scope.post_stock = tonumber(vals[77]) or -1
        h4_scope.post_vertex_copy_calls = tonumber(vals[78]) or -1
        h4_scope.post_vertex_copy_us = tonumber(vals[79]) or -1
        h4_scope.post_index_copy_calls = tonumber(vals[80]) or -1
        h4_scope.post_index_copy_us = tonumber(vals[81]) or -1
        h4_scope.post_component_build_calls = tonumber(vals[82]) or -1
        h4_scope.post_component_build_us = tonumber(vals[83]) or -1
        h4_scope.post_component_final_calls = tonumber(vals[84]) or -1
        h4_scope.post_component_final_us = tonumber(vals[85]) or -1
        h4_scope.post_profiled_us = tonumber(vals[86]) or -1
        h4_scope.inner_install = tonumber(vals[87]) or -999
        h4_scope.inner_restore = tonumber(vals[88]) or -999
        h4_scope.inner_active = tonumber(vals[89]) or -1
        h4_scope.inner_stock = tonumber(vals[90]) or -1
        h4_scope.inner_grow_calls = tonumber(vals[91]) or -1
        h4_scope.inner_grow_us = tonumber(vals[92]) or -1
        h4_scope.inner_payload_a_calls = tonumber(vals[93]) or -1
        h4_scope.inner_payload_a_us = tonumber(vals[94]) or -1
        h4_scope.inner_payload_b_calls = tonumber(vals[95]) or -1
        h4_scope.inner_payload_b_us = tonumber(vals[96]) or -1
        h4_scope.inner_recalc_calls = tonumber(vals[97]) or -1
        h4_scope.inner_recalc_us = tonumber(vals[98]) or -1
        h4_scope.inner_update_calls = tonumber(vals[99]) or -1
        h4_scope.inner_update_us = tonumber(vals[100]) or -1
        h4_scope.inner_tail_calls = tonumber(vals[101]) or -1
        h4_scope.inner_tail_us = tonumber(vals[102]) or -1
        h4_scope.ud_install = tonumber(vals[103]) or -999
        h4_scope.ud_restore = tonumber(vals[104]) or -999
        h4_scope.ud_active = tonumber(vals[105]) or -1
        h4_scope.ud_stock = tonumber(vals[106]) or -1
        h4_scope.ud_create_calls = tonumber(vals[107]) or -1
        h4_scope.ud_create_us = tonumber(vals[108]) or -1
        h4_scope.ud_array_a_calls = tonumber(vals[109]) or -1
        h4_scope.ud_array_a_us = tonumber(vals[110]) or -1
        h4_scope.ud_array_b_calls = tonumber(vals[111]) or -1
        h4_scope.ud_array_b_us = tonumber(vals[112]) or -1
        h4_scope.ud_payload_calls = tonumber(vals[113]) or -1
        h4_scope.ud_payload_us = tonumber(vals[114]) or -1
        h4_scope.ud_dispatch_calls = tonumber(vals[115]) or -1
        h4_scope.ud_dispatch_us = tonumber(vals[116]) or -1
        h4_scope.ud_post_calls = tonumber(vals[117]) or -1
        h4_scope.ud_post_us = tonumber(vals[118]) or -1
        h4_scope.ud_alloc_calls = tonumber(vals[119]) or -1
        h4_scope.ud_alloc_us = tonumber(vals[120]) or -1
        h4_scope.ud_assign_calls = tonumber(vals[121]) or -1
        h4_scope.ud_assign_us = tonumber(vals[122]) or -1
        h4_scope.update_card_before_items = tonumber(vals[123]) or -1
        h4_scope.update_card_after_items = tonumber(vals[124]) or -1
        h4_scope.update_card_nonzero_calls = tonumber(vals[125]) or -1
        h4_scope.update_card_zero_calls = tonumber(vals[126]) or -1
        h4_scope.update_card_max_before = tonumber(vals[127]) or -1
        h4_scope.update_card_guard_fail = tonumber(vals[128]) or -1
        h4_scope.ut_tail_calls = tonumber(vals[129]) or -1
        h4_scope.ut_tail_us = tonumber(vals[130]) or -1
        h4_scope.ut_pre_calls = tonumber(vals[131]) or -1
        h4_scope.ut_pre_us = tonumber(vals[132]) or -1
        h4_scope.ut_dirty_calls = tonumber(vals[133]) or -1
        h4_scope.ut_dirty_us = tonumber(vals[134]) or -1
        h4_scope.ut_dispatch_calls = tonumber(vals[135]) or -1
        h4_scope.ut_dispatch_us = tonumber(vals[136]) or -1
        h4_scope.vt_patched = tonumber(vals[137]) or -1
        h4_scope.vt_peak = tonumber(vals[138]) or -1
        h4_scope.vt_patch_fail = tonumber(vals[139]) or -1
        h4_scope.vt_restore_fail = tonumber(vals[140]) or -1
        h4_scope.vt_guard_fail = tonumber(vals[141]) or -1
        h4_scope.v2d0_calls = tonumber(vals[142]) or -1
        h4_scope.v2d0_us = tonumber(vals[143]) or -1
        h4_scope.v2b0_calls = tonumber(vals[144]) or -1
        h4_scope.v2b0_us = tonumber(vals[145]) or -1
        h4_scope.vt_first = tonumber(vals[146]) or 0
        h4_scope.vt_first_rva = tonumber(vals[147]) or 0
        h4_scope.v2d0_target = tonumber(vals[148]) or 0
        h4_scope.v2d0_target_rva = tonumber(vals[149]) or 0
        h4_scope.v2b0_target = tonumber(vals[150]) or 0
        h4_scope.v2b0_target_rva = tonumber(vals[151]) or 0
        h4_scope.v2b0_target_in_image = tonumber(vals[152]) or 0
        h4_scope.v2b0_sig0 = tonumber(vals[153]) or 0
        h4_scope.v2b0_sig1 = tonumber(vals[154]) or 0
        h4_scope.v2b0_sig2 = tonumber(vals[155]) or 0
        h4_scope.v2b0_sig3 = tonumber(vals[156]) or 0
        h4_scope.vt_capture_count = tonumber(vals[157]) or 0
        h4_scope.v2b0_target_mismatch = tonumber(vals[158]) or 0
        h4_scope.v2b0_heavy_calls = tonumber(vals[159]) or 0
        h4_scope.v2b0_heavy_us = tonumber(vals[160]) or 0
        h4_scope.v2b0_early_calls = tonumber(vals[161]) or 0
        h4_scope.v2b0_early_us = tonumber(vals[162]) or 0
        h4_scope.v2b0_heavy_entries = tonumber(vals[163]) or 0
        h4_scope.v2b0_heavy_entry_max = tonumber(vals[164]) or 0
        h4_scope.v2b0_zero_inner_entries = tonumber(vals[165]) or 0
        h4_scope.v2b0_subcount_total = tonumber(vals[166]) or 0
        h4_scope.v2b0_subcount_max = tonumber(vals[167]) or 0
        h4_scope.v2b0_ptr310_nonzero = tonumber(vals[168]) or 0
        h4_scope.v2b0_structure_guard_fail = tonumber(vals[169]) or 0
        h4_scope.v2b0_child_install = tonumber(vals[170]) or -1
        h4_scope.v2b0_child_restore = tonumber(vals[171]) or -1
        h4_scope.v2b0_child_active = tonumber(vals[172]) or -1
        h4_scope.v2b0_child_stock = tonumber(vals[173]) or -1
        h4_scope.v2b0_r3ba29a0_calls = tonumber(vals[174]) or 0
        h4_scope.v2b0_r3ba29a0_us = tonumber(vals[175]) or 0
        h4_scope.v2b0_r3b87e20_calls = tonumber(vals[176]) or 0
        h4_scope.v2b0_r3b87e20_us = tonumber(vals[177]) or 0
        h4_scope.v2b0_r3b8ade0_calls = tonumber(vals[178]) or 0
        h4_scope.v2b0_r3b8ade0_us = tonumber(vals[179]) or 0
        h4_scope.v2b0_r3b895c0_calls = tonumber(vals[180]) or 0
        h4_scope.v2b0_r3b895c0_us = tonumber(vals[181]) or 0
        h4_scope.v2b0_r3b9bab0_calls = tonumber(vals[182]) or 0
        h4_scope.v2b0_r3b9bab0_us = tonumber(vals[183]) or 0
        h4_scope.v2b0_r3ba2790_calls = tonumber(vals[184]) or 0
        h4_scope.v2b0_r3ba2790_us = tonumber(vals[185]) or 0
        h4_scope.v2b0_r3b8b430_calls = tonumber(vals[186]) or 0
        h4_scope.v2b0_r3b8b430_us = tonumber(vals[187]) or 0
        h4_scope.v2b0_r13ef490_calls = tonumber(vals[188]) or 0
        h4_scope.v2b0_r13ef490_us = tonumber(vals[189]) or 0
        h4_scope.v2b0_r3b9a3d0_calls = tonumber(vals[190]) or 0
        h4_scope.v2b0_r3b9a3d0_us = tonumber(vals[191]) or 0
        h4_scope.v2b0_child_profiled_us = tonumber(vals[192]) or 0
        h4_scope.v2b0_child_guard_fail = tonumber(vals[193]) or 0
        h4_scope.bab0_child_install = tonumber(vals[194]) or -1
        h4_scope.bab0_child_restore = tonumber(vals[195]) or -1
        h4_scope.bab0_child_active = tonumber(vals[196]) or -1
        h4_scope.bab0_child_stock = tonumber(vals[197]) or -1
        h4_scope.bab0_r3b8c990_calls = tonumber(vals[198]) or 0
        h4_scope.bab0_r3b8c990_us = tonumber(vals[199]) or 0
        h4_scope.bab0_r3b98d20_calls = tonumber(vals[200]) or 0
        h4_scope.bab0_r3b98d20_us = tonumber(vals[201]) or 0
        h4_scope.bab0_r3ba15b0_calls = tonumber(vals[202]) or 0
        h4_scope.bab0_r3ba15b0_us = tonumber(vals[203]) or 0
        h4_scope.bab0_r10d1a90_calls = tonumber(vals[204]) or 0
        h4_scope.bab0_r10d1a90_us = tonumber(vals[205]) or 0
        h4_scope.bab0_child_profiled_us = tonumber(vals[206]) or 0
        h4_scope.bab0_child_guard_fail = tonumber(vals[207]) or 0
        h4_scope.d20_child_install = tonumber(vals[208]) or -1
        h4_scope.d20_child_restore = tonumber(vals[209]) or -1
        h4_scope.d20_child_active = tonumber(vals[210]) or -1
        h4_scope.d20_child_stock = tonumber(vals[211]) or -1
        h4_scope.d20_r10d0f20_calls = tonumber(vals[212]) or 0
        h4_scope.d20_r10d0f20_us = tonumber(vals[213]) or 0
        h4_scope.d20_r3b99a20_calls = tonumber(vals[214]) or 0
        h4_scope.d20_r3b99a20_us = tonumber(vals[215]) or 0
        h4_scope.d20_r1a297f0_calls = tonumber(vals[216]) or 0
        h4_scope.d20_r1a297f0_us = tonumber(vals[217]) or 0
        h4_scope.d20_r3b7acf0_calls = tonumber(vals[218]) or 0
        h4_scope.d20_r3b7acf0_us = tonumber(vals[219]) or 0
        h4_scope.d20_r3b7b3a0_calls = tonumber(vals[220]) or 0
        h4_scope.d20_r3b7b3a0_us = tonumber(vals[221]) or 0
        h4_scope.d20_child_profiled_us = tonumber(vals[222]) or 0
        h4_scope.d20_child_guard_fail = tonumber(vals[223]) or 0
        h4_scope.a20_checks = tonumber(vals[224]) or 0
        h4_scope.a20_hash_us = tonumber(vals[225]) or 0
        h4_scope.a20_guard_fail = tonumber(vals[226]) or 0
        h4_scope.a20_promoted = tonumber(vals[227]) or 0
        h4_scope.a20_rejected = tonumber(vals[228]) or 0
        h4_scope.a20_late_demotions = tonumber(vals[229]) or 0
        h4_scope.a20_canary_calls = tonumber(vals[230]) or 0
        h4_scope.a20_canary_mismatch = tonumber(vals[231]) or 0
        h4_scope.a20_candidate_calls = tonumber(vals[232]) or 0
        h4_scope.a20_candidate_us = tonumber(vals[233]) or 0
        h4_scope.a20_proving_calls = tonumber(vals[234]) or 0
        h4_scope.a20_proving_us = tonumber(vals[235]) or 0
        h4_scope.a20_blocked_calls = tonumber(vals[236]) or 0
        h4_scope.a20_blocked_us = tonumber(vals[237]) or 0
        h4_scope.a20_output0_bytes = tonumber(vals[238]) or 0
        h4_scope.a20_output1_bytes = tonumber(vals[239]) or 0
        h4_scope.a20_first_mismatch_source = tonumber(vals[240]) or 0
        h4_scope.a20_first_mismatch_code = tonumber(vals[241]) or 0
        h4_scope.a20_ready_sources = tonumber(vals[242]) or 0
        h4_scope.a20_rejected_current = tonumber(vals[243]) or 0
        h4_scope.a20_proving_sources = tonumber(vals[244]) or 0
        h4_scope.a20_max_matches = tonumber(vals[245]) or 0
        h4_scope.a20_output2_bytes = tonumber(vals[246]) or 0
        h4_scope.a20_output3_bytes = tonumber(vals[247]) or 0
        h4_scope.a20_cache_promoted_sources = tonumber(vals[248]) or 0
        h4_scope.a20_cache_fast_calls = tonumber(vals[249]) or 0
        h4_scope.a20_cache_fast_bytes = tonumber(vals[250]) or 0
        h4_scope.a20_cache_copy_us = tonumber(vals[251]) or 0
        h4_scope.a20_cache_used = tonumber(vals[252]) or 0
        h4_scope.a20_cache_cap = tonumber(vals[253]) or 0
        h4_scope.a20_cache_arena_rejects = tonumber(vals[254]) or 0
        h4_scope.a20_cache_fallback_calls = tonumber(vals[255]) or 0
        h4_scope.a20_cache_apply_fail = tonumber(vals[256]) or 0
        h4_scope.a20_cache_resize_calls = tonumber(vals[257]) or 0
        h4_scope.a20_cache_resize_guard_ok = tonumber(vals[258]) or 0
        h4_scope.f490_install = tonumber(vals[259]) or -1
        h4_scope.f490_restore = tonumber(vals[260]) or -1
        h4_scope.f490_active = tonumber(vals[261]) or -1
        h4_scope.f490_stock = tonumber(vals[262]) or -1
        h4_scope.f490_calls = tonumber(vals[263]) or 0
        h4_scope.f490_us = tonumber(vals[264]) or 0
        h4_scope.f490_checks = tonumber(vals[265]) or 0
        h4_scope.f490_hash_us = tonumber(vals[266]) or 0
        h4_scope.f490_guard_fail = tonumber(vals[267]) or 0
        h4_scope.f490_promoted = tonumber(vals[268]) or 0
        h4_scope.f490_rejected = tonumber(vals[269]) or 0
        h4_scope.f490_late_demotions = tonumber(vals[270]) or 0
        h4_scope.f490_canary_calls = tonumber(vals[271]) or 0
        h4_scope.f490_canary_mismatch = tonumber(vals[272]) or 0
        h4_scope.f490_ready_sources = tonumber(vals[273]) or 0
        h4_scope.f490_rejected_current = tonumber(vals[274]) or 0
        h4_scope.f490_proving_sources = tonumber(vals[275]) or 0
        h4_scope.f490_max_matches = tonumber(vals[276]) or 0
        h4_scope.f490_candidate_calls = tonumber(vals[277]) or 0
        h4_scope.f490_candidate_us = tonumber(vals[278]) or 0
        h4_scope.f490_proving_calls = tonumber(vals[279]) or 0
        h4_scope.f490_proving_us = tonumber(vals[280]) or 0
        h4_scope.f490_blocked_calls = tonumber(vals[281]) or 0
        h4_scope.f490_blocked_us = tonumber(vals[282]) or 0
        h4_scope.f490_first_mismatch_source = tonumber(vals[283]) or 0
        h4_scope.f490_first_mismatch_code = tonumber(vals[284]) or 0
        h4_scope.f490_mid_install = tonumber(vals[285]) or -1
        h4_scope.f490_mid_restore = tonumber(vals[286]) or -1
        h4_scope.f490_mid_active = tonumber(vals[287]) or -1
        h4_scope.f490_mid_stock = tonumber(vals[288]) or -1
        h4_scope.f490_fast_calls = tonumber(vals[289]) or 0
        h4_scope.f490_fast_bytes = tonumber(vals[290]) or 0
        h4_scope.f490_fast_copy_us = tonumber(vals[291]) or 0
        h4_scope.f490_fast_misses = tonumber(vals[292]) or 0
        h4_scope.f490_mid_guard_fail = tonumber(vals[293]) or 0
        h4_scope.f490_finalizer_install = tonumber(vals[294]) or -1
        h4_scope.f490_finalizer_restore = tonumber(vals[295]) or -1
        h4_scope.f490_finalizer_active = tonumber(vals[296]) or -1
        h4_scope.f490_finalizer_stock = tonumber(vals[297]) or -1
        h4_scope.f490_finalizer_calls = tonumber(vals[298]) or 0
        h4_scope.f490_finalizer_us = tonumber(vals[299]) or 0
        h4_scope.f490_finalizer_guard_fail = tonumber(vals[300]) or 0
        h4_scope.f490_tail_install = tonumber(vals[301]) or -1
        h4_scope.f490_tail_restore = tonumber(vals[302]) or -1
        h4_scope.f490_tail_active = tonumber(vals[303]) or -1
        h4_scope.f490_tail_stock = tonumber(vals[304]) or -1
        h4_scope.f490_tail_build_calls = tonumber(vals[305]) or 0
        h4_scope.f490_tail_build_us = tonumber(vals[306]) or 0
        h4_scope.f490_tail_cleanup_calls = tonumber(vals[307]) or 0
        h4_scope.f490_tail_cleanup_us = tonumber(vals[308]) or 0
        h4_scope.f490_tail_guard_fail = tonumber(vals[309]) or 0
    end)
    local repeat_pct = 0.0
    if h4_scope.profile_calls and h4_scope.profile_calls > 0 and h4_scope.repeats and h4_scope.repeats >= 0 then
        repeat_pct = (h4_scope.repeats * 100.0) / h4_scope.profile_calls
    end
    log(string.format(
        'PCL15_11_90_H4_REUSE_PROFILE install=%d restore=%d calls=%d unique_sources=%d repeat_calls=%d repeat_pct=%.2f first_us=%d repeat_us=%d total_us=%d max_calls_per_source=%d max_source=0x%X max_source_us=%d hot_source=0x%X hot_calls=%d hot_us=%d null_sources=%d table_overflow=%d cap=%d qpc_ready=%d profile_calls=%d other_thread_calls=%d active=%d stock_restored=%d scope=seam_only behavior=selective_vertex_cache error=%s',
        h4_scope.install, h4_scope.restore, h4_scope.calls, h4_scope.unique,
        h4_scope.repeats, repeat_pct, h4_scope.first_us, h4_scope.repeat_us,
        h4_scope.total_us, h4_scope.max_calls, h4_scope.max_source, h4_scope.max_source_us,
        h4_scope.hot_source, h4_scope.hot_calls, h4_scope.hot_us, h4_scope.null_sources,
        h4_scope.overflow, h4_scope.cap, h4_scope.qpc_ready, h4_scope.profile_calls,
        h4_scope.other_thread_calls, h4_scope.active, h4_scope.stock, tostring(h4_scope.error)))
    log(string.format(
        'PCL15_11_90_H4_PAYLOAD_STABILITY captured=%d validated=%d mismatch=%d guard_fail=%d checks=%d hash_us=%d index_bytes=%d vertex_bytes=%d first_mismatch_source=0x%X mismatch_code=%d cache_behavior=selective_vertex_loop_only ownership=stock_arrays',
        h4_scope.fp_captured, h4_scope.fp_validated, h4_scope.fp_mismatch,
        h4_scope.fp_guard_fail, h4_scope.fp_checks, h4_scope.fp_hash_us,
        h4_scope.fp_index_bytes, h4_scope.fp_vertex_bytes,
        h4_scope.fp_mismatch_source, h4_scope.fp_mismatch_code))
    local geometry_candidate = (h4_scope.fp_geometry_mismatch == 0 and h4_scope.fp_geometry_validated > 0)
    log(string.format(
        'PCL15_11_90_H4_COMPONENT_STABILITY geometry_validated=%d geometry_mismatch=%d bounds_only_mismatch=%d bounds_mismatch=%d index_num_mismatch=%d vertex_num_mismatch=%d index_hash_mismatch=%d vertex_hash_mismatch=%d first_geometry_mismatch_source=0x%X geometry_mismatch_code=%d geometry_cache_candidate=%s cache_behavior=selective_vertex_loop_only ownership=stock_arrays',
        h4_scope.fp_geometry_validated, h4_scope.fp_geometry_mismatch,
        h4_scope.fp_bounds_only_mismatch, h4_scope.fp_bounds_mismatch,
        h4_scope.fp_index_num_mismatch, h4_scope.fp_vertex_num_mismatch,
        h4_scope.fp_index_hash_mismatch, h4_scope.fp_vertex_hash_mismatch,
        h4_scope.fp_geometry_mismatch_source, h4_scope.fp_geometry_mismatch_code,
        tostring(geometry_candidate)))
    log(string.format(
        'PCL15_11_90_H4_CACHE_CLASS stable_sources=%d unstable_sources=%d unresolved_sources=%d stable_post_calls=%d stable_post_us=%d unstable_post_calls=%d unstable_post_us=%d unresolved_repeat_calls=%d unresolved_repeat_us=%d hot_source_geometry_state=%d max_source_geometry_state=%d',
        h4_scope.stable_sources, h4_scope.unstable_sources, h4_scope.unresolved_sources,
        h4_scope.stable_post_calls, h4_scope.stable_post_us,
        h4_scope.unstable_post_calls, h4_scope.unstable_post_us,
        h4_scope.unresolved_repeat_calls, h4_scope.unresolved_repeat_us,
        h4_scope.hot_geometry_state, h4_scope.max_geometry_state))
    log(string.format(
        'PCL15_11_90_H4_CACHE_RUNTIME entry_install=%d entry_restore=%d entry_active=%d entry_stock_restored=%d loop_install=%d loop_restore=%d loop_active=%d loop_stock_restored=%d proof_required=8 canary_interval=128 promoted_sources=%d rejected_sources=%d late_demotions=%d fast_calls=%d fast_bytes=%d cache_copy_us=%d mid_guard_fail=%d canary_calls=%d canary_mismatch=%d proof_checks=%d proof_hash_us=%d arena_used=%d arena_cap=%d arena_rejects=%d hot_cache_state=%d max_cache_state=%d behavior=skip_vertex_conversion_only',
        h4_scope.install, h4_scope.restore, h4_scope.active, h4_scope.stock,
        h4_scope.loop_install, h4_scope.loop_restore, h4_scope.loop_active, h4_scope.loop_stock,
        h4_scope.cache_promoted, h4_scope.cache_rejected, h4_scope.cache_late_demotions,
        h4_scope.cache_fast_calls, h4_scope.cache_fast_bytes, h4_scope.cache_copy_us,
        h4_scope.cache_mid_guard_fail, h4_scope.cache_canary_calls, h4_scope.cache_canary_mismatch,
        h4_scope.cache_proof_checks, h4_scope.cache_proof_us,
        h4_scope.cache_arena_used, h4_scope.cache_arena_cap, h4_scope.cache_arena_rejects,
        h4_scope.hot_cache_state, h4_scope.max_cache_state))
    local post_unprofiled_us = -1
    if h4_scope.total_us and h4_scope.total_us >= 0 and h4_scope.post_profiled_us and h4_scope.post_profiled_us >= 0 then
        post_unprofiled_us = h4_scope.total_us - h4_scope.post_profiled_us
    end
    log(string.format(
        'PCL15_11_90_H4_POST_LOOP_PROFILE install=%d restore=%d active=%d stock_restored=%d vertex_bulk_calls=%d vertex_bulk_us=%d index_bulk_calls=%d index_bulk_us=%d component_build_calls=%d component_build_us=%d component_final_calls=%d component_final_us=%d profiled_us=%d h4_total_us=%d h4_unprofiled_us=%d behavior=measurement_only_post_loop_calls',
        h4_scope.post_install, h4_scope.post_restore, h4_scope.post_active, h4_scope.post_stock,
        h4_scope.post_vertex_copy_calls, h4_scope.post_vertex_copy_us,
        h4_scope.post_index_copy_calls, h4_scope.post_index_copy_us,
        h4_scope.post_component_build_calls, h4_scope.post_component_build_us,
        h4_scope.post_component_final_calls, h4_scope.post_component_final_us,
        h4_scope.post_profiled_us, h4_scope.total_us, post_unprofiled_us))
    local inner_sum_us = (h4_scope.inner_grow_us or 0) + (h4_scope.inner_payload_a_us or 0) +
                         (h4_scope.inner_payload_b_us or 0) + (h4_scope.inner_recalc_us or 0) +
                         (h4_scope.inner_update_us or 0) + (h4_scope.inner_tail_us or 0)
    local inner_residual_us = -1
    if h4_scope.post_component_build_us and h4_scope.post_component_build_us >= 0 then
        inner_residual_us = h4_scope.post_component_build_us - inner_sum_us
    end
    log(string.format(
        'PCL15_11_90_H4_COMPONENT_BUILD_INNER install=%d restore=%d active=%d stock_restored=%d grow_calls=%d grow_us=%d payload_a_calls=%d payload_a_us=%d payload_b_calls=%d payload_b_us=%d recalc_calls=%d recalc_us=%d update_calls=%d update_us=%d tail_calls=%d tail_us=%d component_build_us=%d measured_sum_us=%d residual_us=%d behavior=update_wrapper_only_high_frequency_inner_hooks_disabled',
        h4_scope.inner_install, h4_scope.inner_restore, h4_scope.inner_active, h4_scope.inner_stock,
        h4_scope.inner_grow_calls, h4_scope.inner_grow_us,
        h4_scope.inner_payload_a_calls, h4_scope.inner_payload_a_us,
        h4_scope.inner_payload_b_calls, h4_scope.inner_payload_b_us,
        h4_scope.inner_recalc_calls, h4_scope.inner_recalc_us,
        h4_scope.inner_update_calls, h4_scope.inner_update_us,
        h4_scope.inner_tail_calls, h4_scope.inner_tail_us,
        h4_scope.post_component_build_us, inner_sum_us, inner_residual_us))
    local card_avg = 0.0
    if h4_scope.inner_update_calls and h4_scope.inner_update_calls > 0 and h4_scope.update_card_before_items and h4_scope.update_card_before_items >= 0 then
        card_avg = h4_scope.update_card_before_items / h4_scope.inner_update_calls
    end
    local update_us_per_item = 0.0
    if h4_scope.update_card_before_items and h4_scope.update_card_before_items > 0 and h4_scope.inner_update_us and h4_scope.inner_update_us >= 0 then
        update_us_per_item = h4_scope.inner_update_us / h4_scope.update_card_before_items
    end
    log(string.format(
        'PCL15_11_90_H4_UPDATE_CARDINALITY update_calls=%d update_us=%d teardown_items=%d post_items=%d nonzero_updates=%d zero_updates=%d max_items=%d guard_fail=%d avg_items_per_update=%.2f update_us_per_item=%.4f observer=single_tarray_header_read_per_update direct_helper_hooks=disabled',
        h4_scope.inner_update_calls, h4_scope.inner_update_us,
        h4_scope.update_card_before_items, h4_scope.update_card_after_items,
        h4_scope.update_card_nonzero_calls, h4_scope.update_card_zero_calls,
        h4_scope.update_card_max_before, h4_scope.update_card_guard_fail, card_avg, update_us_per_item))
    local ut_tail_residual_us = -1
    if h4_scope.inner_update_us and h4_scope.inner_update_us >= 0 and h4_scope.ut_tail_us and h4_scope.ut_tail_us >= 0 then
        ut_tail_residual_us = h4_scope.inner_update_us - h4_scope.ut_tail_us - h4_scope.ut_dispatch_us
    end
    log(string.format(
        'PCL15_11_90_H4_UPDATE_TAIL_PROFILE update_calls=%d update_us=%d tail_calls=%d tail_us=%d pre_calls=%d pre_us=%d dirty_calls=%d dirty_us=%d dispatch_calls=%d dispatch_us=%d outside_tail_dispatch_us=%d observer=update_tail_jump_callsite behavior=measurement_only',
        h4_scope.inner_update_calls, h4_scope.inner_update_us,
        h4_scope.ut_tail_calls, h4_scope.ut_tail_us,
        h4_scope.ut_pre_calls, h4_scope.ut_pre_us,
        h4_scope.ut_dirty_calls, h4_scope.ut_dirty_us,
        h4_scope.ut_dispatch_calls, h4_scope.ut_dispatch_us, ut_tail_residual_us))
    local vt_residual_us = -1
    if h4_scope.inner_update_us and h4_scope.inner_update_us >= 0 then
        vt_residual_us = h4_scope.inner_update_us - (h4_scope.v2d0_us or 0) -
            (h4_scope.v2b0_us or 0) - (h4_scope.ut_tail_us or 0)
    end
    log(string.format(
        'PCL15_11_90_H4_UPDATE_VIRTUAL_PROFILE update_calls=%d update_us=%d vtables_patched=%d vtable_peak=%d patch_fail=%d restore_fail=%d guard_fail=%d vfunc_2d0_calls=%d vfunc_2d0_us=%d vfunc_2b0_calls=%d vfunc_2b0_us=%d tail_us=%d remaining_update_us=%d observer=vtable_slot_swap scope=seam_only behavior=measurement_only',
        h4_scope.inner_update_calls, h4_scope.inner_update_us,
        h4_scope.vt_patched, h4_scope.vt_peak, h4_scope.vt_patch_fail,
        h4_scope.vt_restore_fail, h4_scope.vt_guard_fail,
        h4_scope.v2d0_calls, h4_scope.v2d0_us,
        h4_scope.v2b0_calls, h4_scope.v2b0_us,
        h4_scope.ut_tail_us, vt_residual_us))
    log(string.format(
        'PCL15_11_90_H4_V2B0_TARGET vtable=0x%X vtable_rva=0x%X vfunc_2d0=0x%X vfunc_2d0_rva=0x%X vfunc_2b0=0x%X vfunc_2b0_rva=0x%X target_in_image=%d captures=%d target_mismatch=%d first16_le_dwords=%08X_%08X_%08X_%08X behavior=measurement_only_no_new_detour',
        h4_scope.vt_first or 0, h4_scope.vt_first_rva or 0,
        h4_scope.v2d0_target or 0, h4_scope.v2d0_target_rva or 0,
        h4_scope.v2b0_target or 0, h4_scope.v2b0_target_rva or 0,
        h4_scope.v2b0_target_in_image or 0, h4_scope.vt_capture_count or 0,
        h4_scope.v2b0_target_mismatch or 0,
        h4_scope.v2b0_sig0 or 0, h4_scope.v2b0_sig1 or 0,
        h4_scope.v2b0_sig2 or 0, h4_scope.v2b0_sig3 or 0))
    log(string.format(
        'PCL15_11_90_H4_V2B0_POST_STRUCTURE heavy_calls=%d heavy_us=%d early_calls=%d early_us=%d post_entries=%d max_entries_per_heavy=%d post_inner_zero=%d post_inner_nonzero=%d post_subcount_total=%d post_subcount_max=%d ptr310_post_nonzero_heavy=%d guard_fail=%d target_rva=0x%X entry_stride=0x100 dirty_offset=0xD9 dirty_mask=0x09 inner_num_offset=0x48 subcount_offset=0x38 behavior=measurement_only_post_call_structure_sample',
        h4_scope.v2b0_heavy_calls or 0, h4_scope.v2b0_heavy_us or 0,
        h4_scope.v2b0_early_calls or 0, h4_scope.v2b0_early_us or 0,
        h4_scope.v2b0_heavy_entries or 0, h4_scope.v2b0_heavy_entry_max or 0,
        h4_scope.v2b0_zero_inner_entries or 0,
        math.max(0, (h4_scope.v2b0_heavy_entries or 0) - (h4_scope.v2b0_zero_inner_entries or 0)),
        h4_scope.v2b0_subcount_total or 0, h4_scope.v2b0_subcount_max or 0,
        h4_scope.v2b0_ptr310_nonzero or 0,
        h4_scope.v2b0_structure_guard_fail or 0, h4_scope.v2b0_target_rva or 0))
    local v2b0_child_residual_us = (h4_scope.v2b0_heavy_us or 0) - (h4_scope.v2b0_child_profiled_us or 0)
    log(string.format(
        'PCL15_11_90_H4_V2B0_CHILD_PROFILE install=%d restore=%d active=%d stock_restored=%d r3BA29A0[count=%d us=%d] r3B87E20[count=%d us=%d] r3B8ADE0[count=%d us=%d] r3B895C0[count=%d us=%d] r3B9BAB0[count=%d us=%d] r3BA2790[count=%d us=%d] r3B8B430[count=%d us=%d] r13EF490[count=%d us=%d] r3B9A3D0[count=%d us=%d] profiled_us=%d heavy_us=%d residual_us=%d guard_fail=%d observer=relocation_safe_helper_entry_detours scope=heavy_v2b0_first_level_only',
        h4_scope.v2b0_child_install or -1, h4_scope.v2b0_child_restore or -1,
        h4_scope.v2b0_child_active or -1, h4_scope.v2b0_child_stock or -1,
        h4_scope.v2b0_r3ba29a0_calls or 0, h4_scope.v2b0_r3ba29a0_us or 0,
        h4_scope.v2b0_r3b87e20_calls or 0, h4_scope.v2b0_r3b87e20_us or 0,
        h4_scope.v2b0_r3b8ade0_calls or 0, h4_scope.v2b0_r3b8ade0_us or 0,
        h4_scope.v2b0_r3b895c0_calls or 0, h4_scope.v2b0_r3b895c0_us or 0,
        h4_scope.v2b0_r3b9bab0_calls or 0, h4_scope.v2b0_r3b9bab0_us or 0,
        h4_scope.v2b0_r3ba2790_calls or 0, h4_scope.v2b0_r3ba2790_us or 0,
        h4_scope.v2b0_r3b8b430_calls or 0, h4_scope.v2b0_r3b8b430_us or 0,
        h4_scope.v2b0_r13ef490_calls or 0, h4_scope.v2b0_r13ef490_us or 0,
        h4_scope.v2b0_r3b9a3d0_calls or 0, h4_scope.v2b0_r3b9a3d0_us or 0,
        h4_scope.v2b0_child_profiled_us or 0, h4_scope.v2b0_heavy_us or 0,
        v2b0_child_residual_us, h4_scope.v2b0_child_guard_fail or 0))
    local bab0_child_residual_us = (h4_scope.v2b0_r3b9bab0_us or 0) - (h4_scope.bab0_child_profiled_us or 0)
    log(string.format(
        'PCL15_11_90_H4_BAB0_CHILD_PROFILE install=%d restore=%d active=%d stock_restored=%d r3B8C990[count=%d us=%d] r3B98D20[count=%d us=%d] r3BA15B0[count=%d us=%d] r10D1A90[count=%d us=%d] profiled_us=%d parent_us=%d residual_us=%d guard_fail=%d observer=relocation_safe_helper_entry_detours scope=inside_3B9BAB0_first_level_only',
        h4_scope.bab0_child_install or -1, h4_scope.bab0_child_restore or -1,
        h4_scope.bab0_child_active or -1, h4_scope.bab0_child_stock or -1,
        h4_scope.bab0_r3b8c990_calls or 0, h4_scope.bab0_r3b8c990_us or 0,
        h4_scope.bab0_r3b98d20_calls or 0, h4_scope.bab0_r3b98d20_us or 0,
        h4_scope.bab0_r3ba15b0_calls or 0, h4_scope.bab0_r3ba15b0_us or 0,
        h4_scope.bab0_r10d1a90_calls or 0, h4_scope.bab0_r10d1a90_us or 0,
        h4_scope.bab0_child_profiled_us or 0, h4_scope.v2b0_r3b9bab0_us or 0,
        bab0_child_residual_us, h4_scope.bab0_child_guard_fail or 0))
    local d20_child_residual_us = (h4_scope.bab0_r3b98d20_us or 0) - (h4_scope.d20_child_profiled_us or 0)
    log(string.format(
        'PCL15_11_90_H4_D20_CHILD_PROFILE install=%d restore=%d active=%d stock_restored=%d r10D0F20[count=%d us=%d] r3B99A20[count=%d us=%d] r1A297F0[count=%d us=%d] r3B7ACF0[count=%d us=%d] r3B7B3A0[count=%d us=%d] profiled_us=%d parent_us=%d residual_us=%d guard_fail=%d observer=relocation_safe_helper_entry_detours scope=inside_3B98D20_first_level_only',
        h4_scope.d20_child_install or -1, h4_scope.d20_child_restore or -1,
        h4_scope.d20_child_active or -1, h4_scope.d20_child_stock or -1,
        h4_scope.d20_r10d0f20_calls or 0, h4_scope.d20_r10d0f20_us or 0,
        h4_scope.d20_r3b99a20_calls or 0, h4_scope.d20_r3b99a20_us or 0,
        h4_scope.d20_r1a297f0_calls or 0, h4_scope.d20_r1a297f0_us or 0,
        h4_scope.d20_r3b7acf0_calls or 0, h4_scope.d20_r3b7acf0_us or 0,
        h4_scope.d20_r3b7b3a0_calls or 0, h4_scope.d20_r3b7b3a0_us or 0,
        h4_scope.d20_child_profiled_us or 0, h4_scope.bab0_r3b98d20_us or 0,
        d20_child_residual_us, h4_scope.d20_child_guard_fail or 0))
    log(string.format(
        'PCL15_11_98_H4_A20_FOUR_OUTPUT_STABILITY checks=%d hash_us=%d guard_fail=%d proof_required=8 canary_interval=128 promoted=%d rejected=%d late_demotions=%d canary_calls=%d canary_mismatch=%d ready_sources=%d rejected_sources_current=%d proving_sources=%d max_matches=%d candidate_calls=%d candidate_us=%d proving_calls=%d proving_us=%d blocked_calls=%d blocked_us=%d rcx12_hashed_bytes=%d rdx4_hashed_bytes=%d r8_4_hashed_bytes=%d r9_4_hashed_bytes=%d first_mismatch_source=0x%X mismatch_code=%d mismatch_bits=num0:1_hash0:2_num1:4_hash1:8_num2:16_hash2:32_num3:64_hash3:128 behavior=guarded_cache_proof_and_stock_canary_existing_A20_wrapper_no_new_detour',
        h4_scope.a20_checks or 0, h4_scope.a20_hash_us or 0, h4_scope.a20_guard_fail or 0,
        h4_scope.a20_promoted or 0, h4_scope.a20_rejected or 0, h4_scope.a20_late_demotions or 0,
        h4_scope.a20_canary_calls or 0, h4_scope.a20_canary_mismatch or 0,
        h4_scope.a20_ready_sources or 0, h4_scope.a20_rejected_current or 0,
        h4_scope.a20_proving_sources or 0, h4_scope.a20_max_matches or 0,
        h4_scope.a20_candidate_calls or 0, h4_scope.a20_candidate_us or 0,
        h4_scope.a20_proving_calls or 0, h4_scope.a20_proving_us or 0,
        h4_scope.a20_blocked_calls or 0, h4_scope.a20_blocked_us or 0,
        h4_scope.a20_output0_bytes or 0, h4_scope.a20_output1_bytes or 0,
        h4_scope.a20_output2_bytes or 0, h4_scope.a20_output3_bytes or 0,
        h4_scope.a20_first_mismatch_source or 0, h4_scope.a20_first_mismatch_code or 0))
    log(string.format(
        'PCL15_11_98_H4_A20_CACHE_RUNTIME promoted_sources=%d fast_calls=%d fast_bytes=%d fast_copy_us=%d arena_used=%d arena_cap=%d arena_rejects=%d fallback_calls=%d apply_fail=%d resize_calls=%d resize_guard_ok=%d behavior=cache_four_pod_arrays_after_8_stock_matches_canary_every_128_stock_fallback_all_other_sources resize_guard_modes=0:disable_1:stock_2:existing_pcl_detour_chain ownership=dll_cache_destination_tarrays_game_owned',
        h4_scope.a20_cache_promoted_sources or 0, h4_scope.a20_cache_fast_calls or 0,
        h4_scope.a20_cache_fast_bytes or 0, h4_scope.a20_cache_copy_us or 0,
        h4_scope.a20_cache_used or 0, h4_scope.a20_cache_cap or 0,
        h4_scope.a20_cache_arena_rejects or 0, h4_scope.a20_cache_fallback_calls or 0,
        h4_scope.a20_cache_apply_fail or 0, h4_scope.a20_cache_resize_calls or 0,
        h4_scope.a20_cache_resize_guard_ok or 0))
    log(string.format(
        'PCL15_11_100_H4_F490_BOUNDS_STABILITY install=%d restore=%d active=%d stock_restored=%d calls=%d us=%d checks=%d hash_us=%d guard_fail=%d proof_required=8 canary_interval=128 promoted=%d rejected=%d late_demotions=%d canary_calls=%d canary_mismatch=%d ready_sources=%d rejected_sources_current=%d proving_sources=%d max_matches=%d candidate_calls=%d candidate_us=%d proving_calls=%d proving_us=%d blocked_calls=%d blocked_us=%d first_mismatch_source=0x%X mismatch_code=%d bounds_offset=0x88 bounds_bytes=48 observer=safe_1CFF490_entry_plus_guarded_mid_bypass deeper_child_detours=disabled behavior=proof_plus_bounds_cache',
        h4_scope.f490_install or -1, h4_scope.f490_restore or -1,
        h4_scope.f490_active or -1, h4_scope.f490_stock or -1,
        h4_scope.f490_calls or 0, h4_scope.f490_us or 0,
        h4_scope.f490_checks or 0, h4_scope.f490_hash_us or 0,
        h4_scope.f490_guard_fail or 0, h4_scope.f490_promoted or 0,
        h4_scope.f490_rejected or 0, h4_scope.f490_late_demotions or 0,
        h4_scope.f490_canary_calls or 0, h4_scope.f490_canary_mismatch or 0,
        h4_scope.f490_ready_sources or 0, h4_scope.f490_rejected_current or 0,
        h4_scope.f490_proving_sources or 0, h4_scope.f490_max_matches or 0,
        h4_scope.f490_candidate_calls or 0, h4_scope.f490_candidate_us or 0,
        h4_scope.f490_proving_calls or 0, h4_scope.f490_proving_us or 0,
        h4_scope.f490_blocked_calls or 0, h4_scope.f490_blocked_us or 0,
        h4_scope.f490_first_mismatch_source or 0, h4_scope.f490_first_mismatch_code or 0))
    log(string.format(
        'PCL15_11_100_H4_F490_BOUNDS_CACHE_RUNTIME mid_install=%d mid_restore=%d mid_active=%d mid_stock_restored=%d fast_calls=%d fast_bytes=%d fast_copy_us=%d fast_misses=%d mid_guard_fail=%d fast_cont=0x1CFF98C patch_rva=0x1CFF5E9 patch_bytes=16 behavior=copy_proven_48_byte_bounds_skip_inline_scan_run_stock_finalizer ownership=source_cache_dll_object_game_owned',
        h4_scope.f490_mid_install or -1, h4_scope.f490_mid_restore or -1,
        h4_scope.f490_mid_active or -1, h4_scope.f490_mid_stock or -1,
        h4_scope.f490_fast_calls or 0, h4_scope.f490_fast_bytes or 0,
        h4_scope.f490_fast_copy_us or 0, h4_scope.f490_fast_misses or 0,
        h4_scope.f490_mid_guard_fail or 0))
    local f490_finalizer_residual_us = (h4_scope.f490_us or 0) - (h4_scope.f490_finalizer_us or 0)
    log(string.format(
        'PCL15_11_101_H4_F490_FINALIZER_CALLSITE install=%d restore=%d active=%d stock_restored=%d calls=%d us=%d parent_us=%d residual_us=%d guard_fail=%d callsite_rva=0x1CFF98F target_rva=0x1D361F0 patch_bytes=32 observer=direct_callsite_absolute_indirect_call_no_finalizer_entry_detour bounds_fast_path_preserved=true',
        h4_scope.f490_finalizer_install or -1, h4_scope.f490_finalizer_restore or -1,
        h4_scope.f490_finalizer_active or -1, h4_scope.f490_finalizer_stock or -1,
        h4_scope.f490_finalizer_calls or 0, h4_scope.f490_finalizer_us or 0,
        h4_scope.f490_us or 0, f490_finalizer_residual_us,
        h4_scope.f490_finalizer_guard_fail or 0))
    local f490_tail_profiled_us = (h4_scope.f490_tail_build_us or 0) + (h4_scope.f490_tail_cleanup_us or 0)
    local f490_tail_residual_us = (h4_scope.f490_finalizer_us or 0) - f490_tail_profiled_us
    log(string.format(
        'PCL15_11_103_H4_F490_FINALIZER_TAIL_SPLIT install=%d restore=%d active=%d stock_restored=%d r1D36420[count=%d us=%d] r1D2FEB0[count=%d us=%d] profiled_us=%d parent_us=%d residual_us=%d guard_fail=%d patch_rva=0x1D363D0 patch_bytes=23 observer=direct_tail_bundle_callsite_no_child_entry_detours',
        h4_scope.f490_tail_install or -1, h4_scope.f490_tail_restore or -1,
        h4_scope.f490_tail_active or -1, h4_scope.f490_tail_stock or -1,
        h4_scope.f490_tail_build_calls or 0, h4_scope.f490_tail_build_us or 0,
        h4_scope.f490_tail_cleanup_calls or 0, h4_scope.f490_tail_cleanup_us or 0,
        f490_tail_profiled_us, h4_scope.f490_finalizer_us or 0,
        f490_tail_residual_us, h4_scope.f490_tail_guard_fail or 0))

    if not call_ok then
        return false, 'temp native seam bridge invocation failed: ' .. tostring(status_or_err)
    end

    local status = tonumber(status_or_err) or -999
    log('PCL15_11_13_BRIDGE_RETURN status=' .. tostring(status) ..
        ' meaning=' .. ({
            [1]='native_seam_called',[-1]='lua_arguments_invalid',[-2]='main_module_base_failed',
            [-3]='exe_guard_failed',[-4]='seam_signature_failed',[-5]='pointer_guard_failed',
            [-6]='forge_piece_pointer_mismatch'
        })[status])
    if status ~= 1 then
        return false, 'native bridge refused temp seam call status=' .. tostring(status)
    end

    -- Native seam does not own the GameMode.ForgeMode field, but construction
    -- scripts may have touched it. Keep the player's original actor authoritative.
    pcl151113_restore_game_mode_forge(gm, forge, 'AFTER_SEAM')

    local temp_piece = nil
    local temp_sentinel = nil
    local rebuilt_root = nil
    local temp_frontend = pcl151113_get_frontend(temp)
    pcall(function() temp_piece = temp:GetPiece() end)
    pcall(function() temp_sentinel = temp:GetRootSwordPartActor() end)
    rebuilt_root = pcl151112_first_slot_child(temp_sentinel)

    local active_sentinel_after = nil
    local active_frontend_after = pcl151113_get_frontend(forge)
    pcall(function() active_sentinel_after = forge:GetRootSwordPartActor() end)

    local after_root = -1
    local after_count = -1
    local after_getnum = -1
    local stage_after = -1
    local side_after = -1
    local post_read_ok, post_read_err = pcall(function()
        local d = piece.WeaponDesignDefinition
        after_root = tonumber(d.RootSwordPartIdx) or -1
        after_count = #d.AppliedSwordParts
        after_getnum = piece:GetNumSwordParts()
        stage_after = tonumber(piece.CurrentSwordmakingStage) or -1
        side_after = tonumber(piece.CurrentSideEditingMode) or -1
    end)

    local rebuilt_tree = live_tree_count_14(rebuilt_root)
    local expected_logical_tree = part_count
    if direct_json_mode then
        expected_logical_tree = part_count - blade_count
        if expected_logical_tree < 1 then expected_logical_tree = part_count end
        PCL151165_DIRECT_JSON_LOGICAL_TREE_COUNT = expected_logical_tree
        PCL151165_DIRECT_JSON_BLADE_COUNT = blade_count
        log('PCL15_11_65_DIRECT_JSON_TREE_EXPECTATION applied_parts=' .. tostring(part_count) ..
            ' blade_parts=' .. tostring(blade_count) ..
            ' root_slot_free_tree=' .. tostring(expected_logical_tree))
    end
    local active_sentinel_same =
        pcl151113_obj_addr(active_sentinel_after) == active_sentinel_addr
    local active_frontend_same =
        pcl151113_obj_addr(active_frontend_after) == active_frontend_addr
    local temp_piece_same = pcl151113_obj_addr(temp_piece) == piece_addr

    log(string.format(
        'PCL15_11_13_TEMP_DIRECT_SEAM_RETURN temp_piece_same=%s temp_sentinel=0x%X rebuilt_root=0x%X rebuilt_tree=%d root=%d parts=%d get_num=%d stage_before=%d stage_after=%d side_before=%d side_after=%d active_sentinel_same=%s active_frontend_same=%s temp_frontend=0x%X read_ok=%s error=%s',
        tostring(temp_piece_same), pcl151113_obj_addr(temp_sentinel),
        pcl151113_obj_addr(rebuilt_root), rebuilt_tree, after_root, after_count,
        after_getnum, stage_before, stage_after, side_before, side_after,
        tostring(active_sentinel_same), tostring(active_frontend_same),
        pcl151113_obj_addr(temp_frontend), tostring(post_read_ok), tostring(post_read_err)))

    if not post_read_ok then return false, 'post-temp-seam Piece read failed: ' .. tostring(post_read_err) end
    if not temp_piece_same then return false, 'temp seam did not retain supplied Piece' end
    if after_root ~= root_idx or after_count ~= part_count or after_getnum ~= part_count then
        return false, 'temp seam Piece design mismatch'
    end
    if not active_sentinel_same then return false, 'active ForgeMode sentinel changed during temp seam' end
    if not active_frontend_same then return false, 'active ForgeMode frontend changed during temp seam' end
    if not is_valid(rebuilt_root) or rebuilt_tree ~= expected_logical_tree then
        return false, 'temp rebuilt tree invalid expected=' .. tostring(expected_logical_tree) ..
            ' applied_parts=' .. tostring(part_count) ..
            ' blade_parts=' .. tostring(blade_count) ..
            ' actual=' .. tostring(rebuilt_tree)
    end

    if stage_after ~= stage_before or side_after ~= side_before then
        local restore_ok, restore_err = pcall(function()
            piece.CurrentSwordmakingStage = stage_before
            piece.CurrentSideEditingMode = side_before
        end)
        log('PCL15_11_13_STAGE_RESTORE changed=true ok=' .. tostring(restore_ok) ..
            ' error=' .. tostring(restore_err))
        if not restore_ok then return false, 'stage restore failed: ' .. tostring(restore_err) end
    else
        log('PCL15_11_13_STAGE_RESTORE changed=false')
    end

    -- The active ForgeMode was temporarily suppressed by the common import
    -- pipeline before this function. It was NOT rebuilt, so return it to normal
    -- frontend updates now.
    pcall(function() forge.bSupressFrontendUpdate = false end)

    PCL151113_TEMP_FORGE = temp
    PCL151113_TEMP_SENTINEL = temp_sentinel
    PCL151113_TEMP_FRONTEND = temp_frontend
    PCL151113_ACTIVE_FORGE = forge
    PCL151113_ACTIVE_SENTINEL = active_sentinel
    PCL151113_ACTIVE_FRONTEND = active_frontend
    PCL151113_ACTIVE_HANDLING = active_handling
    PCL151142_ACTIVE_PIECE = piece
    PCL151142_ACTIVE_STAGE_BEFORE = stage_before
    PCL151113_SOURCE_ROOT = source_root
    PCL151113_REBUILT_ROOT = rebuilt_root
    PCL151113_GAME_MODE = gm

    -- Keep both trees hidden until the active handling pointer has been swapped.
    pcl151113_set_tree_hidden(source_root, true)
    pcl151113_set_tree_hidden(rebuilt_root, true)
    pcl151113_make_temp_inert(temp)

    log(string.format(
        'PCL15_11_13_ACTIVE_FORGE_UNTOUCHED forge=0x%X sentinel=0x%X frontend=0x%X handling=0x%X source_tree=%d temp_host=0x%X',
        active_addr, active_sentinel_addr, active_frontend_addr,
        active_handling_addr, live_tree_count_14(source_root), pcl151113_obj_addr(temp)))

    return true, nil
end


-- 15.11.56 direct preview-state rearm. 15.11.55 proved that calling the
-- full native pickup wrapper can enter a specialized "pick a part" branch and
-- disturb a reconstructed multi-part hierarchy. Keep the complete rebuilt root
-- assigned through UE reflection, then invoke only the non-selection state tail
-- used by Bladesong's plain preview branch.
PCL151156_NATIVE_REARM = nil
PCL151156_NATIVE_REARM_LOAD_ERROR = nil

local function pcl151156_get_native_rearm()
    if PCL151156_NATIVE_REARM ~= nil then
        return PCL151156_NATIVE_REARM, nil
    end
    if PCL151156_NATIVE_REARM_LOAD_ERROR ~= nil then
        return nil, PCL151156_NATIVE_REARM_LOAD_ERROR
    end
    local dll_path = pcl151112_script_dir() .. 'pcl_native_seam.dll'
    local loader, load_err = BMF_PCL_NATIVE(dll_path, 'pcl_native_rearm_preview')
    if loader == nil then
        PCL151156_NATIVE_REARM_LOAD_ERROR = tostring(load_err)
        return nil, PCL151156_NATIVE_REARM_LOAD_ERROR
    end
    PCL151156_NATIVE_REARM = loader
    return loader, nil
end

-- Handoff override: use the exact root produced by the temporary host instead
-- of scanning all live actors (there are intentionally now two 50-part trees).
PCL151184_ACTIVE_BLADE_SUPPRESS_RUNS = 0

function pcl151184_hide_runtime_blade_object(obj)
    obj = pcl151114_unwrap(obj)
    if not is_valid(obj) then return false, false end
    local actor_hidden = false
    local component_hidden = false
    pcall(function()
        obj:SetActorHiddenInGame(true)
        actor_hidden = true
    end)
    pcall(function()
        obj:SetVisibility(false, false)
        obj:SetHiddenInGame(true, false)
        component_hidden = true
    end)
    return actor_hidden, component_hidden
end

function pcl151184_suppress_active_blade_preview(active_forge, reason)
    if not is_valid(active_forge) then
        log('PCL15_11_90_ACTIVE_BLADE_PREVIEW_SUPPRESS ok=false reason=active_forge_invalid stage=' .. tostring(reason))
        return false
    end

    PCL151184_ACTIVE_BLADE_SUPPRESS_RUNS = PCL151184_ACTIVE_BLADE_SUPPRESS_RUNS + 1
    local blade_mesh = nil
    local tutorial_shape = nil
    pcall(function() blade_mesh = active_forge.BladeMesh end)
    pcall(function() tutorial_shape = active_forge.TutorialBladeShape end)

    local blade_actor_hidden, blade_component_hidden = pcl151184_hide_runtime_blade_object(blade_mesh)
    local tutorial_actor_hidden, tutorial_component_hidden = pcl151184_hide_runtime_blade_object(tutorial_shape)

    log(string.format(
        'PCL15_11_90_ACTIVE_BLADE_PREVIEW_SUPPRESS run=%d stage=%s blade_mesh=0x%X blade_actor_hidden=%s blade_component_hidden=%s tutorial_shape=0x%X tutorial_actor_hidden=%s tutorial_component_hidden=%s data_blade_parts=0 behavior=presentation_only_runtime_blade_hidden',
        PCL151184_ACTIVE_BLADE_SUPPRESS_RUNS, tostring(reason),
        pcl151113_obj_addr(pcl151114_unwrap(blade_mesh)), tostring(blade_actor_hidden), tostring(blade_component_hidden),
        pcl151113_obj_addr(pcl151114_unwrap(tutorial_shape)), tostring(tutorial_actor_hidden), tostring(tutorial_component_hidden)))
    return blade_actor_hidden or blade_component_hidden or tutorial_actor_hidden or tutorial_component_hidden
end

function pcl15104_finish_handoff(forge3, design3, source_label)
    local ctx = pcl15104_context
    if ctx == nil or not pcl1510_running then return false, 'context unavailable' end

    local active_forge = PCL151113_ACTIVE_FORGE
    local active_sentinel = PCL151113_ACTIVE_SENTINEL
    local handling = PCL151113_ACTIVE_HANDLING
    local source_root = PCL151113_SOURCE_ROOT
    local temp = PCL151113_TEMP_FORGE
    local temp_sentinel = PCL151113_TEMP_SENTINEL
    local rebuilt_root = PCL151113_REBUILT_ROOT

    if not is_valid(active_forge) then return false, 'captured active ForgeMode unavailable' end
    if not is_valid(active_sentinel) then return false, 'captured active sentinel unavailable' end
    if not is_valid(handling) then return false, 'captured active handling unavailable' end
    if not is_valid(temp) or not is_valid(temp_sentinel) then return false, 'temp host unavailable' end
    if not is_valid(rebuilt_root) then return false, 'temp rebuilt root unavailable' end

    local expected_tree = ctx.logical_tree_count or ctx.part_count
    local tree_before = live_tree_count_14(rebuilt_root)
    log('PCL15_11_13_HANDOFF_BEGIN rebuilt_root=' .. safe_full_name(rebuilt_root) ..
        ' tree=' .. tostring(tree_before) .. ' expected=' .. tostring(expected_tree) ..
        ' applied_parts=' .. tostring(ctx.part_count) ..
        ' source=' .. tostring(source_label))
    if tree_before ~= expected_tree then
        return false, 'rebuilt tree changed before handoff count=' .. tostring(tree_before)
    end
    pcl151160_presentation_audit(rebuilt_root, 'pre_logical_unlink')

    -- Detach the native rebuilt tree from the TEMP sentinel.
    local temp_remove_result = nil
    local temp_unlink_ok, temp_unlink_err = pcall(function()
        temp_remove_result = temp_sentinel.SlotChildParts:Remove(0)
    end)
    log('PCL15_11_13_TEMP_SENTINEL_UNLINK ok=' .. tostring(temp_unlink_ok) ..
        ' result=' .. tostring(temp_remove_result) .. ' error=' .. tostring(temp_unlink_err))
    if not temp_unlink_ok then return false, 'temp sentinel unlink failed: ' .. tostring(temp_unlink_err) end

    -- 15.11.61: logical SlotChildParts unlink does not detach the Unreal scene
    -- hierarchy. 15.11.60 measured this root still parented to the TEMP
    -- SwordPartEmptyActor here and after quarantine. Detach it now, preserving
    -- world transform, before the temp host is hidden.
    local scene_detach_ok, scene_detach_err = pcl151161_detach_rebuilt_root_scene(rebuilt_root)
    if not scene_detach_ok then
        return false, 'temp scene detach failed: ' .. tostring(scene_detach_err)
    end
    pcl151160_presentation_audit(rebuilt_root, 'post_scene_detach')

    -- Remove the hidden direct-spawn source tree from the REAL active sentinel.
    -- It remains alive/hidden for this compatibility test; no root ResetPiece or
    -- DissolveFromParent is used.
    if is_valid(source_root) then
        local active_remove_result = nil
        local active_unlink_ok, active_unlink_err = pcall(function()
            active_remove_result = active_sentinel.SlotChildParts:Remove(0)
        end)
        log('PCL15_11_13_ACTIVE_SENTINEL_SOURCE_UNLINK ok=' .. tostring(active_unlink_ok) ..
            ' result=' .. tostring(active_remove_result) .. ' error=' .. tostring(active_unlink_err))
        if not active_unlink_ok then return false, 'active source unlink failed: ' .. tostring(active_unlink_err) end
    else
        log('PCL15_11_65_ACTIVE_SOURCE_UNLINK_SKIPPED reason=no_staging_source_tree')
    end

    local tree_after = live_tree_count_14(rebuilt_root)
    if tree_after ~= expected_tree then
        return false, 'rebuilt tree changed after temp unlink count=' .. tostring(tree_after)
    end
    pcl151160_presentation_audit(rebuilt_root, 'post_logical_unlink')

    pcl151113_set_tree_hidden(source_root, true)
    local unhidden = pcl151113_set_tree_hidden(rebuilt_root, false)

    -- 15.11.60 crash rollback: restore the non-calling 15.11.58 handoff state.
    -- This enum normalization is NOT considered the visual fix; it only keeps
    -- the known-safe baseline while the presentation attachment is audited.
    local handoff_piece = PCL151142_ACTIVE_PIECE
    local handoff_stage_before = -1
    local handoff_stage_after = -1
    local handoff_stage_changed = false
    local stage_ok, stage_err = pcall(function()
        if is_valid(handoff_piece) then
            handoff_stage_before = tonumber(handoff_piece.CurrentSwordmakingStage) or -1
            if handoff_stage_before == 0 then
                handoff_piece.CurrentSwordmakingStage = 1
                handoff_stage_changed = true
            end
            handoff_stage_after = tonumber(handoff_piece.CurrentSwordmakingStage) or -1
        end
    end)
    log('PCL15_11_60_HANDOFF_STAGE_BASELINE ok=' .. tostring(stage_ok) ..
        ' before=' .. tostring(handoff_stage_before) ..
        ' after=' .. tostring(handoff_stage_after) ..
        ' changed=' .. tostring(handoff_stage_changed) ..
        ' reflected_stage_call=false error=' .. tostring(stage_err))
    if not stage_ok or handoff_stage_after ~= 1 then
        return false, 'safe handoff stage baseline failed: ' .. tostring(stage_err)
    end

    -- 15.11.58: restore the proven 15.11.42/15.11.49 raw full-tree handoff.
    -- The repeat-import failure was not a missing pickup/rearm notification: the
    -- global handling lookup could select a retained TEMP Forge's disabled
    -- SwordPartHandling component. pcl1511_private_rebuild now captures handling
    -- strictly from the active ForgeModeFrontend, so no native pickup/rearm call
    -- is needed and the reconstructed hierarchy is never disturbed.
    local preview_before = nil
    pcall(function() preview_before = handling.PreviewSwordPartActor end)
    local preview_before_addr = pcl151113_obj_addr(preview_before)

    local hand_ok, hand_err = pcall(function()
        handling.PreviewSwordPartActor = rebuilt_root
    end)
    if not hand_ok then
        return false, 'active PreviewSwordPartActor write failed: ' .. tostring(hand_err)
    end

    local assigned_preview = nil
    local assigned_ok = false
    pcall(function()
        assigned_preview = handling.PreviewSwordPartActor
        assigned_ok = is_valid(assigned_preview) and
            pcl151113_obj_addr(assigned_preview) == pcl151113_obj_addr(rebuilt_root)
    end)
    local assigned_tree = live_tree_count_14(assigned_preview)
    log('PCL15_11_60_RAW_ACTIVE_HANDOFF' ..
        ' preview_before=0x' .. string.format('%X', preview_before_addr) ..
        ' active_handling=0x' .. string.format('%X', pcl151113_obj_addr(handling)) ..
        ' assigned_ok=' .. tostring(assigned_ok) ..
        ' tree=' .. tostring(assigned_tree) ..
        ' expected=' .. tostring(expected_tree) ..
        ' native_pickup_called=false native_rearm_called=false')
    if not assigned_ok or assigned_tree ~= expected_tree then
        return false, 'raw active-Forge preview assignment did not retain rebuilt logical root'
    end
    if ctx.direct_json == true and (ctx.blade_part_count or 0) == 0 then
        pcl151184_suppress_active_blade_preview(active_forge, 'after_preview_assign')
    end
    pcl151160_presentation_audit(rebuilt_root, 'after_active_preview_assign')

    local preview = nil
    local has_preview = false
    pcall(function()
        preview = handling.PreviewSwordPartActor
        has_preview = handling:HasPreviewSwordPart() and true or false
    end)
    local held_count = live_tree_count_14(preview)

    -- Reassert the actual player ForgeMode after all temporary-host work.
    pcl151113_restore_game_mode_forge(PCL151113_GAME_MODE, active_forge, 'FINAL')
    pcl151113_make_temp_inert(temp)

    -- 15.11.15: presentation quarantine may legitimately encounter objects that
    -- overlap the rebuilt preview graph.  The temp helpers must stay hidden, but
    -- the transferred prefab always wins the final visibility pass.
    local post_quarantine_visible = pcl151113_set_tree_hidden(rebuilt_root, false)
    log('PCL15_11_15_POST_QUARANTINE_VISIBILITY_REASSERT=' ..
        tostring(post_quarantine_visible) .. ' expected=' .. tostring(expected_tree))
    pcl151160_presentation_audit(rebuilt_root, 'post_temp_quarantine')

    pcall(function() active_forge.bSupressFrontendUpdate = false end)
    if ctx.direct_json == true and (ctx.blade_part_count or 0) == 0 then
        pcl151184_suppress_active_blade_preview(active_forge, 'after_frontend_resume')
    end

    log('PCL15_11_13_VERIFY_TEMP_RETAINED=' .. tostring(is_valid(PCL151113_TEMP_FORGE)))
    log('PCL15_11_13_VERIFY_UNHIDDEN_TREE=' .. tostring(post_quarantine_visible) ..
        ' expected=' .. tostring(expected_tree))
    log('PREFAB15_10_VERIFY_HAS_PREVIEW=' .. tostring(has_preview))
    log('PREFAB15_10_VERIFY_HELD_TREE_COUNT=' .. tostring(held_count) ..
        ' expected=' .. tostring(expected_tree) ..
        ' applied_parts=' .. tostring(ctx.part_count))
    log('PCL15_11_13_HANDOFF_SOURCE=' .. tostring(source_label))

    if has_preview and is_valid(preview) and held_count == expected_tree then
        log('PCL15_11_13_OK FULL PREFAB HELD; ACTIVE FORGEMODE NEVER REBUILT')
    else
        return false, 'active preview verification incomplete'
    end

    log('PREFAB15_10_CATALOGUE_CLICKS=0')
    log('PREFAB15_10_ENTER_FORGE_MODE_CALLS=0')
    log('PCL15_11_13_INIT_IN_EDITOR_CALLS=0')
    log('PREFAB15_10_CURSOR_MOVED=false')
    log('PREFAB15_10_4_FIXED_DELAY_MS=0')
    log('Move normally and LEFT CLICK once to place.')

    if PCL151117_CACHE ~= nil then
        local st = PCL151117_CACHE.stats or {}
        log(string.format(
            'PCL15_11_18_FAST_STATS identity_hit=%d identity_miss=%d class_hit=%d class_miss=%d material_handle_hit=%d material_handle_miss=%d render_skipped=%d data_only_links=%d slot_hit=%d slot_miss=%d apply_cache_hit=%d',
            st.identity_hits or 0, st.identity_misses or 0,
            st.class_hits or 0, st.class_misses or 0,
            st.material_handle_hits or 0, st.material_handle_misses or 0,
            st.render_assets_skipped or 0, st.data_only_links or 0,
            st.slot_hits or 0, st.slot_misses or 0,
            st.apply_cache_hits or 0))
    end
    PCL151117_CACHE = nil
    if ctx.direct_json == true then
        PCL151165_DIRECT_JSON_MODE = false
        log('PCL15_11_65_DIRECT_JSON_IMPORT_OK parts=' .. tostring(ctx.part_count) ..
            ' logical_tree=' .. tostring(expected_tree) ..
            ' blade_parts=' .. tostring(ctx.blade_part_count or 0) ..
            ' staging_actors=0 serialize_calls=0 map_passes=0 apply_parts=0')
    end
    pcl15104_context = nil
    pcl1510_running = false
    log('============================================================')
    return true, nil
end

-- If the handoff has to yield, do not rediscover ForgeMode globally because a
-- retained temporary host intentionally exists. Retry only against captured
-- objects.
function pcl15104_retry_ready_state()
    if not pcl1510_running or pcl15104_context == nil then return end
    pcl15104_context.attempt = pcl15104_context.attempt + 1
    local done, reason = pcl15104_finish_handoff(
        PCL151113_ACTIVE_FORGE,
        nil,
        'temp_host_retry_' .. tostring(pcl15104_context.attempt))
    if done then return end

    log('PCL15_11_13_NOT_READY attempt=' .. tostring(pcl15104_context.attempt) ..
        ' reason=' .. tostring(reason))
    if pcl15104_context.attempt >= 120 then
        pcl1510_fail('temp-host handoff never became ready: ' .. tostring(reason))
        pcl15104_context = nil
        return
    end
    schedule_game_11(0, pcl15104_retry_ready_state)
end


-- Restore the real UE4SS key registration function only now.
RegisterKeyBind =
    __PCL159_REAL_REGISTER_KEY_BIND

-- Phase 15.11.37 import bindings.
-- CTRL+ALT+I keeps the established prefab_root_1.pcl behavior.
-- CTRL+ALT+P loads prefab_root_0.pcl through the exact same import pipeline.
-- phase1510_begin only reads PCL_IMPORT_FILENAME during its synchronous parse/setup
-- section, so the root-0 wrapper can restore the default immediately afterward.
function pcl151137_import_root0()
    if pcl1510_running then
        log("PREFAB15_10_ERROR already running")
        return
    end

    local previous_filename = PCL_IMPORT_FILENAME
    PCL_IMPORT_FILENAME = "prefab_root_0.pcl"
    log("PCL15_11_37_IMPORT_SELECT root=0 file=" .. tostring(PCL_IMPORT_FILENAME))

    local ok, err = pcall(phase1510_begin)
    PCL_IMPORT_FILENAME = previous_filename

    if not ok then
        log("PCL15_11_37_ROOT0_IMPORT_ERROR=" .. tostring(err))
        -- phase1510_begin sets pcl1510_running before parsing.  A Lua
        -- exception can therefore bypass its normal pcl1510_fail paths and
        -- leave the importer permanently wedged as "already running".
        -- Always unwind import-scoped state after a caught exception.
        if pcl1510_running then
            pcl1510_fail("root0 import exception: " .. tostring(err))
        else
            pcl11_session = nil
            PCL151117_CACHE = nil
        end
    end
end

RegisterKeyBind(
    Key.I,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(
            phase1510_begin
        )
    end
)

RegisterKeyBind(
    Key.P,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(
            pcl151137_import_root0
        )
    end
)

log("Phase 15.11.13 TEMP FORGEMODE NATIVE REBUILD HOST loader loaded.")
log("All historical PCL probe keybind registrations were suppressed except the active import/export bindings.")
log("CTRL+ALT+I = import scripts\\prefab_root_1.pcl through the Phase 15.11.13 temp-Forge rebuild/handoff pipeline.")
log("CTRL+ALT+P = import scripts\\prefab_root_0.pcl through the same pipeline.")
log("Native bridge active: scripts/pcl_native_seam.dll; active ForgeMode is never passed to the seam; no InitInEditor and no EnterForgeMode call.")
log("Active PCL import hotkeys: CTRL+ALT+I=root1, CTRL+ALT+P=root0. Temp host is retained inert after handoff; runtime seam RVA=0x45AF640.")

-- ============================================================================
-- Phase 15.11.14 - Temporary-host presentation quarantine
--
-- Phase 15.11.13 proved the native rebuild is stable when hosted by a separate
-- ForgeMode.  The temporary host still constructs its own UI and world-space
-- interaction helpers, though, which can leak visible artifacts into the real
-- player's viewport.  Keep the host alive for native/delegate lifetime safety,
-- but remove/hide ONLY its presentation objects after the seam returns.
-- ============================================================================

PCL151114_PRESENTATION_CLEANUP_RUNS = 0
PCL151114_TEMP_HOSTS = PCL151114_TEMP_HOSTS or {}

function pcl151114_unwrap(value)
    if value == nil then return nil end
    local out = value
    pcall(function()
        local v = value:get()
        if v ~= nil then out = v end
    end)
    return out
end

function pcl151114_hide_actor(actor)
    actor = pcl151114_unwrap(actor)
    if not is_valid(actor) then return false end
    if PCL151758_CLEANUP_PROTECTION and PCL151758_CLEANUP_PROTECTION[actor:GetAddress()] then
        log('PCL15_17_58_ACTIVE_HANDLE_PROTECTED actor='..tostring(actor:GetAddress()))
        return false
    end
    pcall(function() actor:SetActorHiddenInGame(true) end)
    pcall(function() actor:SetActorTickEnabled(false) end)
    pcall(function() actor:SetActorEnableCollision(false) end)
    return true
end

function pcl151114_hide_scene_component(component)
    component = pcl151114_unwrap(component)
    if not is_valid(component) then return false end
    -- 15.11.16: NEVER propagate presentation hiding from a temp-host helper
    -- component into attached children. TranslationPivot can sit above the
    -- rebuilt sword-part components in the scene hierarchy; propagating here
    -- makes the 50 actors report visible while their mesh components remain
    -- invisible.
    pcall(function() component:SetVisibility(false, false) end)
    pcall(function() component:SetHiddenInGame(true, false) end)
    pcall(function() component:SetComponentTickEnabled(false) end)
    pcall(function() component:SetActive(false, false) end)
    return true
end

function pcl151114_remove_widget(widget, active_widget_addr)
    widget = pcl151114_unwrap(widget)
    if not is_valid(widget) then return false, 'invalid' end
    local addr = pcl151113_obj_addr(widget)
    if active_widget_addr ~= nil and active_widget_addr ~= 0 and addr == active_widget_addr then
        return false, 'refused_active_widget'
    end
    pcall(function() widget:StopAllAnimations() end)
    pcall(function() widget:CancelLatentActions() end)
    local opacity_ok = pcall(function() widget:SetRenderOpacity(0.0) end)
    local enabled_ok = pcall(function() widget:SetIsEnabled(false) end)
    local remove_ok, remove_err = pcall(function() widget:RemoveFromParent() end)
    return remove_ok, 'opacity=' .. tostring(opacity_ok) ..
        ',enabled=' .. tostring(enabled_ok) .. ',remove_error=' .. tostring(remove_err)
end

function pcl151114_hide_array_actors(array_obj)
    if array_obj == nil then return 0 end
    local hidden = 0
    pcall(function()
        array_obj:ForEach(function(_, vp)
            local actor = pcl151114_unwrap(vp)
            if pcl151114_hide_actor(actor) then
                hidden = hidden + 1
                if PCL151732_CLEANUP_HOST then pcl151732_queue_helper(PCL151732_CLEANUP_HOST,actor) end
            end
        end)
    end)
    return hidden
end

function pcl151114_hide_interactable_manager(manager)
    manager = pcl151114_unwrap(manager)
    if not is_valid(manager) then return 0 end
    local items = nil
    pcall(function() items = manager.InteractableElements end)
    return pcl151114_hide_array_actors(items)
end

function pcl151114_hide_blade_interaction(blade_interaction)
    blade_interaction = pcl151114_unwrap(blade_interaction)
    if not is_valid(blade_interaction) then return 0 end
    pcl151113_disable_component(blade_interaction)

    local hidden = 0
    local interactables = nil
    pcall(function() interactables = blade_interaction.Interactables end)
    hidden = hidden + pcl151114_hide_array_actors(interactables)

    local line = nil
    pcall(function() line = blade_interaction.IntensityLineRenderer end)
    if pcl151114_hide_actor(line) then hidden = hidden + 1 end

    local extra_lines = nil
    pcall(function() extra_lines = blade_interaction.ExtraControlLineRenderers end)
    hidden = hidden + pcl151114_hide_array_actors(extra_lines)

    return hidden
end

function pcl151114_quarantine_temp_presentation(temp)
    if not is_valid(temp) then return false, 'temp invalid' end
    PCL151114_PRESENTATION_CLEANUP_RUNS = PCL151114_PRESENTATION_CLEANUP_RUNS + 1

    pcl151113_set_actor_inert(temp, true)
    pcall(function() temp.bSupressFrontendUpdate = true end)

    local frontend = nil
    local active_frontend = PCL151113_ACTIVE_FRONTEND
    pcall(function() frontend = temp.ForgeModeFrontend end)
    if not is_valid(frontend) then
        return false, 'temp frontend invalid'
    end
    pcl151113_set_actor_inert(frontend, true)

    local active_ui = nil
    local active_watermark = nil
    if is_valid(active_frontend) then
        pcall(function() active_ui = active_frontend.ForgeModeUi end)
        pcall(function() active_watermark = active_frontend.WatermarkUi end)
    end
    local active_ui_addr = pcl151113_obj_addr(active_ui)
    local active_watermark_addr = pcl151113_obj_addr(active_watermark)

    local temp_ui = nil
    local temp_watermark = nil
    pcall(function() temp_ui = frontend.ForgeModeUi end)
    pcall(function() temp_watermark = frontend.WatermarkUi end)

    -- Remove the entire temporary Forge UI from the viewport.  The UObject is
    -- intentionally retained by the temp frontend; RemoveFromParent only stops
    -- it from being drawn/participating in layout.
    local ui_removed, ui_detail = pcl151114_remove_widget(temp_ui, active_ui_addr)
    local watermark_removed, watermark_detail = pcl151114_remove_widget(temp_watermark, active_watermark_addr)

    -- Explicitly quarantine CraftAllButton too in case the Blueprint detached
    -- it into a separate viewport/layout layer.
    local craft_button = nil
    pcall(function()
        if is_valid(temp_ui) then craft_button = temp_ui.CraftAllButton end
    end)
    local craft_removed, craft_detail = pcl151114_remove_widget(craft_button, 0)

    local handling = nil
    local camera = nil
    local blade_interaction = nil
    local interactable_manager = nil
    pcall(function() handling = frontend.SwordPartHandling end)
    pcall(function() camera = frontend.CameraHandling end)
    pcall(function() blade_interaction = frontend.BladeInteraction end)
    pcall(function() interactable_manager = frontend.InteractableManager end)

    pcl151113_disable_component(handling)
    pcl151113_disable_component(camera)

    local slot_hidden = 0
    local aux_hidden = 0
    if is_valid(handling) then
        local slot_pool = nil
        pcall(function() slot_pool = handling.SwordPartSlotActorPool end)
        slot_hidden = pcl151114_hide_array_actors(slot_pool)

        -- Keep the pool allocated and referenced, but report no temporary-host
        -- hardpoints as visible.  This is presentation state only.
        pcall(function() handling.SwordPartSlotActorsVisible = 0 end)

        local bend = nil
        local material_preview = nil
        local material_bad = nil
        pcall(function() bend = handling.BendLineRenderer end)
        pcall(function() material_preview = handling.MaterialPreviewActor end)
        pcall(function() material_bad = handling.MaterialNotAllowedActor end)
        if pcl151114_hide_actor(bend) then aux_hidden = aux_hidden + 1 end
        if pcl151114_hide_actor(material_preview) then aux_hidden = aux_hidden + 1 end
        if pcl151114_hide_actor(material_bad) then aux_hidden = aux_hidden + 1 end
    end

    local interactable_hidden = pcl151114_hide_interactable_manager(interactable_manager)
    local blade_hidden = pcl151114_hide_blade_interaction(blade_interaction)

    -- Hide temp-only auxiliary actors/components owned directly by ForgeMode.
    local direct_aux_hidden = 0
    local names = {
        'BladeMesh', 'TutorialBladeShape', 'PreviewImageCapture', 'SwordOutlineCapture'
    }
    for _, name in ipairs(names) do
        local obj = nil
        pcall(function() obj = temp[name] end)
        if pcl151114_hide_actor(obj) then direct_aux_hidden = direct_aux_hidden + 1 end
    end

    local translation_pivot = nil
    pcall(function() translation_pivot = temp.TranslationPivot end)
    local pivot_hidden = pcl151114_hide_scene_component(translation_pivot)

    -- Frontend Niagara/audio presentation can remain referenced but inactive.
    local metal_glow_instance = nil
    local audio_loop = nil
    pcall(function() metal_glow_instance = frontend.NSMetalGlowInstance end)
    pcall(function() audio_loop = frontend.AudioComponentBladeManipulateLoop end)
    pcl151114_hide_scene_component(metal_glow_instance)
    pcl151114_hide_scene_component(audio_loop)

    log(string.format(
        'PCL15_11_14_PRESENTATION_QUARANTINE run=%d temp=0x%X frontend=0x%X temp_ui=0x%X active_ui=0x%X ui_removed=%s watermark_removed=%s craft_removed=%s slot_markers_hidden=%d interactables_hidden=%d blade_helpers_hidden=%d aux_hidden=%d direct_aux_hidden=%d pivot_hidden=%s ui_detail=%s watermark_detail=%s craft_detail=%s',
        PCL151114_PRESENTATION_CLEANUP_RUNS,
        pcl151113_obj_addr(temp), pcl151113_obj_addr(frontend),
        pcl151113_obj_addr(temp_ui), active_ui_addr,
        tostring(ui_removed), tostring(watermark_removed), tostring(craft_removed),
        slot_hidden, interactable_hidden, blade_hidden, aux_hidden,
        direct_aux_hidden, tostring(pivot_hidden), tostring(ui_detail),
        tostring(watermark_detail), tostring(craft_detail)))

    return true, nil
end

-- Replace 15.11.13's minimal inerting with full presentation quarantine while
-- retaining the temporary ForgeMode and all native lifecycle objects.
function pcl151113_make_temp_inert(temp)
    if not is_valid(temp) then return end

    local active=find_forge()
    if not is_valid(active) or active:GetAddress()==temp:GetAddress() then return end
    local active_frontend=active.ForgeModeFrontend
    if is_valid(temp.ForgeModeFrontend) and is_valid(active_frontend) and temp.ForgeModeFrontend:GetAddress()==active_frontend:GetAddress() then
        log('PCL15_17_30_INERT_REFUSED shared active frontend');return
    end
    local sentinel = nil
    local frontend = nil
    local handling = nil
    local camera = nil
    pcall(function() sentinel = temp:GetRootSwordPartActor() end)
    pcall(function() frontend = temp.ForgeModeFrontend end)
    if is_valid(frontend) then
        pcall(function() handling = frontend.SwordPartHandling end)
        pcall(function() camera = frontend.CameraHandling end)
    end

    -- Sentinel remains hidden/inert, but never hide the rebuilt root here; it
    -- is detached and deliberately unhidden by the normal 15.11.13 handoff.
    pcl151113_set_actor_inert(temp, true)
    if pcl151112_addr(sentinel)~=pcl151112_addr(active:GetRootSwordPartActor()) then pcl151113_set_actor_inert(sentinel,true) end
    local active_handling=is_valid(active_frontend) and active_frontend.SwordPartHandling
    local active_camera=is_valid(active_frontend) and active_frontend.CameraHandling
    if pcl151112_addr(handling)~=pcl151112_addr(active_handling) then pcl151113_disable_component(handling) end
    if pcl151112_addr(camera)~=pcl151112_addr(active_camera) then pcl151113_disable_component(camera) end

    local cleanup_ok, cleanup_err = pcl151114_quarantine_temp_presentation(temp)

    local found = false
    for _, host in ipairs(PCL151114_TEMP_HOSTS) do
        if pcl151113_obj_addr(host) == pcl151113_obj_addr(temp) then found = true break end
    end
    if not found then table.insert(PCL151114_TEMP_HOSTS, temp) end

    log(string.format(
        'PCL15_11_14_TEMP_INERT temp=0x%X sentinel=0x%X frontend=0x%X handling=0x%X camera=0x%X retained=true presentation_quarantined=%s error=%s retained_hosts=%d',
        pcl151113_obj_addr(temp), pcl151113_obj_addr(sentinel),
        pcl151113_obj_addr(frontend), pcl151113_obj_addr(handling),
        pcl151113_obj_addr(camera), tostring(cleanup_ok), tostring(cleanup_err),
        #PCL151114_TEMP_HOSTS))
end

log('Phase 15.11.14 TEMP-HOST PRESENTATION QUARANTINE active.')
log('15.11.13 native temp-host rebuild/handoff unchanged; temp Forge UI, slot markers, interactables, and auxiliary visuals are quarantined after rebuild.')


-- ============================================================================
-- Phase 15.11.15 - Final visibility ownership + stable active-Forge selection
--
-- 15.11.14 successfully removed the temp host's visual artifacts, but the
-- second quarantine pass could hide actors that overlap the transferred native
-- preview.  The handoff above now reasserts visibility on exactly the rebuilt
-- 50-part graph after quarantine.  Also, retained temp ForgeModes must never be
-- selected as the player's ForgeMode on a later import in the same session.
-- ============================================================================

PCL151115_ORIGINAL_FIND_FORGE = PCL151115_ORIGINAL_FIND_FORGE or find_forge

function pcl151115_is_retained_temp_forge(candidate)
    if not is_valid(candidate) then return false end
    local addr = pcl151113_obj_addr(candidate)
    if addr == 0 then return false end
    if PCL151730_HOST_REGISTRY and PCL151730_HOST_REGISTRY[addr] then return true end
    if PCL151114_TEMP_HOSTS ~= nil then
        for _, host in ipairs(PCL151114_TEMP_HOSTS) do
            if is_valid(host) and pcl151113_obj_addr(host) == addr then
                return true
            end
        end
    end
    return false
end

find_forge = function()
    -- The authoritative player ForgeMode is the one owned by the current
    -- Creative GameMode. Prefer it over FindFirstOf(), which can return one of
    -- our deliberately retained temporary reconstruction hosts.
    local gm = nil
    local authoritative = nil
    pcall(function() gm = find_creative_game_mode_6() end)
    if is_valid(gm) then
        pcall(function() authoritative = gm.ForgeMode end)
        if is_valid(authoritative) and not pcl151115_is_retained_temp_forge(authoritative) then
            return authoritative
        end
    end

    local fallback = nil
    if PCL151115_ORIGINAL_FIND_FORGE ~= nil then
        pcall(function() fallback = PCL151115_ORIGINAL_FIND_FORGE() end)
    end
    if is_valid(fallback) and not pcl151115_is_retained_temp_forge(fallback) then
        return fallback
    end

    -- Last-resort scan: use a live ForgeMode that is not one of our hosts.
    local all = nil
    pcall(function() all = FindAllOf('BP_ForgeMode_C') end)
    if all ~= nil then
        for _, candidate in ipairs(all) do
            if is_valid(candidate) and not pcl151115_is_retained_temp_forge(candidate) then
                return candidate
            end
        end
    end
    return nil
end

log('Phase 15.11.15 VISIBILITY OWNERSHIP + ACTIVE FORGE SELECTION active.')
log('Temp presentation remains quarantined; transferred prefab visibility is reasserted AFTER quarantine.')
log('Repeated imports prefer GameMode.ForgeMode and ignore all retained temporary reconstruction hosts.')


-- ============================================================================
-- Phase 15.11.16 - Non-propagating helper visibility
--
-- 15.11.15 proved the transferred 50-part preview remained valid but rendered
-- invisible. The cause was component-level visibility propagation from temp
-- helper SceneComponents (especially TranslationPivot). Helper cleanup now
-- affects ONLY the helper component itself; it never propagates to attached
-- sword-part mesh components.
-- ============================================================================
log('Phase 15.11.16 NON-PROPAGATING HELPER VISIBILITY active.')
log('PCL15_11_16_COMPONENT_HIDE_PROPAGATES=false; 15.11.13 rebuild/handoff and 15.11.15 active-Forge ownership unchanged.')


-- ============================================================================
-- Phase 15.11.17 - Import hot-path optimization
--
-- Stability boundary unchanged from 15.11.16.  Only Lua-side preparation is
-- accelerated: import-scoped identity/class/asset/slot caches, direct serialized
-- SlotChildren native-index mapping, one capture of AppliedSwordParts, and
-- reduced per-part diagnostic chatter.
-- ============================================================================
log('Phase 15.11.17 IMPORT HOT-PATH OPTIMIZATION active.')
log('15.11.16 native seam/temp-host/presentation/handoff are unchanged; optimization caches are import-scoped and discarded after each run.')
log('Phase 15.11.18 DATA-ONLY STAGING active.')
log('Staging render assets/procedural copies/scene attachments are skipped; material handles and FNames are import-cached. Native seam/handoff are unchanged.')

-- ============================================================================
-- Phase 15.11.22 - AppliedSwordParts copy-amplification profiler
--
-- 15.11.20 silently terminated when the native reconstruction seam fired.
-- Root cause: the first trampoline used `mov rax, imm64 ; jmp rax` to return
-- from the copied prologue.  The then-current ForgeMode::Rebuild at 0x45B02F0 intentionally
-- stores the incoming RSP in RAX in its first instruction and keeps using RAX
-- after the stolen bytes.  Clobbering RAX in the trampoline corrupted that
-- prologue state and caused a native process termination.
--
-- 15.11.20.1 fixes that with a 14-byte register-preserving RIP-indirect jump:
--   FF 25 00 00 00 00 + qword destination
-- and removes the HTTP completion callback detour entirely.  We only detour:
--   0x45A2C50  ABladesongGameMode::EnterForgeMode native body
--   0x45B02F0  ForgeMode native reconstruction seam
-- Phase 15.11.26 rebases these to 0x45A1FA0 and 0x45AF640 respectively.
--
-- The reflected DownloadPiece hook remains timing-only. Phase 15.11.45 keeps
-- actual fast-path activation into the native EnterForgeMode hook, where the
-- loaded Piece already exists and its AppliedSwordParts count can be checked.
-- This keeps borrowed-array patches off during network/download wait time.
-- ============================================================================

PCLMWNATIVE = {
    install = nil,
    arm = nil,
    disarm = nil,
    read = nil,
    alias_on = nil,
    alias_off = nil,
    load_error = nil,
    installed = false,
    active = false,
    run = 0,
    download_pre_id = nil,
    download_post_id = nil,
}

function pclmwnative_load()
    if PCLMWNATIVE.install ~= nil then return true, nil end
    if PCLMWNATIVE.load_error ~= nil then return false, PCLMWNATIVE.load_error end

    local path = pcl151112_script_dir() .. 'pcl_mw_native_prof.dll'
    local install_fn, e1, w1 = BMF_PCL_NATIVE(path, 'pcl_mw_prof_install')
    local arm_fn, e2, w2 = BMF_PCL_NATIVE(path, 'pcl_mw_prof_arm')
    local disarm_fn, e3, w3 = BMF_PCL_NATIVE(path, 'pcl_mw_prof_disarm')
    local read_fn, e4, w4 = BMF_PCL_NATIVE(path, 'pcl_mw_prof_read')
    local alias_on_fn, e5, w5 = BMF_PCL_NATIVE(path, 'pcl_mw_prof_alias_on')
    local alias_off_fn, e6, w6 = BMF_PCL_NATIVE(path, 'pcl_mw_prof_alias_off')

    if type(install_fn) ~= 'function' or type(arm_fn) ~= 'function' or
       type(disarm_fn) ~= 'function' or type(read_fn) ~= 'function' or
       type(alias_on_fn) ~= 'function' or type(alias_off_fn) ~= 'function' then
        PCLMWNATIVE.load_error = string.format(
            'loadlib failed path=%s install=%s/%s arm=%s/%s disarm=%s/%s read=%s/%s alias_on=%s/%s alias_off=%s/%s',
            tostring(path), tostring(e1), tostring(w1), tostring(e2), tostring(w2),
            tostring(e3), tostring(w3), tostring(e4), tostring(w4),
            tostring(e5), tostring(w5), tostring(e6), tostring(w6))
        return false, PCLMWNATIVE.load_error
    end

    PCLMWNATIVE.install = install_fn
    PCLMWNATIVE.arm = arm_fn
    PCLMWNATIVE.disarm = disarm_fn
    PCLMWNATIVE.read = read_fn
    PCLMWNATIVE.alias_on = alias_on_fn
    PCLMWNATIVE.alias_off = alias_off_fn
    return true, nil
end

function pclmwnative_verify(run)
    if run ~= PCLMWNATIVE.run then return end
    local gm, forge, piece, root = nil, nil, nil, nil
    local parts = -1
    local forge_addr, piece_addr, root_addr = 0, 0, 0

    pcall(function() gm = find_creative_game_mode_6() end)
    if is_valid(gm) then pcall(function() forge = gm.ForgeMode end) end
    if is_valid(forge) then
        pcall(function() piece = forge:GetPiece() end)
        pcall(function() root = forge:GetRootSwordPartActor() end)
        pcall(function() forge_addr = tonumber(forge:GetAddress()) or 0 end)
    end
    if is_valid(piece) then
        pcall(function() parts = piece:GetNumSwordParts() end)
        pcall(function() piece_addr = tonumber(piece:GetAddress()) or 0 end)
    end
    if is_valid(root) then pcall(function() root_addr = tonumber(root:GetAddress()) or 0 end) end

    log(string.format(
        'MWNATIVE_VERIFY run=%d parts=%d forge=0x%X piece=0x%X root=0x%X',
        run, tonumber(parts) or -1, forge_addr, piece_addr, root_addr))
end

function pclmwnative_poll(run, attempt)
    if run ~= PCLMWNATIVE.run or not PCLMWNATIVE.active then return end
    if type(PCLMWNATIVE.read) ~= 'function' then return end

    local ok, installed, armed, enter_count, seam_count,
          request_to_enter_us, enter_us, seam_us, piece_ptr,
          child_a_count, child_a_us, child_b_count, child_b_us,
          child_c_count, child_c_us, child_d_count, child_d_us,
          child_e_count, child_e_us, applied_count, blade_count,
          copy_calls, copy_elements, copy_us,
          clone_alloc_calls, clone_alloc_us, clone_destroy_calls, clone_destroy_us,
          actor_make_calls, actor_make_us, actor_link_calls, actor_link_us,
          defer_threshold, deferred_refresh_calls, final_refresh_calls,
          final_refresh_us, final_refresh_root,
          link_notify_calls, link_notify_us, link_map_calls, link_map_us,
          actor_spawn_calls, actor_spawn_us, actor_resolve_calls, actor_resolve_us,
          actor_data_calls, actor_data_us = pcall(PCLMWNATIVE.read)

    if not ok then
        log('MWNATIVE_READ_ERROR run=' .. tostring(run) .. ' error=' .. tostring(installed))
        PCLMWNATIVE.active = false
        return
    end

    installed = tonumber(installed) or 0
    armed = tonumber(armed) or 0
    enter_count = tonumber(enter_count) or 0
    seam_count = tonumber(seam_count) or 0
    request_to_enter_us = tonumber(request_to_enter_us) or 0
    enter_us = tonumber(enter_us) or 0
    seam_us = tonumber(seam_us) or 0
    piece_ptr = tonumber(piece_ptr) or 0
    child_a_count = tonumber(child_a_count) or 0
    child_a_us = tonumber(child_a_us) or 0
    child_b_count = tonumber(child_b_count) or 0
    child_b_us = tonumber(child_b_us) or 0
    child_c_count = tonumber(child_c_count) or 0
    child_c_us = tonumber(child_c_us) or 0
    child_d_count = tonumber(child_d_count) or 0
    child_d_us = tonumber(child_d_us) or 0
    child_e_count = tonumber(child_e_count) or 0
    child_e_us = tonumber(child_e_us) or 0
    applied_count = tonumber(applied_count) or 0
    blade_count = tonumber(blade_count) or 0
    copy_calls = tonumber(copy_calls) or 0
    copy_elements = tonumber(copy_elements) or 0
    copy_us = tonumber(copy_us) or 0
    clone_alloc_calls = tonumber(clone_alloc_calls) or 0
    clone_alloc_us = tonumber(clone_alloc_us) or 0
    clone_destroy_calls = tonumber(clone_destroy_calls) or 0
    clone_destroy_us = tonumber(clone_destroy_us) or 0
    actor_make_calls = tonumber(actor_make_calls) or 0
    actor_make_us = tonumber(actor_make_us) or 0
    actor_link_calls = tonumber(actor_link_calls) or 0
    actor_link_us = tonumber(actor_link_us) or 0
    defer_threshold = tonumber(defer_threshold) or 0
    deferred_refresh_calls = tonumber(deferred_refresh_calls) or 0
    final_refresh_calls = tonumber(final_refresh_calls) or 0
    final_refresh_us = tonumber(final_refresh_us) or 0
    final_refresh_root = tonumber(final_refresh_root) or 0
    link_notify_calls = tonumber(link_notify_calls) or 0
    link_notify_us = tonumber(link_notify_us) or 0
    link_map_calls = tonumber(link_map_calls) or 0
    link_map_us = tonumber(link_map_us) or 0
    actor_spawn_calls = tonumber(actor_spawn_calls) or 0
    actor_spawn_us = tonumber(actor_spawn_us) or 0
    actor_resolve_calls = tonumber(actor_resolve_calls) or 0
    actor_resolve_us = tonumber(actor_resolve_us) or 0
    actor_data_calls = tonumber(actor_data_calls) or 0
    actor_data_us = tonumber(actor_data_us) or 0

    if enter_count > 0 and enter_us > 0 then
        local enter_overhead_us = enter_us - seam_us
        if enter_overhead_us < 0 then enter_overhead_us = 0 end
        log(string.format(
            'MWNATIVE_RESULT run=%d request_to_enter_us=%d enter_forge_us=%d native_seam_us=%d enter_overhead_us=%d counts=enter:%d/seam:%d piece=0x%X',
            run, request_to_enter_us, enter_us, seam_us, enter_overhead_us,
            enter_count, seam_count, piece_ptr))
        local known_us = child_a_us + child_b_us + child_c_us + child_d_us + child_e_us
        local unclassified_us = seam_us - known_us
        if unclassified_us < 0 then unclassified_us = 0 end
        log(string.format(
            'MWDEEP_CHILDREN run=%d A[rva=0x45C73B0 count=%d us=%d] B[rva=0x45E89A0 count=%d us=%d] C[rva=0x45E8EA0 count=%d us=%d] D[rva=0x45BAF80 count=%d us=%d] E[rva=0x45C7950 count=%d us=%d] known_us=%d unclassified_us=%d',
            run, child_a_count, child_a_us, child_b_count, child_b_us,
            child_c_count, child_c_us, child_d_count, child_d_us,
            child_e_count, child_e_us, known_us, unclassified_us))
        local copy_bytes = copy_elements * 0x120
        local copy_gib = copy_bytes / (1024 * 1024 * 1024)
        log(string.format(
            'MWCOPY_AMPLIFICATION run=%d applied=%d blade_entries=%d copy_calls=%d copied_elements=%d copied_bytes=%d copied_gib=%.3f copy_us=%d',
            run, applied_count, blade_count, copy_calls, copy_elements, copy_bytes, copy_gib, copy_us))
        if applied_count > 0 then
            log(string.format(
                'MWCOPY_RATIO run=%d copies_per_applied=%.3f elements_per_applied=%.3f',
                run, copy_calls / applied_count, copy_elements / applied_count))
        end
        local clone_lifecycle_us = clone_alloc_us + copy_us + clone_destroy_us
        local actor_stage_us = actor_make_us + actor_link_us
        local classified_leaf_us = clone_lifecycle_us + actor_stage_us
        local residual_d_us = child_d_us - classified_leaf_us
        if residual_d_us < 0 then residual_d_us = 0 end
        log(string.format(
            'MWCOST_BREAKDOWN run=%d clone_alloc[count=%d us=%d] clone_copy[count=%d us=%d] clone_destroy[count=%d us=%d] clone_lifecycle_us=%d actor_make[count=%d us=%d] actor_link[count=%d us=%d] actor_stage_us=%d classified_leaf_us=%d residual_d_us=%d',
            run, clone_alloc_calls, clone_alloc_us, copy_calls, copy_us,
            clone_destroy_calls, clone_destroy_us, clone_lifecycle_us,
            actor_make_calls, actor_make_us, actor_link_calls, actor_link_us,
            actor_stage_us, classified_leaf_us, residual_d_us))
        if applied_count > 0 then
            log(string.format(
                'MWCOST_PER_PART run=%d applied=%d alloc_us_per=%.3f copy_us_per=%.3f destroy_us_per=%.3f actor_make_us_per=%.3f actor_link_us_per=%.3f',
                run, applied_count, clone_alloc_us / applied_count, copy_us / applied_count,
                clone_destroy_us / applied_count, actor_make_us / applied_count,
                actor_link_us / applied_count))
        end
        log(string.format(
            'MWFAST_DEFER_RESULT run=%d threshold=%d eligible=%s deferred_refresh_calls=%d final_refresh_calls=%d final_refresh_us=%d final_refresh_root=0x%X behavior_changed=%s',
            run, defer_threshold, tostring(applied_count >= defer_threshold and defer_threshold > 0),
            deferred_refresh_calls, final_refresh_calls, final_refresh_us, final_refresh_root,
            tostring(deferred_refresh_calls > 0)))
        local link_known_us = link_notify_us + link_map_us
        local link_residual_us = actor_link_us - link_known_us
        if link_residual_us < 0 then link_residual_us = 0 end
        local make_known_nonoverlap_us = actor_spawn_us + actor_resolve_us
        local make_residual_us = actor_make_us - make_known_nonoverlap_us
        if make_residual_us < 0 then make_residual_us = 0 end
        log(string.format(
            'MWSTAGE_DEEP run=%d link_notify[rva=0x3412800 count=%d us=%d] link_map[rva=0x45C97A0 count=%d us=%d] link_known_us=%d link_residual_us=%d actor_spawn[rva=0x39B5920 count=%d us=%d] actor_resolve[rva=0x45ACF20 count=%d us=%d] actor_data_nested[rva=0x45A59A0 count=%d us=%d] make_known_nonoverlap_us=%d make_residual_us=%d',
            run, link_notify_calls, link_notify_us, link_map_calls, link_map_us,
            link_known_us, link_residual_us, actor_spawn_calls, actor_spawn_us,
            actor_resolve_calls, actor_resolve_us, actor_data_calls, actor_data_us,
            make_known_nonoverlap_us, make_residual_us))
        if seam_count == 0 then
            log(string.format(
                'MWNATIVE_RESULT_NOTE run=%d EnterForgeMode_completed_without_native_seam=true', run))
        end
        pcall(function() PCLMWNATIVE.disarm() end)
        PCLMWNATIVE.active = false
        schedule_game_11(1, function() pclmwnative_verify(run) end)
        return
    end

    attempt = (tonumber(attempt) or 0) + 1
    if attempt == 20 or attempt == 100 or attempt == 300 then
        log(string.format(
            'MWNATIVE_WAIT run=%d elapsed_poll_ms~%d enter=%d seam=%d armed=%d',
            run, attempt * 50, enter_count, seam_count, armed))
    end
    if attempt >= 600 then
        log(string.format(
            'MWNATIVE_TIMEOUT run=%d after_ms~30000 enter=%d seam=%d',
            run, enter_count, seam_count))
        pcall(function() PCLMWNATIVE.disarm() end)
        PCLMWNATIVE.active = false
        return
    end
    schedule_game_11(50, function() pclmwnative_poll(run, attempt) end)
end

function pclmwnative_register()
    local loaded, load_err = pclmwnative_load()
    if not loaded then
        log('MWNATIVE_DLL_LOAD=false error=' .. tostring(load_err))
        return
    end

    local ok_install, install_status = pcall(PCLMWNATIVE.install)
    install_status = tonumber(install_status) or -999
    if not ok_install or install_status ~= 1 then
        log(string.format('MWNATIVE_INSTALL=false status=%s pcall=%s',
            tostring(install_status), tostring(ok_install)))
        return
    end
    PCLMWNATIVE.installed = true
    log('MWNATIVE_INSTALL=true phase=15.11.90 profiler_core=15.11.57 bridge_core=15.11.90 export_hotkeys=true export_registration_local_limit_fix=true import_piece_limit=none free_children=true precon_bridge_profiler_coexistence=true exe_size=0x90A0000 deep_children=true copy_amplification=true per_part_costs=true deferred_child_refresh=true borrowed_applied_array=true borrowed_array_scope=general_persistent_backing_plus_pcl_direct_legacy exact_byte_patch_guard=true general_load_auto_arm=true magic_word_zero_copy=persistent_backing creative_menu_zero_copy=persistent_backing pcl_direct_zero_copy=legacy_guarded deep_link_spawn_substages=true actor_make_helper_profile=false scoped_h4_reuse_profile=true scoped_h4_payload_stability=true scoped_h4_component_stability=true scoped_h4_cache_benefit=true scoped_h4_vertex_cache=true scoped_h4_post_loop_profile=true scoped_h4_nested_component_profile=update_only scoped_h4_update_direct_profile=false scoped_h4_update_cardinality=true scoped_h4_update_tail_profile=callsite_only scoped_h4_update_virtual_profile=vtable_slots h4_cache_proof=8 h4_cache_canary=128 scoped_h4_lifetime=seam_only stock_free_zero_copy=temporary_allocations_only persistent_backing_copies=1 persistent_backing_cap=64 immediate_raw_free=false clone_alloc_target_corrected=true defer_threshold=512 callback_detour=false enter_forge_rva=0x45A1FA0 seam_rva=0x45AF640 child_rvas=0x45C73B0,0x45E89A0,0x45E8EA0,0x45BAF80,0x45C7950 cost_rvas=0x10D0AB0,0x452F0C4,0x459E680,0x45E9D30 refresh_rva=0x45F3BD0 stage_rvas=0x3412800,0x45C97A0,0x39B5920,0x45ACF20,0x45A59A0 raw_free_rva=0x11531C0 trampoline_jump=RIP_INDIRECT_NONCLOBBERING behavior_changed=construction_only_direct_json_plus_selective_h4_vertex_cache_plus_safe_update_tail_callsite_plus_vtable_slot_profile_plus_bab0_plus_d20_child_profile')

    local hook_ok, hook_err = pcall(function()
        PCLMWNATIVE.download_pre_id, PCLMWNATIVE.download_post_id =
            RegisterHook('/Script/Bladesong.UWCreativeMode:DownloadPiece',
                function()
                    if PCLMWNATIVE.active then
                        pcall(function() PCLMWNATIVE.disarm() end)
                    end
                    -- 15.11.45: Magic Word is always a stock-ownership load.
                    -- Clear any stale explicit PCL alias request before arming.
                    pcall(function() PCLMWNATIVE.alias_off() end)
                    PCLMWNATIVE.run = (PCLMWNATIVE.run or 0) + 1
                    local run = PCLMWNATIVE.run
                    local arm_ok, arm_status = pcall(PCLMWNATIVE.arm)
                    arm_status = tonumber(arm_status) or -999
                    PCLMWNATIVE.active = arm_ok and arm_status == 1
                    log(string.format(
                        'MWNATIVE_DOWNLOAD_PRE run=%d arm_ok=%s arm_status=%s parameters_touched=false',
                        run, tostring(arm_ok), tostring(arm_status)))
                    if PCLMWNATIVE.active then
                        schedule_game_11(50, function() pclmwnative_poll(run, 0) end)
                    end
                end,
                function()
                    if PCLMWNATIVE.active then
                        log(string.format(
                            'MWNATIVE_DOWNLOAD_POST run=%d request_enqueued=true parameters_touched=false',
                            PCLMWNATIVE.run))
                    end
                end)
    end)

    log(string.format(
        'MWNATIVE_DOWNLOAD_HOOK=%s pre_id=%s post_id=%s error=%s',
        tostring(hook_ok), tostring(PCLMWNATIVE.download_pre_id),
        tostring(PCLMWNATIVE.download_post_id), tostring(hook_err)))
end

pclmwnative_register()

-- Phase 15.11.47: passive reporting for native auto-optimized creation loads.
-- General zero-copy is now owned by already-installed allocator/copy/destructor
-- detours and does not rewrite reconstruction call-site bytes. This one-second
-- poll only emits diagnostics after a >=512-part general load completes.
PCL1543_GENERAL_LAST_SEQ = 0
function pcl1543_general_load_poll()
    if PCLMWNATIVE ~= nil and PCLMWNATIVE.installed and type(PCLMWNATIVE.read) == 'function' then
        local r = {pcall(PCLMWNATIVE.read)}
        if r[1] then
            -- read() historical values occupy r[2]..r[51]. 15.11.43+ appends:
            -- seq, pre_applied, source_mode, alias_status, alias_used, restore_ok, fail_closed.
            local seq = tonumber(r[52]) or 0
            if seq > (PCL1543_GENERAL_LAST_SEQ or 0) then
                PCL1543_GENERAL_LAST_SEQ = seq
                local pre_applied = tonumber(r[53]) or 0
                local source_mode = tonumber(r[54]) or 0
                local alias_status = tonumber(r[55]) or 0
                local alias_used = tonumber(r[56]) or 0
                local restore_ok = tonumber(r[57]) or 0
                local fail_closed = tonumber(r[58]) or 0
                -- 15.11.47 appends six hook-owned zero-copy diagnostics.
                local hook_zero_copy_calls = tonumber(r[59]) or 0
                local hook_zero_copy_elements = tonumber(r[60]) or 0
                local hook_peak = tonumber(r[61]) or 0
                local hook_destroy_suppressed = tonumber(r[62]) or 0
                local hook_guard_misses = tonumber(r[63]) or 0
                local hook_fallback_copies = tonumber(r[64]) or 0
                -- 15.11.49 actor_make helper telemetry follows the 15.11.47 hook fields.
                local make_h1_calls, make_h1_us = tonumber(r[65]) or 0, tonumber(r[66]) or 0
                local make_h2_calls, make_h2_us = tonumber(r[67]) or 0, tonumber(r[68]) or 0
                local make_h3_calls, make_h3_us = tonumber(r[69]) or 0, tonumber(r[70]) or 0
                local make_h4_calls, make_h4_us = tonumber(r[71]) or 0, tonumber(r[72]) or 0
                local make_params_calls, make_params_us = tonumber(r[73]) or 0, tonumber(r[74]) or 0
                -- 15.11.57 persistent-backing diagnostics. One stock deep copy is
                -- retained per optimized general load; the remaining recursive
                -- clones should be zero-copy aliases of that stable backing.
                local backing_stock_copies = tonumber(r[75]) or 0
                local backing_retained = tonumber(r[76]) or 0
                local retained_backing_count = tonumber(r[77]) or 0
                local seam_count = tonumber(r[5]) or 0
                local seam_us = tonumber(r[8]) or 0
                local applied = tonumber(r[20]) or 0
                local copy_calls = tonumber(r[22]) or 0
                local copy_elements = tonumber(r[23]) or 0
                local actor_make_calls, actor_make_us = tonumber(r[29]) or 0, tonumber(r[30]) or 0
                local spawn_us = tonumber(r[43]) or 0
                local resolve_us = tonumber(r[45]) or 0
                local data_us = tonumber(r[47]) or 0
                local deferred = tonumber(r[34]) or 0
                local final_refresh = tonumber(r[35]) or 0
                log(string.format(
                    'PCL15_11_47_GENERAL_LOAD seq=%d source=%s pre_applied=%d applied=%d alias_used=%s alias_status=%d restore_ok=%s seam_count=%d seam_us=%d copy_calls=%d copy_elements=%d deferred_refresh_calls=%d final_refresh_calls=%d fail_closed=%d hook_zero_copy_calls=%d hook_zero_copy_elements=%d hook_peak=%d hook_destroy_suppressed=%d hook_guard_misses=%d hook_fallback_copies=%d',
                    seq, ({[1]='auto_enterforge',[2]='prearmed_enterforge',[3]='auto_seam',[4]='prearmed_seam'})[source_mode] or ('mode_' .. tostring(source_mode)),
                    pre_applied, applied, tostring(alias_used == 1), alias_status,
                    tostring(restore_ok == 1), seam_count, seam_us, copy_calls,
                    copy_elements, deferred, final_refresh, fail_closed,
                    hook_zero_copy_calls, hook_zero_copy_elements, hook_peak,
                    hook_destroy_suppressed, hook_guard_misses, hook_fallback_copies))
                log(string.format(
                    'PCL15_11_57_GENERAL_BACKING stock_copies=%d backing_retained=%s retained_session=%d expected_stock_copies=1',
                    backing_stock_copies, tostring(backing_retained == 1), retained_backing_count))
                local make_known_us = spawn_us + resolve_us + data_us + make_h1_us + make_h2_us + make_h3_us + make_h4_us + make_params_us
                local make_residual_us = actor_make_us - make_known_us
                if make_residual_us < 0 then make_residual_us = 0 end
                log(string.format(
                    'PCL15_11_49_ACTOR_MAKE_PROFILE scope=general seq=%d actor_make[count=%d us=%d] spawn_us=%d resolve_us=%d data_us=%d H1[rva=0x45F9759 count=%d us=%d] H2[rva=0x45F8720 count=%d us=%d] H3[rva=0x45F8770 count=%d us=%d] H4[rva=0x45F8080 count=%d us=%d] PARAMS[rva=0x3EEC910 count=%d us=%d] known_nonoverlap_us=%d residual_us=%d',
                    seq, actor_make_calls, actor_make_us, spawn_us, resolve_us, data_us,
                    make_h1_calls, make_h1_us, make_h2_calls, make_h2_us,
                    make_h3_calls, make_h3_us, make_h4_calls, make_h4_us,
                    make_params_calls, make_params_us, make_known_us, make_residual_us))
                if restore_ok ~= 1 and type(PCLMWNATIVE.disarm) == 'function' then
                    local repair_ok, repair_status = pcall(PCLMWNATIVE.disarm)
                    log(string.format(
                        'PCL15_11_47_GENERAL_RESTORE_RETRY seq=%d ok=%s status=%s',
                        seq, tostring(repair_ok), tostring(repair_status)))
                end
            end
        end
    end
    schedule_game_11(1000, pcl1543_general_load_poll)
end
schedule_game_11(1000, pcl1543_general_load_poll)

-- Phase 15.11.39: preload/cache the unchanged native seam bridge during mod
-- initialization instead of paying package.loadlib latency on the first import.
-- The bridge function is still the exact 15.11.28 coexistence-safe bridge and
-- no rebuild behavior changes here; this only moves one-time DLL load work off
-- the import hot path.
function pcl151139_preload_native_bridge()
    local t0 = os.clock()
    log('PCL15_11_39_BRIDGE_PRELOAD_BEGIN')
    local fn, err = pcl151112_get_native_call()
    local elapsed_ms = (os.clock() - t0) * 1000.0
    log(string.format(
        'PCL15_11_39_BRIDGE_PRELOAD_END ok=%s cached=%s elapsed_ms=%.3f error=%s',
        tostring(type(fn) == 'function'), tostring(type(PCL151112_NATIVE_CALL) == 'function'),
        elapsed_ms, tostring(err)))
end
pcl151139_preload_native_bridge()

log('Phase 15.11.28 PRECON BRIDGE/PROFILER COEXISTENCE FIX active.')
log('The PCL bridge accepts the exact stock seam or verified 15.11.27/15.11.40/15.11.43/15.11.45/15.11.49 profiler seam detours; arbitrary detours remain rejected.')

-- ============================================================================
-- Phase 15.11.30 - restore only the proven Phase 2 PCL export hotkeys.
-- All other historical probe bindings remain suppressed.
-- Keep the iterator locals inside a separate Lua function: the monolithic main
-- chunk is already at Lua's 200-local limit.
-- ============================================================================
function pcl151130_register_export_hotkeys()
    for _, pair in ipairs(export_keys) do
        local export_key = pair[1]
        local root_index = pair[2]
        __PCL159_REAL_REGISTER_KEY_BIND(
            export_key,
            {ModifierKey.CONTROL, ModifierKey.ALT},
            function()
                run_game_thread(function()
                    write_prefab(root_index)
                end)
            end)
    end
end
pcl151130_register_export_hotkeys()

log('Phase 15.11.30 PCL EXPORT HOTKEYS active.')
log('CTRL+ALT+F1..F9 export native root index 0..8 to scripts\\prefab_root_N.pcl. All other historical probe hotkeys remain suppressed.')
log('Phase 15.11.31 ACTIVE IMPORT PIECE LIMIT REMOVED.')
log('CTRL+ALT+I accepts any positive PCL part_count; the former 250-part ceiling is disabled.')
log('Phase 15.11.32 EXPERIMENTAL FREE CHILDREN IMPORT active.')
log('CTRL+ALT+I reconstructs saved FreeChildParts FTransforms and maps serialized FAppliedSwordPart.FreeChildren alongside SlotChildren.')
log('Phase 15.11.33 EMPTY-DESIGN CLASS RESOLVER GUARD active.')
log('Legacy actor-class fallback skips build_actor_map_10 while Forge design is empty and caches resolved classes by SwordPart row.')
log('Phase 15.11.34 LEGACY FREE-CHILD CLASS HOLE RECOVERY active.')
log('Phase 15.11.35 TARGETED CHAIN FREE-CHILD CLASS RECOVERY active.')
log('Phase 15.11.36 SAFE LARGE-GRAPH EXPORT SNAPSHOT active.')
log('Phase 15.11.37 ROOT-0 IMPORT HOTKEY active.')
log('Phase 15.11.38 DIRECT-SEAM DEFERRED REFRESH OPTIMIZATION active.')
log('Phase 15.11.39 EAGER NATIVE BRIDGE PRELOAD active.')
log('Phase 15.11.41 BRIDGE SIGNATURE COEXISTENCE FOR BORROWED-ARRAY PROFILER active.')
log('Phase 15.11.42 ACTIVE HANDOFF PLACEMENT-STAGE NORMALIZATION active.')
log('Phase 15.11.46 PCL BRIDGE SIGNATURE UPDATE active.')
log('Phase 15.11.47 DETOUR-OWNED GENERAL ZERO-COPY experiment active.')
log('Phase 15.11.48 REPEAT-IMPORT PARSER + EXCEPTION-UNWIND HARDENING active.')
log('Phase 15.11.49 ACTOR-MAKE DEEP PROFILING active.')
log('15.11.49 adds exact-byte-guarded timing only for actor_make helper RVAs 0x45F9759,0x45F8720,0x45F8770,0x45F8080,0x3EEC910; loading behavior is unchanged.')
log('Creative-menu/Magic Word >=512: deferred refresh + zero-copy through allocator/copy/destructor hooks; no runtime reconstruction call-site patching.')
log('PCL direct import keeps the proven 15.11.40 exact-byte guarded alias path for this version.')
log('Completed prefab handoff changes Piece stage 0 to placement stage 1 before assigning PreviewSwordPartActor; stages already at 1 are untouched.')
log('The native seam bridge now accepts the exact verified 15.11.45 profiler seam-hook prologue plus the prior 15.11.43/15.11.40/15.11.27 prologues; spawn/rebuild semantics are unchanged.')
log('Phase 15.11.40 BORROWED APPLIED-ARRAY RECURSION active.')
log('PCL direct imports >=512 parts arm deferred refresh and temporarily borrow the read-only Piece.AppliedSwordParts array through the native recursive walker instead of deep-copying it at every recursion edge.')
log('15.11.45 keeps deferred child-refresh optimization on >=512-part Creative-menu and Magic Word loads, but restores stock AppliedSwordParts copy/ownership semantics there. Borrowed-array recursion is PCL-direct-only.')
log('CTRL+ALT+P imports scripts\\prefab_root_0.pcl; CTRL+ALT+I remains scripts\\prefab_root_1.pcl.')
log('Export actor mapping snapshots SlotChildren/FreeChildren into Lua before recursion and reuses one actor map for class + render metadata.')
log('455_MiscAttachment_ChainElement resolves directly to SwordPartDeformableStaticMeshActor before reflected Blueprint/RenderAsset access.')
log('Import seeds exact actor classes by SwordPart row from the prefab itself; empty-Forge live actor scans are disabled. Future exports backfill same-row class/render holes.')

log('Phase 15.11.50 REPEAT PCL HANDOFF REARM active.')
log('Phase 15.11.51 PROFILER/BRIDGE SIGNATURE COMPATIBILITY active.')
log('15.11.51 adds the exact packaged 15.11.49 pcl_mw_seam_hook prologue to the native rebuild bridge allow-list; repeat-handoff behavior is unchanged from 15.11.50.')
log('Phase 15.11.52 STOCK-FREE GENERAL ZERO-COPY active.')
log('Phase 15.11.53 REPEAT-HANDOFF PICKUP LOADER PATH FIX active.')
log('15.11.53 resolves pcl_native_try_pickup from the established script directory instead of the undefined MOD_DIR global; native pickup, zero-copy, deferred refresh, bridge, and profiler behavior are otherwise unchanged.')
log('Phase 15.11.56 DIRECT PREVIEW STATE REARM active.')
log('Phase 15.11.57 GENERAL ZERO-COPY PERSISTENT BACKING active.')
log('15.11.57 Creative/Magic Word loads keep one retained stock deep-copy backing per load; recursive clones alias that stable backing. PCL direct zero-copy remains legacy_guarded.')
log('Phase 15.11.58 ACTIVE-HANDLING OWNERSHIP FIX active.')
log('15.11.58 binds handoff exclusively to active ForgeModeFrontend.SwordPartHandling; retained temp-host handling components are never selected for player handoff.')
log('15.11.58 restores the proven raw full-tree PreviewSwordPartActor assignment and disables the 15.11.55/15.11.56 native pickup/rearm calls in the active PCL handoff path.')
log('Phase 15.11.59 REAL FORGE STAGE TRANSITION code retained for source history but DISABLED in the active import path.')
log('Phase 15.11.60 SETSTAGE CRASH ROLLBACK + PRESENTATION ATTACHMENT AUDIT active.')
log('15.11.60 never calls reflected Forge:SetStage/NextStage during PCL import; 15.11.59 crashed immediately at that boundary before the native seam.')
log('15.11.60 restores the safe handoff-stage baseline and passively audits rebuilt-root/component attachment/visibility/pending state before and after handoff/quarantine.')
log('15.11.60 keeps 15.11.58 active-handling ownership and 15.11.57 persistent-backing general zero-copy unchanged.')
log('Phase 15.11.61 TEMP-SENTINEL SCENE DETACH active.')
log('15.11.61 detaches the rebuilt root actor from the temporary SwordPartEmptyActor scene parent with KeepWorld rules immediately after logical SlotChildParts unlink.')
log('15.11.61 fails closed if the rebuilt RootComponent still has an AttachParent after scene detach; no SwordPart ResetPiece/DissolveFromParent or Forge stage-machine call is used.')
log('15.11.61 keeps 15.11.60 safe stage baseline, 15.11.58 active-handling ownership, and 15.11.57 persistent-backing general zero-copy unchanged.')
log('Phase 15.11.62 EPHEMERAL APPLIED-PART WRAPPER STREAMING active.')
log('15.11.62 replaces the long-lived 3316-entry FAppliedSwordPart wrapper table with a plain integer graph snapshot plus one streamed apply/validation pass; this targets the clean-session AV immediately after PREFAB15_10_SERIALIZED in 15.11.61.')
log('15.11.62 keeps the 15.11.61 temp-sentinel scene-detach handoff unchanged because that code was never reached in the 15.11.61 crash log.')


-- ============================================================================
-- Phase 15.11.63 - SHIPPED FWeaponDesignDefinition JSON EXPORT PROBE
--
-- Static RE of the shipped ForgeModeFrontend copy/paste path proved that
-- Bladesong already serializes Piece.WeaponDesignDefinition directly through
-- FJsonObjectConverter/UStructToJsonObjectString, then places the resulting
-- FString on the Windows clipboard. The matching paste path deserializes JSON
-- straight into a temporary FWeaponDesignDefinition and copies it to Piece.
--
-- This probe exposes ONLY the read/export half through the guarded native
-- bridge. The proven 15.11.62 PCL import path is not changed.
--
-- CTRL+ALT+J:
--   1) resolves the authoritative active GameMode.ForgeMode -> Piece
--   2) asks the native bridge to use Bladesong's own WDD JSON serializer
--   3) leaves the exact game-native JSON on the Windows clipboard
--   4) best-effort saves that clipboard text beside main.lua as
--      bladesong_weapon_design_native.json using PowerShell
-- ============================================================================

PCL151163_JSON_COPY_FN = nil
PCL151163_JSON_COPY_LOAD_ERROR = nil
PCL151163_JSON_FILENAME = 'bladesong_weapon_design_native.json'

function pcl151163_get_json_copy_fn()
    if type(PCL151163_JSON_COPY_FN) == 'function' then
        return PCL151163_JSON_COPY_FN, nil
    end
    if PCL151163_JSON_COPY_LOAD_ERROR ~= nil then
        return nil, PCL151163_JSON_COPY_LOAD_ERROR
    end

    local dll_path = pcl151112_script_dir() .. PCL151112_BRIDGE_FILENAME
    local fn, err, where = BMF_PCL_NATIVE(dll_path, 'pcl_native_copy_weapon_json')
    if type(fn) ~= 'function' then
        PCL151163_JSON_COPY_LOAD_ERROR =
            'package.loadlib failed path=' .. tostring(dll_path) ..
            ' error=' .. tostring(err) .. ' where=' .. tostring(where)
        return nil, PCL151163_JSON_COPY_LOAD_ERROR
    end

    PCL151163_JSON_COPY_FN = fn
    log('PCL15_11_63_JSON_BRIDGE_LOADED path=' .. tostring(dll_path) ..
        ' static_struct_rva=0x4580920 serializer_rva=0x20C5580 clipboard_set_rva=0x1504B00')
    return fn, nil
end

function pcl151163_active_piece()
    local gm = nil
    pcall(function() gm = find_creative_game_mode_6() end)
    if not is_valid(gm) then
        return nil, nil, 'Creative GameMode unavailable'
    end

    local forge = nil
    pcall(function() forge = gm.ForgeMode end)
    if not is_valid(forge) then
        return nil, nil, 'authoritative GameMode.ForgeMode unavailable'
    end

    local piece = nil
    pcall(function() piece = forge:GetPiece() end)
    if not is_valid(piece) then
        return forge, nil, 'active ForgeMode Piece unavailable'
    end

    return forge, piece, nil
end

function pcl151163_shell_quote_single(s)
    return tostring(s or ''):gsub("'", "''")
end

function pcl151163_save_clipboard_json(path)
    -- Diagnostic convenience only. The JSON itself is generated by Bladesong;
    -- PowerShell merely copies the already-generated clipboard text to disk.
    local quoted = pcl151163_shell_quote_single(path)
    local command = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' ..
        '"$t=Get-Clipboard -Raw; [System.IO.File]::WriteAllText(' ..
        "'" .. quoted .. "',$t,[System.Text.UTF8Encoding]::new($false))" ..
        '"'

    local exec_ok = false
    local exec_a, exec_b, exec_c = nil, nil, nil
    local ok, a, b_, c = pcall(function()
        return os.execute(command)
    end)
    if ok then
        exec_a, exec_b, exec_c = a, b_, c
        if a == true or a == 0 or c == 0 then exec_ok = true end
    end

    local size = -1
    local first = ''
    local f = io.open(path, 'rb')
    if f ~= nil then
        size = f:seek('end') or -1
        f:seek('set', 0)
        first = f:read(1) or ''
        f:close()
    end

    return exec_ok, size, first, exec_a, exec_b, exec_c
end

function pcl151163_export_native_json()
    log('============================================================')
    log('PCL15_11_63_NATIVE_JSON_EXPORT_BEGIN')

    local forge, piece, state_err = pcl151163_active_piece()
    if state_err ~= nil then
        log('PCL15_11_63_NATIVE_JSON_EXPORT_ERROR=' .. tostring(state_err))
        log('============================================================')
        return false, 'Export failed; see UE4SS log.'
    end

    local piece_addr = pcl151112_addr(piece)
    local forge_addr = pcl151112_addr(forge)
    local root_idx = -1
    local part_count = -1
    local version = -999
    local stage = -1
    local read_ok, read_err = pcall(function()
        local d = piece.WeaponDesignDefinition
        root_idx = tonumber(d.RootSwordPartIdx) or -1
        part_count = #d.AppliedSwordParts
        version = tonumber(d.Version) or -999
        stage = tonumber(piece.CurrentSwordmakingStage) or -1
    end)

    if not read_ok or piece_addr == 0 or part_count < 0 then
        log('PCL15_11_63_NATIVE_JSON_EXPORT_ERROR=piece/design read failed ' .. tostring(read_err))
        log('============================================================')
        return false, 'Export failed; see UE4SS log.'
    end

    log(string.format(
        'PCL15_11_63_NATIVE_JSON_SOURCE forge=0x%X piece=0x%X parts=%d root=%d version=%d stage=%d',
        forge_addr, piece_addr, part_count, root_idx, version, stage))

    local fn, load_err = pcl151163_get_json_copy_fn()
    if type(fn) ~= 'function' then
        log('PCL15_11_63_NATIVE_JSON_EXPORT_ERROR=' .. tostring(load_err))
        log('============================================================')
        return false, 'Export failed; see UE4SS log.'
    end

    local call_ok, result = pcall(fn, piece_addr, part_count)
    if not call_ok then
        log('PCL15_11_63_NATIVE_JSON_EXPORT_ERROR=native call exception ' .. tostring(result))
        log('============================================================')
        return false, 'Export failed; see UE4SS log.'
    end

    result = tonumber(result) or -9999
    log('PCL15_11_63_NATIVE_JSON_NATIVE_RESULT=' .. tostring(result))
    if result <= 0 then
        log('PCL15_11_63_NATIVE_JSON_EXPORT_ERROR=native status ' .. tostring(result))
        log('============================================================')
        return false, 'Export failed; see UE4SS log.'
    end

    local out_path = OUTPUT_DIR .. PCL151163_JSON_FILENAME
    local save_ok, size, first, ea, eb, ec = pcl151163_save_clipboard_json(out_path)
    local json_shape = (first == '{' or first == '[')
    log(string.format(
        'PCL15_11_63_NATIVE_JSON_CLIPBOARD_READY utf16_num=%d expected_parts=%d',
        result, part_count))
    log(string.format(
        'PCL15_11_63_NATIVE_JSON_FILE path=%s save_ok=%s size=%d first=%s json_shape=%s os_execute=%s/%s/%s',
        tostring(out_path), tostring(save_ok), tonumber(size) or -1,
        tostring(first), tostring(json_shape), tostring(ea), tostring(eb), tostring(ec)))

    if save_ok and size > 0 and json_shape then
        log('PCL15_11_63_NATIVE_JSON_EXPORT_OK')
    else
        log('PCL15_11_63_NATIVE_JSON_EXPORT_CLIPBOARD_ONLY=true')
    end
    log('============================================================')
    return save_ok and size > 0 and json_shape, out_path
end

RegisterKeyBind(
    Key.J,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(pcl151163_export_native_json)
    end
)

-- Preload only the new export symbol. Failure is logged but does not affect the
-- 15.11.62 importer or its already-preloaded pcl_native_rebuild symbol.
do
    local fn, err = pcl151163_get_json_copy_fn()
    log('PCL15_11_63_JSON_PROBE_PRELOAD ok=' .. tostring(type(fn) == 'function') ..
        ' error=' .. tostring(err))
end

log('Phase 15.11.63 SHIPPED WEAPON-DESIGN JSON probe active.')
log('CTRL+ALT+J exports the active Piece WeaponDesignDefinition using Bladesong native JSON serialization; exact JSON is placed on the clipboard and best-effort saved as scripts\\bladesong_weapon_design_native.json.')
log('15.11.62 import/rebuild/handoff behavior is unchanged in 15.11.63.')

-- ============================================================================
-- Phase 15.11.64 - SHIPPED JSON -> TEMP FWeaponDesignDefinition VALIDATION
--
-- 15.11.63 proved Bladesong's shipped serializer can export the live Piece's
-- FWeaponDesignDefinition as native JSON. This phase proves the reverse half
-- without mutating the live Piece or invoking any Forge rebuild.
--
-- CTRL+ALT+O:
--   1) places scripts\bladesong_weapon_design_native.json on the clipboard
--   2) calls the guarded native bridge
--   3) bridge follows Bladesong's stock Paste parser into a TEMP WDD only
--   4) migration/fixup runs on that TEMP WDD
--   5) raw header + SlotChildren/FreeChildren/tree edge invariants are checked
--   6) TEMP WDD is destroyed; live Piece is untouched
--
-- Positive native result = parsed AppliedSwordParts count.
-- ============================================================================

PCL151164_JSON_VALIDATE_FN = nil
PCL151164_JSON_VALIDATE_LOAD_ERROR = nil

function pcl151164_get_json_validate_fn()
    if type(PCL151164_JSON_VALIDATE_FN) == 'function' then
        return PCL151164_JSON_VALIDATE_FN, nil
    end
    if PCL151164_JSON_VALIDATE_LOAD_ERROR ~= nil then
        return nil, PCL151164_JSON_VALIDATE_LOAD_ERROR
    end

    local dll_path = pcl151112_script_dir() .. PCL151112_BRIDGE_FILENAME
    local fn, err, where = BMF_PCL_NATIVE(dll_path, 'pcl_native_validate_weapon_json')
    if type(fn) ~= 'function' then
        PCL151164_JSON_VALIDATE_LOAD_ERROR =
            'package.loadlib failed path=' .. tostring(dll_path) ..
            ' error=' .. tostring(err) .. ' where=' .. tostring(where)
        return nil, PCL151164_JSON_VALIDATE_LOAD_ERROR
    end

    PCL151164_JSON_VALIDATE_FN = fn
    log('PCL15_11_64_JSON_VALIDATE_BRIDGE_LOADED path=' .. tostring(dll_path) ..
        ' clipboard_get_rva=0x1504BF0 wdd_init_rva=0x4631C10 json_parse_rva=0x45CB7D0' ..
        ' wdd_fixup_rva=0x46382C0 wdd_destroy_rva=0x452FCE0')
    return fn, nil
end

function pcl151164_json_file_to_clipboard(path)
    local quoted = pcl151163_shell_quote_single(path)
    local command = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' ..
        '"$t=[System.IO.File]::ReadAllText(' ..
        "'" .. quoted .. "',[System.Text.Encoding]::UTF8); Set-Clipboard -Value $t" ..
        '"'

    local ok, a, b, c = pcall(function()
        return os.execute(command)
    end)
    local success = ok and (a == true or a == 0 or c == 0)
    return success, a, b, c
end

function pcl151164_validate_native_json_file()
    log('============================================================')
    log('PCL15_11_64_NATIVE_JSON_VALIDATE_BEGIN')

    local path = OUTPUT_DIR .. PCL151163_JSON_FILENAME
    local f = io.open(path, 'rb')
    if f == nil then
        log('PCL15_11_64_NATIVE_JSON_VALIDATE_ERROR=file_missing path=' .. tostring(path))
        log('============================================================')
        return
    end
    local size = f:seek('end') or -1
    f:seek('set', 0)
    local first = f:read(1) or ''
    f:close()

    log('PCL15_11_64_NATIVE_JSON_FILE path=' .. tostring(path) ..
        ' size=' .. tostring(size) .. ' first=' .. tostring(first))
    if size <= 0 or (first ~= '{' and first ~= '[') then
        log('PCL15_11_64_NATIVE_JSON_VALIDATE_ERROR=file_not_json_shaped')
        log('============================================================')
        return
    end

    local clip_ok, ca, cb, cc = pcl151164_json_file_to_clipboard(path)
    log('PCL15_11_64_NATIVE_JSON_CLIPBOARD_LOAD ok=' .. tostring(clip_ok) ..
        ' os_execute=' .. tostring(ca) .. '/' .. tostring(cb) .. '/' .. tostring(cc))
    if not clip_ok then
        log('PCL15_11_64_NATIVE_JSON_VALIDATE_ERROR=clipboard_load_failed')
        log('============================================================')
        return
    end

    local fn, load_err = pcl151164_get_json_validate_fn()
    if type(fn) ~= 'function' then
        log('PCL15_11_64_NATIVE_JSON_VALIDATE_ERROR=' .. tostring(load_err))
        log('============================================================')
        return
    end

    local call_ok, result = pcall(fn)
    if not call_ok then
        log('PCL15_11_64_NATIVE_JSON_VALIDATE_ERROR=native_call_exception ' .. tostring(result))
        log('============================================================')
        return
    end

    result = tonumber(result) or -9999
    local meaning = ({
        [-20]='module_or_pe_guard',
        [-21]='exact_signature_guard',
        [-22]='clipboard_empty_or_not_json',
        [-23]='Bladesong_JsonObjectStringToUStruct_returned_false',
        [-24]='parsed_WDD_header_sanity',
        [-25]='parsed_child_array_or_slot_index_sanity',
        [-26]='parsed_tree_edge_count_sanity'
    })[result]

    log('PCL15_11_64_NATIVE_JSON_VALIDATE_RESULT=' .. tostring(result) ..
        ' meaning=' .. tostring(meaning or (result > 0 and 'parsed_applied_sword_parts' or 'unknown')))

    if result > 0 then
        log('PCL15_11_64_NATIVE_JSON_VALIDATE_OK parts=' .. tostring(result) ..
            ' live_piece_mutated=false forge_rebuild_called=false')
    else
        log('PCL15_11_64_NATIVE_JSON_VALIDATE_FAILED status=' .. tostring(result))
    end
    log('============================================================')
    return result > 0, result
end

RegisterKeyBind(
    Key.O,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(pcl151164_validate_native_json_file)
    end
)

do
    local fn, err = pcl151164_get_json_validate_fn()
    log('PCL15_11_64_JSON_VALIDATE_PRELOAD ok=' .. tostring(type(fn) == 'function') ..
        ' error=' .. tostring(err))
end

log('Phase 15.11.64 SHIPPED WEAPON-DESIGN JSON round-trip validation active.')
log('CTRL+ALT+O parses scripts\\bladesong_weapon_design_native.json through Bladesong native JSON->FWeaponDesignDefinition code into a TEMP struct only.')
log('15.11.63 JSON export and 15.11.62 proven PCL import/rebuild/handoff remain available and unchanged.')

-- ============================================================================
-- Phase 15.11.65 - DIRECT NATIVE FWeaponDesignDefinition JSON IMPORT
--
-- 15.11.64 proved Bladesong can parse the exported JSON into a valid temporary
-- FWeaponDesignDefinition without touching the live Piece. This phase performs
-- the stock deep-copy assignment into Piece.WeaponDesignDefinition and feeds
-- that Piece directly to the already-proven TEMP Forge native rebuild seam.
--
-- No PCL staging actors are spawned, no SerializeSwordPartActorsToData() call is
-- made, no local/native index map is constructed, and no per-part APPLY pass
-- runs. CTRL+ALT+P / CTRL+ALT+I retain the 15.11.62 staging importer unchanged.
--
-- CTRL+ALT+D requires an EMPTY active Forge in Hilt Mode (stage 1).
-- ============================================================================

PCL151165_DIRECT_JSON_MODE = false
PCL151165_JSON_LOAD_FN = nil
PCL151165_JSON_LOAD_ERROR = nil

function pcl151165_get_json_load_fn()
    if type(PCL151165_JSON_LOAD_FN) == 'function' then
        return PCL151165_JSON_LOAD_FN, nil
    end
    if PCL151165_JSON_LOAD_ERROR ~= nil then
        return nil, PCL151165_JSON_LOAD_ERROR
    end

    local dll_path = pcl151112_script_dir() .. PCL151112_BRIDGE_FILENAME
    local fn, err, where = BMF_PCL_NATIVE(dll_path, 'pcl_native_load_weapon_json_into_piece')
    if type(fn) ~= 'function' then
        PCL151165_JSON_LOAD_ERROR =
            'package.loadlib failed path=' .. tostring(dll_path) ..
            ' error=' .. tostring(err) .. ' where=' .. tostring(where)
        return nil, PCL151165_JSON_LOAD_ERROR
    end

    PCL151165_JSON_LOAD_FN = fn
    log('PCL15_11_65_JSON_LOAD_BRIDGE_LOADED path=' .. tostring(dll_path) ..
        ' json_parse_rva=0x45CB7D0 wdd_fixup_rva=0x46382C0 wdd_assign_rva=0x4540B60')
    return fn, nil
end

function pcl151165_direct_json_import()
    PCL151710_IMPORT_ERROR = nil
    log('============================================================')
    log('PCL15_11_65_DIRECT_JSON_IMPORT_BEGIN')

    if pcl1510_running then
        PCL151710_IMPORT_ERROR = 'An import is already running.'
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=importer_busy')
        log('============================================================')
        return
    end

    local gm = find_creative_game_mode_6()
    local forge = nil
    if is_valid(gm) then pcall(function() forge = gm.ForgeMode end) end
    if not is_valid(forge) then
        PCL151710_IMPORT_ERROR = 'Open Forge before loading a saved design.'
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=active_forge_unavailable')
        log('============================================================')
        return
    end

    local piece, sentinel, frontend, handling = nil, nil, nil, nil
    pcall(function() piece = forge:GetPiece() end)
    pcall(function() sentinel = forge:GetRootSwordPartActor() end)
    pcall(function() frontend = forge.ForgeModeFrontend end)
    if is_valid(frontend) then
        pcall(function() handling = frontend.SwordPartHandling end)
    end
    if not is_valid(piece) or not is_valid(sentinel) or
       not is_valid(frontend) or not is_valid(handling) then
        PCL151710_IMPORT_ERROR = 'Forge is not ready to load a design.'
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=active_forge_state_invalid')
        log('============================================================')
        return
    end

    local before_count, before_root, stage = -1, -1, -1
    local state_ok, state_err = pcall(function()
        before_count = #piece.WeaponDesignDefinition.AppliedSwordParts
        before_root = tonumber(piece.WeaponDesignDefinition.RootSwordPartIdx) or -1
        stage = tonumber(piece.CurrentSwordmakingStage) or -1
    end)
    local existing_root = pcl151112_first_slot_child(sentinel)
    log('PCL15_11_65_DIRECT_JSON_PRECHECK' ..
        ' forge=0x' .. string.format('%X', pcl151113_obj_addr(forge)) ..
        ' piece=0x' .. string.format('%X', pcl151113_obj_addr(piece)) ..
        ' stage=' .. tostring(stage) ..
        ' design_parts=' .. tostring(before_count) ..
        ' root=' .. tostring(before_root) ..
        ' sentinel_child=' .. (is_valid(existing_root) and safe_full_name(existing_root) or 'None') ..
        ' state_ok=' .. tostring(state_ok) .. ' error=' .. tostring(state_err))

    if not state_ok or before_count ~= 0 or is_valid(existing_root) then
        PCL151710_IMPORT_ERROR = 'Start with an empty Forge before loading.'
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=requires_empty_forge')
        log('============================================================')
        return
    end
    if stage ~= 1 then
        PCL151710_IMPORT_ERROR = 'Switch to Hilt mode before loading.'
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=requires_hilt_mode stage=' .. tostring(stage))
        log('============================================================')
        return
    end

    local path = OUTPUT_DIR .. PCL151163_JSON_FILENAME
    local f = io.open(path, 'rb')
    if f == nil then
        PCL151710_IMPORT_ERROR = 'No local save found. Save a design first.'
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=file_missing path=' .. tostring(path))
        log('============================================================')
        return
    end
    local size = f:seek('end') or -1
    f:close()
    if size <= 0 then
        PCL151710_IMPORT_ERROR = 'The local save file is empty.'
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=file_empty')
        log('============================================================')
        return
    end

    local clip_ok, ca, cb, cc = pcl151164_json_file_to_clipboard(path)
    log('PCL15_11_65_DIRECT_JSON_CLIPBOARD_LOAD ok=' .. tostring(clip_ok) ..
        ' size=' .. tostring(size) ..
        ' os_execute=' .. tostring(ca) .. '/' .. tostring(cb) .. '/' .. tostring(cc))
    if not clip_ok then
        PCL151710_IMPORT_ERROR = 'Could not read the local save through the clipboard.'
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=clipboard_load_failed')
        log('============================================================')
        return
    end

    local load_fn, load_err = pcl151165_get_json_load_fn()
    if type(load_fn) ~= 'function' then
        PCL151710_IMPORT_ERROR = 'Native import bridge unavailable: ' .. tostring(load_err)
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=' .. tostring(load_err))
        log('============================================================')
        return
    end

    pcl1510_running = true
    PCL151165_DIRECT_JSON_MODE = true
    PCL151165_DIRECT_JSON_LOGICAL_TREE_COUNT = nil
    PCL151165_DIRECT_JSON_BLADE_COUNT = nil
    PCL151117_CACHE = nil
    pcl11_session = nil

    local function fail1565(msg)
        PCL151710_IMPORT_ERROR = msg
        log('PCL15_11_65_DIRECT_JSON_IMPORT_ERROR=' .. tostring(msg))
        PCL151165_DIRECT_JSON_MODE = false
        pcl15104_context = nil
        pcl1510_running = false
        pcall(function() forge.bSupressFrontendUpdate = false end)
        log('============================================================')
    end

    local load_ok, load_result = pcall(load_fn, pcl151113_obj_addr(piece))
    if not load_ok then
        fail1565('native_json_assign_exception ' .. tostring(load_result))
        return
    end
    local part_count = tonumber(load_result) or -9999
    log('PCL15_11_65_DIRECT_JSON_ASSIGN_RESULT=' .. tostring(part_count) ..
        ' meaning=' .. tostring(part_count > 0 and 'assigned_applied_sword_parts' or 'native_error'))
    if part_count <= 0 then
        fail1565('native_json_assign_status=' .. tostring(part_count))
        if part_count == -32 then
            PCL151710_IMPORT_ERROR = 'Local import needs a bridge update for this Bladesong build (status -32).'
        elseif part_count == -33 then
            PCL151710_IMPORT_ERROR = 'Native import function signatures do not match this Bladesong build (status -33).'
        end
        return
    end

    local after_count, after_root, after_getnum, after_version, after_blades =
        -1, -1, -1, -1, -1
    local verify_ok, verify_err = pcall(function()
        local d = piece.WeaponDesignDefinition
        after_count = #d.AppliedSwordParts
        after_root = tonumber(d.RootSwordPartIdx) or -1
        after_getnum = piece:GetNumSwordParts()
        after_version = tonumber(d.Version) or -1
        after_blades = #d.BladeSwordParts
    end)
    log('PCL15_11_65_DIRECT_JSON_ASSIGN_VERIFY' ..
        ' read_ok=' .. tostring(verify_ok) ..
        ' parts=' .. tostring(after_count) ..
        ' get_num=' .. tostring(after_getnum) ..
        ' root=' .. tostring(after_root) ..
        ' version=' .. tostring(after_version) ..
        ' blade_parts=' .. tostring(after_blades) ..
        ' error=' .. tostring(verify_err))
    log('PCL15_11_90_DIRECT_JSON_CONSTRUCTION_ONLY' ..
        ' parts=' .. tostring(after_count) ..
        ' blade_parts=' .. tostring(after_blades) ..
        ' construction_only=' .. tostring(after_blades == 0))
    if not verify_ok or after_count ~= part_count or after_getnum ~= part_count or
       after_root < 0 or after_root >= part_count or after_blades ~= 0 then
        fail1565('assigned Piece validation failed or blade filter did not clear BladeSwordParts')
        return
    end

    stop_all_camera_shakes_142()
    pcall(function() forge.bSupressFrontendUpdate = true end)

    log('PCL15_11_65_DIRECT_NATIVE_REBUILD_BEGIN' ..
        ' staging_actors=0 serialize_calls=0 map_passes=0 apply_parts=0 parts=' ..
        tostring(part_count))
    local rebuild_start = os.clock()
    local rebuild_ok, rebuild_err = pcl1511_private_rebuild(forge)
    local rebuild_ms = (os.clock() - rebuild_start) * 1000.0
    log(string.format(
        'PCL15_11_65_DIRECT_NATIVE_REBUILD_RETURNED ok=%s elapsed_ms=%.3f error=%s',
        tostring(rebuild_ok), rebuild_ms, tostring(rebuild_err)))
    if not rebuild_ok then
        fail1565('private native rebuild: ' .. tostring(rebuild_err))
        return
    end

    pcl15104_context = {
        part_count = part_count,
        local_to_native = nil,
        attempt = 0,
        direct_json = true,
        logical_tree_count = PCL151165_DIRECT_JSON_LOGICAL_TREE_COUNT or part_count,
        blade_part_count = PCL151165_DIRECT_JSON_BLADE_COUNT or 0
    }

    local done, reason = pcl15104_finish_handoff(
        forge, piece.WeaponDesignDefinition, 'direct_native_json')
    if done then return end

    log('PCL15_11_65_DIRECT_JSON_IMMEDIATE_NOT_READY reason=' .. tostring(reason))
    -- Keep direct-json mode active for the existing zero-delay readiness retry.
    pcl15104_hide_live_rebuild()
    schedule_game_11(0, pcl15104_retry_ready_state)
end

RegisterKeyBind(
    Key.D,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(pcl151165_direct_json_import)
    end
)

do
    local fn, err = pcl151165_get_json_load_fn()
    log('PCL15_11_65_JSON_LOAD_PRELOAD ok=' .. tostring(type(fn) == 'function') ..
        ' error=' .. tostring(err))
end

log('Phase 15.11.65 DIRECT NATIVE WEAPON-DESIGN JSON IMPORT probe active.')
log('Phase 15.11.90 0x3B98D20 DIRECT-CHILD PROFILER + CONSTRUCTION-ONLY DIRECT JSON IMPORT active; five exact-byte-guarded relocation-safe helper entry detours time direct work inside hotspot 0x3B98D20, including the <65535 and >=65535 final build branches.')
log("15.11.103 keeps the proven A20 and F490 bounds caches, retains the safe F490 finalizer callsite timer, and adds an exact-guarded 23-byte direct tail bundle at RVA 0x1D363D0 to time stock child 0x1D36420 and cleanup 0x1D2FEB0 without detouring either child entry. Expected native marker: PCL15_11_103_H4_F490_FINALIZER_TAIL_SPLIT.")
log('15.11.90 keeps direct JSON assignment construction-only and additionally suppresses the active ForgeMode runtime BladeMesh/TutorialBladeShape during direct preconstruction handoff; the destructor guard accepts exact stock or the exact known PCL detour shape. The 15.11.57 stable profiler core and 15.11.80 H4 measurement behavior are otherwise unchanged.')
log('CTRL+ALT+D imports scripts\\bladesong_weapon_design_native.json directly into the empty Hilt-Mode Piece, rebuilds on the hidden temp Forge, and hands off the native tree. No staging/serialize/map/APPLY path is used.')
log('CTRL+ALT+P and CTRL+ALT+I remain the proven 15.11.62 staging fallback. CTRL+ALT+O remains read-only JSON validation; CTRL+ALT+J remains native JSON export.')


-- ============================================================================
-- Phase 15.12.0 - PRECONSTRUCTION ANCHOR ANATOMY PROBE
--
-- Optimization work is intentionally frozen. This probe is read-only and does
-- not change the proven 15.11.103 direct JSON import/rebuild/handoff path.
--
-- Goal:
--   Compare the complete reflected SwordPartData row + SwordPartSlot fields for
--     80_Misc_Cube
--     574_Hollow
--     482_Quillon_Square40_Straight
--   to identify the native field/type/slot metadata responsible for the
--   "pick up the base and carry the whole construction" behavior.
--
-- CTRL+ALT+Q:
--   - resolves the configured SwordPartDataTables at runtime
--   - dumps all reflected fields for the target rows
--   - recursively dumps every field of every row.Slots[] element
--   - scans/logs Hollow/Quillon/Cube candidate rows for naming confirmation
--   - writes scripts\\anchor_anatomy_probe.txt as well as the UE4SS log
-- ============================================================================

PCL15120_ANCHOR_PROBE_FILENAME = 'anchor_anatomy_probe.txt'
PCL15120_ANCHOR_TARGETS = {
    '80_Misc_Cube',
    '574_Hollow',
    '482_Quillon_Square40_Straight'
}

function pcl15120_prop_name(prop)
    local name = '<unnamed>'
    pcall(function() name = prop:GetFName():ToString() end)
    return tostring(name)
end

function pcl15120_prop_class(prop)
    local out = '<unknown-property-class>'

    -- UE4SS exposes derived property wrappers (ArrayProperty, StructProperty,
    -- BoolProperty, etc.). type() is the most direct discriminator when this
    -- build provides it.
    local type_ok, type_name = pcall(function() return prop:type() end)
    if type_ok and type_name ~= nil and tostring(type_name) ~= '' then
        out = tostring(type_name)
    end

    local ok, cls = pcall(function() return prop:GetClass() end)
    if ok and cls ~= nil and out == '<unknown-property-class>' then
        local ok_name, name = pcall(function()
            if cls.GetFName ~= nil then return cls:GetFName():ToString() end
            return tostring(cls)
        end)
        if ok_name and name ~= nil then out = tostring(name) end
    end
    return out
end

function pcl15120_struct_name(struct_meta)
    if struct_meta == nil then return '<nil-struct>' end
    local out = '<unknown-struct>'
    pcall(function() out = struct_meta:GetFName():ToString() end)
    return tostring(out)
end

function pcl15120_get_row_struct(dt)
    if not is_valid(dt) then return nil, 'DataTable invalid' end

    local row_struct = nil
    local ok, err = pcall(function() row_struct = dt.RowStruct end)
    if ok and row_struct ~= nil then return row_struct, nil end

    ok, err = pcall(function() row_struct = dt:GetRowStruct() end)
    if ok and row_struct ~= nil then return row_struct, nil end

    return nil, 'RowStruct unavailable: ' .. tostring(err)
end

function pcl15120_safe_scalar(value)
    if value == nil then return 'nil' end

    local t = type(value)
    if t == 'string' then return string.format('%q', value) end
    if t == 'number' or t == 'boolean' then return tostring(value) end

    local ok, text = pcall(function() return value:ToString() end)
    if ok and text ~= nil then return tostring(text) end

    ok, text = pcall(function() return safe_full_name(value) end)
    if ok and text ~= nil and text ~= 'None' and text ~= '<valid object>' then
        return tostring(text)
    end

    ok, text = pcall(function() return tostring(value) end)
    if ok and text ~= nil then return tostring(text) end

    return '<unprintable>'
end

function pcl15120_for_each_property(struct_meta, callback)
    if struct_meta == nil then return false, 'nil struct metadata' end

    local ok, err = pcall(function()
        struct_meta:ForEachProperty(function(prop)
            callback(prop)
            return false
        end)
    end)
    if not ok then return false, tostring(err) end

    -- Some inherited data can live on the super struct. Walk it explicitly so
    -- the dump is complete even on UE4SS builds where ForEachProperty excludes
    -- inherited fields.
    local seen_struct = {}
    local current = struct_meta
    while current ~= nil do
        local key = tostring(current)
        if seen_struct[key] then break end
        seen_struct[key] = true

        local super = nil
        local super_ok = pcall(function() super = current:GetSuperStruct() end)
        if not super_ok or super == nil then break end

        local valid_super = true
        pcall(function() valid_super = super:IsValid() end)
        if not valid_super then break end

        local super_ok2, super_err = pcall(function()
            super:ForEachProperty(function(prop)
                callback(prop)
                return false
            end)
        end)
        if not super_ok2 then return false, tostring(super_err) end
        current = super
    end

    return true, nil
end

function pcl15120_dump_struct(emit, instance, struct_meta, prefix, depth, visited)
    prefix = prefix or ''
    depth = depth or 0
    visited = visited or {}

    if instance == nil then
        emit(prefix .. '<nil instance>')
        return
    end
    if struct_meta == nil then
        emit(prefix .. '<no reflected struct metadata> value=' .. pcl15120_safe_scalar(instance))
        return
    end
    if depth > 6 then
        emit(prefix .. '<depth limit>')
        return
    end

    emit(prefix .. 'STRUCT ' .. pcl15120_struct_name(struct_meta))

    local seen_prop = {}
    local ok, err = pcl15120_for_each_property(struct_meta, function(prop)
        local prop_name = pcl15120_prop_name(prop)
        if seen_prop[prop_name] then return end
        seen_prop[prop_name] = true

        local prop_class = pcl15120_prop_class(prop)
        local value = nil
        local value_ok, value_err = pcall(function() value = instance[prop_name] end)

        if not value_ok then
            emit(string.format('%s  %s <%s> = <READ_ERROR %s>',
                prefix, prop_name, prop_class, tostring(value_err)))
            return
        end

        if prop_class:find('ArrayProperty', 1, true) ~= nil then
            local count = -1
            pcall(function() count = #value end)
            emit(string.format('%s  %s <%s> count=%s',
                prefix, prop_name, prop_class, tostring(count)))

            local inner = nil
            pcall(function() inner = prop:GetInner() end)
            local inner_class = inner and pcl15120_prop_class(inner) or '<unknown-inner>'
            local inner_struct = nil
            if inner ~= nil and inner_class:find('StructProperty', 1, true) ~= nil then
                pcall(function() inner_struct = inner:GetStruct() end)
            end

            local emitted = 0
            local arr_ok, arr_err = pcall(function()
                value:ForEach(function(lua_index, elem)
                    emitted = emitted + 1
                    if emitted > 128 then return end

                    local elem_value = nil
                    local elem_ok, elem_err = pcall(function() elem_value = elem:get() end)
                    if not elem_ok then
                        emit(string.format('%s    [%d] <%s> = <GET_ERROR %s>',
                            prefix, lua_index - 1, inner_class, tostring(elem_err)))
                        return
                    end

                    if inner_struct ~= nil then
                        emit(string.format('%s    [%d] <%s>',
                            prefix, lua_index - 1, pcl15120_struct_name(inner_struct)))
                        pcl15120_dump_struct(
                            emit, elem_value, inner_struct,
                            prefix .. '      ', depth + 1, visited)
                    else
                        emit(string.format('%s    [%d] <%s> = %s',
                            prefix, lua_index - 1, inner_class,
                            pcl15120_safe_scalar(elem_value)))
                    end
                end)
            end)
            if not arr_ok then
                emit(prefix .. '    <ARRAY_ITERATION_ERROR ' .. tostring(arr_err) .. '>')
            elseif count > 128 then
                emit(prefix .. '    <ARRAY_TRUNCATED after 128 elements>')
            end
            return
        end

        if prop_class:find('StructProperty', 1, true) ~= nil then
            local nested_meta = nil
            pcall(function() nested_meta = prop:GetStruct() end)
            emit(string.format('%s  %s <%s> =', prefix, prop_name, prop_class))
            pcl15120_dump_struct(
                emit, value, nested_meta,
                prefix .. '    ', depth + 1, visited)
            return
        end

        if prop_class:find('ObjectProperty', 1, true) ~= nil or
           prop_class:find('ClassProperty', 1, true) ~= nil or
           prop_class:find('WeakObjectProperty', 1, true) ~= nil then
            emit(string.format('%s  %s <%s> = %s',
                prefix, prop_name, prop_class, pcl15120_safe_scalar(value)))
            return
        end

        emit(string.format('%s  %s <%s> = %s',
            prefix, prop_name, prop_class, pcl15120_safe_scalar(value)))
    end)

    if not ok then
        emit(prefix .. '<PROPERTY_ENUM_ERROR ' .. tostring(err) .. '>')
    end
end

function pcl15120_dump_target_row(emit, part_tables, row_name)
    emit('----------------------------------------------------------------')
    emit('TARGET row=' .. tostring(row_name))

    local resolved = find_row_in_tables_7(part_tables, row_name)
    if resolved == nil or resolved.row == nil then
        emit('TARGET_RESOLVE_FAIL row=' .. tostring(row_name))
        return false
    end

    emit('TARGET_RESOLVE_OK table=' .. safe_full_name(resolved.data_table) ..
        ' row=' .. safe_name(resolved.row_name))

    local row_struct, struct_err = pcl15120_get_row_struct(resolved.data_table)
    if row_struct == nil then
        emit('ROW_STRUCT_ERROR ' .. tostring(struct_err))
        return false
    end

    emit('ROW_STRUCT=' .. pcl15120_struct_name(row_struct))
    pcl15120_dump_struct(emit, resolved.row, row_struct, '  ', 0, {})

    -- Dedicated slot summary after the complete row dump. This makes the fields
    -- most relevant to pickup/attachment semantics easy to diff in one place.
    local slots_prop = nil
    pcall(function() slots_prop = row_struct:Reflection():GetProperty('Slots') end)
    if slots_prop == nil then
        -- UObjectReflection is not guaranteed on every metadata wrapper; fall
        -- back to property enumeration.
        pcl15120_for_each_property(row_struct, function(prop)
            if pcl15120_prop_name(prop) == 'Slots' then slots_prop = prop end
        end)
    end

    local slot_struct = nil
    if slots_prop ~= nil then
        local inner = nil
        pcall(function() inner = slots_prop:GetInner() end)
        if inner ~= nil then pcall(function() slot_struct = inner:GetStruct() end) end
    end

    local slots = nil
    pcall(function() slots = resolved.row.Slots end)
    local slot_count = -1
    pcall(function() slot_count = #slots end)
    emit('SLOT_SUMMARY_BEGIN count=' .. tostring(slot_count) ..
        ' struct=' .. pcl15120_struct_name(slot_struct))

    if slots ~= nil then
        local slot_ok, slot_err = pcall(function()
            slots:ForEach(function(lua_index, elem)
                local slot = elem:get()
                emit('  SLOT index=' .. tostring(lua_index - 1))
                if slot_struct ~= nil then
                    pcl15120_dump_struct(emit, slot, slot_struct, '    ', 0, {})
                else
                    -- Known fields retained as fallback if metadata resolution
                    -- fails on this UE4SS build.
                    local known = {
                        'BoneName', 'Offset', 'bSpecial', 'Type', 'SlotType',
                        'bInline', 'bConcurrent', 'bConsecutive', 'bRoot',
                        'bPickUpChildren', 'bPickupChildren', 'bCarryChildren'
                    }
                    for _, k in ipairs(known) do
                        local v = nil
                        local read_ok = pcall(function() v = slot[k] end)
                        if read_ok then
                            emit('    ' .. k .. ' = ' .. pcl15120_safe_scalar(v))
                        end
                    end
                end
            end)
        end)
        if not slot_ok then emit('  SLOT_ITERATION_ERROR=' .. tostring(slot_err)) end
    end
    emit('SLOT_SUMMARY_END row=' .. tostring(row_name))

    return true
end

function pcl15120_anchor_anatomy_probe()
    log('============================================================')
    log('PCL15_12_0_ANCHOR_ANATOMY_BEGIN')

    local out_path = OUTPUT_DIR .. PCL15120_ANCHOR_PROBE_FILENAME
    local f, ferr = io.open(out_path, 'w')
    if f == nil then
        log('PCL15_12_0_FILE_OPEN_ERROR path=' .. tostring(out_path) ..
            ' error=' .. tostring(ferr))
    end

    local function emit(msg)
        msg = tostring(msg)
        log('PCL15_12_0 ' .. msg)
        if f ~= nil then
            f:write(msg)
            f:write('\n')
            f:flush()
        end
    end

    emit('ANCHOR_ANATOMY_VERSION=15.12.0')
    emit('READ_ONLY=true')
    emit('OUTPUT=' .. tostring(out_path))

    local modules = find_game_modules_7()
    emit('MODULE_COUNT=' .. tostring(#modules))
    local part_tables = collect_unique_datatables_7(modules, 'SwordPartDataTables')
    emit('SWORD_PART_TABLE_COUNT=' .. tostring(#part_tables))

    for i, dt in ipairs(part_tables) do
        local row_struct, row_struct_err = pcl15120_get_row_struct(dt)
        emit(string.format('TABLE index=%d rows=%d object=%s row_struct=%s error=%s',
            i - 1, #get_row_names_7(dt), safe_full_name(dt),
            pcl15120_struct_name(row_struct), tostring(row_struct_err)))
    end

    -- Naming audit so we can confirm which row the player-facing "Hollow
    -- Quillon" corresponds to without guessing from localization.
    emit('CANDIDATE_ROWS_BEGIN')
    local candidate_seen = {}
    for _, dt in ipairs(part_tables) do
        for _, rn in ipairs(get_row_names_7(dt)) do
            local s = safe_name(rn)
            local lower = tostring(s):lower()
            if lower:find('hollow', 1, true) or
               lower:find('quillon', 1, true) or
               lower:find('cube', 1, true) then
                if not candidate_seen[s] then
                    candidate_seen[s] = true
                    emit('  CANDIDATE ' .. s .. ' table=' .. safe_full_name(dt))
                end
            end
        end
    end
    emit('CANDIDATE_ROWS_END')

    local resolved_count = 0
    for _, target in ipairs(PCL15120_ANCHOR_TARGETS) do
        if pcl15120_dump_target_row(emit, part_tables, target) then
            resolved_count = resolved_count + 1
        end
    end

    emit('TARGETS_RESOLVED=' .. tostring(resolved_count) ..
        '/' .. tostring(#PCL15120_ANCHOR_TARGETS))
    emit('PCL15_12_0_ANCHOR_ANATOMY_END')

    if f ~= nil then f:close() end
    log('PCL15_12_0_ANCHOR_ANATOMY_FILE=' .. tostring(out_path))
    log('============================================================')
end

RegisterKeyBind(
    Key.Q,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(pcl15120_anchor_anatomy_probe)
    end
)

log('Phase 15.12.0 PRECONSTRUCTION ANCHOR ANATOMY PROBE active.')
log('Optimization branch frozen; 15.11.103 import/rebuild/handoff behavior is unchanged.')
log('CTRL+ALT+Q = dump Cube/Hollow/Quillon SwordPartData + complete reflected SwordPartSlot anatomy to scripts\\anchor_anatomy_probe.txt.')

-- ============================================================================
-- Phase 15.12.1 - ANCHOR REFLECTION DUMP FALLBACK
--
-- 15.12.0 proved the target DataTable rows and slot counts, but this UE4SS
-- build throws inside UStruct:ForEachProperty after the first reflected field.
-- Do not guess around that API mismatch. Use UE4SS's own native reflection
-- dumper instead; the resulting JMAP contains exact struct/property names,
-- offsets, sizes and flags.
--
-- CTRL+ALT+R:
--   1) calls DumpJMAP(false) (native types only)
--   2) best-effort copies the newest generated .jmap into this Scripts folder
--      as anchor_reflection.jmap for easy upload
--   3) writes anchor_reflection_probe.txt with status/path information
--
-- Read-only: no DataTable row, SwordPart actor, Piece, JSON, or native hook is
-- modified by this probe.
-- ============================================================================

PCL15121_REFLECTION_STATUS_FILENAME = 'anchor_reflection_probe.txt'
PCL15121_REFLECTION_COPY_FILENAME = 'anchor_reflection.jmap'

function pcl15121_ps_quote_single(s)
    return tostring(s or ''):gsub("'", "''")
end

function pcl15121_anchor_reflection_probe()
    log('============================================================')
    log('PCL15_12_1_ANCHOR_REFLECTION_BEGIN')

    local status_path = OUTPUT_DIR .. PCL15121_REFLECTION_STATUS_FILENAME
    local copied_path = OUTPUT_DIR .. PCL15121_REFLECTION_COPY_FILENAME
    local f, ferr = io.open(status_path, 'w')

    local function emit(msg)
        msg = tostring(msg)
        log('PCL15_12_1 ' .. msg)
        if f ~= nil then
            f:write(msg)
            f:write('\n')
            f:flush()
        end
    end

    emit('ANCHOR_REFLECTION_VERSION=15.12.1')
    emit('READ_ONLY=true')
    emit('STATUS_OUTPUT=' .. tostring(status_path))
    emit('JMAP_COPY_TARGET=' .. tostring(copied_path))
    emit('TARGET_ROWS=80_Misc_Cube,485_Hollow,574_Hollow,482_Quillon_Square40_Straight')
    emit('TARGET_STRUCTS=SwordPartData,SwordPartSlot,ActiveSwordPartSlot')

    if type(DumpJMAP) ~= 'function' then
        emit('DUMPJMAP_AVAILABLE=false')
        emit('ERROR=DumpJMAP global is unavailable in this UE4SS build')
        if f ~= nil then f:close() end
        log('PCL15_12_1_ANCHOR_REFLECTION_END failure=DumpJMAP_unavailable')
        log('============================================================')
        return
    end

    emit('DUMPJMAP_AVAILABLE=true')
    emit('DUMP_BEGIN include_blueprints=false')

    local dump_ok, dump_err = pcall(function()
        DumpJMAP(false)
    end)

    emit('DUMP_RETURNED=' .. tostring(dump_ok) .. ' error=' .. tostring(dump_err))

    if not dump_ok then
        if f ~= nil then f:close() end
        log('PCL15_12_1_ANCHOR_REFLECTION_END failure=dump_exception')
        log('============================================================')
        return
    end

    -- DumpJMAP writes to UE4SS's working directory (normally Binaries\\Win64).
    -- Ask PowerShell to locate the newest JMAP below the Bladesong Win64 tree
    -- and copy it beside this script. Keep this best-effort: the actual dump
    -- remains valid even if the convenience copy fails.
    local script_dir = pcl151112_script_dir()
    local root = tostring(script_dir):gsub('\\ue4ss\\Mods\\.*$', '')
    if root == tostring(script_dir) then
        root = '.'
    end

    local qroot = pcl15121_ps_quote_single(root)
    local qdst = pcl15121_ps_quote_single(copied_path)
    local ps =
        'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' ..
        '"$f=Get-ChildItem -LiteralPath ' .. "'" .. qroot .. "'" ..
        ' -Filter *.jmap -File -Recurse -ErrorAction SilentlyContinue | ' ..
        'Sort-Object LastWriteTime -Descending | Select-Object -First 1; ' ..
        'if($null -eq $f){exit 3}; ' ..
        'Copy-Item -LiteralPath $f.FullName -Destination ' .. "'" .. qdst .. "'" ..
        ' -Force; Write-Output $f.FullName"'

    local exec_ok, a, b, c = pcall(function()
        return os.execute(ps)
    end)
    emit('COPY_COMMAND_PCALL=' .. tostring(exec_ok) ..
        ' os_execute=' .. tostring(a) .. '/' .. tostring(b) .. '/' .. tostring(c))

    local copied_size = -1
    local cf = io.open(copied_path, 'rb')
    if cf ~= nil then
        copied_size = cf:seek('end') or -1
        cf:close()
    end

    emit('JMAP_COPY_EXISTS=' .. tostring(copied_size > 0))
    emit('JMAP_COPY_SIZE=' .. tostring(copied_size))
    if copied_size > 0 then
        emit('UPLOAD_THIS_FILE=' .. tostring(copied_path))
    else
        emit('UPLOAD_FALLBACK=the newest *.jmap in Bladesong\\Binaries\\Win64')
    end

    emit('PCL15_12_1_ANCHOR_REFLECTION_END')
    if f ~= nil then f:close() end

    log('PCL15_12_1_ANCHOR_REFLECTION_STATUS=' .. tostring(status_path))
    log('============================================================')
end

RegisterKeyBind(
    Key.R,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(pcl15121_anchor_reflection_probe)
    end
)

log('Phase 15.12.1 ANCHOR REFLECTION DUMP FALLBACK active.')
log('CTRL+ALT+R = DumpJMAP(false) and copy newest native reflection dump to scripts\\anchor_reflection.jmap.')
log('15.12.0 CTRL+ALT+Q remains available for the row/slot-count anatomy probe.')


-- ============================================================================
-- Phase 15.12.3 - ANCHOR SAFE VALUES PROBE
--
-- 15.12.2 proved DT_SwordParts row access is valid, but reading RenderAsset
-- on 485_Hollow caused a native UE4SS access violation. This revision removes
-- ALL UObject/TSoftObjectPtr/UClass field reads and compares only primitive /
-- enum / FName fields plus the already-proven SwordPartSlot fields.
--
-- CTRL+ALT+T writes scripts\anchor_safe_values_probe.txt
-- Read-only. No DataTable row, actor, Piece, JSON, or native hook is modified.
-- ============================================================================

PCL15123_FILENAME = 'anchor_safe_values_probe.txt'
PCL15123_TARGETS = {
    '80_Misc_Cube',
    '485_Hollow',
    '574_Hollow',
    '482_Quillon_Square40_Straight'
}

function pcl15123_scalar(v)
    if v == nil then return 'nil' end
    if type(v) == 'boolean' then return v and 'true' or 'false' end
    if type(v) == 'number' or type(v) == 'string' then return tostring(v) end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and s ~= nil then return tostring(s) end
    return tostring(v)
end

function pcl15123_vec3(v)
    if v == nil then return 'nil' end
    local x,y,z = 0,0,0
    local ok = pcall(function()
        x = tonumber(v.X) or 0
        y = tonumber(v.Y) or 0
        z = tonumber(v.Z) or 0
    end)
    if not ok then return '<UNREADABLE_VEC3>' end
    return string.format('(%.9g,%.9g,%.9g)', x,y,z)
end

function pcl15123_vec2(v)
    if v == nil then return 'nil' end
    local x,y = 0,0
    local ok = pcall(function()
        x = tonumber(v.X) or 0
        y = tonumber(v.Y) or 0
    end)
    if not ok then return '<UNREADABLE_VEC2>' end
    return string.format('(%.9g,%.9g)', x,y)
end

function pcl15123_read_field(row, name)
    local v = nil
    local ok, err = pcall(function() v = row[name] end)
    if not ok then return false, nil, tostring(err) end
    return true, v, nil
end

function pcl15123_emit_field(emit, row, name)
    local ok, v, err = pcl15123_read_field(row, name)
    if ok then
        emit('  ' .. name .. '=' .. pcl15123_scalar(v))
    else
        emit('  ' .. name .. '=<READ_ERROR ' .. tostring(err) .. '>')
    end
end

function pcl15123_dump_row(emit, part_tables, row_name)
    emit('----------------------------------------------------------------')
    emit('TARGET=' .. row_name)

    local resolved = find_row_in_tables_7(part_tables, row_name)
    if resolved == nil or resolved.row == nil then
        emit('RESOLVE_OK=false')
        return false
    end

    local row = resolved.row
    emit('RESOLVE_OK=true')
    emit('TABLE=' .. safe_full_name(resolved.data_table))
    emit('ROW=' .. safe_name(resolved.row_name))

    -- Safe primitive/enum/FName fields only.
    pcl15123_emit_field(emit, row, 'Type')
    pcl15123_emit_field(emit, row, 'DisplayName')
    pcl15123_emit_field(emit, row, 'Status')
    pcl15123_emit_field(emit, row, 'bHandGrip')
    pcl15123_emit_field(emit, row, 'bPreventPlacingOnSurfaces')
    pcl15123_emit_field(emit, row, 'bWrapAroundBlade')
    pcl15123_emit_field(emit, row, 'bDisplayUpright')
    pcl15123_emit_field(emit, row, 'bHasPrimarySlot')
    pcl15123_emit_field(emit, row, 'VOffsetHandling')
    pcl15123_emit_field(emit, row, 'BendingAxis')
    pcl15123_emit_field(emit, row, 'BendingHandleBoneName')
    pcl15123_emit_field(emit, row, 'RotationHandlePosition')

    local slots = nil
    local slots_ok, slots_err = pcall(function() slots = row.Slots end)
    if not slots_ok or slots == nil then
        emit('  Slots=<READ_ERROR ' .. tostring(slots_err) .. '>')
        return true
    end

    local slot_count = -1
    pcall(function() slot_count = #slots end)
    emit('  SlotCount=' .. tostring(slot_count))
    emit('  SLOTS_BEGIN')

    local iter_ok, iter_err = pcall(function()
        slots:ForEach(function(lua_index, elem)
            local slot = elem:get()
            local idx = lua_index - 1
            emit('    SLOT index=' .. tostring(idx))

            local bone, offset, special, flipped, uv = nil,nil,nil,nil,nil
            local ok_b, er_b = pcall(function() bone = slot.BoneName end)
            local ok_o, er_o = pcall(function() offset = slot.Offset end)
            local ok_s, er_s = pcall(function() special = slot.bSpecial end)
            local ok_f, er_f = pcall(function() flipped = slot.bIsFlippedSlot end)
            local ok_u, er_u = pcall(function() uv = slot.UVPosition end)

            emit('      BoneName=' .. (ok_b and pcl15123_scalar(bone) or ('<READ_ERROR '..tostring(er_b)..'>')))
            emit('      Offset=' .. (ok_o and pcl15123_vec3(offset) or ('<READ_ERROR '..tostring(er_o)..'>')))
            emit('      bSpecial=' .. (ok_s and pcl15123_scalar(special) or ('<READ_ERROR '..tostring(er_s)..'>')))
            emit('      bIsFlippedSlot=' .. (ok_f and pcl15123_scalar(flipped) or ('<READ_ERROR '..tostring(er_f)..'>')))
            emit('      UVPosition=' .. (ok_u and pcl15123_vec2(uv) or ('<READ_ERROR '..tostring(er_u)..'>')))
        end)
    end)

    if not iter_ok then
        emit('    SLOT_ITERATION_ERROR=' .. tostring(iter_err))
    end

    emit('  SLOTS_END')
    return true
end

function pcl15123_anchor_safe_values_probe()
    log('============================================================')
    log('PCL15_12_3_ANCHOR_SAFE_VALUES_BEGIN')

    local path = OUTPUT_DIR .. PCL15123_FILENAME
    local f, ferr = io.open(path, 'w')
    if f == nil then
        log('PCL15_12_3_FILE_OPEN_ERROR=' .. tostring(ferr))
    end

    local function emit(s)
        s = tostring(s)
        log('PCL15_12_3 ' .. s)
        if f ~= nil then
            f:write(s .. '\n')
            f:flush()
        end
    end

    emit('ANCHOR_SAFE_VALUES_VERSION=15.12.3')
    emit('READ_ONLY=true')
    emit('POINTER_FIELDS_SKIPPED=Blueprint,RenderAsset')
    emit('TARGETS=' .. table.concat(PCL15123_TARGETS, ','))

    local modules = find_game_modules_7()
    local part_tables = collect_unique_datatables_7(modules, 'SwordPartDataTables')
    emit('SWORD_PART_TABLE_COUNT=' .. tostring(#part_tables))

    local resolved = 0
    for _, row_name in ipairs(PCL15123_TARGETS) do
        if pcl15123_dump_row(emit, part_tables, row_name) then
            resolved = resolved + 1
        end
    end

    emit('TARGETS_RESOLVED=' .. tostring(resolved) .. '/' .. tostring(#PCL15123_TARGETS))
    emit('PCL15_12_3_ANCHOR_SAFE_VALUES_END')

    if f ~= nil then f:close() end
    log('PCL15_12_3_FILE=' .. tostring(path))
    log('============================================================')
end

RegisterKeyBind(
    Key.T,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(pcl15123_anchor_safe_values_probe)
    end
)

log('Phase 15.12.3 ANCHOR SAFE VALUES PROBE active.')
log('CTRL+ALT+T = safe scalar/slot comparison; UObject/UClass/TSoftObjectPtr reads are intentionally skipped.')


-- ============================================================================
-- Phase 15.12.9 - CORRECT HOLLOW CHILD-SLOT ANCHOR TEST
--
-- Purpose:
--   Test 574_Hollow's native whole-tree pickup/preview behavior with ZERO
--   prefab/JSON/native-DLL import machinery.
--
-- CTRL+ALT+A:
--   1) requires an empty Forge and no active preview
--   2) asks Bladesong's own catalogue to allocate:
--        574_Hollow
--        80_Misc_Cube x4
--   3) clears PreviewSwordPartActor between allocations WITHOUT cancelling
--      the live actors (same proven primitive as Phase 14)
--   4) links:
--        Hollow slot1 (End) -> CubeA
--        CubeA slot1 -> CubeB
--        CubeA slot2 -> CubeC
--        CubeA slot3 -> CubeD
--   5) sets children committed (bPending=false), root pending (bPending=true)
--   6) assigns the Hollow root back to PreviewSwordPartActor
--
-- No SerializeSwordPartActorsToData().
-- No EnterForgeMode().
-- No native bridge/DLL call.
-- No .pcl/.json file read.
-- ============================================================================

PCL15129_RUNNING = false
PCL15129_ACTORS = nil

function pcl15129_cleanup_created(actors)
    if type(actors) ~= 'table' then return end
    for _, actor in ipairs(actors) do
        if is_valid(actor) then
            pcall(function() actor:K2_DestroyActor() end)
        end
    end
end

function pcl15129_take_catalogue_actor(row_name, actors)
    local click_ok, click_err = click_catalogue_row_11(row_name)
    if not click_ok then
        return nil, 'catalogue click ' .. tostring(row_name) .. ': ' .. tostring(click_err)
    end

    local handling, preview = current_preview_14()
    if not is_valid(handling) then
        return nil, 'handling unavailable after catalogue click ' .. tostring(row_name)
    end
    if not is_valid(preview) then
        return nil, 'no preview after catalogue click ' .. tostring(row_name)
    end

    local live_row = live_actor_row_10(preview)
    log('PCL15_12_9_ALLOC row=' .. tostring(row_name) ..
        ' live_row=' .. tostring(live_row) ..
        ' actor=' .. safe_full_name(preview))

    if tostring(live_row) ~= tostring(row_name) then
        return nil, 'catalogue returned wrong row expected=' ..
            tostring(row_name) .. ' actual=' .. tostring(live_row)
    end

    -- Keep the actor alive but remove any automatic parent snap.
    local detach_ok, detach_err = detach_live_actor_14(preview)
    if not detach_ok then
        return nil, 'detach ' .. tostring(row_name) .. ': ' .. tostring(detach_err)
    end

    local clear_ok, clear_err = clear_preview_pointer_14()
    if not clear_ok then
        return nil, 'preview clear ' .. tostring(row_name) .. ': ' .. tostring(clear_err)
    end

    -- Normal catalogue preview actors are already fully initialized/rendered.
    pcall(function()
        preview:SetActorHiddenInGame(false)
        preview:SetActorEnableCollision(true)
        preview:SetActorTickEnabled(true)
    end)

    table.insert(actors, preview)
    return preview, nil
end

function pcl15129_fail(msg, actors)
    log('PCL15_12_9_ERROR=' .. tostring(msg))

    local handling = find_handling_component_9()
    if is_valid(handling) then
        pcall(function()
            handling.PreviewSwordPartActor = nil
            handling.BestSwordPartSlotParent = nil
        end)
    end

    pcl15129_cleanup_created(actors)
    PCL15129_ACTORS = nil
    PCL15129_RUNNING = false
    log('PCL15_12_9_CLEANUP=true')
    log('============================================================')
end

function pcl15129_stock_anchor_test()
    log('============================================================')
    log('PCL15_12_9_STOCK_CATALOGUE_ANCHOR_BEGIN')

    if PCL15129_RUNNING then
        log('PCL15_12_9_ERROR=already_running')
        log('============================================================')
        return
    end

    local forge, piece, design, state_err = state_no_serialize_11()
    if state_err ~= nil then
        log('PCL15_12_9_ERROR=' .. tostring(state_err))
        log('============================================================')
        return
    end

    local design_count = -1
    pcall(function() design_count = #design.AppliedSwordParts end)

    local handling, existing_preview = current_preview_14()
    if not is_valid(handling) then
        log('PCL15_12_9_ERROR=handling_unavailable')
        log('============================================================')
        return
    end
    if is_valid(existing_preview) then
        log('PCL15_12_9_ERROR=preview_already_active press_X_first')
        log('============================================================')
        return
    end
    if design_count ~= 0 then
        log('PCL15_12_9_ERROR=requires_empty_forge design_parts=' .. tostring(design_count))
        log('============================================================')
        return
    end

    PCL15129_RUNNING = true
    local actors = {}
    PCL15129_ACTORS = actors

    -- Allocate stock actors through the game's own catalogue path.
    local root, err = pcl15129_take_catalogue_actor('574_Hollow', actors)
    if not is_valid(root) then
        pcl15129_fail(err, actors)
        return
    end

    local cube_a
    cube_a, err = pcl15129_take_catalogue_actor('80_Misc_Cube', actors)
    if not is_valid(cube_a) then
        pcl15129_fail(err, actors)
        return
    end

    local cube_b
    cube_b, err = pcl15129_take_catalogue_actor('80_Misc_Cube', actors)
    if not is_valid(cube_b) then
        pcl15129_fail(err, actors)
        return
    end

    local cube_c
    cube_c, err = pcl15129_take_catalogue_actor('80_Misc_Cube', actors)
    if not is_valid(cube_c) then
        pcl15129_fail(err, actors)
        return
    end

    local cube_d
    cube_d, err = pcl15129_take_catalogue_actor('80_Misc_Cube', actors)
    if not is_valid(cube_d) then
        pcl15129_fail(err, actors)
        return
    end

    -- Stock/native topology.
    local ok, link_err = attach_child_live_14(root, 1, cube_a)
    if not ok then
        pcl15129_fail('Hollow slot1 (End) -> CubeA: ' .. tostring(link_err), actors)
        return
    end

    ok, link_err = attach_child_live_14(cube_a, 1, cube_b)
    if not ok then
        pcl15129_fail('CubeA slot1 -> CubeB: ' .. tostring(link_err), actors)
        return
    end

    ok, link_err = attach_child_live_14(cube_a, 2, cube_c)
    if not ok then
        pcl15129_fail('CubeA slot2 -> CubeC: ' .. tostring(link_err), actors)
        return
    end

    ok, link_err = attach_child_live_14(cube_a, 3, cube_d)
    if not ok then
        pcl15129_fail('CubeA slot3 -> CubeD: ' .. tostring(link_err), actors)
        return
    end

    local count = live_tree_count_14(root)
    log('PCL15_12_9_LINKED_TREE_COUNT=' .. tostring(count) .. ' expected=5')
    if count ~= 5 then
        pcl15129_fail('linked tree count mismatch actual=' .. tostring(count), actors)
        return
    end

    -- Root is the held/pending native preview. Descendants are committed
    -- members of its live tree.
    pcall(function()
        root.bPending = true
        cube_a.bPending = false
        cube_b.bPending = false
        cube_c.bPending = false
        cube_d.bPending = false
    end)

    pcall(function()
        root:SetActorHiddenInGame(false)
        cube_a:SetActorHiddenInGame(false)
        cube_b:SetActorHiddenInGame(false)
        cube_c:SetActorHiddenInGame(false)
        cube_d:SetActorHiddenInGame(false)

        root:SetActorEnableCollision(true)
        cube_a:SetActorEnableCollision(true)
        cube_b:SetActorEnableCollision(true)
        cube_c:SetActorEnableCollision(true)
        cube_d:SetActorEnableCollision(true)
    end)

    local assign_ok, assign_err = pcall(function()
        handling.BestSwordPartSlotParent = nil
        handling.PreviewSwordPartActor = root
    end)

    if not assign_ok then
        pcl15129_fail('PreviewSwordPartActor handoff: ' .. tostring(assign_err), actors)
        return
    end

    local has_preview = false
    local final_preview = nil
    pcall(function()
        has_preview = handling:HasPreviewSwordPart() and true or false
        final_preview = handling.PreviewSwordPartActor
    end)

    local held_count = live_tree_count_14(final_preview)

    log('PCL15_12_9_HANDOFF_WRITE=true')
    log('PCL15_12_9_HAS_PREVIEW=' .. tostring(has_preview))
    log('PCL15_12_9_HELD_ROOT=' ..
        (is_valid(final_preview) and live_actor_row_10(final_preview) or 'None'))
    log('PCL15_12_9_HELD_TREE_COUNT=' .. tostring(held_count) .. ' expected=5')

    if not has_preview or not is_valid(final_preview) or held_count ~= 5 then
        pcl15129_fail('handoff verification failed', actors)
        return
    end

    PCL15129_RUNNING = false

    log('PCL15_12_9_OK=true')
    log('NO_FILE_IMPORT=true NO_NATIVE_DLL_IMPORT=true NO_SERIALIZE=true NO_REBUILD=true')
    log('The stock 574_Hollow-rooted five-part tree is now in hand.')
    log('LEFT CLICK once to place it, then pick up the Hollow root and see if the whole tree follows.')
    log('============================================================')
end

-- 15.16.1 replaces the old 15.12.9 A hotkey.

log('Phase 15.12.9 CORRECT HOLLOW CHILD-SLOT ANCHOR TEST active.')
log('CTRL+ALT+A = construct Hollow + four cubes entirely through stock catalogue actor allocation.')
log('No prefab file, JSON file, native import bridge, serializer, or rebuild is used.')


-- 15.12.9 note:
-- 574_Hollow slot roles established by live DataTable probe + manual control:
--   slot 0 = SquareModular7by7_End = primary/upstream connector
--   slot 1 = End                    = downstream/carrying child connector
--   slot 2 = Start                  = downstream/carrying child connector
--
-- The synthetic anchor tree therefore MUST begin on slot 1 or slot 2.


-- ============================================================================
-- Phase 15.16.2 - PRECONSTRUCTION ANCHOR ENUM-CLOBBER FIX
--
-- UE4SS 3.0.1 on this UE 5.7 build exposes UDataTable:AddRow, but AddRow
-- aborts because Virtual UScriptStruct::ICppStructOps::Copy is unavailable.
-- Therefore 15.16.1 does NOT call AddRow at all.
--
-- Dedicated backing identity:
--   TRIPLANAR_GRIP
--   (the sole row in DT_SwordParts_DevOnly)
--
-- Player-facing item:
--   DisplayName = Preconstruction Anchor
--   Status      = normal/usable
--   Type        = GuardQuillon
--   Blueprint   = copied natively from 80_Misc_Cube
--   RenderAsset = copied natively from 80_Misc_Cube
--   Cube physical/handling metadata copied natively
--   Slot 0      = Cube Left  (primary/upstream)
--   Slot 1      = Cube Right (prefab/carry child)
--
-- The row key remains TRIPLANAR_GRIP only as persistent storage identity.
-- No normal Cube or Hollow row is modified.
-- ============================================================================

PCL15161_ROW_NAME = 'TRIPLANAR_GRIP'
PCL15161_DISPLAY_NAME = 'Preconstruction Anchor'
PCL15161_DLL = 'pcl_anchor_catalogue_patch_15170.dll'

PCL15161_PATCH_FN = nil
PCL15161_PATCH_LOAD_ERROR = nil
PCL15161_READY = false
PCL15161_PATCHING = false
PCL15161_ATTEMPTS = 0
PCL15161_MAX_ATTEMPTS = 200

function pcl15161_struct_address(row)
    if row == nil then return 0, 'row nil' end

    local addr = 0
    local ok, err = pcall(function()
        addr = row:GetStructAddress()
    end)
    addr = tonumber(addr) or 0
    if ok and addr > 0 then return addr, nil end

    ok, err = pcall(function()
        addr = row:GetAddress()
    end)
    addr = tonumber(addr) or 0
    if ok and addr > 0 then return addr, nil end

    return 0, 'UScriptStruct address unavailable: ' .. tostring(err)
end

function pcl15161_get_native_patch()
    if type(PCL15161_PATCH_FN) == 'function' then
        return PCL15161_PATCH_FN, nil
    end
    if PCL15161_PATCH_LOAD_ERROR ~= nil then
        return nil, PCL15161_PATCH_LOAD_ERROR
    end

    local dll_path = pcl151112_script_dir() .. PCL15161_DLL
    local fn, err, where = BMF_PCL_NATIVE(dll_path, 'pcl_anchor_patch_row')
    if type(fn) ~= 'function' then
        PCL15161_PATCH_LOAD_ERROR =
            'package.loadlib failed path=' .. tostring(dll_path) ..
            ' error=' .. tostring(err) ..
            ' where=' .. tostring(where)
        return nil, PCL15161_PATCH_LOAD_ERROR
    end

    PCL15161_PATCH_FN = fn
    log('PCL15_16_1_NATIVE_PATCH_LOADED path=' .. tostring(dll_path))
    return fn, nil
end


PCL15163_INSPECT_FN = nil
PCL15163_INSPECT_LOAD_ERROR = nil

function pcl15163_get_native_inspector()
    if type(PCL15163_INSPECT_FN) == 'function' then
        return PCL15163_INSPECT_FN, nil
    end
    if PCL15163_INSPECT_LOAD_ERROR ~= nil then
        return nil, PCL15163_INSPECT_LOAD_ERROR
    end

    local dll_path = pcl151112_script_dir() .. PCL15161_DLL
    local fn, err, where = BMF_PCL_NATIVE(dll_path, 'pcl_anchor_inspect_row')
    if type(fn) ~= 'function' then
        PCL15163_INSPECT_LOAD_ERROR =
            'native inspector load failed path=' .. tostring(dll_path) ..
            ' error=' .. tostring(err) ..
            ' where=' .. tostring(where)
        return nil, PCL15163_INSPECT_LOAD_ERROR
    end

    PCL15163_INSPECT_FN = fn
    log('PCL15_16_3_NATIVE_INSPECTOR_LOADED path=' .. tostring(dll_path))
    return fn, nil
end

function pcl15163_native_row_state(row)
    local addr, addr_err = pcl15161_struct_address(row)
    if addr <= 0 then
        return nil, 'row address: ' .. tostring(addr_err)
    end

    local fn, load_err = pcl15163_get_native_inspector()
    if type(fn) ~= 'function' then
        return nil, load_err
    end

    local ok, packed = pcall(fn, addr)
    if not ok then
        return nil, 'native inspect exception: ' .. tostring(packed)
    end

    packed = tonumber(packed)
    if packed == nil or packed < 0 then
        return nil, 'native inspect status=' .. tostring(packed)
    end

    local status = packed % 256
    local typ = math.floor(packed / 256) % 256
    local primary = math.floor(packed / 65536) % 256
    local slots = math.floor(packed / 16777216) % 256

    return {
        address = addr,
        packed = packed,
        status = status,
        typ = typ,
        primary = primary,
        slots = slots
    }, nil
end

function pcl15161_set_display_name(row)
    local text_lib = nil
    local ok, err = pcall(function()
        text_lib = StaticFindObject('/Script/Engine.Default__KismetTextLibrary')
    end)
    if not ok or not is_valid(text_lib) then
        return false, 'Default__KismetTextLibrary unavailable: ' .. tostring(err)
    end

    local txt = nil
    ok, err = pcall(function()
        txt = text_lib:Conv_StringToText(PCL15161_DISPLAY_NAME)
    end)
    if not ok or txt == nil then
        return false, 'Conv_StringToText failed: ' .. tostring(err)
    end

    ok, err = pcall(function()
        row.DisplayName = txt
    end)
    if not ok then
        return false, 'DisplayName write failed: ' .. tostring(err)
    end

    return true, nil
end

function pcl15161_find_rows()
    local modules = find_game_modules_7()
    local tables = collect_unique_datatables_7(modules, 'SwordPartDataTables')
    if #tables == 0 then
        return nil, nil, nil, nil, 'no SwordPartDataTables yet'
    end

    local dst = find_row_in_tables_7(tables, PCL15161_ROW_NAME)
    local hollow = find_row_in_tables_7(tables, '574_Hollow')
    local cube = find_row_in_tables_7(tables, '80_Misc_Cube')

    if dst == nil or dst.row == nil then
        return nil, nil, nil, nil,
            PCL15161_ROW_NAME .. ' dev-only backing row unavailable yet'
    end
    if hollow == nil or hollow.row == nil then
        return nil, nil, nil, nil, '574_Hollow donor unavailable yet'
    end
    if cube == nil or cube.row == nil then
        return nil, nil, nil, nil, '80_Misc_Cube donor unavailable yet'
    end

    return dst, hollow, cube, tables, nil
end

function pcl15161_verify_row(row)
    if row == nil then return false, 'row nil' end

    -- UE4SS 3.0.1 / UE5.7 is returning 0 through the Lua EnumProperty wrapper
    -- for this runtime-mutated row even when the underlying bytes are 2.
    -- Therefore Type/Status truth comes from the native raw-byte inspector.
    local reflected_type = -1
    local reflected_status = -1
    local reflected_primary = false
    local reflected_slots = -1
    local s0 = 'None'
    local s1 = 'None'
    local display = '<unreadable>'

    local ok, err = pcall(function()
        reflected_type = tonumber(row.Type) or -1
        reflected_status = tonumber(row.Status) or -1
        reflected_primary = row.bHasPrimarySlot and true or false
        reflected_slots = #row.Slots
        display = row.DisplayName:ToString()

        row.Slots:ForEach(function(lua_index, elem)
            local idx = lua_index - 1
            local slot = elem:get()
            if idx == 0 then s0 = safe_name(slot.BoneName) end
            if idx == 1 then s1 = safe_name(slot.BoneName) end
        end)
    end)

    if not ok then
        return false, 'reflected verification exception: ' .. tostring(err)
    end

    local native, native_err = pcl15163_native_row_state(row)
    if native == nil then
        return false, 'native verification failed: ' .. tostring(native_err)
    end

    local raw_ok =
        native.typ == 2 and
        native.status == 2 and
        native.primary == 1 and
        native.slots == 2

    local reflected_shape_ok =
        reflected_primary and
        reflected_slots == 2 and
        s0 == 'Left' and
        s1 == 'Right'

    local msg =
        'display=' .. tostring(display) ..
        ' native_type=' .. tostring(native.typ) ..
        ' native_status=' .. tostring(native.status) ..
        ' native_primary=' .. tostring(native.primary) ..
        ' native_slots=' .. tostring(native.slots) ..
        ' lua_type=' .. tostring(reflected_type) ..
        ' lua_status=' .. tostring(reflected_status) ..
        ' lua_primary=' .. tostring(reflected_primary) ..
        ' lua_slots=' .. tostring(reflected_slots) ..
        ' bones=' .. tostring(s0) .. '/' .. tostring(s1) ..
        string.format(' addr=0x%X packed=0x%X',
            native.address, native.packed)

    if not raw_ok or not reflected_shape_ok then
        return false, 'verification mismatch ' .. msg
    end

    return true, msg
end

function pcl15161_patch_catalogue_item()
    if PCL15161_PATCHING then
        return false, 'patch already in progress'
    end
    PCL15161_PATCHING = true

    local function finish(ok, err)
        PCL15161_PATCHING = false
        if ok then PCL15161_READY = true end
        return ok, err
    end

    local dst, hollow, cube, tables, find_err = pcl15161_find_rows()
    if find_err ~= nil then
        return finish(false, find_err)
    end

    local dst_addr, dst_err = pcl15161_struct_address(dst.row)
    if dst_addr <= 0 then return finish(false, 'dst address: ' .. tostring(dst_err)) end

    local hollow_addr, hollow_err = pcl15161_struct_address(hollow.row)
    if hollow_addr <= 0 then return finish(false, 'hollow address: ' .. tostring(hollow_err)) end

    local cube_addr, cube_err = pcl15161_struct_address(cube.row)
    if cube_addr <= 0 then return finish(false, 'cube address: ' .. tostring(cube_err)) end

    local patch_fn, load_err = pcl15161_get_native_patch()
    if type(patch_fn) ~= 'function' then
        return finish(false, load_err)
    end

    -- =====================================================================
    -- 15.16.4 ORDERING FIX
    --
    -- UE4SS's reflected UScriptStruct writes appear to commit a cached struct
    -- image. If we call the native patch first and then write reflected fields,
    -- the cached image restores Status/Type to their original 0/0 values.
    --
    -- Therefore ALL reflected writes happen BEFORE the native patch.
    -- After pcl_anchor_patch_row returns, this function performs READS ONLY.
    -- =====================================================================

    -- Player-facing name first. This lives before Status/Type in the row and
    -- the native patch deliberately does not touch DisplayName.
    local name_ok, name_err = pcl15161_set_display_name(dst.row)
    if not name_ok then
        return finish(false, 'DisplayName failed before native commit: ' ..
            tostring(name_err))
    end

    -- Any other reflected metadata that we want is also applied before the
    -- native patch. These values are redundantly enforced by the DLL afterward.
    local meta_ok, meta_err = pcall(function()
        dst.row.bHandGrip = false
        dst.row.bPreventPlacingOnSurfaces = false
        dst.row.bWrapAroundBlade = false
        dst.row.bDisplayUpright = false
        dst.row.bHasPrimarySlot = true
    end)
    if not meta_ok then
        return finish(false, 'pre-native metadata write failed: ' ..
            tostring(meta_err))
    end

    -- Snapshot raw state immediately before the final native commit.
    local pre_native, pre_err = pcl15163_native_row_state(dst.row)
    if pre_native ~= nil then
        log('PCL15_16_4_PRE_NATIVE' ..
            ' status=' .. tostring(pre_native.status) ..
            ' type=' .. tostring(pre_native.typ) ..
            ' primary=' .. tostring(pre_native.primary) ..
            ' slots=' .. tostring(pre_native.slots) ..
            string.format(' addr=0x%X', pre_native.address))
    else
        log('PCL15_16_4_PRE_NATIVE_INSPECT_ERROR=' .. tostring(pre_err))
    end

    -- FINAL WRITE TO THE ROW.
    -- Nothing reflected is allowed to write to dst.row after this call.
    local call_ok, native_status = pcall(
        patch_fn,
        dst_addr,
        hollow_addr,
        cube_addr
    )
    if not call_ok then
        return finish(false, 'native patch exception: ' .. tostring(native_status))
    end
    native_status = tonumber(native_status) or -9999
    if native_status ~= 1 then
        return finish(false, 'native patch status=' .. tostring(native_status))
    end

    -- Native raw verification FIRST, before any reflected property access.
    local post_native, post_err = pcl15163_native_row_state(dst.row)
    if post_native == nil then
        return finish(false, 'post-native inspect failed: ' .. tostring(post_err))
    end

    log('PCL15_16_4_POST_NATIVE' ..
        ' status=' .. tostring(post_native.status) ..
        ' type=' .. tostring(post_native.typ) ..
        ' primary=' .. tostring(post_native.primary) ..
        ' slots=' .. tostring(post_native.slots) ..
        string.format(' addr=0x%X packed=0x%X',
            post_native.address, post_native.packed))

    if post_native.status ~= 2 or
       post_native.typ ~= 2 or
       post_native.primary ~= 1 or
       post_native.slots ~= 2 then
        return finish(false,
            'native final state mismatch status=' ..
            tostring(post_native.status) ..
            ' type=' .. tostring(post_native.typ) ..
            ' primary=' .. tostring(post_native.primary) ..
            ' slots=' .. tostring(post_native.slots))
    end

    -- READ-ONLY reflected verification. If merely reading the struct causes
    -- native state to change, the second native inspection below catches it.
    local verify_ok, verify_msg = pcl15161_verify_row(dst.row)
    if not verify_ok then
        return finish(false, verify_msg)
    end

    local after_reads, after_reads_err = pcl15163_native_row_state(dst.row)
    if after_reads == nil then
        return finish(false, 'after-read inspect failed: ' ..
            tostring(after_reads_err))
    end

    log('PCL15_16_4_AFTER_REFLECTED_READS' ..
        ' status=' .. tostring(after_reads.status) ..
        ' type=' .. tostring(after_reads.typ) ..
        ' primary=' .. tostring(after_reads.primary) ..
        ' slots=' .. tostring(after_reads.slots) ..
        string.format(' addr=0x%X', after_reads.address))

    if after_reads.status ~= 2 or after_reads.typ ~= 2 then
        return finish(false,
            'reflected reads clobbered native enums status=' ..
            tostring(after_reads.status) ..
            ' type=' .. tostring(after_reads.typ))
    end

    log('PCL15_16_4_ITEM_READY=true' ..
        ' internal_row=' .. PCL15161_ROW_NAME ..
        ' visible_name=' .. PCL15161_DISPLAY_NAME ..
        ' table=' .. safe_full_name(dst.data_table) ..
        string.format(' dst=0x%X hollow=0x%X cube=0x%X',
            dst_addr, hollow_addr, cube_addr) ..
        ' ' .. tostring(verify_msg))

    return finish(true, nil)
end

function pcl15161_install_retry()
    if PCL15161_READY then return end
    PCL15161_ATTEMPTS = PCL15161_ATTEMPTS + 1

    run_game_thread(function()
        if PCL15161_READY then return end

        local ok, err = pcl15161_patch_catalogue_item()
        if not ok then
            if PCL15161_ATTEMPTS == 1 or
               PCL15161_ATTEMPTS % 20 == 0 or
               PCL15161_ATTEMPTS >= PCL15161_MAX_ATTEMPTS then
                log('PCL15_16_1_INSTALL_WAIT attempt=' ..
                    tostring(PCL15161_ATTEMPTS) ..
                    ' error=' .. tostring(err))
            end
        end
    end)

    if not PCL15161_READY and
       PCL15161_ATTEMPTS < PCL15161_MAX_ATTEMPTS then
        pcl15179_schedule(250, pcl15161_install_retry)
    end
end

function pcl15161_fail(msg, actors)
    log('PCL15_16_1_TEST_ERROR=' .. tostring(msg))
    pcl15129_fail(msg, actors)
end

function pcl15161_catalogue_test()
    log('============================================================')
    log('PCL15_16_1_DEDICATED_CATALOGUE_ANCHOR_TEST_BEGIN')

    if not PCL15161_READY then
        local ok, err = pcl15161_patch_catalogue_item()
        if not ok then
            log('PCL15_16_1_TEST_ERROR=item_not_ready ' .. tostring(err))
            log('============================================================')
            return
        end
    end

    local dst, _, _, _, find_err = pcl15161_find_rows()
    if find_err ~= nil or dst == nil then
        log('PCL15_16_1_TEST_ERROR=backing_row_lost ' .. tostring(find_err))
        log('============================================================')
        return
    end

    local verified, verify_msg = pcl15161_verify_row(dst.row)
    if not verified then
        log('PCL15_16_1_TEST_ERROR=pre_spawn_verification ' .. tostring(verify_msg))
        log('============================================================')
        return
    end

    if PCL15129_RUNNING then
        log('PCL15_16_1_TEST_ERROR=already_running')
        log('============================================================')
        return
    end

    local forge, piece, design, state_err = state_no_serialize_11()
    if state_err ~= nil then
        log('PCL15_16_1_TEST_ERROR=' .. tostring(state_err))
        log('============================================================')
        return
    end

    local design_count = -1
    pcall(function() design_count = #design.AppliedSwordParts end)

    local handling, existing_preview = current_preview_14()
    if not is_valid(handling) then
        log('PCL15_16_1_TEST_ERROR=handling_unavailable')
        log('============================================================')
        return
    end
    if is_valid(existing_preview) then
        log('PCL15_16_1_TEST_ERROR=preview_already_active press_X_first')
        log('============================================================')
        return
    end
    if design_count ~= 0 then
        log('PCL15_16_1_TEST_ERROR=requires_empty_forge design_parts=' ..
            tostring(design_count))
        log('============================================================')
        return
    end

    PCL15129_RUNNING = true
    local actors = {}
    PCL15129_ACTORS = actors

    -- Must come through Bladesong's normal catalogue path. The internal row
    -- key is TRIPLANAR_GRIP, but the player-facing DisplayName is
    -- Preconstruction Anchor.
    local root, err =
        pcl15129_take_catalogue_actor(PCL15161_ROW_NAME, actors)

    if not is_valid(root) then
        pcl15161_fail(
            tostring(err) ..
            ' | Catalogue tile was not available. FULLY restart Bladesong with 15.16.1 installed before entering Forge.',
            actors)
        return
    end

    local cube_a
    cube_a, err = pcl15129_take_catalogue_actor('80_Misc_Cube', actors)
    if not is_valid(cube_a) then pcl15161_fail(err, actors); return end

    local cube_b
    cube_b, err = pcl15129_take_catalogue_actor('80_Misc_Cube', actors)
    if not is_valid(cube_b) then pcl15161_fail(err, actors); return end

    local cube_c
    cube_c, err = pcl15129_take_catalogue_actor('80_Misc_Cube', actors)
    if not is_valid(cube_c) then pcl15161_fail(err, actors); return end

    local cube_d
    cube_d, err = pcl15129_take_catalogue_actor('80_Misc_Cube', actors)
    if not is_valid(cube_d) then pcl15161_fail(err, actors); return end

    local ok, link_err = attach_child_live_14(root, 1, cube_a)
    if not ok then
        pcl15161_fail(
            'Preconstruction Anchor slot1 Right -> CubeA: ' ..
            tostring(link_err),
            actors)
        return
    end

    ok, link_err = attach_child_live_14(cube_a, 1, cube_b)
    if not ok then pcl15161_fail('CubeA slot1 -> CubeB: ' .. tostring(link_err), actors); return end

    ok, link_err = attach_child_live_14(cube_a, 2, cube_c)
    if not ok then pcl15161_fail('CubeA slot2 -> CubeC: ' .. tostring(link_err), actors); return end

    ok, link_err = attach_child_live_14(cube_a, 3, cube_d)
    if not ok then pcl15161_fail('CubeA slot3 -> CubeD: ' .. tostring(link_err), actors); return end

    local tree = live_tree_count_14(root)
    log('PCL15_16_1_LINKED_TREE_COUNT=' .. tostring(tree) .. ' expected=5')
    if tree ~= 5 then
        pcl15161_fail('tree count mismatch actual=' .. tostring(tree), actors)
        return
    end

    pcall(function()
        root.bPending = true
        cube_a.bPending = false
        cube_b.bPending = false
        cube_c.bPending = false
        cube_d.bPending = false

        root:SetActorHiddenInGame(false)
        cube_a:SetActorHiddenInGame(false)
        cube_b:SetActorHiddenInGame(false)
        cube_c:SetActorHiddenInGame(false)
        cube_d:SetActorHiddenInGame(false)

        root:SetActorEnableCollision(true)
        cube_a:SetActorEnableCollision(true)
        cube_b:SetActorEnableCollision(true)
        cube_c:SetActorEnableCollision(true)
        cube_d:SetActorEnableCollision(true)
    end)

    local hand_ok, hand_err = pcall(function()
        handling.BestSwordPartSlotParent = nil
        handling.PreviewSwordPartActor = root
    end)
    if not hand_ok then
        pcl15161_fail('preview handoff: ' .. tostring(hand_err), actors)
        return
    end

    local preview = nil
    local has_preview = false
    pcall(function()
        preview = handling.PreviewSwordPartActor
        has_preview = handling:HasPreviewSwordPart() and true or false
    end)

    local held_count = live_tree_count_14(preview)
    local held_row =
        is_valid(preview) and live_actor_row_10(preview) or 'None'

    log('PCL15_16_1_HAS_PREVIEW=' .. tostring(has_preview))
    log('PCL15_16_1_HELD_ROOT_INTERNAL=' .. tostring(held_row))
    log('PCL15_16_1_HELD_TREE_COUNT=' .. tostring(held_count) .. ' expected=5')

    if not has_preview or
       held_row ~= PCL15161_ROW_NAME or
       held_count ~= 5 then
        pcl15161_fail('handoff verification failed', actors)
        return
    end

    PCL15129_RUNNING = false

    log('PCL15_16_1_TEST_OK=true')
    log('VISIBLE_ITEM=Preconstruction Anchor')
    log('PERSISTENT_INTERNAL_ID=TRIPLANAR_GRIP')
    log('CUBE_METADATA_NATIVE_CLONED=true')
    log('ADDROW_USED=false')
    log('Place it, pick it up, then reload/re-enter Forge and test again.')
    log('============================================================')
end

RegisterKeyBind(
    Key.A,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(pcl15161_catalogue_test)
    end
)

pcl15179_schedule(250, pcl15161_install_retry)

log('Phase 15.16.1 DEDICATED PRECONSTRUCTION ANCHOR CATALOGUE ITEM active.')
log('UDataTable:AddRow is intentionally NOT used on this UE4SS/UE5.7 build.')
log('Backing row TRIPLANAR_GRIP is converted into the player-facing Preconstruction Anchor.')
log('FULL GAME RESTART is required before the catalogue/persistence test.')
log('CTRL+ALT+A = construct the five-part test through the patched catalogue item.')


log('Phase 15.16.2 enum-clobber fix overlay active.')
log('Type/Status are now written ONLY by pcl_anchor_catalogue_patch_15161.dll.')
log('Lua no longer assigns integer values to those enum-backed row properties.')


log('Phase 15.16.3 native enum verifier overlay active.')
log('Type/Status verification now reads raw SwordPartData bytes through the DLL.')
log('Lua EnumProperty Type/Status values are diagnostic only and no longer block the item.')


log('Phase 15.16.4 native-last commit fix active.')
log('All reflected row WRITES now occur before the native patch.')
log('After pcl_anchor_patch_row returns, the anchor row is read-only.')


-- ============================================================================
-- Phase 15.16.5 - EXACT DATATABLE PIN
--
-- 15.16.4 proved the patched dev-only row is correct and stable:
--   Status=2 Type=2 Primary=1 Slots=2 Left/Right
--
-- The remaining failure was lookup ambiguity. A later broad
-- find_row_in_tables_7("TRIPLANAR_GRIP") returned a DIFFERENT row object from
-- a different table/address.
--
-- 15.16.5 pins every anchor operation to:
--   /Game/Swordmaking/DataTables/Parts/DT_SwordParts_DevOnly
--
-- The normal donors are pinned to:
--   /Game/Swordmaking/DataTables/Parts/DT_SwordParts
-- ============================================================================

PCL15165_DEV_TABLE_FULL =
    'DataTable /Game/Swordmaking/DataTables/Parts/DT_SwordParts_DevOnly.DT_SwordParts_DevOnly'

PCL15165_MAIN_TABLE_FULL =
    'DataTable /Game/Swordmaking/DataTables/Parts/DT_SwordParts.DT_SwordParts'

function pcl15165_exact_row(table_full, wanted_name)
    local dt = find_saved_datatable_145(table_full)
    if not is_valid(dt) then
        return nil, 'exact DataTable unavailable: ' .. tostring(table_full)
    end

    local names = get_row_names_7(dt)
    for _, rn in ipairs(names) do
        if safe_name(rn) == wanted_name then
            local row = nil
            local ok, err = pcall(function()
                row = dt:FindRow(rn)
            end)

            if not ok or row == nil then
                return nil,
                    'FindRow failed row=' .. tostring(wanted_name) ..
                    ' table=' .. tostring(table_full) ..
                    ' error=' .. tostring(err)
            end

            return {
                data_table = dt,
                row_name = rn,
                row = row
            }, nil
        end
    end

    return nil,
        'row not found in exact DataTable row=' .. tostring(wanted_name) ..
        ' table=' .. tostring(table_full)
end

-- Override the 15.16.x resolver with exact-table identities.
function pcl15161_find_rows()
    local dst, dst_err =
        pcl15165_exact_row(
            PCL15165_DEV_TABLE_FULL,
            PCL15161_ROW_NAME
        )
    if dst == nil then
        return nil, nil, nil, nil, dst_err
    end

    local hollow, hollow_err =
        pcl15165_exact_row(
            PCL15165_MAIN_TABLE_FULL,
            '574_Hollow'
        )
    if hollow == nil then
        return nil, nil, nil, nil, hollow_err
    end

    local cube, cube_err =
        pcl15165_exact_row(
            PCL15165_MAIN_TABLE_FULL,
            '80_Misc_Cube'
        )
    if cube == nil then
        return nil, nil, nil, nil, cube_err
    end

    return dst, hollow, cube,
        { dst.data_table, hollow.data_table },
        nil
end

function pcl15165_button_handle_info(button)
    if not is_valid(button) then
        return 'None', 'None'
    end

    local row_name = 'None'
    local table_full = 'None'

    pcall(function()
        local handle = button.SwordPartDataRowHandle
        if handle ~= nil then
            row_name = safe_name(handle.RowName)

            if is_valid(handle.DataTable) then
                table_full = safe_full_name(handle.DataTable)
            end
        end
    end)

    return tostring(row_name), tostring(table_full)
end

function pcl15165_find_exact_anchor_button()
    local buttons = find_live_part_buttons_9()
    local matches = {}

    for _, button in ipairs(buttons) do
        local row_name, table_full =
            pcl15165_button_handle_info(button)

        if row_name == PCL15161_ROW_NAME then
            table.insert(matches, {
                button = button,
                table_full = table_full,
                object = safe_full_name(button)
            })

            log('PCL15_16_5_ANCHOR_TILE_CANDIDATE' ..
                ' table=' .. tostring(table_full) ..
                ' widget=' .. safe_full_name(button))

            if table_full == PCL15165_DEV_TABLE_FULL then
                return button, nil
            end
        end
    end

    if #matches == 0 then
        return nil,
            'no live catalogue tile with row=' ..
            tostring(PCL15161_ROW_NAME)
    end

    local desc = {}
    for _, m in ipairs(matches) do
        table.insert(
            desc,
            '[' .. tostring(m.table_full) .. ']'
        )
    end

    return nil,
        'row-name tile(s) exist but none point to exact dev-only table; candidates=' ..
        table.concat(desc, ',')
end

function pcl15165_click_exact_anchor_tile(selected_button)
    local button, find_err = selected_button, nil
    if not is_valid(button) then button, find_err = pcl15165_find_exact_anchor_button() end

    if not is_valid(button) then
        return false, find_err
    end

    local common = nil
    local ok, err = pcall(function()
        common = button.Button
    end)

    if not ok or not is_valid(common) then
        return false,
            'exact anchor tile Button unavailable: ' ..
            tostring(err)
    end

    local row_name, table_full =
        pcl15165_button_handle_info(button)

    log('PCL15_16_5_EXACT_TILE_CLICK' ..
        ' row=' .. tostring(row_name) ..
        ' table=' .. tostring(table_full) ..
        ' widget=' .. safe_full_name(button))

    ok, err = pcall(function()
        common:HandleButtonClicked()
    end)

    if not ok then
        return false,
            'exact anchor HandleButtonClicked failed: ' ..
            tostring(err)
    end

    return true, nil
end

function pcl15165_actor_handle_info(actor)
    if not is_valid(actor) then
        return 'None', 'None'
    end

    local row_name = 'None'
    local table_full = 'None'

    pcall(function()
        local handle = actor.SwordPartDataHandle
        if handle ~= nil then
            row_name = safe_name(handle.RowName)
            if is_valid(handle.DataTable) then
                table_full = safe_full_name(handle.DataTable)
            end
        end
    end)

    return tostring(row_name), tostring(table_full)
end

function pcl15165_take_exact_anchor_actor(actors, selected_button)
    local click_ok, click_err =
        pcl15165_click_exact_anchor_tile(selected_button)

    if not click_ok then
        return nil, 'exact catalogue click: ' .. tostring(click_err)
    end

    local handling, preview =
        current_preview_14()

    if not is_valid(handling) then
        return nil, 'handling unavailable after exact anchor click'
    end

    if not is_valid(preview) then
        return nil, 'no preview after exact anchor click'
    end

    local row_name, table_full =
        pcl15165_actor_handle_info(preview)

    log('PCL15_16_5_EXACT_PREVIEW' ..
        ' row=' .. tostring(row_name) ..
        ' table=' .. tostring(table_full) ..
        ' actor=' .. safe_full_name(preview))

    if row_name ~= PCL15161_ROW_NAME then
        return nil,
            'exact tile returned wrong row expected=' ..
            tostring(PCL15161_ROW_NAME) ..
            ' actual=' .. tostring(row_name)
    end

    if table_full ~= PCL15165_DEV_TABLE_FULL then
        return nil,
            'preview row handle points to wrong table expected=' ..
            tostring(PCL15165_DEV_TABLE_FULL) ..
            ' actual=' .. tostring(table_full)
    end

    local detach_ok, detach_err =
        detach_live_actor_14(preview)

    if not detach_ok then
        return nil,
            'anchor detach failed: ' ..
            tostring(detach_err)
    end

    local clear_ok, clear_err =
        clear_preview_pointer_14()

    if not clear_ok then
        return nil,
            'anchor preview clear failed: ' ..
            tostring(clear_err)
    end

    pcall(function()
        preview:SetActorHiddenInGame(false)
        preview:SetActorEnableCollision(true)
        preview:SetActorTickEnabled(true)
    end)

    table.insert(actors, preview)
    return preview, nil
end

-- Force attach_child_live_14 to use the exact patched dev-only row for the
-- anchor root. We temporarily seed its row cache, then restore prior state.
function pcl15165_attach_anchor_child(parent, slot_native, child)
    if not is_valid(parent) or not is_valid(child) then
        return false, 'anchor parent/child invalid'
    end

    local exact, exact_err =
        pcl15165_exact_row(
            PCL15165_DEV_TABLE_FULL,
            PCL15161_ROW_NAME
        )

    if exact == nil then
        return false,
            'exact anchor row unavailable for attach: ' ..
            tostring(exact_err)
    end

    local old_cache = PCL151117_CACHE
    local created_cache = false

    if old_cache == nil then
        PCL151117_CACHE = {
            data_only_staging = false,
            part_rows = {},
            slot_meta = {},
            stats = {}
        }
        created_cache = true
    end

    local cache = PCL151117_CACHE
    cache.part_rows = cache.part_rows or {}
    cache.slot_meta = cache.slot_meta or {}
    cache.stats = cache.stats or {}

    local row_key = tostring(PCL15161_ROW_NAME)
    local meta_key =
        row_key .. '\31' .. tostring(slot_native)

    local previous_row = cache.part_rows[row_key]
    local previous_meta = cache.slot_meta[meta_key]
    local previous_data_only = cache.data_only_staging

    cache.data_only_staging = false
    cache.part_rows[row_key] = exact
    cache.slot_meta[meta_key] = nil

    log('PCL15_16_5_ATTACH_PIN' ..
        ' row=' .. row_key ..
        ' table=' .. safe_full_name(exact.data_table) ..
        ' slot=' .. tostring(slot_native))

    local ok, err =
        attach_child_live_14(
            parent,
            slot_native,
            child
        )

    if created_cache then
        PCL151117_CACHE = nil
    else
        cache.part_rows[row_key] = previous_row
        cache.slot_meta[meta_key] = previous_meta
        cache.data_only_staging = previous_data_only
    end

    return ok, err
end

-- Replace the test with an exact-table-pinned version.
function pcl15161_catalogue_test()
    log('============================================================')
    log('PCL15_16_5_EXACT_TABLE_ANCHOR_TEST_BEGIN')

    if not PCL15161_READY then
        local ok, err = pcl15161_patch_catalogue_item()
        if not ok then
            log('PCL15_16_5_TEST_ERROR=item_not_ready ' ..
                tostring(err))
            log('============================================================')
            return
        end
    end

    local dst, _, _, _, find_err =
        pcl15161_find_rows()

    if find_err ~= nil or dst == nil then
        log('PCL15_16_5_TEST_ERROR=exact_backing_row_lost ' ..
            tostring(find_err))
        log('============================================================')
        return
    end

    local verified, verify_msg =
        pcl15161_verify_row(dst.row)

    if not verified then
        log('PCL15_16_5_TEST_ERROR=exact_pre_spawn_verification ' ..
            tostring(verify_msg))
        log('============================================================')
        return
    end

    log('PCL15_16_5_EXACT_PRECHECK_OK' ..
        ' table=' .. safe_full_name(dst.data_table) ..
        ' ' .. tostring(verify_msg))

    if PCL15129_RUNNING then
        log('PCL15_16_5_TEST_ERROR=already_running')
        log('============================================================')
        return
    end

    local forge, piece, design, state_err =
        state_no_serialize_11()

    if state_err ~= nil then
        log('PCL15_16_5_TEST_ERROR=' .. tostring(state_err))
        log('============================================================')
        return
    end

    local design_count = -1
    pcall(function()
        design_count = #design.AppliedSwordParts
    end)

    local handling, existing_preview =
        current_preview_14()

    if not is_valid(handling) then
        log('PCL15_16_5_TEST_ERROR=handling_unavailable')
        log('============================================================')
        return
    end

    if is_valid(existing_preview) then
        log('PCL15_16_5_TEST_ERROR=preview_already_active press_X_first')
        log('============================================================')
        return
    end

    if design_count ~= 0 then
        log('PCL15_16_5_TEST_ERROR=requires_empty_forge design_parts=' ..
            tostring(design_count))
        log('============================================================')
        return
    end

    PCL15129_RUNNING = true

    local actors = {}
    PCL15129_ACTORS = actors

    -- EXACT dev-only catalogue tile.
    local root, err =
        pcl15165_take_exact_anchor_actor(actors)

    if not is_valid(root) then
        pcl15161_fail(
            'exact Preconstruction Anchor allocation: ' ..
            tostring(err),
            actors)
        return
    end

    local cube_a
    cube_a, err =
        pcl15129_take_catalogue_actor(
            '80_Misc_Cube',
            actors
        )
    if not is_valid(cube_a) then
        pcl15161_fail(err, actors)
        return
    end

    local cube_b
    cube_b, err =
        pcl15129_take_catalogue_actor(
            '80_Misc_Cube',
            actors
        )
    if not is_valid(cube_b) then
        pcl15161_fail(err, actors)
        return
    end

    local cube_c
    cube_c, err =
        pcl15129_take_catalogue_actor(
            '80_Misc_Cube',
            actors
        )
    if not is_valid(cube_c) then
        pcl15161_fail(err, actors)
        return
    end

    local cube_d
    cube_d, err =
        pcl15129_take_catalogue_actor(
            '80_Misc_Cube',
            actors
        )
    if not is_valid(cube_d) then
        pcl15161_fail(err, actors)
        return
    end

    -- EXACT patched dev-only row for root slot metadata.
    local ok, link_err =
        pcl15165_attach_anchor_child(
            root,
            1,
            cube_a
        )

    if not ok then
        pcl15161_fail(
            'exact Preconstruction Anchor Right -> CubeA: ' ..
            tostring(link_err),
            actors)
        return
    end

    ok, link_err =
        attach_child_live_14(cube_a, 1, cube_b)
    if not ok then
        pcl15161_fail(
            'CubeA slot1 -> CubeB: ' ..
            tostring(link_err),
            actors)
        return
    end

    ok, link_err =
        attach_child_live_14(cube_a, 2, cube_c)
    if not ok then
        pcl15161_fail(
            'CubeA slot2 -> CubeC: ' ..
            tostring(link_err),
            actors)
        return
    end

    ok, link_err =
        attach_child_live_14(cube_a, 3, cube_d)
    if not ok then
        pcl15161_fail(
            'CubeA slot3 -> CubeD: ' ..
            tostring(link_err),
            actors)
        return
    end

    local tree =
        live_tree_count_14(root)

    log('PCL15_16_5_LINKED_TREE_COUNT=' ..
        tostring(tree) ..
        ' expected=5')

    if tree ~= 5 then
        pcl15161_fail(
            'tree count mismatch actual=' ..
            tostring(tree),
            actors)
        return
    end

    pcall(function()
        root.bPending = true

        cube_a.bPending = false
        cube_b.bPending = false
        cube_c.bPending = false
        cube_d.bPending = false

        root:SetActorHiddenInGame(false)
        cube_a:SetActorHiddenInGame(false)
        cube_b:SetActorHiddenInGame(false)
        cube_c:SetActorHiddenInGame(false)
        cube_d:SetActorHiddenInGame(false)

        root:SetActorEnableCollision(true)
        cube_a:SetActorEnableCollision(true)
        cube_b:SetActorEnableCollision(true)
        cube_c:SetActorEnableCollision(true)
        cube_d:SetActorEnableCollision(true)
    end)

    local hand_ok, hand_err =
        pcall(function()
            handling.BestSwordPartSlotParent = nil
            handling.PreviewSwordPartActor = root
        end)

    if not hand_ok then
        pcl15161_fail(
            'preview handoff: ' ..
            tostring(hand_err),
            actors)
        return
    end

    local preview = nil
    local has_preview = false

    pcall(function()
        preview =
            handling.PreviewSwordPartActor

        has_preview =
            handling:HasPreviewSwordPart() and
            true or false
    end)

    local held_count =
        live_tree_count_14(preview)

    local held_row, held_table =
        pcl15165_actor_handle_info(preview)

    log('PCL15_16_5_HAS_PREVIEW=' ..
        tostring(has_preview))

    log('PCL15_16_5_HELD_ROOT_INTERNAL=' ..
        tostring(held_row))

    log('PCL15_16_5_HELD_ROOT_TABLE=' ..
        tostring(held_table))

    log('PCL15_16_5_HELD_TREE_COUNT=' ..
        tostring(held_count) ..
        ' expected=5')

    if not has_preview or
       held_row ~= PCL15161_ROW_NAME or
       held_table ~= PCL15165_DEV_TABLE_FULL or
       held_count ~= 5 then

        pcl15161_fail(
            'exact handoff verification failed',
            actors)
        return
    end

    PCL15129_RUNNING = false

    log('PCL15_16_5_TEST_OK=true')
    log('VISIBLE_ITEM=Preconstruction Anchor')
    log('PERSISTENT_INTERNAL_ID=TRIPLANAR_GRIP')
    log('PERSISTENT_DATATABLE=' ..
        PCL15165_DEV_TABLE_FULL)
    log('CUBE_METADATA_NATIVE_CLONED=true')
    log('EXACT_TABLE_PIN=true')
    log('Place it, pick it up, then reload/re-enter Forge and test again.')
    log('============================================================')
end

log('Phase 15.16.5 EXACT DATATABLE PIN active.')
log('Anchor row/tile/slot lookup is pinned to DT_SwordParts_DevOnly.')
log('Normal donor rows are pinned to DT_SwordParts.')


-- ============================================================================
-- Phase 15.16.6 - LIVE ROW INSTANCE REPATCH
--
-- 15.16.5 proved the exact asset path is correct, but Bladesong reconstructs
-- or reloads the row storage after startup. The same exact DataTable asset had:
--
--   startup patched row  : 0x27EEF256A00  type=2 status=2 Left/Right
--   later live Forge row : 0x27F5B72D200  type=7 status=1 None/None
--
-- Therefore the row definition must be re-applied whenever the live row
-- instance/address or raw native state changes.
-- ============================================================================

PCL15166_LAST_GOOD_ADDR = 0
PCL15166_MONITOR_STARTED = false
PCL15166_MONITOR_INTERVAL_MS = 1000
PCL15166_REPATCH_COUNT = 0

function pcl15166_current_exact_anchor()
    local dst, err =
        pcl15165_exact_row(
            PCL15165_DEV_TABLE_FULL,
            PCL15161_ROW_NAME
        )

    if dst == nil or dst.row == nil then
        return nil, nil, 'exact live anchor row unavailable: ' .. tostring(err)
    end

    local raw, raw_err =
        pcl15163_native_row_state(dst.row)

    if raw == nil then
        return dst, nil, 'native row inspect failed: ' .. tostring(raw_err)
    end

    return dst, raw, nil
end

function pcl15166_raw_anchor_is_good(raw)
    if raw == nil then return false end

    return
        raw.status == 2 and
        raw.typ == 2 and
        raw.primary == 1 and
        raw.slots == 2
end

function pcl15166_ensure_current_anchor(reason)
    local dst, raw, inspect_err =
        pcl15166_current_exact_anchor()

    if dst == nil or raw == nil then
        return false, inspect_err
    end

    local current_addr =
        tonumber(raw.address) or 0

    local address_changed =
        PCL15166_LAST_GOOD_ADDR ~= 0 and
        current_addr ~= PCL15166_LAST_GOOD_ADDR

    local state_good =
        pcl15166_raw_anchor_is_good(raw)

    if state_good and not address_changed then
        return true, nil
    end

    log('PCL15_16_6_REPATCH_NEEDED' ..
        ' reason=' .. tostring(reason) ..
        ' address_changed=' .. tostring(address_changed) ..
        string.format(' current_addr=0x%X last_good=0x%X',
            current_addr,
            PCL15166_LAST_GOOD_ADDR) ..
        ' status=' .. tostring(raw.status) ..
        ' type=' .. tostring(raw.typ) ..
        ' primary=' .. tostring(raw.primary) ..
        ' slots=' .. tostring(raw.slots))

    -- Force the complete exact-table patch again. Do not trust READY=true
    -- because READY only described a previous row instance.
    local patch_ok, patch_err =
        pcl15161_patch_catalogue_item()

    if not patch_ok then
        return false,
            'live row repatch failed: ' ..
            tostring(patch_err)
    end

    local verify_dst, verify_raw, verify_err =
        pcl15166_current_exact_anchor()

    if verify_dst == nil or verify_raw == nil then
        return false,
            'post-repatch live row inspect failed: ' ..
            tostring(verify_err)
    end

    if not pcl15166_raw_anchor_is_good(verify_raw) then
        return false,
            'post-repatch raw state mismatch' ..
            ' status=' .. tostring(verify_raw.status) ..
            ' type=' .. tostring(verify_raw.typ) ..
            ' primary=' .. tostring(verify_raw.primary) ..
            ' slots=' .. tostring(verify_raw.slots)
    end

    -- Verify Left/Right + DisplayName through the exact current struct proxy.
    local reflected_ok, reflected_msg =
        pcl15161_verify_row(verify_dst.row)

    if not reflected_ok then
        return false,
            'post-repatch reflected verification failed: ' ..
            tostring(reflected_msg)
    end

    PCL15166_LAST_GOOD_ADDR =
        tonumber(verify_raw.address) or 0

    PCL15166_REPATCH_COUNT =
        PCL15166_REPATCH_COUNT + 1

    log('PCL15_16_6_REPATCH_OK' ..
        ' reason=' .. tostring(reason) ..
        ' count=' .. tostring(PCL15166_REPATCH_COUNT) ..
        string.format(' addr=0x%X',
            PCL15166_LAST_GOOD_ADDR) ..
        ' ' .. tostring(reflected_msg))

    return true, nil
end

function pcl15166_monitor_tick()
    run_game_thread(function()
        local ok, err =
            pcl15166_ensure_current_anchor(
                'monitor'
            )

        if not ok then
            -- Throttle noise: only log monitor failures when the row/table is
            -- genuinely unavailable or a repatch failed. The next tick retries.
            log('PCL15_16_6_MONITOR_WAIT=' ..
                tostring(err))
        end
    end)

    pcl15179_schedule(
        PCL15166_MONITOR_INTERVAL_MS,
        pcl15166_monitor_tick
    )
end

function pcl15166_start_monitor()
    if PCL15166_MONITOR_STARTED then
        return
    end

    PCL15166_MONITOR_STARTED = true

    pcl15179_schedule(
        50,
        pcl15166_monitor_tick
    )

    log('PCL15_16_6_MONITOR_STARTED interval_ms=' ..
        tostring(PCL15166_MONITOR_INTERVAL_MS))
end

-- Final override of the test: before any verification or catalogue work,
-- force the exact CURRENT live row instance into the anchor state.
local pcl15165_catalogue_test_previous =
    pcl15161_catalogue_test

function pcl15161_catalogue_test()
    log('============================================================')
    log('PCL15_16_6_LIVE_REPATCH_TEST_GATE_BEGIN')

    local ensure_ok, ensure_err =
        pcl15166_ensure_current_anchor(
            'hotkey_preflight'
        )

    if not ensure_ok then
        log('PCL15_16_6_TEST_ERROR=current_row_repatch ' ..
            tostring(ensure_err))
        log('============================================================')
        return
    end

    local dst, raw, raw_err =
        pcl15166_current_exact_anchor()

    if dst == nil or raw == nil then
        log('PCL15_16_6_TEST_ERROR=current_row_reinspect ' ..
            tostring(raw_err))
        log('============================================================')
        return
    end

    local verify_ok, verify_msg =
        pcl15161_verify_row(
            dst.row
        )

    if not verify_ok then
        log('PCL15_16_6_TEST_ERROR=current_row_verify ' ..
            tostring(verify_msg))
        log('============================================================')
        return
    end

    log('PCL15_16_6_CURRENT_ROW_OK' ..
        string.format(' addr=0x%X', raw.address) ..
        ' table=' ..
        safe_full_name(dst.data_table) ..
        ' ' .. tostring(verify_msg))

    -- Run the exact-table-pinned 15.16.5 test only after the current live row
    -- has been repatched and verified.
    pcl15165_catalogue_test_previous()
end

pcl15166_start_monitor()

log('Phase 15.16.6 LIVE ROW INSTANCE REPATCH active.')
log('The exact dev-only anchor row is monitored and repatched after reload/reallocation.')
log('CTRL+ALT+A now force-repatches the current live row before the 15.16.5 exact-table test.')


-- ============================================================================
-- Phase 15.16.7b - ANCHOR SLOT 1 CORNER OFFSET
--
-- Same geometry test as 15.16.7, but intentionally adds ZERO top-level local
-- declarations. 15.16.7 crossed Lua's 200-local limit in the main chunk.
-- ============================================================================

PCL15167_SLOT1_OFFSET = {
    X = 0.0,
    Y = -5.0,
    Z = -5.0,
}

function pcl15167_make_vec(v)
    return {
        X = tonumber(v and v.X) or 0,
        Y = tonumber(v and v.Y) or 0,
        Z = tonumber(v and v.Z) or 0,
    }
end

function pcl15167_is_exact_anchor_actor(actor)
    if not is_valid(actor) then
        return false
    end

    local row_name, table_full =
        pcl15165_actor_handle_info(actor)

    return
        row_name == PCL15161_ROW_NAME and
        table_full == PCL15165_DEV_TABLE_FULL
end

function pcl15167_apply_slot1_offset_to_row(dst)
    if dst == nil or dst.row == nil then
        return false, 'anchor row missing'
    end

    local slot, slot_err =
        get_slot_struct_10(
            dst.row,
            1
        )

    if slot == nil then
        return false,
            'slot 1 resolve failed: ' ..
            tostring(slot_err)
    end

    local wanted =
        pcl15167_make_vec(
            PCL15167_SLOT1_OFFSET
        )

    local ok, err =
        pcall(function()
            slot.Offset.X = wanted.X
            slot.Offset.Y = wanted.Y
            slot.Offset.Z = wanted.Z
        end)

    if not ok then
        return false,
            'slot 1 offset write failed: ' ..
            tostring(err)
    end

    local rx, ry, rz = 0, 0, 0

    ok, err =
        pcall(function()
            rx = tonumber(slot.Offset.X) or 0
            ry = tonumber(slot.Offset.Y) or 0
            rz = tonumber(slot.Offset.Z) or 0
        end)

    if not ok then
        return false,
            'slot 1 offset reread failed: ' ..
            tostring(err)
    end

    log('PCL15_16_7_SLOT1_OFFSET_ROW' ..
        ' X=' .. tostring(rx) ..
        ' Y=' .. tostring(ry) ..
        ' Z=' .. tostring(rz))

    return true, nil
end

PCL15167_PREVIOUS_ENSURE_CURRENT_ANCHOR =
    pcl15166_ensure_current_anchor

function pcl15166_ensure_current_anchor(reason)
    local ok, err =
        PCL15167_PREVIOUS_ENSURE_CURRENT_ANCHOR(
            reason
        )

    if not ok then
        return false, err
    end

    local dst, raw, inspect_err =
        pcl15166_current_exact_anchor()

    if dst == nil or raw == nil then
        return false, inspect_err
    end

    local offset_ok, offset_err =
        pcl15167_apply_slot1_offset_to_row(
            dst
        )

    if not offset_ok then
        return false,
            'slot1 corner offset apply failed: ' ..
            tostring(offset_err)
    end

    return true, nil
end

PCL15167_PREVIOUS_ATTACH_ANCHOR_CHILD =
    pcl15165_attach_anchor_child

function pcl15165_attach_anchor_child(parent, slot_native, child)
    local ok, err =
        PCL15167_PREVIOUS_ATTACH_ANCHOR_CHILD(
            parent,
            slot_native,
            child
        )

    if not ok then
        return ok, err
    end

    if slot_native ~= 1 then
        return ok, err
    end

    if not pcl15167_is_exact_anchor_actor(parent) then
        return ok, err
    end

    local wanted =
        pcl15167_make_vec(
            PCL15167_SLOT1_OFFSET
        )

    local child_root = nil
    pcall(function()
        child_root =
            child:K2_GetRootComponent()
    end)

    if not is_valid(child_root) then
        return false,
            'child root unavailable for slot1 override'
    end

    local hit = {}

    local live_ok, live_err =
        pcall(function()
            child_root:K2_SetRelativeLocation(
                wanted,
                false,
                hit,
                true
            )
        end)

    if not live_ok then
        return false,
            'slot1 live relative location failed: ' ..
            tostring(live_err)
    end

    log('PCL15_16_7_SLOT1_OFFSET_LIVE' ..
        ' X=' .. tostring(wanted.X) ..
        ' Y=' .. tostring(wanted.Y) ..
        ' Z=' .. tostring(wanted.Z))

    return true, nil
end

log('Phase 15.16.7b ANCHOR SLOT 1 CORNER OFFSET active.')
log('No new top-level locals are used in this phase.')
log('Current slot1 override = X=' ..
    tostring(PCL15167_SLOT1_OFFSET.X) ..
    ' Y=' ..
    tostring(PCL15167_SLOT1_OFFSET.Y) ..
    ' Z=' ..
    tostring(PCL15167_SLOT1_OFFSET.Z))


-- ============================================================================
-- Phase 15.16.8 - LIVE ANCHOR HARDPOINT XYZ TUNER
--
-- No new top-level locals: the main chunk is at Lua's 200-local ceiling.
--
-- 15.16.7b proved Slot.Offset is live, but -5/-5 was too large and buried the
-- anchor/assembly geometry. This phase resets the offset to zero and lets the
-- user tune X/Y/Z interactively in 0.5-unit increments without restarting.
-- ============================================================================

PCL15168_STEP = 0.5
PCL15167_SLOT1_OFFSET = { X = 0.0, Y = 0.0, Z = 0.0 }
PCL15168_LAST_LOGGED_OFFSET = ""

-- Quiet replacement: only write/log slot 1 when its current value differs
-- from the requested tuner value. This avoids the 200-ms monitor log flood.
function pcl15167_apply_slot1_offset_to_row(dst)
    if dst == nil or dst.row == nil then
        return false, 'anchor row missing'
    end

    local slot, slot_err =
        get_slot_struct_10(dst.row, 1)

    if slot == nil then
        return false,
            'slot 1 resolve failed: ' ..
            tostring(slot_err)
    end

    local wanted =
        pcl15167_make_vec(
            PCL15167_SLOT1_OFFSET
        )

    local rx, ry, rz = 0, 0, 0
    local read_ok, read_err =
        pcall(function()
            rx = tonumber(slot.Offset.X) or 0
            ry = tonumber(slot.Offset.Y) or 0
            rz = tonumber(slot.Offset.Z) or 0
        end)

    if not read_ok then
        return false,
            'slot 1 offset read failed: ' ..
            tostring(read_err)
    end

    local differs =
        math.abs(rx - wanted.X) > 0.0001 or
        math.abs(ry - wanted.Y) > 0.0001 or
        math.abs(rz - wanted.Z) > 0.0001

    if differs then
        local write_ok, write_err =
            pcall(function()
                slot.Offset.X = wanted.X
                slot.Offset.Y = wanted.Y
                slot.Offset.Z = wanted.Z
            end)

        if not write_ok then
            return false,
                'slot 1 offset write failed: ' ..
                tostring(write_err)
        end

        log('PCL15_16_8_SLOT1_ROW_UPDATED' ..
            ' X=' .. tostring(wanted.X) ..
            ' Y=' .. tostring(wanted.Y) ..
            ' Z=' .. tostring(wanted.Z))
    end

    return true, nil
end

function pcl15168_find_live_anchor()
    local live =
        collect_live_sword_part_actors_10()

    for _, actor in ipairs(live) do
        if pcl15167_is_exact_anchor_actor(actor) then
            return actor
        end
    end

    return nil
end

function pcl15168_slot_child(parent, wanted_slot)
    if not is_valid(parent) then
        return nil
    end

    local result = nil
    local map = nil
    pcall(function()
        map = parent.SlotChildParts
    end)

    if map == nil then
        return nil
    end

    pcall(function()
        map:ForEach(function(kp, vp)
            local k = tonumber(kp:get()) or -999
            if k == wanted_slot then
                local v = vp:get()
                if is_valid(v) then
                    result = v
                    return true
                end
            end
        end)
    end)

    return result
end

function pcl15168_apply_live_offset(reason)
    local ensure_ok, ensure_err =
        pcl15166_ensure_current_anchor(
            'tuner_' .. tostring(reason)
        )

    if not ensure_ok then
        log('PCL15_16_8_TUNER_ERROR ensure=' ..
            tostring(ensure_err))
        return
    end

    local anchor =
        pcl15168_find_live_anchor()

    if is_valid(anchor) then
        local child =
            pcl15168_slot_child(
                anchor,
                1
            )

        if is_valid(child) then
            local child_root = nil
            pcall(function()
                child_root =
                    child:K2_GetRootComponent()
            end)

            if is_valid(child_root) then
                local hit = {}
                local wanted =
                    pcl15167_make_vec(
                        PCL15167_SLOT1_OFFSET
                    )

                local move_ok, move_err =
                    pcall(function()
                        child_root:K2_SetRelativeLocation(
                            wanted,
                            false,
                            hit,
                            true
                        )
                    end)

                if not move_ok then
                    log('PCL15_16_8_TUNER_ERROR live_move=' ..
                        tostring(move_err))
                    return
                end
            end
        end
    end

    log('PCL15_16_8_OFFSET' ..
        ' reason=' .. tostring(reason) ..
        ' X=' .. tostring(PCL15167_SLOT1_OFFSET.X) ..
        ' Y=' .. tostring(PCL15167_SLOT1_OFFSET.Y) ..
        ' Z=' .. tostring(PCL15167_SLOT1_OFFSET.Z))
end

function pcl15168_adjust(dx, dy, dz, label)
    PCL15167_SLOT1_OFFSET.X =
        (tonumber(PCL15167_SLOT1_OFFSET.X) or 0) +
        (tonumber(dx) or 0)

    PCL15167_SLOT1_OFFSET.Y =
        (tonumber(PCL15167_SLOT1_OFFSET.Y) or 0) +
        (tonumber(dy) or 0)

    PCL15167_SLOT1_OFFSET.Z =
        (tonumber(PCL15167_SLOT1_OFFSET.Z) or 0) +
        (tonumber(dz) or 0)

    pcl15168_apply_live_offset(label)
end

function pcl15168_reset()
    PCL15167_SLOT1_OFFSET.X = 0
    PCL15167_SLOT1_OFFSET.Y = 0
    PCL15167_SLOT1_OFFSET.Z = 0
    pcl15168_apply_live_offset('reset')
end

-- X axis / depth
RegisterKeyBind(
    Key.B,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15168_adjust(
                PCL15168_STEP, 0, 0,
                'X_plus'
            )
        end)
    end
)

RegisterKeyBind(
    Key.V,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15168_adjust(
                -PCL15168_STEP, 0, 0,
                'X_minus'
            )
        end)
    end
)

-- Y axis
RegisterKeyBind(
    Key.E,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15168_adjust(
                0, PCL15168_STEP, 0,
                'Y_plus'
            )
        end)
    end
)

RegisterKeyBind(
    Key.F,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15168_adjust(
                0, -PCL15168_STEP, 0,
                'Y_minus'
            )
        end)
    end
)

-- Z axis
RegisterKeyBind(
    Key.W,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15168_adjust(
                0, 0, PCL15168_STEP,
                'Z_plus'
            )
        end)
    end
)

RegisterKeyBind(
    Key.S,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15168_adjust(
                0, 0, -PCL15168_STEP,
                'Z_minus'
            )
        end)
    end
)

RegisterKeyBind(
    Key.C,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(
            pcl15168_reset
        )
    end
)

log('Phase 15.16.8 LIVE HARDPOINT XYZ TUNER active.')
log('15.16.8 starts slot1 offset at X=0 Y=0 Z=0; step=0.5.')
log('CTRL+ALT+B/V = X +/-.')
log('CTRL+ALT+E/F = Y +/-.')
log('CTRL+ALT+W/S = Z +/-.')
log('CTRL+ALT+C = reset offset to 0,0,0.')
log('CTRL+ALT+A still creates the five-part anchor test using the current offset.')


-- ============================================================================
-- Phase 15.16.9 - LIVE POSITION + ROTATION TUNER
--
-- Adds rotation tuning without adding top-level locals.
--
-- Slot structs expose position Offset but no independent rotation field, so
-- orientation is applied to the attached slot-1 child/root relative to the
-- anchor socket using K2_SetRelativeRotation.
-- ============================================================================

PCL15169_ROT_STEP = 5.0
PCL15169_ROTATION = {
    Pitch = 0.0,
    Yaw = 0.0,
    Roll = 0.0,
}

function pcl15169_make_rot()
    return {
        Pitch = tonumber(PCL15169_ROTATION.Pitch) or 0,
        Yaw = tonumber(PCL15169_ROTATION.Yaw) or 0,
        Roll = tonumber(PCL15169_ROTATION.Roll) or 0,
    }
end

function pcl15169_apply_rotation_to_child(child, reason)
    if not is_valid(child) then
        return false, 'child invalid'
    end

    local child_root = nil
    pcall(function()
        child_root = child:K2_GetRootComponent()
    end)

    if not is_valid(child_root) then
        return false, 'child root unavailable'
    end

    local rot = pcl15169_make_rot()
    local hit = {}

    local ok, err =
        pcall(function()
            child_root:K2_SetRelativeRotation(
                rot,
                false,
                hit,
                true
            )
        end)

    if not ok then
        return false,
            'K2_SetRelativeRotation failed: ' ..
            tostring(err)
    end

    log('PCL15_16_9_ROTATION' ..
        ' reason=' .. tostring(reason) ..
        ' Pitch=' .. tostring(rot.Pitch) ..
        ' Yaw=' .. tostring(rot.Yaw) ..
        ' Roll=' .. tostring(rot.Roll))

    return true, nil
end

function pcl15169_apply_live_rotation(reason)
    local anchor =
        pcl15168_find_live_anchor()

    if not is_valid(anchor) then
        log('PCL15_16_9_ROTATION_WAIT no_live_anchor')
        return
    end

    local child =
        pcl15168_slot_child(
            anchor,
            1
        )

    if not is_valid(child) then
        log('PCL15_16_9_ROTATION_WAIT no_slot1_child')
        return
    end

    local ok, err =
        pcl15169_apply_rotation_to_child(
            child,
            reason
        )

    if not ok then
        log('PCL15_16_9_ROTATION_ERROR=' ..
            tostring(err))
    end
end

function pcl15169_adjust(dp, dy, dr, label)
    PCL15169_ROTATION.Pitch =
        (tonumber(PCL15169_ROTATION.Pitch) or 0) +
        (tonumber(dp) or 0)

    PCL15169_ROTATION.Yaw =
        (tonumber(PCL15169_ROTATION.Yaw) or 0) +
        (tonumber(dy) or 0)

    PCL15169_ROTATION.Roll =
        (tonumber(PCL15169_ROTATION.Roll) or 0) +
        (tonumber(dr) or 0)

    pcl15169_apply_live_rotation(label)
end

function pcl15169_reset_rotation()
    PCL15169_ROTATION.Pitch = 0
    PCL15169_ROTATION.Yaw = 0
    PCL15169_ROTATION.Roll = 0
    pcl15169_apply_live_rotation('rotation_reset')
end

PCL15169_PREVIOUS_ATTACH_ANCHOR_CHILD =
    pcl15165_attach_anchor_child

function pcl15165_attach_anchor_child(parent, slot_native, child)
    local ok, err =
        PCL15169_PREVIOUS_ATTACH_ANCHOR_CHILD(
            parent,
            slot_native,
            child
        )

    if not ok then
        return ok, err
    end

    if slot_native == 1 and
       pcl15167_is_exact_anchor_actor(parent) then

        local rot_ok, rot_err =
            pcl15169_apply_rotation_to_child(
                child,
                'initial_attach'
            )

        if not rot_ok then
            return false, rot_err
        end
    end

    return true, nil
end

-- Pitch
RegisterKeyBind(
    Key.G,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15169_adjust(
                PCL15169_ROT_STEP, 0, 0,
                'Pitch_plus'
            )
        end)
    end
)

RegisterKeyBind(
    Key.H,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15169_adjust(
                -PCL15169_ROT_STEP, 0, 0,
                'Pitch_minus'
            )
        end)
    end
)

-- Yaw
RegisterKeyBind(
    Key.K,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15169_adjust(
                0, PCL15169_ROT_STEP, 0,
                'Yaw_plus'
            )
        end)
    end
)

RegisterKeyBind(
    Key.L,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15169_adjust(
                0, -PCL15169_ROT_STEP, 0,
                'Yaw_minus'
            )
        end)
    end
)

-- Roll
RegisterKeyBind(
    Key.N,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15169_adjust(
                0, 0, PCL15169_ROT_STEP,
                'Roll_plus'
            )
        end)
    end
)

RegisterKeyBind(
    Key.M,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(function()
            pcl15169_adjust(
                0, 0, -PCL15169_ROT_STEP,
                'Roll_minus'
            )
        end)
    end
)

RegisterKeyBind(
    Key.X,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(
            pcl15169_reset_rotation
        )
    end
)

log('Phase 15.16.9 LIVE POSITION + ROTATION TUNER active.')
log('Rotation step = 5 degrees.')
log('CTRL+ALT+G/H = Pitch +/-.')
log('CTRL+ALT+K/L = Yaw +/-.')
log('CTRL+ALT+N/M = Roll +/-.')
log('CTRL+ALT+X = reset rotation to 0,0,0.')


-- ============================================================================
-- Phase 15.16.10 - PHYSICAL CHILD ROTATION FIX
--
-- 15.16.9 hotkeys fired, but the logical SlotChildParts map was not exposing
-- slot 1 after placement, so rotation stopped at "no_slot1_child".
--
-- This phase resolves the attached prefab root using the ACTUAL scene
-- attachment relationship:
--   Actor:GetAttachParentActor()
-- and, as a fallback:
--   RootComponent:GetAttachParent()
--
-- It also carries forward the user's roughly-correct position from the
-- 15.16.9 tuning run:
--   X=1.5, Y=-1.0, Z=0.0
--
-- No new top-level locals are introduced.
-- ============================================================================

PCL15167_SLOT1_OFFSET = {
    X = 1.5,
    Y = -1.0,
    Z = 0.0,
}

function pcl151610_find_physical_anchor_child(anchor)
    if not is_valid(anchor) then
        return nil, 'anchor invalid'
    end

    -- First try the logical slot map because it is cheapest when available.
    local logical =
        pcl15168_slot_child(
            anchor,
            1
        )

    if is_valid(logical) then
        return logical, 'slot_map'
    end

    local anchor_addr =
        pcl151112_addr(anchor)

    local anchor_root = nil
    pcall(function()
        anchor_root =
            anchor:K2_GetRootComponent()
    end)

    local anchor_root_addr =
        pcl151112_addr(anchor_root)

    local live =
        collect_live_sword_part_actors_10()

    for _, actor in ipairs(live) do
        if is_valid(actor) and
           pcl151112_addr(actor) ~= anchor_addr then

            local parent_actor = nil
            pcall(function()
                parent_actor =
                    actor:GetAttachParentActor()
            end)

            if is_valid(parent_actor) and
               pcl151112_addr(parent_actor) == anchor_addr then

                return actor, 'actor_attach_parent'
            end

            if anchor_root_addr ~= 0 then
                local actor_root = nil
                local component_parent = nil

                pcall(function()
                    actor_root =
                        actor:K2_GetRootComponent()
                end)

                if is_valid(actor_root) then
                    pcall(function()
                        component_parent =
                            actor_root:GetAttachParent()
                    end)
                end

                if is_valid(component_parent) and
                   pcl151112_addr(component_parent) == anchor_root_addr then

                    return actor, 'component_attach_parent'
                end
            end
        end
    end

    return nil, 'no physical attached child found'
end

function pcl15169_apply_live_rotation(reason)
    local anchor =
        pcl15168_find_live_anchor()

    if not is_valid(anchor) then
        log('PCL15_16_10_ROTATION_WAIT no_live_anchor')
        return
    end

    local child, source =
        pcl151610_find_physical_anchor_child(
            anchor
        )

    if not is_valid(child) then
        log('PCL15_16_10_ROTATION_WAIT ' ..
            tostring(source))
        return
    end

    log('PCL15_16_10_ROTATION_TARGET' ..
        ' source=' .. tostring(source) ..
        ' anchor=' .. safe_full_name(anchor) ..
        ' child=' .. safe_full_name(child))

    local ok, err =
        pcl15169_apply_rotation_to_child(
            child,
            reason
        )

    if not ok then
        log('PCL15_16_10_ROTATION_ERROR=' ..
            tostring(err))
        return
    end

    local child_root = nil
    local rp, ry, rr = 0, 0, 0

    pcall(function()
        child_root =
            child:K2_GetRootComponent()

        if is_valid(child_root) then
            rp =
                tonumber(
                    child_root.RelativeRotation.Pitch
                ) or 0

            ry =
                tonumber(
                    child_root.RelativeRotation.Yaw
                ) or 0

            rr =
                tonumber(
                    child_root.RelativeRotation.Roll
                ) or 0
        end
    end)

    log('PCL15_16_10_ROTATION_APPLIED' ..
        ' Pitch=' .. tostring(rp) ..
        ' Yaw=' .. tostring(ry) ..
        ' Roll=' .. tostring(rr))
end

-- Re-apply the roughly-correct saved position immediately whenever the anchor
-- definition is ensured.
PCL151610_PREVIOUS_ENSURE_CURRENT_ANCHOR =
    pcl15166_ensure_current_anchor

function pcl15166_ensure_current_anchor(reason)
    local ok, err =
        PCL151610_PREVIOUS_ENSURE_CURRENT_ANCHOR(
            reason
        )

    if not ok then
        return false, err
    end

    local dst, raw, inspect_err =
        pcl15166_current_exact_anchor()

    if dst == nil or raw == nil then
        return false, inspect_err
    end

    local pos_ok, pos_err =
        pcl15167_apply_slot1_offset_to_row(
            dst
        )

    if not pos_ok then
        return false,
            '15.16.10 position restore failed: ' ..
            tostring(pos_err)
    end

    return true, nil
end

log('Phase 15.16.10 PHYSICAL CHILD ROTATION FIX active.')
log('Default tuned position carried forward: X=1.5 Y=-1.0 Z=0.0.')
log('Rotation now resolves the physical attached child instead of relying only on SlotChildParts.')


-- ============================================================================
-- Phase 15.16.11 - HARDPOINT SOCKET ORIENTATION TUNER
--
-- Child/prefab rotation is independent from the orange hardpoint arrow.
-- The arrow comes from the selected StaticMesh socket transform.
--
-- This phase lets us:
--   1) toggle bIsFlippedSlot live
--   2) cycle slot native=1 among Cube sockets:
--        Right -> Left -> Top -> Bottom -> Default -> Right ...
--
-- The slot index stays 1, so GuardQuillon carry semantics are preserved.
-- The currently tuned offset is preserved and the live child is rebound to
-- the newly selected socket.
--
-- ZERO new top-level locals.
-- ============================================================================

PCL151611_SOCKET_NAMES = {
    'Right',
    'Left',
    'Top',
    'Bottom',
    'Default',
}

PCL151611_SOCKET_INDEX = 1
PCL151611_FLIPPED = false

function pcl151611_current_socket_name()
    return
        PCL151611_SOCKET_NAMES[
            PCL151611_SOCKET_INDEX
        ] or 'Right'
end

function pcl151611_apply_slot_orientation_to_row(dst)
    if dst == nil or dst.row == nil then
        return false, 'anchor row missing'
    end

    local slot, slot_err =
        get_slot_struct_10(
            dst.row,
            1
        )

    if slot == nil then
        return false,
            'slot 1 resolve failed: ' ..
            tostring(slot_err)
    end

    local wanted_name =
        pcl151611_current_socket_name()

    local wanted_fname, fname_err =
        make_existing_fname_83(
            wanted_name
        )

    if wanted_fname == nil then
        return false,
            'FName failed for ' ..
            tostring(wanted_name) ..
            ': ' ..
            tostring(fname_err)
    end

    local ok, err =
        pcall(function()
            slot.BoneName =
                wanted_fname

            slot.bIsFlippedSlot =
                PCL151611_FLIPPED and true or false

            slot.Offset.X =
                tonumber(PCL15167_SLOT1_OFFSET.X) or 0

            slot.Offset.Y =
                tonumber(PCL15167_SLOT1_OFFSET.Y) or 0

            slot.Offset.Z =
                tonumber(PCL15167_SLOT1_OFFSET.Z) or 0
        end)

    if not ok then
        return false,
            'slot orientation write failed: ' ..
            tostring(err)
    end

    log('PCL15_16_11_SLOT_ROW' ..
        ' BoneName=' .. tostring(wanted_name) ..
        ' Flipped=' .. tostring(PCL151611_FLIPPED) ..
        ' X=' .. tostring(PCL15167_SLOT1_OFFSET.X) ..
        ' Y=' .. tostring(PCL15167_SLOT1_OFFSET.Y) ..
        ' Z=' .. tostring(PCL15167_SLOT1_OFFSET.Z))

    return true, nil
end

PCL151611_PREVIOUS_ENSURE_CURRENT_ANCHOR =
    pcl15166_ensure_current_anchor

function pcl15166_ensure_current_anchor(reason)
    local ok, err =
        PCL151611_PREVIOUS_ENSURE_CURRENT_ANCHOR(
            reason
        )

    if not ok then
        return false, err
    end

    local dst, raw, inspect_err =
        pcl15166_current_exact_anchor()

    if dst == nil or raw == nil then
        return false, inspect_err
    end

    local orient_ok, orient_err =
        pcl151611_apply_slot_orientation_to_row(
            dst
        )

    if not orient_ok then
        return false,
            '15.16.11 slot orientation restore failed: ' ..
            tostring(orient_err)
    end

    return true, nil
end

function pcl151611_rebind_live_child(reason)
    local anchor =
        pcl15168_find_live_anchor()

    if not is_valid(anchor) then
        log('PCL15_16_11_REBIND_WAIT no_live_anchor')
        return
    end

    local child, source =
        pcl151610_find_physical_anchor_child(
            anchor
        )

    if not is_valid(child) then
        log('PCL15_16_11_REBIND_WAIT ' ..
            tostring(source))
        return
    end

    local parent_component = nil
    local child_root = nil

    pcall(function()
        parent_component =
            anchor:K2_GetRootComponent()

        child_root =
            child:K2_GetRootComponent()
    end)

    if not is_valid(parent_component) or
       not is_valid(child_root) then
        log('PCL15_16_11_REBIND_ERROR components_unavailable')
        return
    end

    local socket_name =
        pcl151611_current_socket_name()

    local socket_fname, fname_err =
        make_existing_fname_83(
            socket_name
        )

    if socket_fname == nil then
        log('PCL15_16_11_REBIND_ERROR fname=' ..
            tostring(fname_err))
        return
    end

    local attach_ok, attach_err =
        pcall(function()
            child:K2_AttachToComponent(
                parent_component,
                socket_fname,
                2, 2, 2,
                false
            )
        end)

    if not attach_ok then
        log('PCL15_16_11_REBIND_ERROR attach=' ..
            tostring(attach_err))
        return
    end

    local hit = {}
    local pos =
        pcl15167_make_vec(
            PCL15167_SLOT1_OFFSET
        )

    local rot =
        pcl15169_make_rot()

    local transform_ok, transform_err =
        pcall(function()
            child_root:K2_SetRelativeLocation(
                pos,
                false,
                hit,
                true
            )

            child_root:K2_SetRelativeRotation(
                rot,
                false,
                hit,
                true
            )
        end)

    if not transform_ok then
        log('PCL15_16_11_REBIND_ERROR transform=' ..
            tostring(transform_err))
        return
    end

    log('PCL15_16_11_SOCKET' ..
        ' reason=' .. tostring(reason) ..
        ' BoneName=' .. tostring(socket_name) ..
        ' Flipped=' .. tostring(PCL151611_FLIPPED) ..
        ' child_source=' .. tostring(source) ..
        ' X=' .. tostring(pos.X) ..
        ' Y=' .. tostring(pos.Y) ..
        ' Z=' .. tostring(pos.Z) ..
        ' Pitch=' .. tostring(rot.Pitch) ..
        ' Yaw=' .. tostring(rot.Yaw) ..
        ' Roll=' .. tostring(rot.Roll))
end

function pcl151611_apply_and_rebind(reason)
    local ok, err =
        pcl15166_ensure_current_anchor(
            'socket_' .. tostring(reason)
        )

    if not ok then
        log('PCL15_16_11_TUNER_ERROR=' ..
            tostring(err))
        return
    end

    pcl151611_rebind_live_child(
        reason
    )
end

function pcl151611_cycle_socket()
    PCL151611_SOCKET_INDEX =
        PCL151611_SOCKET_INDEX + 1

    if PCL151611_SOCKET_INDEX >
       #PCL151611_SOCKET_NAMES then
        PCL151611_SOCKET_INDEX = 1
    end

    pcl151611_apply_and_rebind(
        'cycle_socket'
    )
end

function pcl151611_toggle_flip()
    PCL151611_FLIPPED =
        not PCL151611_FLIPPED

    pcl151611_apply_and_rebind(
        'toggle_flip'
    )
end

-- Cycle socket orientation.
RegisterKeyBind(
    Key.J,
    {
        ModifierKey.CONTROL,
        ModifierKey.ALT,
        ModifierKey.SHIFT
    },
    function()
        run_game_thread(
            pcl151611_cycle_socket
        )
    end
)

-- Toggle slot flip flag.
RegisterKeyBind(
    Key.F,
    {
        ModifierKey.CONTROL,
        ModifierKey.ALT,
        ModifierKey.SHIFT
    },
    function()
        run_game_thread(
            pcl151611_toggle_flip
        )
    end
)

log('Phase 15.16.11 HARDPOINT SOCKET ORIENTATION TUNER active.')
log('CTRL+ALT+SHIFT+J = cycle slot1 socket Right/Left/Top/Bottom/Default.')
log('CTRL+ALT+SHIFT+F = toggle slot1 bIsFlippedSlot.')
log('The slot stays native index 1 so carry semantics remain unchanged.')


-- ============================================================================
-- Phase 15.16.12 - ISOLATED SOCKET / FLIP CONTROLS
--
-- 15.16.11 used CTRL+ALT+SHIFT+F for flip, but UE4SS also fired the existing
-- CTRL+ALT+F Y-minus binding. The log showed the anchor remained
-- Right/Flipped=false while Y marched downward.
--
-- This phase adds completely separate base keys:
--   CTRL+ALT+F10 = cycle socket
--   CTRL+ALT+F11 = toggle bIsFlippedSlot
--   CTRL+ALT+F12 = print current tuner state
--
-- It also suppresses the 200-ms repeated SLOT_ROW spam unless the slot state
-- actually changes.
--
-- ZERO new top-level locals.
-- ============================================================================

PCL151612_LAST_SLOT_STATE = ""
PCL151612_STATE_FILE = "pcl_anchor_tuner_state.txt"

function pcl151612_write_state(reason)
    local socket_name =
        pcl151611_current_socket_name()

    local state =
        'reason=' .. tostring(reason) ..
        ' BoneName=' .. tostring(socket_name) ..
        ' Flipped=' .. tostring(PCL151611_FLIPPED) ..
        ' X=' .. tostring(PCL15167_SLOT1_OFFSET.X) ..
        ' Y=' .. tostring(PCL15167_SLOT1_OFFSET.Y) ..
        ' Z=' .. tostring(PCL15167_SLOT1_OFFSET.Z) ..
        ' Pitch=' .. tostring(PCL15169_ROTATION.Pitch) ..
        ' Yaw=' .. tostring(PCL15169_ROTATION.Yaw) ..
        ' Roll=' .. tostring(PCL15169_ROTATION.Roll)

    log('PCL15_16_12_STATE ' .. state)

    pcall(function()
        local path =
            pcl151112_script_dir() ..
            PCL151612_STATE_FILE

        local f =
            io.open(path, 'w')

        if f ~= nil then
            f:write(state)
            f:write('\n')
            f:close()
        end
    end)
end

function pcl151611_apply_slot_orientation_to_row(dst)
    if dst == nil or dst.row == nil then
        return false, 'anchor row missing'
    end

    local slot, slot_err =
        get_slot_struct_10(
            dst.row,
            1
        )

    if slot == nil then
        return false,
            'slot 1 resolve failed: ' ..
            tostring(slot_err)
    end

    local wanted_name =
        pcl151611_current_socket_name()

    local wanted_fname, fname_err =
        make_existing_fname_83(
            wanted_name
        )

    if wanted_fname == nil then
        return false,
            'FName failed for ' ..
            tostring(wanted_name) ..
            ': ' ..
            tostring(fname_err)
    end

    local wanted_flip =
        PCL151611_FLIPPED and true or false

    local wanted_x =
        tonumber(PCL15167_SLOT1_OFFSET.X) or 0

    local wanted_y =
        tonumber(PCL15167_SLOT1_OFFSET.Y) or 0

    local wanted_z =
        tonumber(PCL15167_SLOT1_OFFSET.Z) or 0

    local ok, err =
        pcall(function()
            slot.BoneName =
                wanted_fname

            slot.bIsFlippedSlot =
                wanted_flip

            slot.Offset.X = wanted_x
            slot.Offset.Y = wanted_y
            slot.Offset.Z = wanted_z
        end)

    if not ok then
        return false,
            'slot orientation write failed: ' ..
            tostring(err)
    end

    local state =
        tostring(wanted_name) .. '|' ..
        tostring(wanted_flip) .. '|' ..
        tostring(wanted_x) .. '|' ..
        tostring(wanted_y) .. '|' ..
        tostring(wanted_z)

    if state ~= PCL151612_LAST_SLOT_STATE then
        PCL151612_LAST_SLOT_STATE = state

        log('PCL15_16_12_SLOT_CHANGED' ..
            ' BoneName=' .. tostring(wanted_name) ..
            ' Flipped=' .. tostring(wanted_flip) ..
            ' X=' .. tostring(wanted_x) ..
            ' Y=' .. tostring(wanted_y) ..
            ' Z=' .. tostring(wanted_z))
    end

    return true, nil
end

function pcl151612_cycle_socket()
    PCL151611_SOCKET_INDEX =
        PCL151611_SOCKET_INDEX + 1

    if PCL151611_SOCKET_INDEX >
       #PCL151611_SOCKET_NAMES then
        PCL151611_SOCKET_INDEX = 1
    end

    pcl151611_apply_and_rebind(
        'isolated_cycle_socket'
    )

    pcl151612_write_state(
        'cycle_socket'
    )
end

function pcl151612_toggle_flip()
    PCL151611_FLIPPED =
        not PCL151611_FLIPPED

    pcl151611_apply_and_rebind(
        'isolated_toggle_flip'
    )

    pcl151612_write_state(
        'toggle_flip'
    )
end

function pcl151612_print_state()
    pcl151612_write_state(
        'manual_state'
    )
end

RegisterKeyBind(
    Key.F10,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(
            pcl151612_cycle_socket
        )
    end
)

RegisterKeyBind(
    Key.F11,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(
            pcl151612_toggle_flip
        )
    end
)

RegisterKeyBind(
    Key.F12,
    {ModifierKey.CONTROL, ModifierKey.ALT},
    function()
        run_game_thread(
            pcl151612_print_state
        )
    end
)

log('Phase 15.16.12 ISOLATED SOCKET CONTROLS active.')
log('CTRL+ALT+F10 = cycle socket Right/Left/Top/Bottom/Default.')
log('CTRL+ALT+F11 = toggle bIsFlippedSlot.')
log('CTRL+ALT+F12 = print/write current tuner state.')
log('Do NOT use the old SHIFT+F / SHIFT+J controls from 15.16.11.')


-- ============================================================================
-- Phase 15.17.0 - REAL BLUEPRINT + STATICMESH ANCHOR ASSETS
-- ============================================================================

-- Anchors carry their attached build by default; the menu can opt out.
PCL151741_CARRY_ALL=true
PCL151741_BATCH=nil

PCL15170_CUSTOM_MESH_PATH =
    '/Game/Swordmaking/SwordParts/Meshes/Misc/SM_Misc_Cube.SM_Misc_Cube'

PCL15170_CUSTOM_BP_PATH =
    '/Game/PCL/Anchor/BP_PCL_PreconstructionAnchor.BP_PCL_PreconstructionAnchor'

PCL15170_CUSTOM_BP_CLASS_PATH =
    '/Game/PCL/Anchor/BP_PCL_PreconstructionAnchor.BP_PCL_PreconstructionAnchor_C'

PCL15170_CUSTOM_MESH = nil
PCL15170_CUSTOM_BP_CLASS = nil
PCL15170_SET_BP_FN = nil
PCL15170_MISSING_LOGGED = false
PCL15170_MONITOR_STARTED = false
PCL15170_APPLIED_ACTORS = {}

-- Mod-only containers deliberately do not replace the game's AssetRegistry.bin.
-- LoadAsset queries that registry before loading and cannot discover these new
-- paths. Use the same explicit FAssetData route as BPModLoaderMod instead.
PCL15174_LOAD_MESSAGES = {}
PCL15175_TRACE_SEEN = {}
PCL15177_FORGE_ACTIVE = false
PCL15177_TRACE_CALLBACKS = false
function pcl15177_reset_forge_references()
    if type(pcl151762_cleanup_home)=='function' then pcall(pcl151762_cleanup_home) end
    if type(pcl151760_release_input)=='function' then pcl151760_release_input('forge_reset') end
    PCL151745_OPEN=nil
    PCL151724_PREVIEWS={}
    PCL151730_PREVIEW_CHECKED={}
    PCL151727_PREVIEW_QUEUE=nil
    PCL151756_WARM_OBJECTS=nil
    if PCL151710_MENU_STATE ~= nil then
        for _, name in ipairs({'panel','launcher','close','dismiss'}) do
            local widget = PCL151710_MENU_STATE[name]
            if is_valid(widget) then
                if name=='panel' then PCL151723_UI[widget:GetAddress()]=nil end
                pcall(function() widget:SetVisibility(1);widget:RemoveFromParent() end)
            end
        end
        PCL151710_MENU_STATE = nil
    end
    PCL15177_FORGE_ACTIVE = false
    PCL15170_CUSTOM_MESH = nil
    PCL15170_CUSTOM_BP_CLASS = nil
    PCL15171_UI_CLASS_OBJ = nil
    PCL15171_ENTRY_CLASS_OBJ = nil
    PCL15171_CREATIVE_SERVICE = nil
    PCL15171_CATALOGUES = {}
    PCL15171_ACTIONS = {}
    PCL15171_BOUND = {}
    PCL15171_LAST_CLICK = {}
    PCL15176_BUTTONS = {}
    PCL15170_APPLIED_ACTORS = {}
    PCL15175_TRACE_SEEN = {}
end
function pcl15177_live_forge()
    if type(pcl15171_find_catalogues) ~= 'function' then return false end
    local catalogues = pcl15171_find_catalogues()
    local active = #catalogues > 0
    if active ~= PCL15177_FORGE_ACTIVE then
        PCL15177_FORGE_ACTIVE = active
        log('PCL15_17_7_FORGE_LIFECYCLE active=' .. tostring(active))
    end
    return active
end
function pcl15175_trace(stage, object)
    local key = stage .. ':' .. tostring(pcl151112_addr(object))
    if PCL15175_TRACE_SEEN[key] then return end
    PCL15175_TRACE_SEEN[key] = true
    log('PCL15_17_5_UI_TRACE stage=' .. stage .. ' object=' .. safe_full_name(object))
end
function pcl15178_style_call(stage, fn)
    local ok, err = pcall(fn)
    if not ok then log('PCL15_17_8_STYLE_ERROR stage=' .. stage .. ' error=' .. tostring(err)) end
    return ok
end
function pcl15178_style_text(label, size)
    if not is_valid(label) then return end
    pcl15178_style_call('text_font', function()
        local font = label.Font
        font.Size = size
        label:SetFont(font)
    end)
    pcl15178_style_call('text_color', function()
        label:SetColorAndOpacity({
            SpecifiedColor = {R=0.76, G=0.69, B=0.46, A=1.0}, ColorUseRule=0
        })
        label:SetAutoWrapText(true)
    end)
end
-- Menu presentation uses the same section and text-button classes as Forge.
PCL151723_UI = {}
PCL151723_NATIVE_BUTTONS = {}

function pcl151723_references()
    local forge=find_forge()
    if not is_valid(forge) then return nil end
    for _,ui in pairs(FindAllOf('WBP_ForgeMode_C') or {}) do
        if is_valid(ui) and is_valid(ui.ForgeMode) and ui.ForgeMode:GetAddress()==forge:GetAddress() and
           is_valid(ui.LeaveForgeModeButton) and is_valid(ui.GameplayValuesSection) then return ui end
    end
end

function pcl151723_new(panel,class_name)
    local widget=StaticConstructObject(StaticFindObject('/Script/UMG.'..class_name),panel.WidgetTree)
    assert(is_valid(widget),'Menu widget unavailable: '..class_name)
    return widget
end

function pcl151723_label(panel,text,size,secondary)
    local label=pcl151723_new(panel,'TextBlock')
    label:SetText(pcl15171_to_text(text))
    local state=PCL151723_UI[panel:GetAddress()]
    local font=label.Font
    local native=state.reference.AbilityHistoryPlaceholderText.Font
    font.FontObject=native.FontObject
    font.TypefaceFontName=FName('Regular',EFindName.FNAME_Find)
    font.Size=size
    label:SetFont(font)
    label:SetAutoWrapText(true)
    label:SetColorAndOpacity({SpecifiedColor=secondary and {R=0.30,G=0.28,B=0.22,A=1} or {R=0.56,G=0.51,B=0.35,A=1},ColorUseRule=0})
    return label
end

function pcl151723_button(panel,caption,height)
    local state=PCL151723_UI[panel:GetAddress()]
    local reference=state.reference.LeaveForgeModeButton
    local button=pcl15171_create_widget(panel,reference:GetClass())
    assert(is_valid(button),'Native menu button unavailable')
    button:SetStyle(reference:GetStyle():GetClass())
    button:SetCaption(pcl15171_to_text(caption))
    button:SetToolTipText(pcl15171_to_text(''))
    button:SetMinDimensions(0,height or 56)
    PCL151723_NATIVE_BUTTONS[button:GetAddress()]=true
    pcl151722_native_click_hook()
    return button
end

function pcl151723_vadd(parent,widget,top,bottom)
    local slot=parent:AddChildToVerticalBox(widget)
    slot:SetPadding({Left=0,Top=top or 0,Right=0,Bottom=bottom or 0})
    slot:SetHorizontalAlignment(0)
    return slot
end

function pcl151723_hadd(parent,widget,fill,right)
    local slot=parent:AddChildToHorizontalBox(widget)
    slot:SetPadding({Left=0,Top=0,Right=right or 0,Bottom=0})
    slot:SetVerticalAlignment(2)
    if fill then slot:SetSize({Value=1,SizeRule=1}) end
    return slot
end

function pcl151723_resize(panel)
    local state=PCL151723_UI[panel:GetAddress()]
    if not state then return end
    local count=#PCL15171_LIBRARY
    local base=PCL151761_MODE=='blades' and 434 or 518
    local form_height=state.magic_open and (state.upload_held and 330 or 250) or 0
    local visible_rows=state.magic_open and 4 or 6
    local entries_height=math.max(1,math.min(count,visible_rows))*208
    -- Fill down to the native bottom-right control band, in DPI-scaled UI
    -- units. Extra form space comes from the list rather than moving the bottom.
    pcall(function()
        local layout=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
        if not is_valid(layout) then return end
        local viewport,scale=layout:GetViewportSize(panel),layout:GetViewportScale(panel)
        if scale>0 and viewport.Y>0 then
            local available=viewport.Y/scale-150-220
            entries_height=math.max(120,available-base-form_height)
        end
    end)
    state.entries_size:SetHeightOverride(entries_height)
    state.count:SetText(pcl15171_to_text(tostring(count)..(PCL151761_MODE=='blades' and (count==1 and ' saved blade' or ' saved blades') or (count==1 and ' saved build' or ' saved builds'))))
    state.empty:SetVisibility(count==0 and 0 or 1)
    local height=base+entries_height+form_height
    panel:SetDesiredSizeInViewport({X=800,Y=height})
    panel:SetPositionInViewport({X=-24,Y=150},false)
    panel:SetAnchorsInViewport({Minimum={X=1,Y=0},Maximum={X=1,Y=0}})
    panel:SetAlignmentInViewport({X=1,Y=0})
end

function pcl151723_build_panel(panel)
    local reference=pcl151723_references()
    if not is_valid(reference) then return false end
    -- Capture original named controls before introducing native UserWidgets,
    -- whose private widget trees are not traversed by the old panel lookup.
    local controls={}
    for _,name in ipairs({'PCL_Root','PCL_Background','PCL_MainColumn','PCL_HeaderText','PCL_HeaderHint',
        'PCL_FixedEntries','PCL_PlusButton','PCL_AnchorButton','PCL_LocalTools',
        'PCL_SaveLocalButton','PCL_ValidateLocalButton','PCL_LoadLocalButton','PCL_DynamicEntries',
        'PCL_MagicWordPanel','PCL_MagicWordColumn','PCL_MagicWordTitle','PCL_MagicWordLabel',
        'PCL_MagicWordInput','PCL_MagicWordButtons','PCL_SubmitButton','PCL_CancelButton','PCL_StatusText'}) do
        controls[name]=pcl15171_widget_by_name(panel,name)
    end
    local state={controls=controls,reference=reference,panel=panel,magic_open=false}
    PCL151723_UI[panel:GetAddress()]=state
    local root=controls.PCL_Root
    root:SetMinDesiredWidth(0);root:SetWidthOverride(800);root:SetMaxDesiredWidth(800)
    local frame=pcl15171_create_widget(panel,reference.GameplayValuesSection:GetClass())
    assert(is_valid(frame),'Native menu frame unavailable')
    frame.Headline=pcl15171_to_text('')
    frame:UpdateHeadline()
    frame.Border:SetPadding({Left=24,Top=20,Right=24,Bottom=22})
    local column=controls.PCL_MainColumn
    column:ClearChildren()
    local inset=pcl151723_new(panel,'Border')
    inset:SetBrushColor({R=0,G=0,B=0,A=0})
    inset:SetPadding({Left=24,Top=20,Right=24,Bottom=22})
    inset:SetContent(column)
    frame.Content:SetContent(inset)
    local backdrop=pcl151723_new(panel,'Border')
    backdrop:SetBrushColor({R=0.008,G=0.008,B=0.006,A=0.94})
    backdrop:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
    backdrop:SetContent(frame)
    root:SetContent(backdrop)
    state.frame=frame

    local header=pcl151723_new(panel,'HorizontalBox')
    local hint=pcl151723_label(panel,'PRECONSTRUCTION LIBRARY',28,false)
    pcl151723_hadd(header,hint,true,16)
    state.close=pcl151723_button(panel,'Close',40)
    pcl151723_hadd(header,state.close,false,0)
    pcl15171_bind_button(state.close,{kind='library_close',panel=panel})
    pcl151723_vadd(column,header,0,22)

    pcl151761_build_tabs(panel,column)
    controls.PCL_AnchorButton=pcl151723_button(panel,'Place anchor',72)
    pcl151723_vadd(column,controls.PCL_AnchorButton,0,12)
    local actions=pcl151723_new(panel,'HorizontalBox')
    controls.PCL_PlusButton=pcl151723_button(panel,'Import Magic Word',48)
    local recovery=pcl151723_button(panel,'Recover unsaved build',48)
    pcl15171_bind_button(recovery,{kind='recover_draft',panel=panel})
    pcl151723_hadd(actions,controls.PCL_PlusButton,true,12)
    pcl151723_hadd(actions,recovery,true,0)
    pcl151723_vadd(column,actions,0,24)
    state.recovery=recovery
    recovery:SetIsEnabled(false)
    local uploads=pcl151723_new(panel,'HorizontalBox')
    state.upload=pcl151723_button(panel,'Upload',48)
    state.carry=pcl151723_button(panel,'Pick up whole build: '..(PCL151741_CARRY_ALL and 'On' or 'Off'),48)
    pcl15171_bind_button(state.upload,{kind='batch_upload',panel=panel})
    pcl15171_bind_button(state.carry,{kind='carry_toggle',panel=panel})
    pcl151723_hadd(uploads,state.upload,true,12)
    pcl151723_hadd(uploads,state.carry,true,0)
    pcl151723_vadd(column,uploads,0,12)
    state.operation_message=pcl151723_label(panel,'',18,true)
    state.operation_message:SetVisibility(1)
    pcl151723_vadd(column,state.operation_message,0,12)

    local saved_header=pcl151723_new(panel,'HorizontalBox')
    state.saved_title=pcl151723_label(panel,'PARTS',18,true)
    pcl151723_hadd(saved_header,state.saved_title,true,12)
    state.count=pcl151723_label(panel,'',18,true)
    state.count:SetAutoWrapText(false)
    pcl151723_hadd(saved_header,state.count,false,0)
    pcl151723_vadd(column,saved_header,0,10)

    state.entries_size=pcl151723_new(panel,'SizeBox')
    local scroll=pcl151723_new(panel,'ScrollBox')
    state.entries_size:SetContent(scroll)
    local entries=pcl151723_new(panel,'VerticalBox')
    scroll:AddChild(entries)
    controls.PCL_DynamicEntries=entries
    state.empty=pcl151723_label(panel,'Import a Magic Word to add your first build.',20,true)
    pcl151723_vadd(column,state.empty,0,8)
    pcl151723_vadd(column,state.entries_size,0,0)

    local magic=controls.PCL_MagicWordPanel
    magic:SetPadding({Left=16,Top=14,Right=16,Bottom=14})
    magic:SetBrushColor({R=0.012,G=0.012,B=0.009,A=0.96})
    local magic_column=controls.PCL_MagicWordColumn
    magic_column:ClearChildren()
    controls.PCL_MagicWordTitle=pcl151723_label(panel,'Import preconstruction',24,false)
    pcl151723_vadd(magic_column,controls.PCL_MagicWordTitle,0,10)
    local input=pcl151723_new(panel,'EditableText')
    controls.PCL_MagicWordInput=input
    local input_font=controls.PCL_MagicWordTitle.Font
    input_font.Size=24
    input:SetFont(input_font)
    input:SetRenderOpacity(0.78)
    input:SetHintText(pcl15171_to_text('Enter Magic Word'))
    local input_border=pcl151723_new(panel,'Border')
    input_border:SetBrushColor({R=0.035,G=0.035,B=0.028,A=1})
    input_border:SetPadding({Left=12,Top=12,Right=12,Bottom=12})
    input_border:SetContent(input)
    pcl151723_vadd(magic_column,input_border,0,12)
    local author=pcl151723_new(panel,'EditableText')
    controls.PCL_AuthorInput=author
    author:SetFont(input_font)
    author:SetRenderOpacity(0.78)
    author:SetHintText(pcl15171_to_text('Your name'))
    local author_border=pcl151723_new(panel,'Border')
    controls.PCL_AuthorBorder=author_border
    author_border:SetBrushColor({R=0.035,G=0.035,B=0.028,A=1})
    author_border:SetPadding({Left=12,Top=12,Right=12,Bottom=12})
    author_border:SetContent(author)
    author_border:SetVisibility(1)
    pcl151723_vadd(magic_column,author_border,0,12)
    local magic_buttons=pcl151723_new(panel,'HorizontalBox')
    controls.PCL_SubmitButton=pcl151723_button(panel,'Add to library',48)
    controls.PCL_CancelButton=pcl151723_button(panel,'Cancel',48)
    pcl151723_hadd(magic_buttons,controls.PCL_SubmitButton,true,10)
    pcl151723_hadd(magic_buttons,controls.PCL_CancelButton,true,0)
    pcl151723_vadd(magic_column,magic_buttons,0,0)
    pcl151723_vadd(column,magic,18,0)
    magic:SetVisibility(1)
    controls.PCL_StatusText=pcl151723_label(panel,'',20,true)
    controls.PCL_StatusText:SetVisibility(1) -- no footer/status text
    pcl151723_resize(panel)
    log('PCL15_17_23_NATIVE_MENU frame='..safe_full_name(frame:GetClass())..' button_style='..safe_full_name(reference.LeaveForgeModeButton:GetStyle()))
    return true
end

function pcl15178_style_panel(panel)
    local ok,result=pcall(pcl151723_build_panel,panel)
    if not ok then log('PCL15_17_23_MENU_BUILD_ERROR '..tostring(result)) end
    return ok and result==true
end

PCL15176_BUTTONS = {}
PCL15176_INPUT_STARTED = false
function pcl15176_input_tick()
    run_game_thread(function()
        if not PCL15177_FORGE_ACTIVE then
            pcl15179_schedule(50, pcl15176_input_tick)
            return
        end
        local released = {}
        for address, state in pairs(PCL15176_BUTTONS) do
            local action = PCL15171_ACTIONS[address]
            local menu = PCL151710_MENU_STATE
            local relevant = menu == nil or menu.open or
                (action ~= nil and action.kind == 'library_toggle')
            if not relevant then
                state.pressed = false
                state.keyboard = false
            elseif not is_valid(state.button) or not is_valid(state.panel) then
                PCL15176_BUTTONS[address] = nil
                PCL15171_ACTIONS[address] = nil
                PCL15171_BOUND[address] = nil
            else
                local ok, pressed, hovered, focused = pcall(function()
                    return state.button:IsPressed(), state.button:IsHovered(),
                        state.button:HasKeyboardFocus()
                end)
                if ok then
                    if is_valid(state.icon) then
                        local tint = pressed and 0.65 or (hovered and 1 or 0.85)
                        if state.icon_tint ~= tint then
                            state.icon:SetColorAndOpacity({R=tint,G=tint,B=tint,A=1})
                            state.icon_tint = tint
                        end
                    end
                    if pressed and not state.pressed then
                        state.keyboard = not hovered and focused
                    elseif not pressed and state.pressed then
                        if hovered or (state.keyboard and focused) then
                            table.insert(released, state.button)
                        end
                        state.keyboard = false
                    end
                    state.pressed = pressed
                end
            end
        end
        for _, button in ipairs(released) do
            log('PCL15_17_6_BUTTON_RELEASE button=' .. safe_full_name(button))
            pcl15171_dispatch(button)
            -- A native import/action can replace objects synchronously.
            PCL151715_VALIDATION_CACHE = {}
        end
        pcl15179_schedule(33, pcl15176_input_tick)
    end)
end
function pcl15176_start_input_monitor()
    if PCL15176_INPUT_STARTED then return end
    PCL15176_INPUT_STARTED = true
    pcl15179_schedule(16, pcl15176_input_tick)
    log('PCL15_17_6_BUTTON_INPUT_STARTED delegate_binding=false')
end
function pcl15174_load_object(path)
    local found = nil
    pcall(function() found = StaticFindObject(path) end)
    if is_valid(found) then return found end
    local package_name, asset_name = string.match(path, '^(.-)%.([^%.]+)$')
    if package_name == nil then return nil end
    local ok, result = pcall(function()
        local helpers = require('UEHelpers')
        local registry = StaticFindObject('/Script/AssetRegistry.Default__AssetRegistryHelpers')
        if not is_valid(registry) then error('AssetRegistryHelpers unavailable') end
        return registry:GetAsset({
            PackageName = helpers.FindOrAddFName(package_name),
            AssetName = helpers.FindOrAddFName(asset_name)
        })
    end)
    local message = ok and is_valid(result) and 'loaded' or
        (ok and 'returned invalid object' or tostring(result))
    if PCL15174_LOAD_MESSAGES[path] ~= message then
        PCL15174_LOAD_MESSAGES[path] = message
        log('PCL15_17_4_DIRECT_ASSET path=' .. path .. ' result=' .. message)
    end
    if ok and is_valid(result) then return result end
    return nil
end

function pcl15170_load_assets()
    if not PCL151756_PRELOAD_ACTIVE and not pcl15177_live_forge() then return false end
    PCL15170_CUSTOM_MESH = pcl15174_load_object(PCL15170_CUSTOM_MESH_PATH)
    PCL15170_CUSTOM_BP_CLASS = pcl15174_load_object(PCL15170_CUSTOM_BP_CLASS_PATH)
    if not is_valid(PCL15170_CUSTOM_MESH) then
        pcall(function()
            PCL15170_CUSTOM_MESH =
                LoadAsset(PCL15170_CUSTOM_MESH_PATH)
        end)
    end

    if not is_valid(PCL15170_CUSTOM_BP_CLASS) then
        pcall(function()
            LoadAsset(PCL15170_CUSTOM_BP_PATH)
        end)

        pcall(function()
            PCL15170_CUSTOM_BP_CLASS =
                StaticFindObject(PCL15170_CUSTOM_BP_CLASS_PATH)
        end)

        if not is_valid(PCL15170_CUSTOM_BP_CLASS) then
            pcall(function()
                PCL15170_CUSTOM_BP_CLASS =
                    LoadAsset(PCL15170_CUSTOM_BP_CLASS_PATH)
            end)
        end
    end

    if is_valid(PCL15170_CUSTOM_MESH) and
       is_valid(PCL15170_CUSTOM_BP_CLASS) then

        if PCL15170_MISSING_LOGGED then
            PCL15170_MISSING_LOGGED = false
        end
        return true
    end

    if not PCL15170_MISSING_LOGGED then
        PCL15170_MISSING_LOGGED = true
        log('PCL15_17_0_ASSETS_NOT_MOUNTED mesh=' ..
            tostring(is_valid(PCL15170_CUSTOM_MESH)) ..
            ' bp_class=' ..
            tostring(is_valid(PCL15170_CUSTOM_BP_CLASS)))
    end

    return false
end

function pcl15170_get_set_bp_fn()
    if type(PCL15170_SET_BP_FN) == 'function' then
        return PCL15170_SET_BP_FN, nil
    end

    local path =
        pcl151112_script_dir() ..
        'pcl_anchor_socket_151741.dll'

    local fn, err, where =
        BMF_PCL_NATIVE(
            path,
            'pcl_anchor_set_socket_row'
        )

    if type(fn) ~= 'function' then
        return nil,
            'set-blueprint export load failed: ' ..
            tostring(err) ..
            ' where=' .. tostring(where)
    end

    PCL15170_SET_BP_FN = fn
    return fn, nil
end

function pcl15170_existing_fname(name)
    local value = nil
    pcall(function()
        value =
            FName(
                name,
                EFindName.FNAME_Find
            )
    end)
    return value
end

function pcl15170_apply_asset_row()
    if not pcl15170_load_assets() then
        return false, 'assets not mounted'
    end

    local dst, dst_err =
        pcl15165_exact_row(
            PCL15165_DEV_TABLE_FULL,
            PCL15161_ROW_NAME
        )

    if dst == nil or dst.row == nil then
        return false, tostring(dst_err)
    end

    -- Match the actual shipped Cube contract: primary at Y=0, Default output
    -- at Y=-1. Leave the shared stock mesh and all of its sockets untouched.
    local attach = pcl15170_existing_fname('Default')
    if attach == nil then return false,'Stock Cube Default socket name unavailable' end
    local primary=PCL151741_CARRY_ALL and 0 or 1
    local name_index=attach:GetComparisonIndex()
    if name_index<=0 then return false,'Stock Cube Default name not loaded' end
    local socket=PCL15170_CUSTOM_MESH:FindSocket(attach)
    if not is_valid(socket) then return false,'Stock Cube Default socket unavailable' end
    local location,rotation=socket.RelativeLocation,socket.RelativeRotation
    if math.abs(location.X)>0.0001 or math.abs(location.Y+1)>0.0001 or math.abs(location.Z)>0.0001 or
       math.abs(rotation.Pitch)>0.0001 or math.abs(rotation.Yaw)>0.0001 or math.abs(rotation.Roll)>0.0001 then
        return false,'Stock Cube opposite-face transform differs from extracted asset'
    end

    local fn, fn_err =
        pcl15170_get_set_bp_fn()

    if type(fn) ~= 'function' then
        return false, fn_err
    end

    local row_addr, row_addr_err =
        pcl15161_struct_address(dst.row)

    if row_addr <= 0 then
        return false, tostring(row_addr_err)
    end

    local class_addr =
        pcl151112_addr(
            PCL15170_CUSTOM_BP_CLASS
        )

    if class_addr <= 0 then
        return false, 'BlueprintGeneratedClass address unavailable'
    end

    local call_ok, status =
        pcall(
            fn,
            row_addr,
            class_addr,
            name_index,
            primary
        )

    if not call_ok or tonumber(status) ~= 1 then
        return false,
            'native Blueprint pointer set failed status=' ..
            tostring(status)
    end

    if PCL151718_VERIFY_FN == nil then
        local verify, err = BMF_PCL_NATIVE(pcl151112_script_dir() ..
            'pcl_anchor_socket_151741.dll','pcl_anchor_check_socket_row')
        if type(verify) ~= 'function' then return false, 'Native socket verifier: ' .. tostring(err) end
        PCL151718_VERIFY_FN = verify
    end
    local checked, result = pcall(PCL151718_VERIFY_FN,row_addr,class_addr,name_index,primary)
    if not checked or result ~= 1 then return false, 'Native socket row readback: ' .. tostring(result) end
    if PCL151718_VERIFIED_ROW ~= row_addr then
        PCL151718_VERIFIED_ROW = row_addr
        log('PCL_ANCHOR_SOCKET_LOC x=' .. tostring(location.X) .. ' y=' .. tostring(location.Y) ..
            ' z=' .. tostring(location.Z) .. ' yaw=' .. tostring(rotation.Yaw) .. ' slot_offset=0,0,0 native_cube=true')
        log('PCL_ANCHOR_SOCKET_OK name=Default count=1 native_row_verified=true primary='..tostring(primary==1)..' native_cube=true')
    end

    PCL15167_SLOT1_OFFSET.X = 0
    PCL15167_SLOT1_OFFSET.Y = 0
    PCL15167_SLOT1_OFFSET.Z = 0

    PCL15169_ROTATION.Pitch = 0
    PCL15169_ROTATION.Yaw = 0
    PCL15169_ROTATION.Roll = 0

    return true, nil
end

PCL151739_ANCHOR_COLORS={}
function pcl151739_apply_color(actor,root)
    assert(pcl15167_is_exact_anchor_actor(actor),'Refused non-anchor material change')
    if not is_valid(root) then return false,'anchor mesh is not ready' end
    local address=actor:GetAddress()
    local entry=PCL151739_ANCHOR_COLORS[address]
    if not entry or not is_valid(entry.actor) or not is_valid(entry.root) or not is_valid(entry.mid) or entry.root:GetAddress()~=root:GetAddress() then
        local base=pcl15174_load_object('/Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial')
        assert(is_valid(base),'Shipped emissive material unavailable')
        local mid=root:CreateDynamicMaterialInstance(0,base,FName('None',EFindName.FNAME_Find))
        assert(is_valid(mid),'Anchor color instance unavailable')
        local parameter=pcl15170_existing_fname('Color')
        assert(parameter,'Shipped material Color parameter unavailable')
        mid:SetVectorParameterValue(parameter,{R=0.005,G=0.8,B=1,A=1})
        local value=mid:K2_GetVectorParameterValue(parameter)
        assert(math.abs(value.G-0.8)<0.001 and math.abs(value.B-1)<0.001,'Anchor cyan parameter readback failed')
        entry={actor=actor,root=root,mid=mid};PCL151739_ANCHOR_COLORS[address]=entry
        log('PCL15_17_39_ANCHOR_COLOR material=EmissiveMeshMaterial parameter=Color cyan=true')
    end
    local current=root:GetMaterial(0)
    if not is_valid(current) or current:GetAddress()~=entry.mid:GetAddress() then root:SetMaterial(0,entry.mid) end
    local marked,mark_err=pcall(pcl151747_apply_camera_mark,actor,root)
    if not marked and not entry.mark_error then entry.mark_error=true;log('PCL15_17_47_CAMERA_MARK_FAILED '..tostring(mark_err)) end
    return true
end

function pcl15170_apply_mesh_to_actor(actor)
    if not is_valid(actor) or
       not pcl15167_is_exact_anchor_actor(actor) then
        return false, 'not exact anchor'
    end

    if not pcl15170_load_assets() then
        return false, 'assets not mounted'
    end

    local root = nil
    pcall(function()
        root =
            actor:K2_GetRootComponent()
    end)

    if not is_valid(root) then
        return false, 'root unavailable'
    end

    local ok, err =
        pcall(function()
            root:SetStaticMesh(
                PCL15170_CUSTOM_MESH
            )
            pcl151739_apply_color(actor,root)
            actor:SetActorHiddenInGame(false)
            actor:SetActorEnableCollision(true)
        end)

    if not ok then
        return false, tostring(err)
    end

    local addr = pcl151112_addr(actor)
    if PCL15170_APPLIED_ACTORS[addr] ~= true then
        local socket_transform = root:GetSocketTransform(pcl15170_existing_fname('Default'),2)
        local point = socket_transform.Translation
        if math.abs(point.X)>0.0001 or math.abs(point.Y+1.0)>0.0001 or math.abs(point.Z)>0.0001 then
            return false, 'Actor component socket does not match cooked face centre'
        end
        PCL15170_APPLIED_ACTORS[addr] = true
        log('PCL_ANCHOR_ACTOR_SOCKET_OK x=' .. tostring(point.X) .. ' y=' ..
            tostring(point.Y) .. ' z=' .. tostring(point.Z))
        pcl15179_schedule(300,function() pcl151721_marker_snapshot(actor,1) end)
        log('PCL15_17_0_ACTOR_ASSET_APPLIED addr=' ..
            tostring(addr) ..
            ' class=' .. safe_full_name(actor:GetClass()))
    end

    return true, nil
end

PCL15170_PREVIOUS_ENSURE =
    pcl15166_ensure_current_anchor

function pcl15166_ensure_current_anchor(reason)
    if not PCL151756_PRELOAD_ACTIVE and not pcl15177_live_forge() then return false,'waiting for Forge or pre-load hook' end
    -- Final production schema: one outgoing connector, actor-origin placement.
    -- Do not run the historical slot-1 corner/rotation experiments here.
    local dst, raw = pcl15166_current_exact_anchor()
    if raw == nil or raw.status ~= 2 or raw.typ ~= 2 or
       raw.primary ~= (PCL151741_CARRY_ALL and 0 or 1) or raw.slots ~= 1 then
        local ok, err = pcl15161_patch_catalogue_item()
        if not ok then return false, err end
    end
    return pcl15170_apply_asset_row()
end

PCL15170_PREVIOUS_ATTACH =
    pcl15165_attach_anchor_child

function pcl15165_attach_anchor_child(parent, slot_native, child)
    if is_valid(parent) and
       pcl15167_is_exact_anchor_actor(parent) and
       pcl15170_load_assets() then

        local row_ok, row_err =
            pcl15170_apply_asset_row()

        if not row_ok then
            return false, row_err
        end

        local mesh_ok, mesh_err =
            pcl15170_apply_mesh_to_actor(parent)

        if not mesh_ok then
            return false, mesh_err
        end
    end

    return
        PCL15170_PREVIOUS_ATTACH(
            parent,
            slot_native,
            child
        )
end

function pcl15170_monitor_tick()
    run_game_thread(function()
        for address,entry in pairs(PCL151747_CAMERA_MARKS) do
            if not is_valid(entry.actor) then PCL151747_CAMERA_MARKS[address]=nil end
        end
        for address,entry in pairs(PCL151739_ANCHOR_COLORS) do
            if not is_valid(entry.actor) or not is_valid(entry.root) then
                PCL151739_ANCHOR_COLORS[address]=nil
            end
        end
        if pcl15170_load_assets() then
            pcl15175_trace('anchor_row_begin', nil)
            pcl15170_apply_asset_row()
            pcl15175_trace('anchor_row_done', nil)

            -- New anchor actors use this dedicated class. Do not enumerate
            -- six base actor classes and inspect every imported sword part.
            local actors = FindAllOf('BP_PCL_PreconstructionAnchor_C') or {}

            for _, actor in ipairs(actors) do
                if pcl15167_is_exact_anchor_actor(actor) then
                    if not PCL15170_APPLIED_ACTORS[pcl151112_addr(actor)] then
                        pcl15170_apply_mesh_to_actor(actor)
                    else
                        -- Stock material resets can occur after selection or
                        -- placement. Restore only this anchor's owned MID.
                        local ok,root=pcall(function()return actor:K2_GetRootComponent()end)
                        if ok and is_valid(root) then
                            pcall(pcl151739_apply_color,actor,root)
                        else
                            PCL15170_APPLIED_ACTORS[pcl151112_addr(actor)]=nil
                        end
                    end
                end
            end
        end
    end)

    pcl15179_schedule(
        1000,
        pcl15170_monitor_tick
    )
end

function pcl15170_start_monitor()
    if PCL15170_MONITOR_STARTED then
        return
    end

    PCL15170_MONITOR_STARTED = true

    pcl15179_schedule(
        100,
        pcl15170_monitor_tick
    )

    log('PCL15_17_0_ASSET_MONITOR_STARTED interval_ms=1000')
end

-- Old Cube socket tuners are intentionally disabled when the real assets load.
function pcl151612_cycle_socket()
    if pcl15170_load_assets() then
        log('PCL15_17_0_SOCKET_TUNER_DISABLED stock Default socket active')
        return
    end
end

function pcl151612_toggle_flip()
    if pcl15170_load_assets() then
        log('PCL15_17_0_FLIP_TUNER_DISABLED stock Default socket active')
        return
    end
end

pcl15170_start_monitor()

log('Phase 15.17.0 REAL BLUEPRINT/STATICMESH ANCHOR active.')
log('Blueprint=/Game/PCL/Anchor/BP_PCL_PreconstructionAnchor')
log('Mesh=' .. PCL15170_CUSTOM_MESH_PATH)
log('Sockets=implicit_primary,Default')


-- ============================================================================
-- Phase 15.17.1 - FORGE PRECONSTRUCTION LIBRARY UI
--
-- Adds a first-class "Preconstruction Library" area to the live Forge sword
-- part catalogue. Fixed entries are:
--   1) +
--   2) Preconstruction Anchor
--
-- + opens an inline Magic Word editor. Submitted Magic Words are persisted to:
--   Scripts/preconstructions/library.index
-- and materialized as reusable library-entry buttons.
--
-- UI assets are supplied by the cooked UE4SS Blueprint mod:
--   /Game/PCL/UI/WBP_PCL_PreconstructionLibrary
--   /Game/PCL/UI/WBP_PCL_LibraryEntry
--
-- No new top-level locals: the historical main chunk is already close to the
-- Lua 200-local limit.
-- ============================================================================

PCL15171_UI_BP =
    '/Game/PCL/UI/WBP_PCL_PreconstructionLibrary.WBP_PCL_PreconstructionLibrary'

PCL15171_UI_CLASS =
    '/Game/PCL/UI/WBP_PCL_PreconstructionLibrary.WBP_PCL_PreconstructionLibrary_C'

PCL15171_ENTRY_BP =
    '/Game/PCL/UI/WBP_PCL_LibraryEntry.WBP_PCL_LibraryEntry'

PCL15171_ENTRY_CLASS =
    '/Game/PCL/UI/WBP_PCL_LibraryEntry.WBP_PCL_LibraryEntry_C'

PCL15171_CREATIVE_BP =
    '/Game/UI/CreativeMode/WBP_CreativeModeHome.WBP_CreativeModeHome'

PCL15171_CREATIVE_CLASS =
    '/Game/UI/CreativeMode/WBP_CreativeModeHome.WBP_CreativeModeHome_C'

PCL15171_UI_CLASS_OBJ = nil
PCL15171_ENTRY_CLASS_OBJ = nil
PCL15171_CREATIVE_CLASS_OBJ = nil
PCL15171_WIDGET_LIB = nil
PCL15171_TEXT_LIB = nil
PCL15171_CREATIVE_SERVICE = nil

PCL15171_CATALOGUES = {}
PCL15171_ACTIONS = {}
PCL15171_BOUND = {}
PCL15171_LAST_CLICK = {}
PCL15171_LIBRARY = {}
PCL15171_MONITOR_STARTED = false
PCL15171_FOCUS_HOOKED = false
PCL15171_FOCUS_PRE = nil
PCL15171_FOCUS_POST = nil
PCL15171_ASSET_WAIT_LOGGED = false

PCL15171_LIBRARY_DIR =
    pcl151112_script_dir() .. 'preconstructions\\'

PCL15171_LIBRARY_PATH =
    PCL15171_LIBRARY_DIR .. 'library.index'

function pcl15171_unwrap(value)
    if value == nil then
        return nil
    end

    local out = value

    pcall(function()
        if type(value.get) == 'function' then
            out = value:get()
        end
    end)

    return out
end

function pcl15171_text_lib()
    if is_valid(PCL15171_TEXT_LIB) then
        return PCL15171_TEXT_LIB
    end

    pcall(function()
        PCL15171_TEXT_LIB =
            StaticFindObject(
                '/Script/Engine.Default__KismetTextLibrary'
            )
    end)

    return PCL15171_TEXT_LIB
end

function pcl15171_to_text(value)
    local lib =
        pcl15171_text_lib()

    if not is_valid(lib) then
        return nil
    end

    local txt = nil
    pcall(function()
        txt =
            lib:Conv_StringToText(
                tostring(value or '')
            )
    end)

    return txt
end

function pcl15171_from_text(value)
    if type(value) == 'string' then return value end
    if value == nil then return '', 'Text value is unavailable.' end
    local direct_ok, direct = pcall(function() return value:ToString() end)
    if direct_ok and type(direct) == 'string' then return direct end
    local lib =
        pcl15171_text_lib()

    if not is_valid(lib) then
        return '', 'Text conversion service is unavailable.'
    end

    local out = ''
    pcall(function()
        out =
            lib:Conv_TextToString(
                value
            )
    end)

    if type(out) == 'string' then return out end
    local ok, text = pcall(function() return out:ToString() end)
    if ok and type(text) == 'string' then return text end
    return '', 'Could not read the Magic Word text.'
end

function pcl15171_trim(value)
    value = tostring(value or '')
    value = value:gsub('[\r\n]', '')
    value = value:gsub('^%s+', '')
    value = value:gsub('%s+$', '')
    return value
end

function pcl15171_ensure_library_dir()
    if PCL151758_LIBRARY_DIR_READY==PCL15171_LIBRARY_DIR then return end
    -- Existing installations need no shell command. Recovery checks run each
    -- time the library opens, so mkdir must never block that input path.
    local existing=io.open(PCL15171_LIBRARY_PATH,'rb')
    if existing then existing:close();PCL151758_LIBRARY_DIR_READY=PCL15171_LIBRARY_DIR;return end
    local ok,created=pcall(os.execute,'mkdir "'..tostring(PCL15171_LIBRARY_DIR)..'" >nul 2>nul')
    if ok and (created==true or created==0) then PCL151758_LIBRARY_DIR_READY=PCL15171_LIBRARY_DIR end
end

function pcl15171_load_library()
    PCL15171_LIBRARY = {}

    local f = nil
    pcall(function()
        f =
            io.open(
                PCL15171_LIBRARY_PATH,
                'r'
            )
    end)

    if f == nil then
        return
    end

    for line in f:lines() do
        local code =
            pcl15171_trim(line)

        code = code:gsub('^\239\187\191', '')
        if code ~= '' and
           code:sub(1, 1) ~= '#' and
           code:sub(1, 1) ~= ';' and
           not code:match('^PCL_LIBRARY_INDEX_V%d+$') and
           not code:match('^FString:%s*%x+$') then
            local exists = false

            for _, existing in ipairs(PCL15171_LIBRARY) do
                if existing == code then
                    exists = true
                    break
                end
            end

            if not exists then
                table.insert(
                    PCL15171_LIBRARY,
                    code
                )
            end
        end
    end

    f:close()
end

function pcl15171_save_library()
    pcl15171_ensure_library_dir()

    local f = nil
    local ok, err =
        pcall(function()
            f =
                io.open(
                    PCL15171_LIBRARY_PATH,
                    'w'
                )
        end)

    if not ok or f == nil then
        return false,
            'library.index open failed: ' ..
            tostring(err)
    end

    f:write('# PCL Preconstruction Library v1\n')

    for _, code in ipairs(PCL15171_LIBRARY) do
        f:write(tostring(code))
        f:write('\n')
    end

    f:close()
    return true, nil
end

function pcl15171_add_code(code)
    code =
        pcl15171_trim(code)

    if code == '' then
        return false, 'Magic Word is empty'
    end
    if code:match('^FString:%s*%x+$') or code:match('^PCL_LIBRARY_INDEX_V%d+$') then
        return false, 'Enter the actual Magic Word.'
    end

    for _, existing in ipairs(PCL15171_LIBRARY) do
        if existing == code then
            return true, 'already_saved'
        end
    end

    table.insert(
        PCL15171_LIBRARY,
        code
    )

    return
        pcl15171_save_library()
end

function pcl15171_load_widget_assets(creative_context)
    if not is_valid(creative_context) and not pcl15177_live_forge() then return false end
    PCL15171_UI_CLASS_OBJ = pcl15174_load_object(PCL15171_UI_CLASS)
    PCL15171_ENTRY_CLASS_OBJ = pcl15174_load_object(PCL15171_ENTRY_CLASS)
    if is_valid(PCL15171_UI_CLASS_OBJ) and
       is_valid(PCL15171_ENTRY_CLASS_OBJ) then
        return true
    end

    pcall(function()
        LoadAsset(PCL15171_UI_BP)
    end)

    pcall(function()
        LoadAsset(PCL15171_ENTRY_BP)
    end)

    pcall(function()
        PCL15171_UI_CLASS_OBJ =
            StaticFindObject(
                PCL15171_UI_CLASS
            )
    end)

    pcall(function()
        PCL15171_ENTRY_CLASS_OBJ =
            StaticFindObject(
                PCL15171_ENTRY_CLASS
            )
    end)

    if is_valid(PCL15171_UI_CLASS_OBJ) and
       is_valid(PCL15171_ENTRY_CLASS_OBJ) then

        if PCL15171_ASSET_WAIT_LOGGED then
            PCL15171_ASSET_WAIT_LOGGED = false
        end

        log('PCL15_17_1_UI_ASSET_LOADED')
        return true
    end

    if not PCL15171_ASSET_WAIT_LOGGED then
        PCL15171_ASSET_WAIT_LOGGED = true
        log('PCL15_17_1_UI_ASSET_WAIT' ..
            ' panel=' ..
            tostring(is_valid(PCL15171_UI_CLASS_OBJ)) ..
            ' entry=' ..
            tostring(is_valid(PCL15171_ENTRY_CLASS_OBJ)))
    end

    return false
end

function pcl15171_widget_library()
    if is_valid(PCL15171_WIDGET_LIB) then
        return PCL15171_WIDGET_LIB
    end

    pcall(function()
        PCL15171_WIDGET_LIB =
            StaticFindObject(
                '/Script/UMG.Default__WidgetBlueprintLibrary'
            )
    end)

    return PCL15171_WIDGET_LIB
end

function pcl15171_widget_by_name(owner, wanted)
    if is_valid(owner) and PCL151723_UI then
        local state=PCL151723_UI[owner:GetAddress()]
        if state and state.controls[wanted] then return state.controls[wanted] end
    end
    if not is_valid(owner) then
        return nil
    end

    pcl15175_trace('lookup_' .. wanted .. '_begin', owner)
    -- These generated widgets are named tree nodes, not reflected fields on
    -- the UserWidget. Do not probe arbitrary field names through UE4SS.
    local root = nil
    pcall(function()
        if is_valid(owner.WidgetTree) then
            root =
                owner.WidgetTree.RootWidget
        end
    end)

    if not is_valid(root) then
        return nil
    end

    local result = pcl15171_find_widget_recursive(
            root,
            wanted
        )
    pcl15175_trace('lookup_' .. wanted .. (is_valid(result) and '_found' or '_missing'), owner)
    return result
end

function pcl15171_find_widget_recursive(widget, wanted, seen, depth)
    if not is_valid(widget) then
        return nil
    end
    seen = seen or {}
    depth = depth or 0
    if depth > 32 then return nil end
    local address = pcl151112_addr(widget)
    if address <= 0 or seen[address] then return nil end
    seen[address] = true
    local name = nil
    pcall(function() name = widget:GetFName():ToString() end)
    if name == tostring(wanted) then
        return widget
    end
    -- Leaf widgets do not expose PanelWidget child functions. Check the native
    -- type before asking UE4SS to resolve or invoke either function.
    local panel_class = nil
    local panel_widget = false
    pcall(function()
        panel_class = StaticFindObject('/Script/UMG.PanelWidget')
        if is_valid(panel_class) then panel_widget = widget:IsA(panel_class) end
    end)
    if not panel_widget then return nil end
    local count = 0
    pcall(function()
        count =
            tonumber(
                widget:GetChildrenCount()
            ) or 0
    end)

    if count <= 0 then
        return nil
    end
    if count > 1024 then return nil end

    for i = 0, count - 1 do
        local child = nil

        pcall(function()
            child =
                widget:GetChildAt(i)
        end)

        local found =
            pcl15171_find_widget_recursive(
                child,
                wanted,
                seen,
                depth + 1
            )

        if is_valid(found) then
            return found
        end
    end

    return nil
end

function pcl15171_create_widget(context, class_obj)
    if not is_valid(context) or
       not is_valid(class_obj) then
        return nil
    end

    local lib =
        pcl15171_widget_library()

    if not is_valid(lib) then
        return nil
    end

    local owner = nil
    pcall(function()
        owner =
            context:GetOwningPlayer()
    end)

    local widget = nil
    pcall(function()
        widget =
            lib:Create(
                context,
                class_obj,
                owner
            )
    end)

    return widget
end

function pcl15171_set_status(panel,message)
    -- Keep diagnostics out of the menu footer, including long native paths.
    log('PCL_STATUS '..tostring(message))
end

function pcl15171_set_magic_visible(panel, visible)
    local box=pcl15171_widget_by_name(panel,'PCL_MagicWordPanel')
    if is_valid(box) then box:SetVisibility(visible and 0 or 1) end
    local state=PCL151723_UI[panel:GetAddress()]
    if state then state.magic_open=visible;pcl151723_resize(panel) end
end


function pcl15171_bind_button(button, action)
    if not is_valid(button) then return false end
    local addr=pcl151112_addr(button)
    if addr<=0 then return false end
    local native=PCL151723_NATIVE_BUTTONS and PCL151723_NATIVE_BUTTONS[addr]
    if native then action.native_menu=true end
    PCL15171_ACTIONS[addr]=action
    if PCL15171_BOUND[addr] then return true end
    if not native then
        PCL15176_BUTTONS[addr]={button=button,panel=action.panel,pressed=false,keyboard=false}
        pcl15176_start_input_monitor()
    end
    PCL15171_BOUND[addr]=true
    return true
end


PCL151724_META = {}
PCL151724_PREVIEWS = {}

function pcl151724_encode(value)
    return tostring(value or ''):gsub('([^%w %-%_%.])',function(c) return string.format('%%%02X',string.byte(c)) end)
end
function pcl151724_decode(value)
    return tostring(value or ''):gsub('%%(%x%x)',function(c) return string.char(tonumber(c,16)) end)
end
function pcl151724_load_metadata()
    PCL151724_META={}
    local file=io.open(PCL15171_LIBRARY_DIR..'names.index','r')
    if not file then return end
    for line in file:lines() do
        local code,custom,original=line:match('^([^\t]+)\t([^\t]*)\t([^\t]*)$')
        if code then PCL151724_META[pcl151724_decode(code)]={custom=pcl151724_decode(custom),original=pcl151724_decode(original)} end
    end
    file:close()
end
function pcl151724_save_metadata()
    pcl15171_ensure_library_dir()
    local path=PCL15171_LIBRARY_DIR..'names.index'
    local file,err=io.open(path..'.tmp','w')
    if not file then return false,tostring(err) end
    for _,code in ipairs(PCL15171_LIBRARY) do
        local data=PCL151724_META[code]
        if data then
            local ok,write_err=file:write(pcl151724_encode(code)..'\t'..pcl151724_encode(data.custom)..'\t'..pcl151724_encode(data.original)..'\n')
            if not ok then file:close();return false,tostring(write_err) end
        end
    end
    local ok,close_err=file:close()
    if not ok then return false,tostring(close_err) end
    -- Keep the previous complete metadata file if promotion fails.
    local existing=io.open(path,'r')
    if existing then
        existing:close()
        os.remove(path..'.bak')
        local moved,move_err=os.rename(path,path..'.bak')
        if not moved then return false,tostring(move_err) end
    end
    local moved,move_err=os.rename(path..'.tmp',path)
    if not moved then os.rename(path..'.bak',path);return false,tostring(move_err) end
    return true
end
function pcl151724_name(code)
    local data=PCL151724_META[code] or {}
    if data.custom and data.custom~='' then return data.custom end
    if data.original and data.original~='' then return data.original end
    return tostring(code)
end
function pcl151724_capture_metadata(request)
    local ok,err=pcall(function()
        if not request or not is_valid(request.temp) then return end
        local piece=request.temp:GetPiece()
        if not is_valid(piece) then return end
        local name=pcl15171_trim(pcl15171_from_text(piece:GetRawPieceName()))
        local data=PCL151724_META[request.code] or {}
        if name~='' then data.original=name;PCL151724_META[request.code]=data;pcl151724_save_metadata() end
        local texture=piece:GetPreviewImage()
        if is_valid(texture) then
            PCL151724_PREVIEWS[request.code]={piece=piece,texture=texture}
            pcl151727_save_preview(request.code,texture,piece)
        end
        log('PCL15_17_24_METADATA name='..tostring(name)..' preview='..tostring(is_valid(texture)))
    end)
    if not ok then log('PCL15_17_24_METADATA_UNAVAILABLE '..tostring(err)) end
end
function pcl151724_open_rename(panel,code)
    local state=PCL151723_UI[panel:GetAddress()]
    if not state then return end
    state.upload_held=nil
    state.controls.PCL_AuthorBorder:SetVisibility(1)
    state.rename_code=code
    state.controls.PCL_MagicWordTitle:SetText(pcl15171_to_text('Rename preconstruction'))
    state.controls.PCL_MagicWordInput:SetHintText(pcl15171_to_text('Build name'))
    state.controls.PCL_MagicWordInput:SetText(pcl15171_to_text(pcl151724_name(code)))
    state.controls.PCL_SubmitButton:SetCaption(pcl15171_to_text('Save name'))
    pcl15171_set_magic_visible(panel,true)
    pcl15171_set_status(panel,'Choose a name for this library entry. Leave blank to use its original name or Magic Word.')
    state.controls.PCL_MagicWordInput:SetKeyboardFocus()
end
function pcl151724_submit_rename(panel)
    local state=PCL151723_UI[panel:GetAddress()]
    local code=state and state.rename_code
    if not code then return false end
    local name,text_error=pcl15171_from_text(state.controls.PCL_MagicWordInput:GetText())
    if text_error then pcl15171_set_status(panel,text_error);return true end
    name=pcl15171_trim(name):gsub('[%z\1-\31\127]','')
    if #name>160 then pcl15171_set_status(panel,'Use a shorter name (160 UTF-8 bytes maximum).');return true end
    local previous=PCL151724_META[code]
    local data={custom=name,original=previous and previous.original or ''}
    PCL151724_META[code]=data
    local saved,err=pcl151724_save_metadata()
    if not saved then
        PCL151724_META[code]=previous
        pcl15171_set_status(panel,'Could not save name: '..tostring(err));return true
    end
    state.rename_code=nil
    pcl15171_set_magic_visible(panel,false)
    pcl15171_refresh_dynamic(panel)
    pcl15171_set_status(panel,'Name saved: '..pcl151724_name(code))
    return true
end

function pcl15171_library_label(code)
    code =
        tostring(code or '')

    if #code > 34 then
        code =
            code:sub(1, 31) .. '...'
    end

    return 'Place: ' .. code
end

function pcl15171_refresh_dynamic(panel)
    pcl151761_update_controls(panel)
    if not is_valid(panel) then return end
    local state=PCL151723_UI[panel:GetAddress()]
    if not state then return end
    local container=state.controls.PCL_DynamicEntries
    for _,button in ipairs(state.entries or {}) do
        local address=button:GetAddress()
        PCL15171_ACTIONS[address]=nil;PCL15171_BOUND[address]=nil
        PCL15171_LAST_CLICK[address]=nil;PCL151723_NATIVE_BUTTONS[address]=nil
    end
    state.entries={}
    container:ClearChildren()
    for _,code in ipairs(PCL15171_LIBRARY) do
        local line=pcl151723_new(panel,'HorizontalBox')
        local preview=PCL151724_PREVIEWS[code]
        local thumb=pcl151723_new(panel,'SizeBox')
        thumb:SetWidthOverride(200);thumb:SetHeightOverride(200)
        if preview and is_valid(preview.texture) then
            local image=pcl151723_new(panel,'Image')
            image:SetBrushFromTexture(preview.texture,true)
            pcl151751_image_tooltip(panel,thumb,preview.texture)
            local fit=pcl151723_new(panel,'ScaleBox')
            fit:SetStretch(1);fit:SetContent(image);thumb:SetContent(fit)
        else
            local placeholder=pcl151723_label(panel,PCL151761_MODE=='blades' and 'Blade preview' or 'Place once to create preview',24,false)
            placeholder:SetAutoWrapText(true);placeholder:SetJustification(1)
            thumb:SetContent(placeholder)
        end
        pcl151723_hadd(line,thumb,false,16)
        local details=pcl151723_new(panel,'VerticalBox')
        local name=pcl151723_label(panel,pcl151724_name(code),28,false)
        name:SetAutoWrapText(false);name:SetTextOverflowPolicy(1)
        pcl151723_vadd(details,name,0,4)
        local button=pcl151723_button(panel,PCL151761_MODE=='blades' and 'Use blade' or 'Place build',48)
        pcl15171_bind_button(button,{kind='magic_entry',code=code,panel=panel})
        pcl151723_vadd(details,button,0,8)
        local actions=pcl151723_new(panel,'HorizontalBox')
        local rename=pcl151723_button(panel,'Rename',48)
        pcl15171_bind_button(rename,{kind='rename_entry',code=code,panel=panel})
        pcl151723_hadd(actions,rename,false,12)
        local copy=pcl151723_button(panel,'Copy Magic Word',48)
        pcl15171_bind_button(copy,{kind='copy_word',code=code,panel=panel})
        pcl151723_hadd(actions,copy,true,0)
        pcl151723_vadd(details,actions,0,0)
        local delete=pcl151734_delete_button(panel,code)
        pcl151723_vadd(details,delete,8,0)
        state.entries[#state.entries+1]=delete
        pcl151723_hadd(line,details,true,0)
        state.entries[#state.entries+1]=copy
        -- Two nested solid brushes leave a thin gold edge around the whole entry.
        local frame=pcl151723_new(panel,'Border')
        frame:SetBrushColor({R=.30,G=.28,B=.20,A=1})
        frame:SetPadding({Left=2,Top=2,Right=2,Bottom=2})
        local inside=pcl151723_new(panel,'Border')
        inside:SetBrushColor({R=.006,G=.006,B=.004,A=1})
        inside:SetPadding({Left=8,Top=8,Right=8,Bottom=8})
        inside:SetContent(line);frame:SetContent(inside)
        local row=pcl151723_new(panel,'SizeBox')
        row:SetHeightOverride(224)
        row:SetContent(frame)
        pcl151723_vadd(container,row,0,8)
        state.entries[#state.entries+1]=button
        state.entries[#state.entries+1]=rename
    end
    pcl151723_resize(panel)
    pcl151737_start_holds()
    log('PCL15_17_23_LIBRARY_REFRESH count='..tostring(#PCL15171_LIBRARY))
end


function pcl15171_find_creative_service(context)
    if is_valid(PCL15171_CREATIVE_SERVICE) then
        return PCL15171_CREATIVE_SERVICE
    end

    local found = nil

    pcall(function()
        local all =
            FindAllOf(
                'WBP_CreativeModeHome_C'
            )

        if all ~= nil then
            for _, candidate in pairs(all) do
                if is_valid(candidate) and
                   not string.find(
                       safe_full_name(candidate),
                       'Default__',
                       1,
                       true
                   ) then

                    found = candidate
                    break
                end
            end
        end
    end)

    if is_valid(found) then
        PCL15171_CREATIVE_SERVICE = found
        return found
    end

    pcall(function()
        LoadAsset(
            PCL15171_CREATIVE_BP
        )
    end)

    pcall(function()
        PCL15171_CREATIVE_CLASS_OBJ =
            StaticFindObject(
                PCL15171_CREATIVE_CLASS
            )
    end)

    if is_valid(PCL15171_CREATIVE_CLASS_OBJ) then
        found =
            pcl15171_create_widget(
                context,
                PCL15171_CREATIVE_CLASS_OBJ
            )
    end

    if is_valid(found) then
        PCL15171_CREATIVE_SERVICE = found
        log('PCL15_17_1_CREATIVE_SERVICE_CREATED')
    end

    return found
end

function pcl15171_download_magic(context, code)
    if PCL151716_IMPORT ~= nil then return false, 'An import is already waiting for its build.' end
    code =
        pcl15171_trim(code)

    if code == '' then
        return false, 'Magic Word is empty'
    end

    local creative =
        pcl15171_find_creative_service(
            context
        )

    if not is_valid(creative) then
        return false,
            'UWCreativeMode service unavailable'
    end

    local before_root = 0
    pcall(function()
        local forge = find_forge()
        before_root = pcl151112_addr(pcl151112_first_slot_child(forge:GetRootSwordPartActor()))
    end)
    local ok, err =
        pcall(function()
            creative:DownloadPiece(
                code
            )
        end)
    PCL151715_VALIDATION_CACHE = {}

    if not ok then
        return false,
            'DownloadPiece failed: ' ..
            tostring(err)
    end

    PCL151716_IMPORT = {before_root=before_root,attempts=0,stable=0,root=0,code=code}
    pcl15179_schedule(1000, pcl151716_import_tick)
    return true, nil
end

function pcl151717_prepare_hilt(forge)
    local stage_class = StaticFindObject('/Script/Bladesong.UWSwordmakingStageButton')
    if not is_valid(stage_class) then return false end
    local frontend=is_valid(forge) and forge.ForgeModeFrontend or nil
    local active_ui=is_valid(frontend) and frontend.ForgeModeUi or nil
    for _,ui in ipairs(is_valid(active_ui) and {active_ui} or {}) do
        if is_valid(ui) and is_valid(ui.ForgeMode) and
           ui.ForgeMode:GetAddress() == forge:GetAddress() then
            local container = ui.SwordmakingStageButtonContainer
            if is_valid(container) then
                for index=0,container:GetChildrenCount()-1 do
                    local stage = container:GetChildAt(index)
                    if is_valid(stage) and stage:IsA(stage_class) then
                        local title = pcl15171_from_text(stage.Title)
                        if type(title)=='string' and title:lower():find('hilt',1,true) then
                            if stage:IsStageActive() then return true end
                            if not is_valid(stage.Button) then return false end
                            stage.Button:HandleButtonClicked()
                            PCL151715_VALIDATION_CACHE = {}
                            log('PCL15_17_17_HILT_REQUEST stock_stage_button=true')
                            return false
                        end
                    end
                end
            end
        end
    end
    return false
end

function pcl151716_import_tick()
    local pending = PCL151716_IMPORT
    if pending == nil then return end
    pending.attempts = pending.attempts + 1
    local forge = find_forge()
    local sentinel, root = nil, nil
    if is_valid(forge) then
        sentinel = forge:GetRootSwordPartActor()
        root = pcl151112_first_slot_child(sentinel)
    end
    local address = pcl151112_addr(root)
    if address ~= 0 and address ~= pending.before_root then
        pending.stable = pending.root == address and pending.stable + 1 or 1
        pending.root = address
        if pending.stable >= 2 then
            if not pcl151717_prepare_hilt(forge) then
                pending.stable = 0
                if pending.attempts < 60 then
                    pcl15179_schedule(1000,pcl151716_import_tick)
                else
                    PCL151716_IMPORT = nil
                    log('PCL15_17_17_IMPORT_MODE_TIMEOUT imported_build_kept=true')
                end
                return
            end
            -- End the bounded watcher before changing any native topology.
            PCL151716_IMPORT = nil
            local menu = PCL151710_MENU_STATE
            if menu ~= nil then pcl151710_set_menu_visible(false) end
            -- Let focus changes and the mode switch finish before assigning
            -- the native preview. Closing UI after assignment can cancel it.
            pcl15179_schedule(100,function()
                local current_forge = find_forge()
                if not is_valid(current_forge) then return end
                local current_sentinel = current_forge:GetRootSwordPartActor()
                local current_root = pcl151112_first_slot_child(current_sentinel)
                local ok, err = pcl151716_hold_import(current_forge,current_sentinel,current_root)
                local current_menu = PCL151710_MENU_STATE
                if current_menu ~= nil then
                    pcl15171_set_status(current_menu.panel,ok and 'Checking held preview...' or
                        ('Import loaded; placement handoff failed: ' .. tostring(err)))
                end
                log('PCL15_17_17_IMPORT_ASSIGN ok=' .. tostring(ok) .. ' detail=' .. tostring(err))
                if ok then pcl15179_schedule(100,pcl151717_verify_handoff) end
            end)
            return
        end
    end
    if pending.attempts >= 60 then
        PCL151716_IMPORT = nil
        log('PCL15_17_16_IMPORT_HANDOFF_TIMEOUT no_new_live_root=true')
        return
    end
    pcl15179_schedule(1000, pcl151716_import_tick)
end

function pcl151716_hold_import(forge, sentinel, root)
    if not is_valid(root) or not is_valid(sentinel) then return false, 'import root unavailable' end
    local handling, preview = current_preview_14()
    if not is_valid(handling) then return false, 'active handling unavailable' end
    if is_valid(preview) then return false, 'finish the existing held part first' end
    local ready, err = pcl15166_ensure_current_anchor('import_handoff')
    if not ready then return false, err end
    local actors = {}
    local anchor
    anchor, err = pcl15165_take_exact_anchor_actor(actors)
    if not is_valid(anchor) then return false, err end
    pcl15170_apply_mesh_to_actor(anchor)
    local original = root:GetTransform()
    local transform = {
        Rotation={X=original.Rotation.X,Y=original.Rotation.Y,Z=original.Rotation.Z,W=original.Rotation.W},
        Translation={X=original.Translation.X,Y=original.Translation.Y,Z=original.Translation.Z},
        Scale3D={X=original.Scale3D.X,Y=original.Scale3D.Y,Z=original.Scale3D.Z}}
    -- Allocate and validate the anchor before unlinking the downloaded build.
    -- Keep the imported actors and materials; no rebuild or per-part scan.
    sentinel.SlotChildParts:Remove(0)
    local linked, link_err = pcl15165_attach_anchor_child(anchor, 0, root)
    if not linked then
        anchor.SlotChildParts:Remove(0)
        sentinel.SlotChildParts:Add(0, root)
        root:K2_AttachToActor(sentinel, FName('None', EFindName.FNAME_Find), 1,1,1,false)
        return false, link_err
    end
    root.bPending = false
    anchor.bPending = true
    handling.BestSwordPartSlotParent = nil
    handling.PreviewSwordPartActor = anchor
    PCL151717_HANDOFF = {anchor=anchor,root=root,sentinel=sentinel,
        handling=handling,transform=transform,checks=0}
    return true, 'single_connector_anchor'
end

function pcl151717_verify_handoff()
    local transfer = PCL151717_HANDOFF
    if transfer == nil then return end
    transfer.checks = transfer.checks + 1
    local handling, preview = current_preview_14()
    local held = is_valid(preview) and is_valid(transfer.anchor) and
        preview:GetAddress() == transfer.anchor:GetAddress()
    local placed = false
    if is_valid(transfer.sentinel) then
        local current = pcl151112_first_slot_child(transfer.sentinel)
        placed = is_valid(current) and is_valid(transfer.anchor) and
            current:GetAddress() == transfer.anchor:GetAddress()
    end
    log('PCL15_17_17_IMPORT_VERIFY check=' .. tostring(transfer.checks) ..
        ' held=' .. tostring(held) .. ' placed=' .. tostring(placed))
    pcall(function()
        pcl151160_presentation_audit(transfer.root,'import_check_' .. tostring(transfer.checks))
    end)
    if held or placed then
        transfer.anchor:SetActorHiddenInGame(false)
        if is_valid(transfer.root) then transfer.root:SetActorHiddenInGame(false) end
        if held and transfer.checks < 2 then
            pcl15179_schedule(600,pcl151717_verify_handoff)
            return
        end
        local menu = PCL151710_MENU_STATE
        if menu ~= nil then pcl15171_set_status(menu.panel,placed and 'Build placed.' or
            'Build is held. Move the cursor and click to place.') end
    else
        -- A dropped preview must not take the downloaded build with it.
        -- Restore its original live relation and transform, never rebuild it.
        local restored = false
        if is_valid(transfer.root) and is_valid(transfer.sentinel) and
           not transfer.root:IsActorBeingDestroyed() then
            local current = pcl151112_first_slot_child(transfer.sentinel)
            restored = is_valid(current) and current:GetAddress() == transfer.root:GetAddress()
            if not is_valid(current) then
                if is_valid(transfer.anchor) then transfer.anchor.SlotChildParts:Remove(0) end
                transfer.sentinel.SlotChildParts:Add(0,transfer.root)
                transfer.root:K2_AttachToActor(transfer.sentinel,FName('None',EFindName.FNAME_Find),1,1,1,false)
                transfer.root:K2_SetActorTransform(transfer.transform,false,{},true)
                transfer.root:SetActorHiddenInGame(false)
                if is_valid(transfer.anchor) then
                    transfer.anchor:SetActorHiddenInGame(true)
                    transfer.anchor:SetActorEnableCollision(false)
                end
                log('PCL15_17_17_IMPORT_RESTORED preview_was_dropped=true')
                restored = true
            end
        end
        local menu = PCL151710_MENU_STATE
        if menu ~= nil then pcl15171_set_status(menu.panel,restored and
            'Placement did not stay active. The imported build was restored in the Forge.' or
            'The preview was dropped. See the import verification details in UE4SS.log.') end
    end
    PCL151717_HANDOFF = nil
end

function pcl15171_open_magic(panel)
    if not is_valid(panel) then
        return
    end

    local state=PCL151723_UI[panel:GetAddress()]
    if state then
        state.rename_code=nil;state.upload_held=nil
        state.controls.PCL_AuthorBorder:SetVisibility(1)
        state.controls.PCL_MagicWordTitle:SetText(pcl15171_to_text('Import preconstruction'))
        state.controls.PCL_MagicWordInput:SetHintText(pcl15171_to_text('Enter Magic Word'))
        state.controls.PCL_MagicWordInput:SetText(pcl15171_to_text(''))
        state.controls.PCL_SubmitButton:SetCaption(pcl15171_to_text('Add to library'))
    end

    pcl15171_set_magic_visible(
        panel,
        true
    )

    pcl15171_set_status(
        panel,
        'Enter a Magic Word to add it to the library.'
    )

    local input =
        pcl15171_widget_by_name(
            panel,
            'PCL_MagicWordInput'
        )

    if is_valid(input) then
        pcall(function()
            input:SetKeyboardFocus()
        end)
    end

    log('PCL15_17_1_UI_PLUS')
end

function pcl15171_cancel_magic(panel)
    if PCL151741_BATCH then pcl151741_cancel_batch(panel);return end
    if PCL151741_BATCH then pcl151741_cancel_batch(panel);return end
    if PCL151741_BATCH then pcl151741_cancel_batch(panel);return end
    if PCL151741_BATCH then pcl151741_cancel_batch(panel);return end
    local upload_state=is_valid(panel) and PCL151723_UI[panel:GetAddress()]
    if upload_state and upload_state.upload_held and pcl151727_restore_draft(panel) then return end
    local state=is_valid(panel) and PCL151723_UI[panel:GetAddress()]
    if state then state.rename_code=nil;state.upload_held=nil;state.controls.PCL_AuthorBorder:SetVisibility(1) end
    if not is_valid(panel) then
        return
    end

    pcl15171_set_magic_visible(
        panel,
        false
    )

    pcl15171_set_status(
        panel,
        ''
    )
end

function pcl15171_submit_magic(panel)
    if pcl151726_submit_upload(panel) then return end
    if pcl151724_submit_rename(panel) then return end
    if not is_valid(panel) then
        return
    end

    local input =
        pcl15171_widget_by_name(
            panel,
            'PCL_MagicWordInput'
        )

    if not is_valid(input) then
        pcl15171_set_status(
            panel,
            'Magic Word text box is unavailable.'
        )
        return
    end

    local raw = nil
    pcall(function()
        raw =
            input:GetText()
    end)

    local text, text_error = pcl15171_from_text(raw)
    if text_error then
        pcl15171_set_status(panel, text_error)
        return
    end
    local code = pcl15171_trim(text)

    if code == '' then
        pcl15171_set_status(
            panel,
            'Enter a Magic Word first.'
        )
        return
    end

    local save_ok, save_err =
        pcl15171_add_code(
            code
        )

    if not save_ok then
        pcl15171_set_status(
            panel,
            'Could not save entry: ' ..
            tostring(save_err)
        )
        return
    end

    pcl15171_refresh_dynamic(
        panel
    )

    local download_ok, download_err =
        pcl15171_download_magic(
            panel,
            code,
            true,
            true -- library only; placement is an explicit Place build action
        )

    pcl15171_set_magic_visible(panel, false)
    pcall(function() input:SetText(pcl15171_to_text('')) end)

    if download_ok then
        pcl15171_set_status(
            panel,
            (PCL151719_IMPORT and 'Saving build to library: ' .. tostring(code)
                or 'Build is saved locally. Choose Place build when ready.')
        )

        log('PCL15_17_1_MAGIC_SUBMIT code=' ..
            tostring(code) ..
            ' saved=true native_download=true')
    else
        -- The entry is deliberately still persisted: the + button's purpose
        -- is to add it to PCL's library even if the game's download service
        -- is not available in the current Forge state.
        pcl15171_set_status(
            panel,
            'Saved. Native Magic Word load unavailable: ' ..
            tostring(download_err)
        )

        log('PCL15_17_1_MAGIC_SUBMIT code=' ..
            tostring(code) ..
            ' saved=true native_download=false error=' ..
            tostring(download_err))
    end
end

function pcl15171_click_anchor(panel)
    if PCL151742_ANCHOR_REQUEST then return end
    local ok,err=pcall(function()
        assert(not PCL151741_BATCH and not PCL151725_UPLOAD_PENDING and not PCL151719_IMPORT and not PCL151729_HANDOFF,'Finish the current operation first')
        local forge=find_forge()
        assert(is_valid(forge),'Active Forge unavailable')
        local handling,held=current_preview_14()
        assert(is_valid(handling),'Active part handling unavailable')
        assert(not is_valid(held),'Place the held item before selecting another anchor')
        if BMF_PCL_DIRECT_ANCHOR() then
            local menu=PCL151710_MENU_STATE
            if PCL151745_OPEN and PCL151745_OPEN.anchor then return end
            if not pcl151761_prepare_parts_stage(forge) then
                local request={state=menu,forge=forge,checks=0,anchor=true}
                PCL151745_OPEN=request
                pcl15179_schedule(100,function() pcl151745_open_tick(request) end)
                return
            end
        end
        local ready,ready_err=pcl15166_ensure_current_anchor('forge_library_anchor')
        assert(ready,tostring(ready_err))
        local request={panel=panel,forge=forge,handling=handling,checks=0}
        PCL151742_ANCHOR_REQUEST=request
        if BMF_PCL_DIRECT_ANCHOR() then
            local anchor,spawn_error=pcl151728_spawn_anchor(request)
            assert(is_valid(anchor),tostring(spawn_error))
            handling.BestSwordPartSlotParent=nil
            handling.PreviewSwordPartActor=anchor
            local _,assigned=current_preview_14()
            assert(is_valid(assigned) and assigned:GetAddress()==anchor:GetAddress(),'Anchor handoff did not persist')
        else
            local button,button_err=pcl151719_active_anchor_button(forge)
            assert(is_valid(button),tostring(button_err))
            local clicked,click_err=pcl15165_click_exact_anchor_tile(button)
            assert(clicked,tostring(click_err))
        end
        pcl151742_finish_anchor(request)
    end)
    if not ok then
        pcl151742_discard_spawn(PCL151742_ANCHOR_REQUEST)
        PCL151742_ANCHOR_REQUEST=nil
        pcl151741_message(panel,'Place anchor failed: '..tostring(err))
    end
end

function pcl15171_dispatch(button)
    if not is_valid(button) then
        return
    end

    local addr =
        pcl151112_addr(button)

    local action =
        PCL15171_ACTIONS[addr]

    if action == nil then
        return
    end

    local now =
        os.clock()

    local last =
        tonumber(
            PCL15171_LAST_CLICK[addr]
        ) or -100

    if now - last < 0.15 then
        return
    end

    PCL15171_LAST_CLICK[addr] = now

    if pcl151762_dispatch(action) then return end
    if pcl151761_dispatch(action) then return end
    if action.kind == 'batch_upload' then pcl151741_start_batch(action.panel);return end
    if action.kind == 'carry_toggle' then pcl151741_toggle_carry(action.panel);return end
    if PCL151741_BATCH and (action.kind=='rename_entry' or action.kind=='plus' or action.kind=='anchor' or action.kind=='magic_entry' or action.kind=='load_local') then pcl151741_message(action.panel,'Finish or cancel the upload queue first.');return end
    if action.kind == 'recover_draft' then pcl151727_restore_draft(action.panel);return end
    if action.kind == 'delete_entry' then pcl151734_delete_entry(action);return end
    if action.kind == 'copy_word' then pcl151733_copy_word(action.panel,action.code);return end
    if action.kind == 'rename_entry' then pcl151724_open_rename(action.panel,action.code);return end
    if action.kind == 'library_toggle' then
        local state = PCL151710_MENU_STATE
        if state ~= nil then pcl151710_set_menu_visible(not state.open and not PCL151745_OPEN) end
        return
    end
    if action.kind == 'library_close' then
        pcl151710_set_menu_visible(false)
        return
    end

    if action.kind == 'save_local' then
        local call_ok, saved, detail = pcall(pcl151163_export_native_json)
        pcl15171_set_status(action.panel,
            call_ok and saved and 'Saved latest.json and a timestamped snapshot.' or
            ('Save failed: ' .. tostring(call_ok and detail or saved)))
        return
    end
    if action.kind == 'validate_local' then
        local ok, valid, detail = pcall(pcl151164_validate_native_json_file)
        local message = 'Validation failed; check the UE4SS log for details.'
        if not ok then
            message = 'Validation failed: ' .. tostring(valid)
        elseif valid then
            message = 'Native validation passed: ' .. tostring(detail) .. ' parts.'
        elseif detail == -20 or detail == -21 then
            message = 'Local validation needs a bridge update for this Bladesong build (status ' .. tostring(detail) .. ').'
        elseif detail ~= nil then
            message = 'Native validation failed (status ' .. tostring(detail) .. ').'
        end
        pcl15171_set_status(action.panel, message)
        return
    end
    if action.kind == 'load_local' then
        -- The native importer enforces an empty Forge in Hilt mode.
        -- Never clear or replace the user's active design to satisfy it.
        local ok, err = pcall(pcl151165_direct_json_import)
        pcl15171_set_status(action.panel,
            not ok and ('Load failed: ' .. tostring(err)) or
            PCL151710_IMPORT_ERROR or 'Native load started; rebuilding the design.')
        return
    end

    if action.kind == 'plus' then
        pcl15171_open_magic(
            action.panel
        )
        return
    end

    if action.kind == 'cancel' then
        pcl15171_cancel_magic(
            action.panel
        )
        return
    end

    if action.kind == 'submit' then
        pcl15171_submit_magic(
            action.panel
        )
        return
    end

    if action.kind == 'anchor' then
        pcl15171_click_anchor(
            action.panel
        )
        return
    end

    if action.kind == 'magic_entry' then
        local ok, err =
            pcl15171_download_magic(
                action.panel,
                action.code
            )

        if ok then
            pcl15171_set_status(
                action.panel,
                'Loading build: ' ..
                tostring(action.code)
            )
        else
            pcl15171_set_status(
                action.panel,
                'Magic Word load failed: ' ..
                tostring(err)
            )
        end

        log('PCL15_17_1_LIBRARY_ENTRY code=' ..
            tostring(action.code) ..
            ' native_download=' ..
            tostring(ok) ..
            ' error=' ..
            tostring(err))
        return
    end
end

function pcl15171_register_focus_hook()
    if PCL15171_FOCUS_HOOKED then
        return true
    end

    local ok, err =
        pcall(function()
            PCL15171_FOCUS_PRE,
            PCL15171_FOCUS_POST =
                RegisterHook(
                    '/Script/UMG.Widget:SetFocus',
                    function(context)
                        local widget =
                            pcl15171_unwrap(
                                context
                            )

                        if is_valid(widget) then
                            local addr =
                                pcl151112_addr(
                                    widget
                                )

                            if PCL15171_ACTIONS[addr] ~= nil then
                                run_game_thread(
                                    function()
                                        pcl15171_dispatch(
                                            widget
                                        )
                                    end
                                )
                            end
                        end
                    end
                )
        end)

    if not ok then
        log('PCL15_17_1_FOCUS_HOOK_ERROR=' ..
            tostring(err))
        return false
    end

    PCL15171_FOCUS_HOOKED = true
    log('PCL15_17_1_FOCUS_HOOK_OK')
    return true
end

function pcl15171_hide_stock_anchor_tile()
    local button, err =
        pcl15165_find_exact_anchor_button()

    if not is_valid(button) then
        return
    end

    pcall(function()
        button:SetVisibility(1)
    end)
end

function pcl15171_create_panel(catalogue)
    if not is_valid(catalogue) or
       not pcl15171_load_widget_assets() then
        return nil
    end

    pcl15175_trace('create_panel_begin', catalogue)
    local panel =
        pcl15171_create_widget(
            catalogue,
            PCL15171_UI_CLASS_OBJ
        )

    if not is_valid(panel) then
        pcl15175_trace('create_panel_invalid', catalogue)
        return nil
    end
    pcl15175_trace('create_panel_ok', catalogue)
    if not pcl15178_style_panel(panel) then return nil end

    pcl15175_trace('find_controls_begin', catalogue)
    local plus =
        pcl15171_widget_by_name(
            panel,
            'PCL_PlusButton'
        )

    local anchor =
        pcl15171_widget_by_name(
            panel,
            'PCL_AnchorButton'
        )

    local submit =
        pcl15171_widget_by_name(
            panel,
            'PCL_SubmitButton'
        )

    local cancel =
        pcl15171_widget_by_name(
            panel,
            'PCL_CancelButton'
        )

    pcl15175_trace('find_controls_done_bind_begin', catalogue)
    pcl15171_bind_button(
        plus,
        {
            kind = 'plus',
            panel = panel
        }
    )

    pcl15171_bind_button(
        anchor,
        {
            kind = 'anchor',
            panel = panel
        }
    )

    pcl15171_bind_button(
        submit,
        {
            kind = 'submit',
            panel = panel
        }
    )

    pcl15171_bind_button(
        cancel,
        {
            kind = 'cancel',
            panel = panel
        }
    )

    for _, item in ipairs({
        {'PCL_SaveLocalButton', 'save_local'},
        {'PCL_ValidateLocalButton', 'validate_local'},
        {'PCL_LoadLocalButton', 'load_local'}
    }) do
        pcl15171_bind_button(pcl15171_widget_by_name(panel, item[1]),
            {kind = item[2], panel = panel})
    end

    pcl15175_trace('bind_done_refresh_begin', catalogue)
    pcl15171_refresh_dynamic(
        panel
    )

    pcl15175_trace('create_panel_done', catalogue)
    return panel
end

function pcl15171_panel_child_index(container, panel)
    if not is_valid(container) or
       not is_valid(panel) then
        return -1
    end

    local idx = -1
    pcall(function()
        idx =
            tonumber(
                container:GetChildIndex(
                    panel
                )
            ) or -1
    end)

    return idx
end

function pcl151710_position_widget(widget, width, height, top, order)
    widget:AddToViewport(order)
    widget:SetDesiredSizeInViewport({X=width,Y=height})
    widget:SetPositionInViewport({X=-24,Y=top}, false)
    -- Both size and position setters reset anchors to the top-left. Anchors
    -- must be assigned last, otherwise negative right offsets go off-screen.
    widget:SetAnchorsInViewport({Minimum={X=1,Y=0}, Maximum={X=1,Y=0}})
    widget:SetAlignmentInViewport({X=1,Y=0})
end

function pcl151710_set_menu_visible(visible)
    local state = PCL151710_MENU_STATE
    if state == nil or not is_valid(state.panel) then return end
    if not visible then PCL151745_OPEN=nil end
    if visible then
        local forge=find_forge()
        if not is_valid(forge) then pcl151741_message(state.panel,'Open the Forge first.');return end
        local prepared,ready=true,false
        local pending=PCL151745_OPEN
        local mode=PCL151761_MODE
        if pending and pending.state==state and pending.ready and pending.mode==mode and
            is_valid(pending.forge) and pending.forge:GetAddress()==forge:GetAddress() then
            ready=true
        else
            local prepare=mode=='blades' and pcl15181_prepare_blade or pcl151717_prepare_hilt
            prepared,ready=pcall(prepare,forge)
        end
        if not prepared then pcl151741_message(state.panel,'Could not select Forge mode: '..tostring(ready));return end
        if not ready then
            if not PCL151745_OPEN or PCL151745_OPEN.state~=state then
                local request={state=state,forge=forge,checks=0,mode=mode}
                PCL151745_OPEN=request
                pcl15179_schedule(100,function() pcl151745_open_tick(request) end)
            end
            return
        end
        PCL151745_OPEN=nil
        pcl15179_schedule(50,function()
            if PCL151710_MENU_STATE~=state or not state.open or not is_valid(state.panel) then return end
            local started=os.clock()
            local recovery_state=PCL151723_UI[state.panel:GetAddress()]
            -- An already rendered empty list has no rows or previews to rebuild.
            if #PCL15171_LIBRARY>0 or not recovery_state or #(recovery_state.entries or {})>0 then
                pcl15171_refresh_dynamic(state.panel)
                pcl151727_queue_previews(state.panel)
            end
            if recovery_state and is_valid(recovery_state.recovery) then
                recovery_state.recovery:SetIsEnabled(not PCL151741_BATCH and pcl151727_draft()~=nil)
            end
            log('PCL_FORGE_UI_TIMING refresh='..string.format('%.3f',os.clock()-started))
        end)
        -- Recovery drafts remain available through an explicit ribbon action.
        -- Merely opening the library must never open the upload form.

    end
    state.open = visible
    if visible then pcl151737_start_holds()
    else for _,action in pairs(PCL151737_HOLDS) do pcl151737_reset_hold(action) end end
    local show_started=os.clock()
    state.panel:SetVisibility(visible and 0 or 1)
    if is_valid(state.close) then state.close:SetVisibility(visible and 0 or 1) end
    local shown=os.clock()
    local player = nil
    pcall(function() player = state.catalogue:GetOwningPlayer() end)
    local lib = pcl15171_widget_library()
    if is_valid(player) and is_valid(lib) then
        local ok, err = pcall(function()
            if visible then
                lib:SetInputMode_UIOnlyEx(player, state.panel, 0, false)
                PCL151760_INPUT_PLAYER=player;PCL151760_INPUT_LOCKED=true
            else
                lib:SetInputMode_GameAndUIEx(player, nil, 0, false, false)
                PCL151760_INPUT_PLAYER=nil;PCL151760_INPUT_LOCKED=false
            end
        end)
        if not ok then log('PCL15_17_10_INPUT_MODE_ERROR=' .. tostring(err)) end
    end
    log('PCL15_17_10_MENU_VISIBLE=' .. tostring(visible))
    if visible then log('PCL_FORGE_UI_TIMING visibility='..string.format('%.3f',shown-show_started)
        ..' input='..string.format('%.3f',os.clock()-shown)) end
end

function pcl151710_menu_button(catalogue, panel, label, kind, width)
    local entry = pcl15171_create_widget(catalogue, PCL15171_ENTRY_CLASS_OBJ)
    if not is_valid(entry) then return nil end
    local root = pcl15171_widget_by_name(entry, 'PCL_EntryRoot')
    local button = pcl15171_widget_by_name(entry, 'PCL_EntryButton')
    local text = pcl15171_widget_by_name(entry, 'PCL_EntryLabel')
    if is_valid(root) then
        root:SetMinDesiredWidth(0)
        root:SetWidthOverride(width)
        root:SetMaxDesiredWidth(width)
        root:SetMinDesiredHeight(40)
    end
    if is_valid(text) then
        text:SetText(pcl15171_to_text(label))
        pcl15178_style_text(text, 20)
    end
    if is_valid(button) then
        button:SetBackgroundColor({R=0.14,G=0.12,B=0.08,A=1})
        pcl15171_bind_button(button, {kind=kind,panel=panel})
    end
    return entry
end

-- Match the actual native feature button; never use viewport fallback dimensions.
function pcl151710_find_tool_row(catalogue)
    local forge=find_forge()
    if not is_valid(forge) then return nil end
    for _,owner in pairs(FindAllOf('WBP_ForgeMode_C') or {}) do
        if is_valid(owner) and is_valid(owner.ForgeMode) and owner.ForgeMode:GetAddress()==forge:GetAddress() then
            local reference=owner.ButtonEnvironment
            if is_valid(reference) and reference:GetVisibility()==0 and is_valid(reference:GetParent()) then
                return reference:GetParent(),reference
            end
        end
    end
end

function pcl151722_insert_launcher(parent,button,reference)
    -- UPanelWidget has no runtime Blueprint InsertChildAt. Retain each live
    -- widget and its exact wrap-slot settings, then insert before the reference.
    local children={}
    for i=0,parent:GetChildrenCount()-1 do
        local child=parent:GetChildAt(i)
        if child:GetAddress()~=button:GetAddress() then
            local s=child.Slot
            children[#children+1]={widget=child,padding={Left=s.Padding.Left,Top=s.Padding.Top,Right=s.Padding.Right,Bottom=s.Padding.Bottom},h=s.HorizontalAlignment,v=s.VerticalAlignment,fill=s.bFillEmptySpace,span=s.FillSpanWhenLessThan,line=s.bForceNewLine}
        end
    end
    local function add(widget,c)
        local s=parent:AddChildToWrapBox(widget)
        s:SetPadding(c.padding);s:SetHorizontalAlignment(c.h);s:SetVerticalAlignment(c.v)
        s:SetFillEmptySpace(c.fill);s:SetFillSpanWhenLessThan(c.span);s:SetNewLine(c.line)
    end
    parent:ClearChildren()
    for _,c in ipairs(children) do
        if c.widget:GetAddress()==reference:GetAddress() then add(button,c) end
        add(c.widget,c)
    end
end

function pcl151722_native_click_hook()
    if PCL151722_CLICK_HOOK then return end
    local pre,post=RegisterHook('/Script/CommonUI.CommonButtonBase:HandleButtonClicked',function() end,function(context)
        local button=pcl15171_unwrap(context)
        local state=PCL151710_MENU_STATE
        local action=is_valid(button) and PCL15171_ACTIONS[button:GetAddress()] or nil
        if action and action.kind=='delete_entry' then return end -- handled only by hold monitor
        if action and action.native_menu then
            pcl15179_schedule(1,function()
                if is_valid(button) and PCL15171_ACTIONS[button:GetAddress()]==action then pcl15171_dispatch(button) end
            end)
        elseif state and state.native_launcher and is_valid(button) and is_valid(state.launcher) and button:GetAddress()==state.launcher:GetAddress() then
            -- Run after the feature blueprint has completed its own menu work.
            pcl15179_schedule(1,function()
                local current=PCL151710_MENU_STATE
                if current==state and is_valid(button) then
                    if is_valid(button.MenuAnchor) then button.MenuAnchor:Close() end
                    pcl15171_dispatch(button)
                end
            end)
        end
    end)
    PCL151722_CLICK_HOOK={pre,post}
end

PCL151737_HOLDS={}
function pcl151737_reset_hold(action)
    action.elapsed=0;action.pressed=false;action.keyboard=false;action.hold_confirmed=false
    if is_valid(action.hold_button) and action.caption~='Hold to delete' then
        action.hold_button:SetCaption(pcl15171_to_text('Hold to delete'))
        action.caption='Hold to delete'
    end
end
function pcl151737_start_holds()
    if PCL151737_HOLD_RUNNING then return end
    local menu=PCL151710_MENU_STATE
    if not menu or not menu.open then return end
    PCL151737_HOLD_RUNNING=true
    PCL151737_HOLD_TIME=os.clock()
    pcl15179_schedule(33,pcl151737_hold_tick)
end
function pcl151737_hold_tick()
    local menu=PCL151710_MENU_STATE
    local now=os.clock()
    local dt=math.max(0,math.min(0.1,now-(PCL151737_HOLD_TIME or now)))
    PCL151737_HOLD_TIME=now
    if not menu or not menu.open or not PCL15177_FORGE_ACTIVE then
        for _,action in pairs(PCL151737_HOLDS) do pcl151737_reset_hold(action) end
        PCL151737_HOLD_RUNNING=false
        return
    end
    for address,action in pairs(PCL151737_HOLDS) do
        local button=action.hold_button
        if PCL15171_ACTIONS[address]~=action or not is_valid(button) or not is_valid(action.panel) then
            PCL151737_HOLDS[address]=nil
        elseif action.panel:GetAddress()~=menu.panel:GetAddress() then
            pcl151737_reset_hold(action)
        else
            local pressed=button:IsPressed()
            local hovered=button:IsHovered()
            if pressed and not action.pressed then
                action.elapsed=0
            end
            local continuing=pressed and hovered
            if not continuing or PCL151719_IMPORT or PCL151725_UPLOAD_PENDING then
                pcl151737_reset_hold(action)
            else
                action.pressed=true
                action.elapsed=(action.elapsed or 0)+dt
                local percent=math.min(100,math.floor(action.elapsed/action.hold_seconds*100))
                local caption='Hold to delete '..percent..'%'
                if caption~=action.caption then button:SetCaption(pcl15171_to_text(caption));action.caption=caption end
                if action.elapsed>=action.hold_seconds then
                    action.hold_confirmed=true
                    local deleted=pcl151734_delete_entry(action)
                    pcl151737_reset_hold(action)
                    if not deleted and is_valid(button) then button:SetCaption(pcl15171_to_text('Hold to retry')) end
                    break
                end
            end
        end
    end
    pcl15179_schedule(33,pcl151737_hold_tick)
end

function pcl151734_delete_button(panel,code)
    local button=pcl151723_button(panel,'Hold to delete',48)
    button:SetRequiresHold(false) -- native dynamic-button hold time is zero
    button:SetIsEnabled(true)
    local action={kind='delete_entry',code=code,panel=panel,hold_button=button,hold_seconds=1.5,elapsed=0}
    pcl15171_bind_button(button,action)
    PCL151737_HOLDS[button:GetAddress()]=action
    return button
end
function pcl151734_delete_entry(action)
    local ok,err=pcall(function()
        local button=action.hold_button
        assert(is_valid(button) and action.hold_confirmed==true,'Hold confirmation required')
        action.hold_confirmed=false -- one confirmation authorizes one deletion
        local code=action.code
        pcl151726_slot(code)
        assert(not PCL151719_IMPORT and not PCL151725_UPLOAD_PENDING,'Finish the current import/upload first.')
        local remaining,found={},false
        for _,entry in ipairs(PCL15171_LIBRARY) do
            if entry==code then found=true else remaining[#remaining+1]=entry end
        end
        assert(found,'This entry is already removed.')
        local temporary=PCL15171_LIBRARY_PATH..'.delete.tmp'
        local f=assert(io.open(temporary,'w'))
        assert(f:write('# PCL Preconstruction Library v1\n'))
        for _,entry in ipairs(remaining) do assert(f:write(entry..'\n')) end
        assert(f:close())
        local backup=PCL15171_LIBRARY_PATH..'.delete.bak'
        os.remove(backup)
        assert(os.rename(PCL15171_LIBRARY_PATH,backup),'Could not preserve library index')
        local committed,why=os.rename(temporary,PCL15171_LIBRARY_PATH)
        if not committed then os.rename(backup,PCL15171_LIBRARY_PATH);error(tostring(why)) end
        os.remove(backup)
        PCL15171_LIBRARY=remaining
        PCL151724_META[code]=nil;PCL151724_PREVIEWS[code]=nil;PCL151730_PREVIEW_CHECKED[code]=nil
        pcl151724_save_metadata()
        local failures={}
        local statics=gameplay_statics_15()
        local slot=pcl151726_slot(code)
        if statics:DoesSaveGameExist(slot,0) and not statics:DeleteGameInSlot(slot,0) then failures[#failures+1]='cached build' end
        for _,path in ipairs({pcl151733_photo_path(code),PCL15171_LIBRARY_DIR..'preview_v35_'..code..'.png',PCL15171_LIBRARY_DIR..'preview_v34_'..code..'.png',PCL15171_LIBRARY_DIR..'preview_v33_'..code..'.png',pcl151727_preview_path(code)}) do
            local exists=io.open(path,'rb')
            if exists then exists:close();if not os.remove(path) then failures[#failures+1]='preview file' end end
        end
        pcl15171_refresh_dynamic(action.panel)
        pcl15171_set_status(action.panel,#failures==0 and 'Deleted local preconstruction.' or 'Entry removed; could not remove '..table.concat(failures,', ')..'.')
        log('PCL15_17_34_LOCAL_DELETED code='..code..' cleanup_failures='..#failures)
    end)
    if not ok then pcl15171_set_status(action.panel,'Delete stopped: '..tostring(err)) end
    return ok
end

function pcl151733_copy_word(panel,code)
    local ok,err=pcall(function()
        pcl151726_slot(code)
        local args={#code}
        for i=1,#code do args[#args+1]=code:byte(i) end
        assert(pcl151726_bridge().copy_word(table.unpack(args))==1,'Clipboard is busy; try again.')
        pcl15171_set_status(panel,'Copied Magic Word: '..code)
    end)
    if not ok then pcl15171_set_status(panel,'Copy failed: '..tostring(err)) end
end
function pcl151733_photo_path(code)
    pcl151726_slot(code)
    return PCL15171_LIBRARY_DIR..'preview_v36_'..code..'.png'
end
function pcl151733_promote_photo(temporary,path)
    assert(pcl151727_preview_file(temporary),'Thumbnail PNG was not written')
    local existing=io.open(path,'rb')
    local backup=path..'.bak'
    if existing then
        existing:close();os.remove(backup)
        assert(os.rename(path,backup),'Could not preserve previous thumbnail')
    end
    local ok,err=os.rename(temporary,path)
    if not ok then os.rename(backup,path);error(tostring(err)) end
    os.remove(backup)
end
function pcl151736_has_image(rendering,root,target,mathlib,position,center,radius,nodes,view_rotation)
    -- A valid PNG header is not proof that anything was rendered. Sample the
    -- target before promoting a new image; never replace a good PNG with an
    -- empty camera frame. No cooked mesh CPU-buffer access is involved.
    local low,high=math.huge,-math.huge
    local sampled={}
    local function sample(x,y)
        x=math.max(0,math.min(511,math.floor(x)))
        y=math.max(0,math.min(511,math.floor(y)))
        local id=y*512+x
        if sampled[id] then return end
        sampled[id]=true
        local color=rendering:ReadRenderTargetPixel(root,target,x,y)
        for _,channel in ipairs({'R','G','B'}) do
            local value=tonumber(color[channel]) or 0
            low=math.min(low,value);high=math.max(high,value)
        end
    end
    for _,x in ipairs({64,256,448}) do for _,y in ipairs({64,256,448}) do sample(x,y) end end
    if high>16 and high-low>8 then return true end
    local rotation=view_rotation or mathlib:FindLookAtRotation(position,center)
    local right,up=mathlib:GetRightVector(rotation),mathlib:GetUpVector(rotation)
    local stride=math.max(1,math.ceil(#nodes/8))
    for index=1,#nodes,stride do
        local origin,extent={X=0,Y=0,Z=0},{X=0,Y=0,Z=0}
        nodes[index]:GetActorBounds(false,origin,extent,false)
        local dx,dy=0,0
        for _,axis in ipairs({'X','Y','Z'}) do
            dx=dx+(origin[axis]-center[axis])*right[axis]
            dy=dy+(origin[axis]-center[axis])*up[axis]
        end
        local x,y=256+dx/(radius*2.05)*512,256-dy/(radius*2.05)*512
        sample(x,y);sample(x-2,y);sample(x+2,y)
        if high>16 and high-low>8 then return true end
    end
    log('PCL15_17_36_EMPTY_CAPTURE min='..tostring(low)..' max='..tostring(high))
    return false
end

function pcl151733_capture(code,root,nodes,anchor)
    local camera=nil
    local ok,err=pcall(function()
        assert(is_valid(root),'Thumbnail root unavailable')
        if not nodes then
            local _,_,held_root,held_nodes=pcl151725_held_tree()
            assert(held_root:GetAddress()==root:GetAddress(),'Held build changed before thumbnail')
            nodes=held_nodes
        end
        local min={X=math.huge,Y=math.huge,Z=math.huge}
        local max={X=-math.huge,Y=-math.huge,Z=-math.huge}
        for _,actor in ipairs(nodes) do
            assert(is_valid(actor),'Thumbnail part unavailable')
            local origin,extent={X=0,Y=0,Z=0},{X=0,Y=0,Z=0}
            actor:GetActorBounds(false,origin,extent,false)
            for _,axis in ipairs({'X','Y','Z'}) do
                min[axis]=math.min(min[axis],origin[axis]-extent[axis])
                max[axis]=math.max(max[axis],origin[axis]+extent[axis])
            end
        end
        local center,extent={},{}
        for _,axis in ipairs({'X','Y','Z'}) do center[axis]=(min[axis]+max[axis])/2;extent[axis]=(max[axis]-min[axis])/2 end
        local radius=math.sqrt(extent.X^2+extent.Y^2+extent.Z^2)
        assert(radius>0.001 and radius<100000,'Thumbnail bounds unavailable')
        local basis=pcl151747_preview_basis(root,anchor)
        local forward,right,up=root:GetActorForwardVector(),root:GetActorRightVector(),root:GetActorUpVector()
        if basis then
            forward,up=pcl151751_view_axes(basis) -- match this anchor's selected camera face
        end
        local position={}
        for _,axis in ipairs({'X','Y','Z'}) do
            position[axis]=center[axis]+radius*3*(basis and forward[axis] or (0.25*forward[axis]-right[axis]+0.55*up[axis]))
        end
        local mathlib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary')
        local rendering=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
        local class=StaticFindObject('/Script/Engine.SceneCapture2D')
        assert(is_valid(mathlib) and is_valid(rendering) and is_valid(class),'Thumbnail renderer unavailable')
        local transform=neutral_spawn_transform_153()
        transform.Translation=position
        local gameplay=gameplay_statics_15()
        camera=gameplay:BeginDeferredActorSpawnFromClass(root,class,transform,1,nil,2)
        pcl151731_fresh(camera)
        assert(is_valid(camera),'Thumbnail camera allocation failed')
        local component=camera.CaptureComponent2D
        assert(is_valid(component),'Thumbnail capture component unavailable')
        component.bCaptureEveryFrame=false;component.bCaptureOnMovement=false
        camera=gameplay:FinishSpawningActor(camera,transform,2)
        assert(is_valid(camera),'Thumbnail camera initialization failed')
        local view_rotation
        if basis then
            view_rotation=mathlib:MakeRotFromXZ({X=-forward.X,Y=-forward.Y,Z=-forward.Z},up)
        else view_rotation=mathlib:FindLookAtRotation(position,center) end
        camera:K2_SetActorRotation(view_rotation,true)
        component=camera.CaptureComponent2D
        local target=rendering:CreateRenderTarget2D(root,512,512,2,{R=0.025,G=0.023,B=0.018,A=1},false,false)
        assert(is_valid(target),'Thumbnail render target allocation failed')
        component.TextureTarget=target;component.ProjectionType=1;component.OrthoWidth=radius*2.05
        component.PrimitiveRenderMode=2;component.CaptureSource=2
        component.bCaptureEveryFrame=false;component.bCaptureOnMovement=false
        pcl151748_preview_lights(camera,component,radius)
        for _,actor in ipairs(nodes) do component:ShowOnlyActorComponents(actor,false) end
        component:CaptureScene()
        assert(pcl151736_has_image(rendering,root,target,mathlib,position,center,radius,nodes,view_rotation),'Empty thumbnail capture; existing preview kept')
        local path=pcl151733_photo_path(code)
        local directory,filename=path:match('^(.*[\\/])([^\\/]+)$')
        assert(directory and filename,'Thumbnail directory unavailable')
        rendering:ExportRenderTarget(root,target,directory,filename..'.tmp.png')
        pcl151733_promote_photo(path..'.tmp.png',path)
        local state=PCL151710_MENU_STATE
        if state and is_valid(state.panel) then pcl151727_load_preview(code,state.panel) end
        PCL151730_PREVIEW_CHECKED[code]=nil
        log('PCL15_17_33_PREVIEW_CAPTURED code='..code..' parts='..#nodes..' size=512 view='..(basis and 'anchor_minus_x_hardpoint_up' or 'local_oblique')..' lighting=key_fill continuous=false')
    end)
    if is_valid(camera) then pcall(function() camera:K2_DestroyActor() end) end
    if not ok then log('PCL15_17_33_PREVIEW_CAPTURE_FAILED code='..code..' '..tostring(err)) end
    return ok
end
function pcl151733_copy_photo(from,to)
    local ok,err=pcall(function()
        local source=io.open(pcl151733_photo_path(from),'rb')
        if not source then return end
        local bytes=source:read('*a');source:close()
        local path=pcl151733_photo_path(to)
        local dest=assert(io.open(path..'.tmp.png','wb'))
        assert(dest:write(bytes));assert(dest:close())
        pcl151733_promote_photo(path..'.tmp.png',path)
    end)
    if not ok then log('PCL15_17_33_PREVIEW_COPY_FAILED '..tostring(err)) end
end

-- Retire temp helper components with one shared, bounded queue. Native actors
-- remain referenced for lifecycle safety. Real sword parts are excluded by
-- pcl151730_hide_helper; no player Forge object is ever queued deliberately.
PCL151732_HELPER_QUEUE={items={},head=1,seen={},scheduled=false}
function pcl151732_queue_helper(host,actor)
    if not is_valid(host) or not is_valid(actor) then return end
    local queue=PCL151732_HELPER_QUEUE
    local address=actor:GetAddress()
    if queue.seen[address] then return end
    queue.seen[address]=true
    queue.items[#queue.items+1]={host=host,actor=actor}
    if not queue.scheduled then
        queue.scheduled=true
        pcl15179_schedule(1,pcl151732_helper_tick)
    end
end
function pcl151732_helper_tick()
    local queue=PCL151732_HELPER_QUEUE
    local active=find_forge()
    local protected=pcl151758_active_helpers(active)
    local deadline=os.clock()+0.003
    local processed=0
    while queue.head<=#queue.items and processed<16 and (processed==0 or os.clock()<deadline) do
        local entry=queue.items[queue.head]
        queue.head=queue.head+1;processed=processed+1
        if is_valid(active) and is_valid(entry.host) and entry.host:GetAddress()~=active:GetAddress() and is_valid(entry.actor) then
            local ok,err=pcall(pcl151730_hide_helper,entry.actor,protected)
            if not ok then log('PCL15_17_32_HELPER_RETIRE_FAILED '..tostring(err)) end
        end
    end
    if queue.head<=#queue.items then pcl15179_schedule(1,pcl151732_helper_tick)
    else
        local count=#queue.items
        queue.items={};queue.head=1;queue.seen={};queue.scheduled=false
        log('PCL15_17_32_HELPER_COMPONENTS_RETIRED actors='..count)
    end
end

-- 15.17.31: fresh allocations must not inherit a previous object's path or
-- serial when Unreal recycles its address (including within one callback).
function pcl151731_fresh(obj)
    if obj==nil then return end
    local ok,address=pcall(function() return obj:GetAddress() end)
    if not ok or not address or address==0 then return end
    PCL151714_OBJECT_PATHS[obj]=nil
    if PCL151715_VALIDATION_CACHE then PCL151715_VALIDATION_CACHE[obj]=nil end
    if PCL151731_SERIALS then PCL151731_SERIALS[obj]=nil end
end

-- Validate the actual restored tree without spending seconds in one callback.
-- The backup survives every failed, interrupted or superseded verification.
function pcl151731_verify_recovery(request)
    PCL151731_RECOVERY=request
    local stack={{actor=request.root,depth=1}}
    local seen,count={},0
    local started=os.clock()
    local function step()
        if PCL151731_RECOVERY~=request then return end
        local ok,err=pcall(function()
            local _,held=current_preview_14()
            local forge=find_forge()
            assert(is_valid(held) and is_valid(request.anchor) and held:GetAddress()==request.anchor:GetAddress(),'Hand changed during recovery verification')
            assert(is_valid(forge) and forge:GetAddress()==request.forge:GetAddress(),'Forge changed during recovery verification')
            assert(request.anchor.bHidden==false or request.anchor.bHidden==0,'Anchor is hidden')
            local connected=pcl151112_first_slot_child(request.anchor)
            assert(is_valid(connected) and is_valid(request.root) and connected:GetAddress()==request.root:GetAddress(),'Restored root detached from its anchor')
            local budget=os.clock()+0.003
            local processed=0
            while #stack>0 and processed<16 and (processed==0 or os.clock()<budget) do
                local entry=table.remove(stack)
                local actor=entry.actor
                assert(is_valid(actor) and entry.depth<=128,'Restored attachment is unavailable')
                local address=actor:GetAddress()
                assert(not seen[address] and count<6000,'Duplicate or oversized restored tree')
                assert(actor.bHidden==false or actor.bHidden==0,'Restored part is hidden')
                seen[address]=true;count=count+1;processed=processed+1
                local function push(child)
                    child=pcl15171_unwrap(child)
                    if is_valid(child) then stack[#stack+1]={actor=child,depth=entry.depth+1} end
                end
                actor.SlotChildParts:ForEach(function(_,value) push(value) end)
                actor.FreeChildParts:ForEach(function(key,_) push(key) end)
            end
        end)
        if not ok then
            PCL151731_RECOVERY=nil
            pcl151719_status('Recovery backup kept: '..tostring(err))
            return
        end
        if #stack>0 then pcl15179_schedule(1,step);return end
        PCL151731_RECOVERY=nil
        if count~=request.restore_upload.parts then
            pcl151719_status('Recovery backup kept: restored part count differs.')
            return
        end
        pcl151727_forget_draft(request.restore_upload)
        log('PCL15_17_31_DRAFT_RESTORED verified_parts='..count..' held=true visible=true seconds='..string.format('%.3f',os.clock()-started))
    end
    pcl15179_schedule(1,step)
end

-- 15.17.26: cache one native FPieceSaveData per Magic Word, including Name.
function pcl151726_bridge()
    if PCL151726_BRIDGE then return PCL151726_BRIDGE end
    local bridge={}
    for _,key in ipairs({'probe','store','restore','rebuild','lines','valid','copy_word'}) do
        local fn,err=BMF_PCL_NATIVE(pcl151112_script_dir()..'pcl_local_cache_151733.dll','pcl_cache_'..key)
        assert(type(fn)=='function',tostring(err));bridge[key]=fn
    end
    assert(bridge.probe()==1,'Local cache bridge refused this executable')
    PCL151726_BRIDGE=bridge
    PCL151731_SERIALS=PCL151731_SERIALS or setmetatable({},{__mode='k'})
    PCL151731_VALIDATOR=bridge.valid
    return bridge
end
function pcl151726_slot(code)
    assert(type(code)=='string' and code:match('^[%a]+%-[%a]+%-[%a]+$'),'Invalid cache Magic Word')
    return 'PCL26_'..code:lower()
end
function pcl151726_save(code,piece)
    local ok,err=pcall(function()
        assert(is_valid(piece),'Build data unavailable for local save')
        local statics=gameplay_statics_15()
        local class=StaticFindObject('/Script/Bladesong.CreativeModeSave')
        assert(is_valid(statics) and is_valid(class),'Native local save service unavailable')
        local save=statics:CreateSaveGameObject(class)
        assert(is_valid(save),'Could not create local build file')
        local status=pcl151726_bridge().store(save:GetAddress(),piece:GetAddress(),class:GetAddress(),piece:GetClass():GetAddress())
        assert(status==1,'Local build serialization refused ('..tostring(status)..')')
        assert(statics:SaveGameToSlot(save,pcl151726_slot(code),0),'Could not write local build file')
        local check=statics:LoadGameFromSlot(pcl151726_slot(code),0)
        assert(is_valid(check) and check:GetClass():GetAddress()==class:GetAddress() and #check.Pieces==1,'Local build readback failed')
        local native_name=''
        check.Pieces:ForEach(function(_,value)
            local entry=value:get()
            native_name=pcl15171_from_text(entry.Name)
            assert(#entry.WeaponDesignDefinition.AppliedSwordParts==#piece.WeaponDesignDefinition.AppliedSwordParts,'Local build readback part count differs')
        end)
        assert(native_name==pcl15171_from_text(piece:GetRawPieceName()),'Local build readback name differs')
        if PCL151730_PREVIEW_CHECKED then PCL151730_PREVIEW_CHECKED[code]=nil end
        log('PCL15_17_26_CACHE_SAVED code='..code..' parts='..tostring(#piece.WeaponDesignDefinition.AppliedSwordParts)..' native_name='..native_name)
    end)
    return ok,not ok and tostring(err) or nil
end
function pcl151726_has_cache(code)
    local ok,exists=pcall(function()
        return gameplay_statics_15():DoesSaveGameExist(pcl151726_slot(code),0)
    end)
    return ok and exists==true
end
function pcl151726_restore(request,before)
    local statics=gameplay_statics_15()
    local class=StaticFindObject('/Script/Bladesong.CreativeModeSave')
    local save=statics:LoadGameFromSlot(pcl151726_slot(request.code),0)
    assert(is_valid(save) and is_valid(class) and save:GetClass():GetAddress()==class:GetAddress(),'Local build file unavailable or incompatible')
    local piece=StaticConstructObject(before:GetClass(),request.temp)
    pcl151731_fresh(piece)
    assert(is_valid(piece),'Could not create local build data')
    request.temp.Piece=piece
    local bridge=pcl151726_bridge()
    local status=bridge.restore(save:GetAddress(),piece:GetAddress(),class:GetAddress(),before:GetClass():GetAddress())
    assert(status==1,'Local build restoration refused ('..tostring(status)..')')
    local saved_name=''
    save.Pieces:ForEach(function(_,value) saved_name=pcl15171_from_text(value:get().Name) end)
    piece.Name=pcl15171_to_text(saved_name)
    local used=false
    request.bridge={rebuild=function(host_addr,piece_addr)
        if used then return -36 end
        used=true
        return bridge.rebuild(host_addr,piece_addr,request.forge:GetAddress(),request.gm:GetAddress())
    end}
    local metadata=PCL151724_META[request.code]
    local preview=PCL151724_PREVIEWS[request.code]
    if not request.skip_metadata and
        (not metadata or not metadata.original or not preview or not is_valid(preview.texture)) then
        pcl151724_capture_metadata(request)
    end
    log('PCL15_17_26_CACHE_HIT code='..request.code..' parts='..tostring(#piece.WeaponDesignDefinition.AppliedSwordParts)..' http=false')
end


function pcl151726_clear_uploaded_hand(request)
    local handling,held=current_preview_14()
    if not is_valid(handling) or not is_valid(held) or not is_valid(request.held) or held:GetAddress()~=request.held:GetAddress() then
        return false,'The hand changed; the current item was kept.'
    end
    local _,_,root,nodes=pcl151725_held_tree()
    if root:GetAddress()~=request.root:GetAddress() or #nodes~=#request.nodes then return false,'The held build changed; it was kept.' end
    for i,actor in ipairs(nodes) do
        if actor:GetAddress()~=request.nodes[i]:GetAddress() then return false,'The held build changed; it was kept.' end
    end
    local cleared,err=clear_preview_pointer_14()
    if not cleared then return false,tostring(err) end
    -- Remove only the exact held tree that was serialized and saved above.
    -- Clear handling references before destruction; never touch placed Forge parts.
    if is_valid(handling.ActorPreviewMaterialSetLastFrame) and handling.ActorPreviewMaterialSetLastFrame:GetAddress()==held:GetAddress() then
        handling.ActorPreviewMaterialSetLastFrame=nil
    end
    if is_valid(handling.InteractingSwordPartActor) and handling.InteractingSwordPartActor:GetAddress()==held:GetAddress() then
        handling.InteractingSwordPartActor=nil
    end
    pcl151113_set_tree_hidden(held,true)
    if request.keep_anchor_shell and pcl15167_is_exact_anchor_actor(held) then
        local detached,detach_err=detach_live_actor_14(root)
        assert(detached,tostring(detach_err))
        held.SlotChildParts:Remove(0)
        held.FreeChildParts:Remove(root)
        held:SetActorEnableCollision(false);held:SetActorTickEnabled(false)
        request.anchor_shell=held
    end
    for i=#nodes,1,-1 do nodes[i]:K2_DestroyActor() end
    if held:GetAddress()~=root:GetAddress() and is_valid(held) and not request.anchor_shell then held:K2_DestroyActor() end
    log('PCL15_17_26_UPLOAD_HAND_CLEARED parts='..tostring(#nodes))
    return true
end

function pcl151727_preview_path(code)
    pcl151726_slot(code) -- validate before using a Magic Word in a filename
    return PCL15171_LIBRARY_DIR..'preview_'..code..'.png'
end
function pcl151727_preview_file(path)
    local file=io.open(path,'rb')
    if not file then return false end
    local signature=file:read(8);local size=file:seek('end');file:close()
    return signature=='\137PNG\13\10\26\10' and size and size>32
end
function pcl151727_save_preview(code,texture,owner)
    local ok,err=pcall(function()
        local path=pcl151727_preview_path(code)
        if pcl151727_preview_file(path) then return end
        assert(is_valid(texture),'No preview texture to save')
        local writer=StaticFindObject('/Script/ImageWriteQueue.Default__ImageWriteBlueprintLibrary')
        assert(is_valid(writer),'Native PNG writer unavailable')
        local temporary=path..'.tmp.png'
        writer:ExportToDisk(texture,temporary,{Format=0,CompressionQuality=100,bOverwriteFile=true,bAsync=false})
        assert(pcl151727_preview_file(temporary),'Preview PNG was not written')
        local promoted,promote_err=os.rename(temporary,path)
        assert(promoted,tostring(promote_err))
        log('PCL15_17_27_PREVIEW_PNG_SAVED code='..code)
    end)
    if not ok then log('PCL15_17_27_PREVIEW_PNG_FAILED code='..code..' '..tostring(err)) end
    return ok
end
function pcl151727_load_preview(code,panel)
    local path=pcl151733_photo_path(code)
    if not pcl151727_preview_file(path) then path=PCL15171_LIBRARY_DIR..'preview_v33_'..code..'.png' end
    if not pcl151727_preview_file(path) then path=pcl151727_preview_path(code) end
    if not pcl151727_preview_file(path) then return false end
    local rendering=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
    assert(is_valid(rendering),'Native PNG importer unavailable')
    local texture=rendering:ImportFileAsTexture2D(panel,path)
    assert(is_valid(texture),'Could not reload preview PNG')
    PCL151724_PREVIEWS[code]={owner=panel,texture=texture}
    log('PCL15_17_27_PREVIEW_PNG_LOADED code='..code..' http=false actors_built=0')
    return true
end

function pcl151728_recovery_anchor(request)
    local draft=request.restore_upload
    if draft and is_valid(draft.anchor_shell) then
        log('PCL15_17_28_ANCHOR_SHELL_REUSED')
        return draft.anchor_shell,nil
    end
    local anchor,err=pcl151728_spawn_anchor(request)
    if not is_valid(anchor) then return nil,err end
    draft.anchor_shell=anchor
    log('PCL15_17_28_RECOVERY_ANCHOR_SPAWNED catalogue_click=false')
    return anchor,nil
end

function pcl151742_discard_spawn(request)
    if not request or not is_valid(request.anchor) then return end
    local anchor=request.anchor
    request.anchor=nil
    pcall(function()
        local handling=request.handling
        if is_valid(handling) and is_valid(handling.PreviewSwordPartActor)
            and handling.PreviewSwordPartActor:GetAddress()==anchor:GetAddress() then
            handling.PreviewSwordPartActor=nil
        end
    end)
    pcall(function() anchor:K2_DestroyActor() end)
end

function pcl151728_spawn_anchor(request)
    -- A recovery after restart has no live shell. Spawn the existing cooked
    -- anchor Blueprint directly; do not depend on catalogue selection/filter.
    local ok,actor=pcall(function()
        assert(pcl15170_load_assets(),'Anchor assets unavailable')
        local exact,err=pcl15165_exact_row(PCL15165_DEV_TABLE_FULL,PCL15161_ROW_NAME)
        assert(exact and is_valid(exact.data_table),tostring(err))
        local gameplay=gameplay_statics_15()
        local transform=neutral_spawn_transform_153()
        local deferred=gameplay:BeginDeferredActorSpawnFromClass(request.forge,PCL15170_CUSTOM_BP_CLASS,transform,1,nil,2)
        assert(is_valid(deferred),'Could not allocate recovery anchor')
        request.anchor=deferred
        deferred:SetActorHiddenInGame(true);deferred:SetActorEnableCollision(false)
        deferred.SwordPartDataHandle.DataTable=exact.data_table
        deferred.SwordPartDataHandle.RowName=pcl15170_existing_fname(PCL15161_ROW_NAME)
        deferred.Scale=1;deferred.bPending=true
        deferred.Deflection.X=0;deferred.Deflection.Y=0;deferred.Deflection.Z=0;deferred.Deflection.W=1
        local anchor=gameplay:FinishSpawningActor(deferred,transform,2)
        if is_valid(anchor) then request.anchor=anchor end
        assert(is_valid(anchor) and pcl15167_is_exact_anchor_actor(anchor),'Recovery anchor identity mismatch')
        local applied,apply_err=pcl15170_apply_mesh_to_actor(anchor)
        assert(applied,tostring(apply_err))
        anchor:SetActorHiddenInGame(true)
        request.anchor=anchor
        return anchor
    end)
    if not ok then
        pcl151742_discard_spawn(request)
        return nil,tostring(actor)
    end
    return actor,nil
end
function pcl151728_suspend_form(panel,message)
    local state=is_valid(panel) and PCL151723_UI[panel:GetAddress()]
    local draft=pcl151727_draft()
    if draft then draft.suspended=true end
    if state then
        state.upload_held=nil
        state.controls.PCL_AuthorBorder:SetVisibility(1)
        pcl15171_set_magic_visible(panel,false)
        pcl15171_refresh_dynamic(panel)
        pcl15171_set_status(panel,message or 'Temporary build kept. Reopen the library after restarting to recover it.')
    end
end

PCL151729_HANDOFF=nil
function pcl151729_release_tick()
    local request=PCL151729_HANDOFF
    if not request then return end
    request.ticks=request.ticks+1
    local ok,err=pcall(function()
        assert(is_valid(request.anchor) and is_valid(request.root),'Restored actors unavailable')
        assert(pcl151112_addr(find_forge())==pcl151112_addr(request.forge),'Forge changed during Cancel')
        local handling,held=current_preview_14()
        assert(is_valid(handling) and not is_valid(held),'Another part entered the hand')
        local menu=PCL151710_MENU_STATE
        local player=menu and is_valid(menu.catalogue) and menu.catalogue:GetOwningPlayer()
        assert(is_valid(player),'Player input state unavailable')
        local mouse=pcl15170_existing_fname('LeftMouseButton')
        assert(mouse,'Mouse key unavailable')
        local down=player:IsInputKeyDown({KeyName=mouse})
        request.released=down and 0 or request.released+1
        if request.released<3 then
            assert(request.ticks<200,'Cancel click is still held; backup kept')
            pcl15179_schedule(50,pcl151729_release_tick)
            return
        end
        -- Input mode and mouse-up have settled on separate frames after the
        -- expensive reconstruction. Only now give the preview to the player.
        handling.BestSwordPartSlotParent=nil
        handling.PreviewSwordPartActor=request.anchor
        local _,assigned=current_preview_14()
        assert(pcl151112_addr(assigned)==pcl151112_addr(request.anchor),'Hand assignment did not persist')
        pcl151113_set_tree_hidden(request.root,false)
        local _,_,restored_root,restored_nodes=pcl151725_held_tree()
        assert(restored_root:GetAddress()==request.root:GetAddress(),'Restored root differs')
        local restored_count=#restored_nodes
        request.anchor:SetActorHiddenInGame(false)
        request.anchor:SetActorEnableCollision(true);request.anchor:SetActorTickEnabled(true)
        local _,visible_hand=current_preview_14()
        assert(is_valid(visible_hand) and visible_hand:GetAddress()==request.anchor:GetAddress(),'Restored hand changed')
        assert(restored_count==request.restore_upload.parts,'Restored part count differs; backup kept')
        assert(request.root.bHidden==false or request.root.bHidden==0,'Restored root is hidden')
        -- The synchronous unhide walk already visited the actual restored tree.
        -- Commit cleanup now, before the player can place it on a later frame.
        local cleaned,cleanup_err=pcl151727_forget_draft(request.restore_upload)
        assert(cleaned,tostring(cleanup_err))
        log('PCL15_17_35_CANCEL_COMPLETE held=true verified_parts='..restored_count..' temp_deleted=true')
        PCL151719_VERIFY={forge=request.forge,active_sentinel=request.active_sentinel,anchor=request.anchor,root=request.root,checks=0}
        PCL151729_HANDOFF=nil
        pcl15179_schedule(100,pcl151719_verify)
        log('PCL15_17_29_CANCEL_HANDOFF mouse_released=true placed_by_mod=false')
    end)
    if not ok then
        PCL151729_HANDOFF=nil
        pcl151719_status('Cancel recovery stopped; temporary copy kept: '..tostring(err))
    end
end
function pcl151729_archive_draft(draft)
    if not draft then return end
    local file,err=io.open(PCL15171_LIBRARY_DIR..'upload_drafts.archive','a')
    assert(file,tostring(err))
    assert(file:write(draft.code..'\n'));assert(file:close())
    -- The older native save remains on disk; it is not the current hand.
    log('PCL15_17_29_OLDER_DRAFT_PRESERVED code='..draft.code)
end

PCL151727_DRAFT=nil
PCL151727_PREVIEW_QUEUE=nil
function pcl151727_manifest()
    return PCL15171_LIBRARY_DIR..'upload_draft.index'
end
function pcl151727_draft()
    if PCL151727_DRAFT then return PCL151727_DRAFT end
    local file=io.open(pcl151727_manifest(),'r')
    if not file then return nil end
    local code=file:read('*l');file:close()
    if code and code:match('^draft%-%a+%-%a+$') and pcl151726_has_cache(code) then
        PCL151727_DRAFT={code=code,detached=true,recovered=true}
    end
    return PCL151727_DRAFT
end
function pcl151727_forget_draft(draft)
    if PCL151727_DRAFT~=draft then return false,'Recovery draft changed' end
    -- Delete the native payload first and verify it is gone. Keep the manifest
    -- on any failure so a successful handoff cannot hide a cleanup failure.
    local removed,remove_err=pcall(function()
        local statics=gameplay_statics_15()
        local slot=pcl151726_slot(draft.code)
        if statics:DoesSaveGameExist(slot,0) then
            assert(statics:DeleteGameInSlot(slot,0),'Temporary save deletion failed')
        end
        assert(not statics:DoesSaveGameExist(slot,0),'Temporary save still exists')
        if draft.code:match('^draft%-') then
            for _,prefix in ipairs({'preview_v36_','preview_v35_','preview_v34_','preview_v33_','preview_'}) do
                local base=PCL15171_LIBRARY_DIR..prefix..draft.code..'.png'
                for _,suffix in ipairs({'','.tmp.png','.bak'}) do
                    local path=base..suffix
                    local file=io.open(path,'rb')
                    if file then file:close();assert(os.remove(path),'Temporary preview deletion failed') end
                end
            end
        end
        local manifest=io.open(pcl151727_manifest(),'r')
        if manifest then manifest:close();assert(os.remove(pcl151727_manifest()),'Temporary manifest deletion failed') end
    end)
    if not removed then log('PCL15_17_35_TEMP_CLEANUP_FAILED '..tostring(remove_err));return false,remove_err end
    if draft.code and draft.code:match('^draft%-') then
        os.remove(pcl151733_photo_path(draft.code))
        PCL151724_PREVIEWS[draft.code]=nil
    end
    if is_valid(draft.anchor_shell) then
        local _,held=current_preview_14()
        if not is_valid(held) or held:GetAddress()~=draft.anchor_shell:GetAddress() then draft.anchor_shell:K2_DestroyActor() end
    end
    PCL151727_DRAFT=nil
    local menu=PCL151710_MENU_STATE
    local state=menu and is_valid(menu.panel) and PCL151723_UI[menu.panel:GetAddress()]
    if state then state.upload_held=nil;state.controls.PCL_AuthorBorder:SetVisibility(1);pcl15171_set_magic_visible(menu.panel,false) end
    return true
end
function pcl151727_show_form(panel,draft)
    local state=PCL151723_UI[panel:GetAddress()]
    assert(state,'Library menu unavailable')
    if state.upload_held~=draft then
        state.rename_code=nil;state.upload_held=draft
        state.controls.PCL_MagicWordTitle:SetText(pcl15171_to_text('Name and upload build'))
        state.controls.PCL_MagicWordInput:SetHintText(pcl15171_to_text('Build name'))
        state.controls.PCL_MagicWordInput:SetText(pcl15171_to_text(draft.build_name or ''))
        state.controls.PCL_AuthorInput:SetText(pcl15171_to_text(draft.author or PCL151726_AUTHOR or ''))
        state.controls.PCL_AuthorBorder:SetVisibility(0)
    end
    state.controls.PCL_SubmitButton:SetCaption(pcl15171_to_text(draft.upload_code and 'Save uploaded build' or 'Upload build'))
    pcl15171_set_magic_visible(panel,true)
end
function pcl151727_materialize(draft)
    local forge=find_forge()
    assert(is_valid(forge),'Open the Forge to resume the temporary build.')
    if not is_valid(draft.host) or not is_valid(draft.piece) then
        local before=forge:GetPiece()
        local host,gm,err=pcl151113_spawn_temp_forge(forge,before)
        assert(is_valid(host),tostring(err))
        PCL151725_UPLOAD_HOSTS[#PCL151725_UPLOAD_HOSTS+1]=host
        local request={temp=host,forge=forge,gm=gm,code=draft.code,skip_metadata=true}
        pcl151726_restore(request,before)
        draft.host=host;draft.piece=host:GetPiece();draft.parts=#draft.piece.WeaponDesignDefinition.AppliedSwordParts
    end
    draft.forge=forge;draft.ui=pcl151723_references()
    assert(is_valid(draft.ui),'Active Forge UI unavailable')
    return draft
end
function pcl151726_prompt_upload(panel)
    if PCL151725_UPLOAD_PENDING then pcl151725_upload_status('An upload is already pending.',true);return end
    local ok,err=pcall(function()
        assert(not PCL151729_HANDOFF,'A Cancel handoff is finishing')
        local draft=pcl151727_draft()
        local previous=draft
        local _,current_held=current_preview_14()
        if is_valid(current_held) then
            draft=pcl151725_snapshot_held('Temporary preconstruction')
            -- Letters keep the existing cache-slot validator and path rules.
            local stamp=tostring(os.time())..tostring(math.floor(os.clock()*1000000))
            stamp=stamp:gsub('%d',function(c)return string.char(97+tonumber(c)) end)
            draft.code='draft-'..stamp..'-held'
            local saved,save_err=pcl151726_save(draft.code,draft.piece)
            assert(saved,'Temporary save failed; hand kept: '..tostring(save_err))
            pcl151729_archive_draft(previous)
            pcl15171_ensure_library_dir()
            local file,open_err=io.open(pcl151727_manifest(),'w')
            assert(file,'Temporary recovery record failed; hand kept: '..tostring(open_err))
            assert(file:write(draft.code..'\n'));assert(file:close())
            PCL151727_DRAFT=draft
            draft.keep_anchor_shell=true
            pcl151733_capture(draft.code,draft.root,draft.nodes,draft.held)
            local cleared,clear_err=pcl151726_clear_uploaded_hand(draft)
            if not cleared then
                pcl151727_forget_draft(draft)
                error('Could not clear held build: '..tostring(clear_err))
            end
            draft.detached=true;draft.nodes=nil;draft.held=nil;draft.root=nil
            log('PCL15_17_27_DRAFT_CLEARED code='..draft.code..' parts='..tostring(draft.parts)..' disk_verified=true form_open=false')
        end
        assert(draft,'Hold a build before clicking the upload ribbon.')
        pcl151710_set_menu_visible(true)
        pcl151727_show_form(panel,draft)
        pcl15171_set_status(panel,'Build saved temporarily; hand cleared. Enter build name and your name, or Cancel to return it to your hand.')
        PCL151723_UI[panel:GetAddress()].controls.PCL_MagicWordInput:SetKeyboardFocus()
    end)
    if not ok then pcl151725_upload_status(tostring(err),true) end
end
function pcl151727_restore_draft(panel)
    if PCL151741_BATCH then return pcl151741_cancel_batch(panel) end
    local draft=pcl151727_draft()
    if not draft then return false end
    if PCL151725_UPLOAD_PENDING then
        pcl151728_suspend_form(panel,'Upload is still running. You can close this menu; the backup is kept.');return true
    end
    if PCL151719_IMPORT then pcl151728_suspend_form(panel,'A build is already loading. The backup is kept.');return true end
    local _,held=current_preview_14()
    if is_valid(held) then pcl151728_suspend_form(panel,'Finish the current held part first; the backup is kept.');return true end
    local ok,err=pcl15171_download_magic(panel,draft.code)
    if not ok then pcl151728_suspend_form(panel,'Temporary build kept: '..tostring(err));return true end
    PCL151719_IMPORT.restore_upload=draft
    PCL151719_IMPORT.skip_metadata=true
    pcl151728_suspend_form(panel,'Returning temporary build to your hand...')
    return true
end
function pcl151726_submit_upload(panel)
    local state=is_valid(panel) and PCL151723_UI[panel:GetAddress()]
    local draft=state and state.upload_held
    if not draft then return false end
    if PCL151725_UPLOAD_PENDING then pcl15171_set_status(panel,'Upload is still pending.');return true end
    local name=pcl15171_trim(pcl15171_from_text(state.controls.PCL_MagicWordInput:GetText())):gsub('[%z\1-\31\127]','')
    local author=pcl15171_trim(pcl15171_from_text(state.controls.PCL_AuthorInput:GetText())):gsub('[%z\1-\31\127]','')
    if name=='' or author=='' then pcl15171_set_status(panel,'Both the build name and your name are required.');if draft.batch then pcl151741_message(panel,'Enter both the build name and your name.') end;return true end
    if #name+#author+4>160 then pcl15171_set_status(panel,'Use shorter names (160 UTF-8 bytes combined).');if draft.batch then pcl151741_message(panel,'Use shorter names (160 UTF-8 bytes combined).') end;return true end
    draft.build_name=name;draft.author=author;PCL151726_AUTHOR=author
    pcl151725_upload_held(name..' by '..author)
    return true
end
function pcl151727_complete_upload(draft,code)
    draft.upload_code=code
    local saved,err=pcl151726_save(code,draft.piece)
    if not saved then
        pcl151725_upload_status('Uploaded: '..code..' | Permanent save failed; temporary build kept. Retry save or Cancel: '..tostring(err),true)
        return false
    end
    local indexed,index_err=pcl15171_add_code(code)
    if not indexed then pcl151725_upload_status('Uploaded: '..code..' | Temporary build kept; library save failed: '..tostring(index_err),true);return false end
    PCL151724_META[code]={original=draft.name,custom=''};pcl151724_save_metadata()
    local name=draft.name
    pcl151733_copy_photo(draft.code,code)
    local cleaned,cleanup_err=pcl151727_forget_draft(draft)
    if not cleaned then
        pcl151725_upload_status('Uploaded and saved: '..code..' | Temporary cleanup failed: '..tostring(cleanup_err),true)
        return false
    end
    pcl151725_upload_status('Uploaded and saved locally: '..name..' | Magic Word: '..code,true)
    if draft.batch then pcl151741_batch_completed(draft,code) end
    return true
end
function pcl151725_upload_held(chosen_name)
    if PCL151725_UPLOAD_PENDING then return false end
    local ok,err=pcall(function()
        local draft=assert(pcl151727_draft(),'Temporary upload build unavailable')
        pcl151727_materialize(draft)
        -- A successful network upload with a disk/index failure retries only
        -- local finalization, never submits the same payload a second time.
        if draft.upload_code then
            if not pcl151727_complete_upload(draft,draft.upload_code) and draft.batch then pcl151741_batch_error(draft,'Uploaded, but the local save is incomplete. Retry save or Cancel.') end
            return
        end
        if draft.batch then pcl151741_message(draft.batch.panel,'Uploading '..draft.batch.index..' of '..#draft.batch.items..'...') end
        draft.name=chosen_name;draft.piece.Name=pcl15171_to_text(chosen_name)
        local saved,save_err=pcl151726_save(draft.code,draft.piece)
        assert(saved,'Temporary name save failed: '..tostring(save_err))
        pcl151725_upload_hooks(draft.ui)
        draft.started=os.clock();draft.warned=false;PCL151725_UPLOAD_PENDING=draft
        pcl15179_schedule(5000,function() pcl151741_upload_watchdog(draft) end)
        local sent=pcl151725_bridge().send(draft.ui:GetAddress(),draft.forge:GetAddress(),draft.host:GetAddress(),draft.piece:GetAddress())
        if sent~=1 then PCL151725_UPLOAD_PENDING=nil;error('Upload start refused ('..tostring(sent)..')') end
        pcl15171_set_magic_visible(PCL151710_MENU_STATE.panel,false)
        pcl151725_upload_status(draft.blade and 'Uploading blade. Your current build stays unchanged.' or ('Uploading '..tostring(draft.parts)..' parts. Temporary build retained; hand stays clear.'),false)
    end)
    if not ok then pcl151725_upload_status('Upload stopped; temporary build kept: '..tostring(err),true);if PCL151741_BATCH then pcl151741_batch_error(pcl151727_draft(),'Upload stopped: '..tostring(err)) end end
    return ok
end
function pcl151727_queue_previews(panel)
    if PCL151727_PREVIEW_QUEUE then return end
    local queue={panel=panel,codes={},index=0,forge=pcl151112_addr(find_forge())}
    for _,code in ipairs(PCL15171_LIBRARY) do
        local preview=PCL151724_PREVIEWS[code]
        if PCL151730_PREVIEW_CHECKED[code]~=panel:GetAddress() and (not preview or not is_valid(preview.texture)) and (pcl151727_preview_file(pcl151733_photo_path(code)) or pcl151727_preview_file(PCL15171_LIBRARY_DIR..'preview_v33_'..code..'.png') or pcl151727_preview_file(pcl151727_preview_path(code)) or pcl151726_has_cache(code)) then queue.codes[#queue.codes+1]=code end
    end
    if #queue.codes==0 then return end
    PCL151727_PREVIEW_QUEUE=queue
    pcl15179_schedule(100,pcl151727_preview_tick)
end
function pcl151727_preview_tick()
    local queue=PCL151727_PREVIEW_QUEUE
    if not queue then return end
    local menu=PCL151710_MENU_STATE
    if not menu or not is_valid(menu.panel) or not is_valid(queue.panel) or menu.panel:GetAddress()~=queue.panel:GetAddress() or
       not PCL15177_FORGE_ACTIVE or pcl151112_addr(find_forge())~=queue.forge then PCL151727_PREVIEW_QUEUE=nil;return end
    queue.index=queue.index+1
    local code=queue.codes[queue.index]
    if not code then PCL151727_PREVIEW_QUEUE=nil;return end
    PCL151730_PREVIEW_CHECKED[code]=queue.panel:GetAddress()
    local ok,err=pcall(function()
        if not pcl151727_load_preview(code,queue.panel) then pcl151730_preview_from_save(code,queue.panel) end
        local preview=PCL151724_PREVIEWS[code]
        if preview and is_valid(preview.texture) then pcl15171_refresh_dynamic(queue.panel) end
    end)
    if not ok then log('PCL15_17_30_PREVIEW_UNAVAILABLE '..tostring(err)) end
    pcl15179_schedule(100,pcl151727_preview_tick)
end

PCL151730_PREVIEW_CHECKED={}
PCL151730_HOST_REGISTRY=PCL151730_HOST_REGISTRY or {}
function pcl151730_field(object,name)
    if not is_valid(object) then return nil end
    local ok,value=pcall(function()return object[name]end)
    return ok and value or nil
end
PCL151730_QUARANTINES={}
function pcl151730_extra_line_ids(interaction,host,frontend)
    if not is_valid(interaction) then return {} end
    local class=StaticFindObject('/Script/Bladesong.BladeInteractionComponent')
    if not is_valid(class) or not interaction:IsA(class) then return {} end
    local available,bridge=pcall(pcl151726_bridge)
    if not available then return nil end
    local status,a,b,c,d=bridge.lines(interaction:GetAddress(),host:GetAddress(),frontend:GetAddress())
    if status~=1 then log('PCL15_17_30_LINE_READ_REFUSED '..tostring(status));return {} end
    local ids={}
    for _,address in ipairs({a,b,c,d}) do if address and address~=0 then ids[address]=true end end
    return ids
end
function pcl151730_hide_helper(actor,protected)
    if not is_valid(actor) or protected[actor:GetAddress()] then return 0 end
    -- Never hide transferred part actors or propagate component visibility to
    -- their attachment descendants. Only the helper's own components change.
    local part_class=StaticFindObject('/Script/Bladesong.SwordPartActor')
    if is_valid(part_class) and actor:IsA(part_class) then return 0 end
    pcl151114_hide_actor(actor)
    local actor_component=StaticFindObject('/Script/Engine.ActorComponent')
    local scene_component=StaticFindObject('/Script/Engine.SceneComponent')
    local niagara=StaticFindObject('/Script/Niagara.NiagaraComponent')
    local audio=StaticFindObject('/Script/Engine.AudioComponent')
    local capture=StaticFindObject('/Script/Engine.SceneCaptureComponent')
    local components={}
    local returned=actor:K2_GetComponentsByClass(actor_component)
    if type(returned)=='table' and type(returned.ForEach)~='function' then
        for _,value in pairs(returned) do components[#components+1]=pcl151114_unwrap(value) end
    elseif returned then
        returned:ForEach(function(_,value) components[#components+1]=pcl151114_unwrap(value) end)
    end
    for _,component in ipairs(components) do
        if is_valid(component) then
            if is_valid(capture) and component:IsA(capture) then
                component.bCaptureEveryFrame=false
                component.bCaptureOnMovement=false
            end
            component:SetComponentTickEnabled(false)
            component:SetActive(false,false)
            if is_valid(scene_component) and component:IsA(scene_component) then pcl151114_hide_scene_component(component) end
            if is_valid(niagara) and component:IsA(niagara) then component:DeactivateImmediate() end
            if is_valid(audio) and component:IsA(audio) then component:Stop() end
        end
    end
    return #components
end
PCL151730_PREVIOUS_QUARANTINE=pcl151114_quarantine_temp_presentation
function pcl151114_quarantine_temp_presentation(temp)
    pcl151757_hide_temp_environments(temp)
    local active=find_forge()
    if not is_valid(temp) or not is_valid(active) or temp:GetAddress()==active:GetAddress() then return false,'refused active or unavailable Forge' end
    local frontend=temp.ForgeModeFrontend
    local active_frontend=active.ForgeModeFrontend
    if not is_valid(frontend) or not is_valid(active_frontend) or frontend:GetAddress()==active_frontend:GetAddress() then return false,'refused shared/active frontend' end
    for _,name in ipairs({'SwordPartHandling','CameraHandling','BladeInteraction','InteractableManager'}) do
        local a=pcl151730_field(frontend,name)
        local b=pcl151730_field(active_frontend,name)
        if is_valid(a) and is_valid(b) and a:GetAddress()==b:GetAddress() then return false,'refused shared active helper '..name end
    end
    PCL151113_ACTIVE_FRONTEND=active_frontend
    local state=PCL151730_QUARANTINES[temp:GetAddress()]
    local protected=pcl151758_active_helpers(active)
    local previous_protection=PCL151758_CLEANUP_PROTECTION
    PCL151758_CLEANUP_PROTECTION=protected
    local ok,detail=true,nil
    if not state or not state.baseline_done then
        local previous=PCL151732_CLEANUP_HOST
        PCL151732_CLEANUP_HOST=temp
        local passed,a,b=pcall(PCL151730_PREVIOUS_QUARANTINE,temp)
        PCL151732_CLEANUP_HOST=previous
        if passed then ok,detail=a,b else ok,detail=false,a end
    end
    PCL151758_CLEANUP_PROTECTION=previous_protection
    protected[active_frontend:GetAddress()]=true
    local helpers={temp,frontend}
    local function add(obj)if is_valid(obj) then helpers[#helpers+1]=obj end end
    for _,name in ipairs({'BladeMesh','TutorialBladeShape','PreviewImageCapture','SwordOutlineCapture'}) do
        local current=pcl151730_field(active,name)
        if is_valid(current) then protected[current:GetAddress()]=true end
        add(pcl151730_field(temp,name))
    end
    for _,name in ipairs({'InstantiatedMusic'}) do
        local current=pcl151730_field(active_frontend,name)
        if is_valid(current) then protected[current:GetAddress()]=true end
        add(pcl151730_field(frontend,name))
    end
    local interaction=frontend.BladeInteraction
    local active_interaction=active_frontend.BladeInteraction
    local ids=pcl151730_extra_line_ids(interaction,temp,frontend)
    local active_ids=pcl151730_extra_line_ids(active_interaction,active,active_frontend)
    if is_valid(interaction) then
        for _,name in ipairs({'IntensityLineRenderer','DragLineRenderer','InteractableRangeX','InteractableRangeY','InteractableBlendX','InteractableBlendY'}) do
            local current=pcl151730_field(active_interaction,name)
            if is_valid(current) then protected[current:GetAddress()]=true end
            add(pcl151730_field(interaction,name))
        end
    end
    local handling=frontend.SwordPartHandling
    local active_handling=active_frontend.SwordPartHandling
    if is_valid(handling) then
        for _,name in ipairs({'BendLineRenderer','MaterialPreviewActor','MaterialNotAllowedActor'}) do
            local current=pcl151730_field(active_handling,name)
            if is_valid(current) then protected[current:GetAddress()]=true end
            add(pcl151730_field(handling,name))
        end
    end
    local matched=0
    local line_seen={}
    if ids and active_ids and next(ids) then
        for _,class_name in ipairs({'LineRenderer','BP_LineRenderer_C','BP_TutorialBladeShapeLineRenderer_C'}) do
            for _,line in ipairs(FindAllOf(class_name) or {}) do
                if is_valid(line) and ids[line:GetAddress()] and not active_ids[line:GetAddress()] and not line_seen[line:GetAddress()] then
                    line_seen[line:GetAddress()]=true;add(line);matched=matched+1
                end
            end
        end
    end
    local components=0;local seen={}
    for _,helper in ipairs(helpers) do
        if not seen[helper:GetAddress()] then
            seen[helper:GetAddress()]=true
            local hidden,count=pcall(pcl151730_hide_helper,helper,protected)
            if hidden then components=components+count else log('PCL15_17_30_HELPER_HIDE_FAILED '..tostring(count)) end
        end
    end
    local state=PCL151730_QUARANTINES[temp:GetAddress()]
    if not state then
        state={};PCL151730_QUARANTINES[temp:GetAddress()]=state
        -- Native/Blueprint initialization can finish after the immediate pass.
        -- Bounded rechecks, not a permanent world scan or render-frame loop.
        for _,delay in ipairs({100,750,2500}) do
            pcl15179_schedule(delay,function()
                if is_valid(temp) then
                    local passed,err=pcall(pcl151114_quarantine_temp_presentation,temp)
                    if not passed then log('PCL15_17_30_DELAYED_QUARANTINE_FAILED '..tostring(err)) end
                end
            end)
        end
    end
    state.baseline_done=ok
    log('PCL15_17_30_QUARANTINE extra_lines='..tostring(matched)..' helper_components='..tostring(components)..' active_protected=true propagate=false')
    return ok,detail
end
function pcl151730_preview_from_save(code,panel)
    local forge=find_forge()
    assert(is_valid(forge),'Forge unavailable')
    local before=forge:GetPiece()
    local class=StaticFindObject('/Script/Bladesong.CreativeModeSave')
    local save=gameplay_statics_15():LoadGameFromSlot(pcl151726_slot(code),0)
    assert(is_valid(save) and save:GetClass():GetAddress()==class:GetAddress(),'Preview cache unavailable')
    -- A data-only UObject, not an AForgeMode: no world actors, UI, stage,
    -- particles, interactables or native reconstruction are created here.
    local piece=StaticConstructObject(before:GetClass(),panel)
    pcl151731_fresh(piece)
    assert(is_valid(piece),'Preview data allocation failed')
    local status=pcl151726_bridge().restore(save:GetAddress(),piece:GetAddress(),class:GetAddress(),before:GetClass():GetAddress())
    assert(status==1,'Preview restoration failed ('..tostring(status)..')')
    local texture=piece:GetPreviewImage()
    if is_valid(texture) then
        PCL151724_PREVIEWS[code]={owner=panel,texture=texture}
        pcl151727_save_preview(code,texture,panel)
    end
    log('PCL15_17_30_PREVIEW_DATA_ONLY code='..code..' texture='..tostring(is_valid(texture))..' forge_spawns=0')
end


PCL151725_UPLOAD_HOSTS={}
PCL151725_UPLOAD_PENDING=nil

function pcl151725_upload_status(message,show)
    log('PCL15_17_25_UPLOAD '..tostring(message))
    local menu=PCL151710_MENU_STATE
    if menu and is_valid(menu.panel) then
        pcl15171_set_status(menu.panel,message)
        if show then pcl151710_set_menu_visible(true) end
    end
end
function pcl151725_upload_hooks(ui)
    PCL151725_UPLOAD_HOOKS=PCL151725_UPLOAD_HOOKS or {}
    local class_path=safe_full_name(ui:GetClass()):match('^[^ ]+ (.+)$')
    local prefixes={'/Script/Bladesong.UWForgeMode'}
    if class_path then prefixes[#prefixes+1]=class_path end
    for _,prefix in ipairs(prefixes) do
      for _,success in ipairs({true,false}) do
        local path=prefix..':'..(success and 'OnPieceUploadSuccessful' or 'OnPieceUploadFailed')
        if not PCL151725_UPLOAD_HOOKS[path] then
          local ok,pre,post=pcall(RegisterHook,path,function(context,message)
            local request=PCL151725_UPLOAD_PENDING
            local ui=pcl15171_unwrap(context)
            if not request or not is_valid(ui) or ui:GetAddress()~=request.ui:GetAddress() then return end
            local raw=pcl15171_unwrap(message)
            local text=pcl15171_from_text(raw)
            if text=='' then text=tostring(raw or '') end
            pcl15179_schedule(1,function()
                if PCL151725_UPLOAD_PENDING~=request then return end
                PCL151725_UPLOAD_PENDING=nil
                if success then
                    local code=pcl15171_trim(text)
                    if code:match('^[%a]+%-[%a]+%-[%a]+$') then
                        if not pcl151727_complete_upload(request,code) and request.batch then pcl151741_batch_error(request,'Uploaded, but the local save is incomplete. Retry save or Cancel.') end
                    else pcl151725_upload_status('Unexpected upload reply; temporary build kept: '..text,true);if request.batch then pcl151741_batch_error(request,'Unexpected upload reply. Retry or Cancel. The placed build is unchanged.') end end
                else pcl151725_upload_status('Upload failed; temporary build kept: '..text,true);if request.batch then pcl151741_batch_error(request,'Upload failed: '..text..'. Retry or Cancel; placed builds are unchanged.') end end
            end)
          end,function() end)
          if ok then
            PCL151725_UPLOAD_HOOKS[path]={pre,post}
            log('PCL15_17_25_UPLOAD_RESULT_HOOK '..path)
          else log('PCL15_17_25_UPLOAD_RESULT_HOOK_UNAVAILABLE '..path..' '..tostring(pre)) end
        end
      end
    end
end
function pcl151725_bridge()
    if PCL151725_BRIDGE then return PCL151725_BRIDGE end
    local path=pcl151112_script_dir()..'pcl_held_upload_151725b.dll'
    local bridge={}
    for _,key in ipairs({'probe','snapshot','send'}) do
        local fn,err=BMF_PCL_NATIVE(path,'pcl_upload_'..key)
        assert(type(fn)=='function',tostring(err))
        bridge[key]=fn
    end
    assert(bridge.probe()==1,'Upload bridge executable guard refused this build')
    PCL151725_BRIDGE=bridge
    return bridge
end
function pcl151725_held_tree()
    local handling,held=current_preview_14()
    assert(is_valid(handling) and is_valid(held),'Hold an item or a build on an anchor first.')
    local root=held
    if pcl15167_is_exact_anchor_actor(held) then
        local roots={}
        held.SlotChildParts:ForEach(function(_,value)
            local actor=pcl15171_unwrap(value)
            if is_valid(actor) then roots[#roots+1]=actor end
        end)
        held.FreeChildParts:ForEach(function(key,_)
            local actor=pcl15171_unwrap(key)
            if is_valid(actor) then roots[#roots+1]=actor end
        end)
        assert(#roots==1,'The anchor must hold exactly one connected build.')
        root=roots[1]
    end
    local nodes,seen={},{}
    local function visit(actor,depth)
        assert(is_valid(actor),'A held part became unavailable.')
        assert(depth<=128 and #nodes<6000,'Held build exceeds the upload snapshot limit.')
        local addr=actor:GetAddress()
        assert(not seen[addr],'Held build has a duplicate or cyclic attachment.')
        assert(not pcl15167_is_exact_anchor_actor(actor),'Remove nested preconstruction anchors before uploading.')
        seen[addr]=true;nodes[#nodes+1]=actor
        actor.SlotChildParts:ForEach(function(_,value)
            local child=pcl15171_unwrap(value)
            if is_valid(child) then visit(child,depth+1) end
        end)
        actor.FreeChildParts:ForEach(function(key,_)
            local child=pcl15171_unwrap(key)
            if is_valid(child) then visit(child,depth+1) end
        end)
    end
    visit(root,1)
    return handling,held,root,nodes
end
function pcl151725_snapshot_held(chosen_name,source)
        local handling,held,root,nodes
        if source then root,nodes=source.root,source.nodes else handling,held,root,nodes=pcl151725_held_tree() end
        local ui=pcl151723_references()
        local forge=find_forge()
        assert(is_valid(ui) and is_valid(forge),'Active Forge UI unavailable.')
        local before=forge:GetPiece()
        local sentinel=forge:GetRootSwordPartActor()
        assert(is_valid(before) and is_valid(sentinel),'Active Forge data unavailable.')
        local bridge=pcl151725_bridge()
        pcl151725_upload_hooks(ui)
        local host,gm,host_err
        if source and is_valid(source.host) and is_valid(source.gm) then
            host,gm=source.host,source.gm
        else
            host,gm,host_err=pcl151113_spawn_temp_forge(forge,before)
            assert(is_valid(host),tostring(host_err))
            PCL151725_UPLOAD_HOSTS[#PCL151725_UPLOAD_HOSTS+1]=host
        end
        if source then source.host,source.gm=host,gm end
        local piece=StaticConstructObject(before:GetClass(),host)
        pcl151731_fresh(piece)
        assert(is_valid(piece),'Could not create isolated upload data.')
        host.Piece=piece
        piece.CurrentSwordmakingStage=before.CurrentSwordmakingStage
        local name=pcl15171_trim(chosen_name or '')
        assert(name~='' and #name<=160,'Enter a valid build name before uploading.')
        piece.Name=pcl15171_to_text(name)
        local args={forge:GetAddress(),piece:GetAddress(),root:GetAddress(),#nodes}
        for _,actor in ipairs(nodes) do args[#args+1]=actor:GetAddress() end
        local result=bridge.snapshot(table.unpack(args))
        assert(result==#nodes,'Held snapshot refused (status '..tostring(result)..').')
        assert(#piece.WeaponDesignDefinition.AppliedSwordParts==#nodes,'Held snapshot count changed.')
        assert((source or handling.PreviewSwordPartActor:GetAddress()==held:GetAddress()) and
            forge:GetPiece():GetAddress()==before:GetAddress() and forge:GetRootSwordPartActor():GetAddress()==sentinel:GetAddress() and
            gm.ForgeMode:GetAddress()==forge:GetAddress(),'Active Forge ownership changed during snapshot.')
        local request={ui=ui,host=host,piece=piece,name=name,held=held,root=root,nodes=nodes,parts=#nodes,started=os.clock(),placed_source=source}
    return request
end
function pcl151722_create_launcher(catalogue,panel)
    local parent,reference=pcl151710_find_tool_row(catalogue)
    if not is_valid(reference) then return nil end
    local button=pcl15171_create_widget(catalogue,reference:GetClass())
    if not is_valid(button) then return nil end
    button:SetStyle(reference:GetStyle():GetClass())
    button.ToolTip=pcl15171_to_text('Preconstruction Library')
    local size=reference:GetDesiredSize()
    if size.X<=0 or size.Y<=0 or math.abs(size.X-size.Y)>0.01 then return nil end
    button:SetMinDimensions(size.X,size.Y)
    local content_size=reference.Content:GetDesiredSize()
    local texture=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary'):ImportFileAsTexture2D(catalogue,pcl151112_script_dir()..'assets\\pcl_library_glyph.png')
    if not is_valid(texture) then error('Library glyph texture unavailable') end
    local icon=StaticConstructObject(StaticFindObject('/Script/UMG.Image'),button.WidgetTree)
    icon:SetBrushFromTexture(texture,false)
    icon:SetDesiredSizeOverride({X=content_size.X,Y=content_size.Y})
    -- The texture supplies the requested #AEAEAE; do not darken it again.
    icon:SetColorAndOpacity({R=1,G=1,B=1,A=1})
    icon:SetVisibility(4)
    button.Content:SetContent(icon)
    pcl151722_insert_launcher(parent,button,reference)
    -- Use the native click handler, scoped to this one button. No unsafe
    -- multicast-delegate binding and no polling that can miss a short click.
    PCL15171_ACTIONS[button:GetAddress()]={kind='library_toggle',panel=panel}
    pcl151722_native_click_hook()
    log('PCL15_17_22_NATIVE_BUTTON reference='..safe_full_name(reference)..' size='..size.X..'x'..size.Y..' icon='..content_size.X..'x'..content_size.Y..' style='..safe_full_name(button:GetStyle()))
    return button,icon
end

function pcl151711_align_launcher(state)
    if not state.native_launcher or not is_valid(state.launcher) then return false end
    local parent,reference=pcl151710_find_tool_row(state.catalogue)
    if not is_valid(reference) then return false end
    local size=reference:GetDesiredSize()
    if size.X<=0 or size.Y<=0 then return false end
    local toolbar_item=is_valid(state.launcher_wrap) and state.launcher_wrap or state.launcher
    if not is_valid(toolbar_item:GetParent()) or toolbar_item:GetParent():GetAddress()~=parent:GetAddress() then
        toolbar_item:RemoveFromParent()
        pcl151722_insert_launcher(parent,toolbar_item,reference)
    end
    state.launcher:SetMinDimensions(size.X,size.Y)
    return true
end

function pcl15171_inject_catalogue(catalogue)
    if not is_valid(catalogue) then return false end
    local state=PCL151710_MENU_STATE
    local forge=find_forge()
    if not is_valid(forge) then return false end
    local forge_address=forge:GetAddress()
    local frontend=forge.ForgeModeFrontend
    local ui=is_valid(frontend) and frontend.ForgeModeUi or nil
    if not is_valid(ui) then return false end
    local ui_address=ui:GetAddress()
    if state and (state.forge_address~=forge_address or state.forge_ui_address~=ui_address
        or not is_valid(state.panel) or not is_valid(state.launcher)) then
        pcl15177_reset_forge_references()
    end
    if PCL151710_MENU_STATE ~= nil and is_valid(PCL151710_MENU_STATE.panel) then
        -- Use a freshly enumerated catalogue; Forge can replace this child
        -- without loading a new map, leaving the old Lua wrapper behind.
        PCL151710_MENU_STATE.catalogue = catalogue
        local ok, err = pcall(pcl151711_align_launcher, PCL151710_MENU_STATE)
        if not ok and not PCL151710_MENU_STATE.align_error then
            PCL151710_MENU_STATE.align_error = true
            log('PCL15_17_11_ICON_POSITION_ERROR=' .. tostring(err))
        end
        return true
    end
    local retry=PCL15171_FORGE_RETRY
    if retry and retry.ui==ui_address and os.time()<retry.until_time then return false end
    local ok,panel=pcall(pcl15171_create_panel,catalogue)
    if not ok or not is_valid(panel) then
        PCL15171_FORGE_RETRY={ui=ui_address,until_time=os.time()+2}
        if not ok then log('PCL_FORGE_PANEL_RETRY '..tostring(panel)) end
        return false
    end
    PCL15171_FORGE_RETRY=nil
    -- Keep the library out of SwordPartButtonContainer. All three widgets are
    -- viewport-owned so closing the library cannot disturb catalogue layout.
    local root = pcl15171_widget_by_name(panel, 'PCL_Root')
    if is_valid(root) then
        root:SetWidthOverride(800)
        root:SetMaxDesiredWidth(800)
    end
    local launcher, icon = pcl151722_create_launcher(catalogue, panel)
    local close = PCL151723_UI[panel:GetAddress()].close
    if not is_valid(launcher) or not is_valid(close) then
        log('PCL15_17_10_MENU_CREATE_ERROR=launcher_or_close_missing')
        return false
    end
    PCL151710_MENU_STATE = {
        panel=panel,launcher=launcher,close=close,catalogue=catalogue,open=false,
        native_launcher=true,icon=icon,forge_address=forge_address,forge_ui_address=ui_address
    }
    pcall(pcl151727_draft)
    panel:SetVisibility(1)
    close:SetVisibility(1)
    log('PCL15_17_12_PANEL_POSITION_BEGIN')
    pcl151710_position_widget(panel, 800, 516, 150, 100)
    pcl151723_resize(panel)
    log('PCL15_17_12_PANEL_POSITION_DONE')
    if not BMF_PCL_DIRECT_ANCHOR() then
        pcl15171_hide_stock_anchor_tile()
    end
    log('PCL15_17_10_LIBRARY_LAUNCHER_READY location=top_right')
    return true
end

function pcl15171_active_catalogue(ui,frontend)
    local ok,catalogue=pcall(function() return ui.SwordPartCatalogue end)
    if ok and is_valid(catalogue) then return catalogue end
    -- The new catalogue stores the frontend that owns it.
    local match=nil
    for _,candidate in ipairs(FindAllOf('UWSwordPartCatalogue') or {}) do
        if is_valid(candidate) then
            local valid,owner=pcall(function() return candidate.ForgeModeFrontend end)
            if valid and is_valid(owner) and owner:GetAddress()==frontend:GetAddress() then
                if match then return nil end
                match=candidate
            end
        end
    end
    return match
end

function pcl15171_find_catalogues()
    local out={}
    local ok,err=pcall(function()
        local forge=find_forge()
        if not is_valid(forge) then return end
        local frontend=forge.ForgeModeFrontend
        if not is_valid(frontend) then return end
        local ui=frontend.ForgeModeUi
        if not is_valid(ui) or not is_valid(ui.ForgeMode) or ui.ForgeMode:GetAddress()~=forge:GetAddress() then return end
        if BMF_PCL_DIRECT_ANCHOR() then
            out[1]=ui
            return
        end
        local catalogue=pcl15171_active_catalogue(ui,frontend)
        if is_valid(catalogue) then
            out[1]=catalogue
        elseif is_valid(ui.SwordPartCatalogueParent) then
            -- The reworked catalogue is hosted by the Forge UI. The launcher
            -- only needs the owning widget and finds its toolbar separately.
            out[1]=ui
        end
    end)
    return out
end

function pcl15171_monitor_tick()
    -- The Forge toolbar and Creative home can be rebuilt independently.
    -- A transient error in one screen must not prevent the other from returning.
    run_game_thread(function()
        if pcl15171_load_widget_assets() then
            local catalogues=pcl15171_find_catalogues()
            if PCL15174_CATALOGUE_COUNT~=#catalogues then
                PCL15174_CATALOGUE_COUNT=#catalogues
                log('PCL15_17_4_UI_READY catalogue_count='..tostring(#catalogues))
            end
            for _,catalogue in ipairs(catalogues) do
                pcl15171_inject_catalogue(catalogue)
            end
        end
    end)
    if os.clock()>=(PCL151760_FORGE_ENTRY_UNTIL or 0) then
        run_game_thread(pcl151762_monitor_home)
    end
    run_game_thread(pcl151751_update_hint)
    pcl15179_schedule(500,pcl15171_monitor_tick)
end

function pcl15171_start_monitor()
    if PCL15171_MONITOR_STARTED then
        return
    end

    PCL15171_MONITOR_STARTED = true

    pcl15171_load_library()
    pcl151724_load_metadata()

    pcl15179_schedule(
        250,
        pcl15171_monitor_tick
    )

    log('Phase 15.17.1 FORGE PRECONSTRUCTION LIBRARY UI active.')
    log('PCL15_17_1_LIBRARY_PATH=' ..
        tostring(PCL15171_LIBRARY_PATH))
    log('PCL15_17_1_LIBRARY_COUNT=' ..
        tostring(#PCL15171_LIBRARY))
end

pcall(function()
    RegisterLoadMapPreHook(function()
        -- Clear Lua handles before Unreal tears down the world they refer to.
        pcl15177_reset_forge_references()
        log('PCL15_17_7_MAP_TRANSITION references_cleared=true')
    end)
end)
pcl15171_start_monitor()


-- ============================================================================
-- Phase 15.17.2 - ORGANIZED JSON PRECONSTRUCTION LIBRARY
--
-- Old behavior:
--   Scripts\bladesong_weapon_design_native.json
-- and every CTRL+ALT+J export overwrote the previous file.
--
-- New behavior:
--   Scripts\preconstructions\json\latest.json
--   Scripts\preconstructions\json\preconstruction_YYYYMMDD_HHMMSS_NNN.json
--
-- latest.json remains the compatibility path used by the proven:
--   CTRL+ALT+O native JSON validation
--   CTRL+ALT+D direct native JSON import
--
-- Every successful export also creates a permanent timestamped snapshot.
-- If an old root-level JSON exists and latest.json does not, it is migrated.
--
-- ZERO new top-level locals.
-- ============================================================================

PCL151172_JSON_RELATIVE_DIR =
    'preconstructions\\json\\'

PCL151172_JSON_DIR =
    pcl151112_script_dir() ..
    PCL151172_JSON_RELATIVE_DIR

PCL151172_LATEST_FILENAME =
    'latest.json'

PCL151172_LATEST_RELATIVE_PATH =
    PCL151172_JSON_RELATIVE_DIR ..
    PCL151172_LATEST_FILENAME

PCL151172_OLD_JSON_PATH =
    OUTPUT_DIR ..
    'bladesong_weapon_design_native.json'

PCL151172_EXPORT_SEQUENCE = 0
PCL151172_LAST_ARCHIVE_PATH = nil
PCL151172_LAST_LATEST_PATH = nil

-- Redirect all existing validate/import code to the organized compatibility
-- file without changing the proven native JSON pipeline.
PCL151163_JSON_FILENAME =
    PCL151172_LATEST_RELATIVE_PATH

function pcl151172_ensure_json_dir()
    local command =
        'mkdir "' ..
        tostring(PCL151172_JSON_DIR) ..
        '" >nul 2>nul'

    pcall(function()
        os.execute(command)
    end)
end

function pcl151172_file_exists(path)
    local f = nil

    pcall(function()
        f =
            io.open(
                path,
                'rb'
            )
    end)

    if f == nil then
        return false
    end

    f:close()
    return true
end

function pcl151172_copy_file(src, dst)
    local input = nil
    local output = nil

    local ok, err =
        pcall(function()
            input =
                io.open(
                    src,
                    'rb'
                )

            if input == nil then
                error(
                    'source open failed'
                )
            end

            local bytes =
                input:read('*a')

            input:close()
            input = nil

            output =
                io.open(
                    dst,
                    'wb'
                )

            if output == nil then
                error(
                    'destination open failed'
                )
            end

            output:write(bytes)
            output:close()
            output = nil
        end)

    if input ~= nil then
        pcall(function()
            input:close()
        end)
    end

    if output ~= nil then
        pcall(function()
            output:close()
        end)
    end

    return ok, err
end

function pcl151172_migrate_old_json()
    pcl151172_ensure_json_dir()

    local latest =
        OUTPUT_DIR ..
        PCL151172_LATEST_RELATIVE_PATH

    if pcl151172_file_exists(latest) then
        return
    end

    if not pcl151172_file_exists(
           PCL151172_OLD_JSON_PATH
       ) then
        return
    end

    local ok, err =
        pcl151172_copy_file(
            PCL151172_OLD_JSON_PATH,
            latest
        )

    if ok then
        log('PCL15_17_2_JSON_MIGRATED' ..
            ' from=' ..
            tostring(PCL151172_OLD_JSON_PATH) ..
            ' to=' ..
            tostring(latest))
    else
        log('PCL15_17_2_JSON_MIGRATION_ERROR=' ..
            tostring(err))
    end
end

function pcl151172_next_archive_path()
    pcl151172_ensure_json_dir()

    local stamp =
        os.date(
            '%Y%m%d_%H%M%S'
        )

    local attempt = 0
    local path = nil

    repeat
        PCL151172_EXPORT_SEQUENCE =
            PCL151172_EXPORT_SEQUENCE + 1

        attempt =
            PCL151172_EXPORT_SEQUENCE

        path =
            PCL151172_JSON_DIR ..
            string.format(
                'preconstruction_%s_%03d.json',
                tostring(stamp),
                tonumber(attempt) or 0
            )
    until
        not pcl151172_file_exists(path)

    return path
end

function pcl151163_save_clipboard_json(path)
    pcl151172_ensure_json_dir()

    local latest_path =
        tostring(path)

    local archive_path =
        pcl151172_next_archive_path()

    local latest_q =
        pcl151163_shell_quote_single(
            latest_path
        )

    local archive_q =
        pcl151163_shell_quote_single(
            archive_path
        )

    -- Clipboard JSON is generated by Bladesong's native serializer. PowerShell
    -- only writes that exact text to both the compatibility file and a unique
    -- permanent snapshot.
    local command =
        'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' ..
        '"$t=Get-Clipboard -Raw; ' ..
        '[System.IO.File]::WriteAllText(' ..
        "'" .. latest_q .. "',$t,[System.Text.UTF8Encoding]::new($false)); " ..
        '[System.IO.File]::WriteAllText(' ..
        "'" .. archive_q .. "',$t,[System.Text.UTF8Encoding]::new($false))" ..
        '"'

    local exec_ok = false
    local exec_a, exec_b, exec_c = nil, nil, nil

    local ok, a, b_, c =
        pcall(function()
            return os.execute(
                command
            )
        end)

    if ok then
        exec_a, exec_b, exec_c =
            a, b_, c

        if a == true or
           a == 0 or
           c == 0 then
            exec_ok = true
        end
    end

    local size = -1
    local first = ''

    local f =
        io.open(
            latest_path,
            'rb'
        )

    if f ~= nil then
        size =
            f:seek('end') or -1

        f:seek(
            'set',
            0
        )

        first =
            f:read(1) or ''

        f:close()
    end

    PCL151172_LAST_ARCHIVE_PATH =
        archive_path

    PCL151172_LAST_LATEST_PATH =
        latest_path

    log('PCL15_17_2_JSON_SAVE' ..
        ' latest=' ..
        tostring(latest_path) ..
        ' archive=' ..
        tostring(archive_path) ..
        ' ok=' ..
        tostring(exec_ok) ..
        ' size=' ..
        tostring(size))

    return
        exec_ok,
        size,
        first,
        exec_a,
        exec_b,
        exec_c
end

pcl151172_migrate_old_json()

log('Phase 15.17.2 ORGANIZED JSON PRECONSTRUCTION LIBRARY active.')
log('PCL15_17_2_JSON_DIR=' ..
    tostring(PCL151172_JSON_DIR))
log('PCL15_17_2_JSON_LATEST=' ..
    tostring(
        OUTPUT_DIR ..
        PCL151172_LATEST_RELATIVE_PATH
    ))
log('CTRL+ALT+J now saves latest.json plus a unique timestamped preconstruction JSON.')
log('CTRL+ALT+O and CTRL+ALT+D now read preconstructions\\json\\latest.json.')

-- 15.17.19: native download -> isolated construction -> held anchor.
-- The stock download callback never opens/replaces the player's Forge for a
-- matching PCL request. Keep the 15.17.18 asset/socket and toolbar code unchanged.
PCL151719_BRIDGE = nil
PCL151719_IMPORT = nil
PCL151719_HOSTS = {}

function pcl151719_bridge()
    if PCL151719_BRIDGE ~= nil then return PCL151719_BRIDGE end
    local dll = pcl151112_script_dir() .. 'pcl_download_capture_151762.dll'
    local exports = {probe='pcl_download_probe',arm='pcl_download_arm',
        status='pcl_download_status',cancel='pcl_download_cancel',rebuild='pcl_download_rebuild',arm_home='pcl_download_arm_home',failed='pcl_download_failed'}
    local bridge = {}
    for name, symbol in pairs(exports) do
        local fn, err = BMF_PCL_NATIVE(dll,symbol)
        if type(fn) ~= 'function' then return nil, tostring(err) end
        bridge[name] = fn
    end
    local guard = bridge.probe()
    if guard ~= 1 then return nil, 'native executable guard refused status=' .. tostring(guard) end
    PCL151719_BRIDGE = bridge
    return bridge
end

function pcl151719_status(message)
    local menu = PCL151710_MENU_STATE
    if menu ~= nil and is_valid(menu.panel) then pcl15171_set_status(menu.panel,message) end
end

function pcl151719_fail(message)
    local request = PCL151719_IMPORT
    if request ~= nil and request.armed then request.bridge.cancel() end
    if request ~= nil and is_valid(request.anchor) then
        request.anchor:SetActorHiddenInGame(true)
    end
    PCL151719_IMPORT = nil
    log('PCL15_17_20_IMPORT_FAILED reason=' .. tostring(message) .. ' stock_auto_place=false')
    pcl151719_status('Import stopped: ' .. tostring(message))
    if request and request.restore_upload then
        local menu=PCL151710_MENU_STATE
        if menu then pcl151728_suspend_form(menu.panel,'Restore stopped; backup kept. You can close this menu and use the Forge. The recovery copy remains on disk.') end
    end
end

function pcl151719_verify()
    local request = PCL151719_VERIFY
    if request == nil then return end
    request.checks = request.checks + 1
    local handling, preview = current_preview_14()
    local held = is_valid(preview) and is_valid(request.anchor) and
        preview:GetAddress() == request.anchor:GetAddress()
    local placed_root = pcl151112_first_slot_child(request.active_sentinel)
    local placed = is_valid(placed_root) and is_valid(request.anchor) and
        placed_root:GetAddress() == request.anchor:GetAddress()
    local current_forge = find_forge()
    local unchanged = is_valid(request.forge) and is_valid(current_forge) and
        current_forge:GetAddress() == request.forge:GetAddress()
    log('PCL15_17_20_DIRECT_VERIFY check=' .. tostring(request.checks) ..
        ' held=' .. tostring(held) .. ' placed=' .. tostring(placed) ..
        ' same_active_forge=' .. tostring(unchanged))
    if held then
        pcl151719_status('Build is held on its anchor. Move the cursor and click to place.')
    elseif placed then
        pcl151719_status('Build placed.')
    else
        pcl151719_status('The held preview was dropped; the imported actors were retained for diagnosis.')
    end
    if request.restore_upload and request.checks>=2 then
        if held and unchanged then
            pcl151731_verify_recovery(request)
        else
            pcl151719_status('Recovery backup kept: restored build did not pass the visible hand check.')
        end
    end
    if request.checks < 2 then pcl15179_schedule(600,pcl151719_verify)
    else PCL151719_VERIFY = nil end
end

function pcl151719_active_anchor_button(forge)
    if not is_valid(forge) then return nil,'active Forge unavailable' end
    -- Only this Forge's frontend/UI owns the live catalogue. Old widgets can
    -- survive map changes and must never be selected by global enumeration.
    local frontend=forge.ForgeModeFrontend
    local ui=is_valid(frontend) and frontend.ForgeModeUi or nil
    if not is_valid(ui) or not is_valid(ui.ForgeMode) or ui.ForgeMode:GetAddress()~=forge:GetAddress() then
        return nil,'active Forge UI ownership mismatch'
    end
    local ok,catalogue=pcall(function() return ui.SwordPartCatalogue end)
    local path=ok and is_valid(catalogue) and safe_full_name(catalogue):match('^%S+ (.+)$')
    local match=nil
    for _,button in ipairs(find_live_part_buttons_9()) do
        local belongs=path and safe_full_name(button):find(path..'.',1,true)
        if not path then
            local valid,owner=pcall(function() return button.ForgeModeFrontendPtr end)
            belongs=valid and is_valid(owner) and owner:GetAddress()==frontend:GetAddress()
                and is_valid(button:GetParent())
        end
        if belongs then
            local row,table_name=pcl15165_button_handle_info(button)
            if row==PCL15161_ROW_NAME and table_name==PCL15165_DEV_TABLE_FULL then
                if match then return nil,'multiple anchor tiles belong to the active Forge' end
                match=button
            end
        end
    end
    if match then return match,nil end
    return nil,'anchor tile is not present on the active parts page'
end

function pcl151719_finish(request)
    local forge = find_forge()
    if not is_valid(forge) or forge:GetAddress() ~= request.forge:GetAddress() then
        return false, 'active Forge changed while downloading'
    end
    local handling, preview = current_preview_14()
    if not is_valid(handling) or is_valid(preview) then return false, 'another part is being held' end
    local active_sentinel = forge:GetRootSwordPartActor()
    local before_child=pcl151112_addr(pcl151112_first_slot_child(active_sentinel))
    local piece = request.temp:GetPiece()
    if not is_valid(piece) or piece:GetAddress() == request.before_piece then
        return false, 'captured Piece is unavailable'
    end
    -- Allocate through the player's catalogue BEFORE the isolated seam creates
    -- a second catalogue. This prevents selecting a temporary host's tile.
    local anchor,anchor_err
    if request.restore_upload then
        anchor,anchor_err=pcl151728_recovery_anchor(request)
    elseif BMF_PCL_DIRECT_ANCHOR() then
        anchor,anchor_err=pcl151728_spawn_anchor({forge=forge,handling=handling})
    else
        local button,button_err=pcl151719_active_anchor_button(forge)
        if not is_valid(button) then return false,button_err end
        anchor,anchor_err=pcl15165_take_exact_anchor_actor({},button)
    end
    if not is_valid(anchor) then return false, tostring(anchor_err) end
    request.anchor = anchor
    local mesh_ok, mesh_err = pcl15170_apply_mesh_to_actor(anchor)
    if not mesh_ok then return false, tostring(mesh_err) end
    anchor:SetActorHiddenInGame(true)
    -- Construction occurs synchronously on the temporary host. The active
    -- Piece, frontend, handling and sentinel are never passed to this seam.
    local before_frontend = pcl151112_addr(forge.ForgeModeFrontend)
    local native_started=os.clock()
    local seam_status = request.bridge.rebuild(request.temp:GetAddress(),piece:GetAddress())
    log('PCL15_17_31_TIMING stage=native_rebuild seconds='..string.format('%.3f',os.clock()-native_started))
    pcl151113_restore_game_mode_forge(request.gm,forge,'DIRECT_DOWNLOAD')
    local sentinel = request.temp:GetRootSwordPartActor()
    local root = pcl151112_first_slot_child(sentinel)
    PCL151113_ACTIVE_FRONTEND = forge.ForgeModeFrontend
    pcl151113_make_temp_inert(request.temp)
    if seam_status ~= 1 or not is_valid(root) then
        return false, 'isolated native construction failed status=' .. tostring(seam_status)
    end
    if pcl151112_addr(forge:GetPiece()) ~= request.before_piece or
       pcl151112_addr(forge.ForgeModeFrontend) ~= before_frontend or
       pcl151112_addr(forge:GetRootSwordPartActor()) ~= pcl151112_addr(active_sentinel) or
       pcl151112_addr(pcl151112_first_slot_child(active_sentinel))~=before_child then
        pcl151113_set_tree_hidden(root,true)
        return false, 'active Forge ownership changed during isolated construction'
    end
    local linked, link_err = pcl15165_attach_anchor_child(anchor,0,root)
    if not linked then
        pcl151113_set_tree_hidden(root,true)
        return false, link_err
    end
    sentinel.SlotChildParts:Remove(0)
    root.bPending = false
    anchor.bPending = true
    if request.restore_upload then
        pcl151113_set_tree_hidden(root,true);anchor:SetActorHiddenInGame(true)
        PCL151729_HANDOFF={forge=forge,active_sentinel=active_sentinel,anchor=anchor,root=root,restore_upload=request.restore_upload,ticks=0,released=0}
        pcl15179_schedule(100,function()
            pcl151710_set_menu_visible(false)
            pcl151729_release_tick()
        end)
        return true,nil
    end
    handling.BestSwordPartSlotParent = nil
    handling.PreviewSwordPartActor = anchor
    local _, assigned = current_preview_14()
    if not is_valid(assigned) or assigned:GetAddress() ~= anchor:GetAddress() then
        pcl151113_set_tree_hidden(root,true)
        return false, 'anchor preview assignment did not stay active'
    end
    pcl151113_set_tree_hidden(root,false)
    anchor:SetActorHiddenInGame(false)
    anchor:SetActorEnableCollision(true);anchor:SetActorTickEnabled(true)
    local photo_code=request.code
    pcl15179_schedule(350,function()
        local _,held=current_preview_14()
        if is_valid(held) and is_valid(anchor) and held:GetAddress()==anchor:GetAddress()
            and not pcl151727_preview_file(pcl151733_photo_path(photo_code)) then
            pcl151733_capture(photo_code,root,nil,anchor)
        end
    end)
    PCL151719_VERIFY = {forge=forge,active_sentinel=active_sentinel,anchor=anchor,root=root,checks=0}
    log('PCL15_17_20_DIRECT_HANDOFF same_active_forge=true active_piece_unchanged=true' ..
        ' native_enter_forge_calls=0 preview_anchor=' .. tostring(anchor:GetAddress()))
    pcl15179_schedule(100,pcl151719_verify)
    return true, nil
end

function pcl151719_tick()
    local request = PCL151719_IMPORT
    if request == nil then return end
    local ok, err = pcall(function()
        request.ticks = request.ticks + 1
        local forge = find_forge()
        if not is_valid(forge) or not is_valid(request.forge) or
           forge:GetAddress() ~= request.forge:GetAddress() then
            error('active Forge changed')
        end
        if not request.armed then
            if request.ticks > 100 then error('Hilt mode did not become ready') end
            if not pcl151717_prepare_hilt(forge) then
                pcl15179_schedule(100,pcl151719_tick)
                return
            end
            local handling, preview = current_preview_14()
            if not request.library_only and (not is_valid(handling) or is_valid(preview)) then error('finish the held part first') end
            local before = forge:GetPiece()
            if not is_valid(before) then error('active Piece unavailable') end
            if PCL151761_MODE~='blades' then
                local ready, anchor_err = pcl15166_ensure_current_anchor('direct_download')
                if not ready then error(tostring(anchor_err)) end
            end
            local temp, gm, spawn_err = pcl151113_spawn_temp_forge(forge,before)
            if not is_valid(temp) then error(tostring(spawn_err)) end
            request.temp, request.gm = temp, gm
            request.before_piece = before:GetAddress()
            -- Retain the world actor before arming; its Piece UPROPERTY owns
            -- the captured UPiece even if GC runs before the next polling tick.
            PCL151719_HOSTS[#PCL151719_HOSTS+1] = temp
            PCL151114_TEMP_HOSTS[#PCL151114_TEMP_HOSTS+1] = temp
            if not is_valid(gm.ForgeMode) or gm.ForgeMode:GetAddress() ~= forge:GetAddress() then
                error('GameMode reflection does not own the active Forge')
            end
            if request.local_cache then
                pcl151726_restore(request,before)
                if request.restore_upload then request.restore_upload.parts=#request.temp:GetPiece().WeaponDesignDefinition.AppliedSwordParts
                else pcl151710_set_menu_visible(false) end
                local finished,finish_err=pcl151719_finish(request)
                if not finished then error(tostring(finish_err)) end
                PCL151719_IMPORT=nil
                if request.restore_upload then
                    log('PCL15_17_29_CANCEL_CONSTRUCTED handoff_queued=true')
                end
                return
            end
            local creative=pcl15171_find_creative_service(request.context)
            if not is_valid(creative) then error('native download service unavailable') end
            local status = request.bridge.arm(creative:GetAddress(),gm:GetAddress(),forge:GetAddress(),
                temp:GetAddress(),before:GetAddress(),before:GetClass():GetAddress())
            if status ~= 1 then
                local reasons = {[-52]='GameMode active Forge differs',[-53]='active Piece differs from GetPiece',[-54]='temporary Piece bind differs',
                    [-55]='Piece class differs',[-56]='temporary Forge class differs',
                    [-61]='download service weak handle',[-62]='GameMode weak handle',
                    [-63]='active Forge weak handle',[-64]='temporary Forge weak handle',
                    [-65]='Piece weak handle',[-66]='Piece class weak handle'}
                error('download capture refused: ' .. tostring(reasons[status] or status) .. ' (' .. tostring(status) .. ')')
            end
            request.armed = true
            request.ticks = 0
            if not request.library_only then pcl151710_set_menu_visible(false) end
            creative:DownloadPiece(request.code)
            log('PCL15_17_20_DOWNLOAD_ARMED callback_before_enter=true code=' .. request.code)
        else
            if not is_valid(request.temp) then error('construction host became invalid') end
            local status = request.bridge.status()
            if status == 2 then
                if request.library_only then
                    pcl151756_finish_library_import(request)
                    PCL151719_IMPORT=nil
                    return
                end
                if not pcl151717_prepare_hilt(forge) then
                    if request.ticks > 1300 then error('Hilt mode did not become ready for handoff') end
                    pcl15179_schedule(100,pcl151719_tick)
                    return
                end
                pcl151724_capture_metadata(request)
                local cached,cache_err=pcl151726_save(request.code,request.temp:GetPiece())
                if not cached then log('PCL15_17_26_CACHE_SAVE_FAILED '..tostring(cache_err)) end
                log('PCL15_17_20_DOWNLOAD_CAPTURED stock_auto_place=false')
                local finished, finish_err = pcl151719_finish(request)
                if not finished then error(tostring(finish_err)) end
                PCL151719_IMPORT = nil
                return
            elseif status ~= 1 then
                error('download capture stopped status=' .. tostring(status))
            elseif request.ticks > 1200 then
                error('download timed out; late completion will not auto-place')
            end
        end
        pcl15179_schedule(100,pcl151719_tick)
    end)
    if not ok then pcl151719_fail(tostring(err)) end
end

function pcl15171_download_magic(context,code,refresh,library_only)
    if PCL151729_HANDOFF then return false,'Cancel is returning the build to your hand.' end
    if PCL151719_IMPORT ~= nil or PCL151716_IMPORT ~= nil then
        return false, 'An import is already pending.'
    end
    code = pcl15171_trim(code)
    local draft=pcl151727_draft()

    if code == '' then return false, 'Magic Word is empty' end
    local forge = find_forge()
    if not is_valid(forge) then return false, 'Open the Forge first.' end
    if library_only and pcl151726_has_cache(code) then
        pcl151727_queue_previews(context)
        pcl151719_status('Build is saved locally. Choose Place build when ready.')
        return true,nil
    end
    if not refresh and pcl151726_has_cache(code) then
        local cache_ready,cache_error=pcall(pcl151726_bridge)
        if cache_ready then
            PCL151719_IMPORT={context=context,code=code,forge=forge,ticks=0,armed=false,local_cache=true}
            pcl15179_schedule(1,pcl151719_tick)
            return true,nil
        end
        log('PCL_LOCAL_CACHE_UNAVAILABLE using_magic_word=true reason='..tostring(cache_error))
    end
    local bridge, err = pcl151719_bridge()
    if bridge == nil then return false, tostring(err) end
    local pending_status = bridge.status()
    if pending_status == 1 or pending_status == -9 then
        return false, 'The previous native download is still pending. Wait for it to finish or restart the game.'
    end
    PCL151719_IMPORT = {context=context,code=code,forge=forge,bridge=bridge,ticks=0,armed=false,library_only=library_only==true}
    pcl15179_schedule(100,pcl151719_tick)
    return true, nil
end

log('PCL_RUNTIME_VERSION=15.17.62 menu=native_sections_names_and_local_cache import_and_socket=15.17.20')

-- Read-only marker capture. Placement and native download code stay at 15.17.20.
function pcl151721_marker_snapshot(anchor,attempt)
    if not is_valid(anchor) then return end
    local ok, err = pcall(function()
        local handling = find_handling_component_9()
        if not is_valid(handling) then return end
        local root = anchor:K2_GetRootComponent()
        if not is_valid(root) then return end
        local socket = root:GetSocketTransform(pcl15170_existing_fname('Default'),0)
        local point = socket.Translation
        log('PCL15_17_21_MARKER_ANCHOR actor=' .. tostring(anchor:GetAddress()) ..
            ' actor_world=' .. vec3(anchor:GetTransform().Translation) ..
            ' socket_world=' .. vec3(point) .. ' socket_rotation=' .. quat(socket.Rotation) ..
            ' visible_pool=' .. tostring(handling.SwordPartSlotActorsVisible))
        local count = 0
        handling.SwordPartSlotActorPool:ForEach(function(_,vp)
            local marker = pcl151114_unwrap(vp)
            if count>=16 or not is_valid(marker) then return end
            count=count+1
            local transform = marker:GetTransform()
            local location = transform.Translation
            local dx,dy,dz = location.X-point.X,location.Y-point.Y,location.Z-point.Z
            log('PCL15_17_21_MARKER actor=' .. tostring(marker:GetAddress()) ..
                ' hidden=' .. tostring(marker.bHidden) .. ' world=' .. vec3(location) ..
                ' rotation=' .. quat(transform.Rotation) .. ' scale=' .. vec3(transform.Scale3D) ..
                ' socket_distance=' .. tostring(math.sqrt(dx*dx+dy*dy+dz*dz)))
        end)
    end)
    if not ok then log('PCL15_17_21_MARKER_READ_ERROR=' .. tostring(err)) end
    if attempt<2 then
        pcl15179_schedule(700,function() pcl151721_marker_snapshot(anchor,attempt+1) end)
    end
end

-- Initialize the guarded validator on the game thread before large builds.
pcl15179_schedule(1,function() pcl151726_bridge() end)

-- 15.17.56: snapshot placed anchored builds; never detach or destroy Forge parts.
function pcl151741_message(panel,message)
    local state=is_valid(panel) and PCL151723_UI[panel:GetAddress()]
    if state and is_valid(state.operation_message) then
        state.operation_message:SetText(pcl15171_to_text(message or ''))
        state.operation_message:SetVisibility(message and message~='' and 0 or 1)
    end
    log('PCL15_17_41 '..tostring(message))
end
function pcl151741_controls(panel,busy)
    local state=is_valid(panel) and PCL151723_UI[panel:GetAddress()]
    if not state then return end
    state.controls.PCL_AnchorButton:SetIsEnabled(not busy)
    state.controls.PCL_PlusButton:SetIsEnabled(not busy)
    state.carry:SetIsEnabled(not busy)
    state.recovery:SetIsEnabled(not busy and pcl151727_draft()~=nil)
end
function pcl151741_children(actor)
    local children={}
    actor.SlotChildParts:ForEach(function(_,value)
        local child=pcl15171_unwrap(value)
        if is_valid(child) then children[#children+1]=child end
    end)
    actor.FreeChildParts:ForEach(function(key,_)
        local child=pcl15171_unwrap(key)
        if is_valid(child) then children[#children+1]=child end
    end)
    return children
end
function pcl151741_nodes(root)
    local nodes,seen,stack={},{},{{actor=root,depth=1}}
    while #stack>0 do
        local entry=table.remove(stack)
        local actor=entry.actor
        assert(is_valid(actor),'An anchored part became unavailable')
        assert(entry.depth<=128 and #nodes<6000,'Anchored build exceeds the upload limit')
        local address=actor:GetAddress()
        assert(not seen[address],'Duplicate or cyclic build attachment')
        assert(not pcl15167_is_exact_anchor_actor(actor),'Nested anchors: use one anchor per build')
        seen[address]=true;nodes[#nodes+1]=actor
        for _,child in ipairs(pcl151741_children(actor)) do stack[#stack+1]={actor=child,depth=entry.depth+1} end
    end
    return nodes
end
function pcl151741_finish_batch(batch,message)
    if PCL151741_BATCH~=batch then return end
    PCL151741_BATCH=nil
    pcl151741_controls(batch.panel,false)
    pcl151741_message(batch.panel,message)
end
function pcl151741_start_batch(panel)
    if PCL151741_BATCH then
        local draft=pcl151727_draft()
        if draft and draft.batch==PCL151741_BATCH then pcl151727_show_form(panel,draft) end
        pcl151741_message(panel,'Upload '..PCL151741_BATCH.index..' of '..#PCL151741_BATCH.items..' is in progress.');return
    end
    local ok,err=pcall(function()
        assert(not PCL151725_UPLOAD_PENDING and not PCL151719_IMPORT and not PCL151729_HANDOFF,'Finish the current upload or import first')
        assert(not pcl151727_draft(),'Recover the existing unsaved build before starting uploads')
        local _,held=current_preview_14()
        assert(not is_valid(held),'Place the held item before uploading placed anchors')
        local forge=find_forge()
        assert(is_valid(forge),'Open the Forge first')
        local root=forge:GetRootSwordPartActor()
        assert(is_valid(root),'Forge assembly unavailable')
        local stack={root}
        local blade=forge:GetBladeMesh()
        local blade_roots=0
        if is_valid(blade) then
            blade.SwordParts:ForEach(function(key,_)
                local actor=pcl15171_unwrap(key)
                if is_valid(actor) then stack[#stack+1]=actor;blade_roots=blade_roots+1 end
            end)
        end
        -- Native root collections do not contain every independently placed
        -- anchor. Enumerate only our anchor class and prove current-Forge scope
        -- through live owner/attachment links before adding it to the scan.
        local scope={forge=forge,targets={[forge:GetAddress()]=true,[root:GetAddress()]=true}}
        if is_valid(blade) then scope.targets[blade:GetAddress()]=true end
        local physical=0
        for _,anchor in ipairs(FindAllOf('BP_PCL_PreconstructionAnchor_C') or {}) do
            if pcl15167_is_exact_anchor_actor(anchor) then
                local belongs,reason=pcl151743_anchor_scope(anchor,scope)
                local children=pcl151741_children(anchor)
                log('PCL15_17_43_ANCHOR_SCAN actor='..tostring(anchor:GetAddress())..' scoped='..tostring(belongs)..' reason='..reason..' pending='..tostring(anchor.bPending)..' children='..#children)
                if belongs then stack[#stack+1]=anchor;physical=physical+1 end
            end
        end
        log('PCL15_17_43_BATCH_ROOTS sword_root='..tostring(root:GetAddress())..' blade_roots='..blade_roots..' physical_anchors='..physical)
        local batch={panel=panel,forge=forge,items={},index=0,completed=0,stack=stack,seen={},count=0,phase='scan'}
        PCL151741_BATCH=batch
        pcl151741_controls(panel,true)
        pcl151741_message(panel,'Finding placed anchors...')
        pcl15179_schedule(1,function() pcl151741_scan_batch(batch) end)
    end)
    if not ok then pcl151741_message(panel,tostring(err)) end
end
function pcl151741_scan_batch(batch)
    if PCL151741_BATCH~=batch then return end
    local ok,err=pcall(function()
        local forge=find_forge()
        assert(is_valid(forge) and is_valid(batch.forge) and forge:GetAddress()==batch.forge:GetAddress(),'Forge changed; upload queue stopped')
        -- Catalogue anchors can retain bPending after placement. The live
        -- handling pointer is authoritative; never commit/mutate their flags.
        local _,held=current_preview_14()
        assert(not is_valid(held),'A part was picked up; upload queue stopped without changing it')
        local budget=os.clock()+0.003;local processed=0
        while #batch.stack>0 and processed<300 and (processed==0 or os.clock()<budget) do
            local actor=table.remove(batch.stack)
            assert(is_valid(actor),'A placed part became unavailable')
            local address=actor:GetAddress()
            if not batch.seen[address] then
                batch.seen[address]=true;batch.count=batch.count+1;processed=processed+1
                assert(batch.count<=60000,'Forge exceeds the batch scan limit')
                if pcl15167_is_exact_anchor_actor(actor) then
                    local children=pcl151741_children(actor)
                    assert(#children<=1,'Each anchor must contain exactly one connected build')
                    if #children==1 then
                        batch.items[#batch.items+1]={anchor=actor,root=children[1]}
                        log('PCL15_17_43_QUEUED anchor='..address..' root='..children[1]:GetAddress())
                    end
                end
                for _,child in ipairs(pcl151741_children(actor)) do batch.stack[#batch.stack+1]=child end
            end
        end
        if #batch.stack>0 then pcl15179_schedule(1,function() pcl151741_scan_batch(batch) end);return end
        if #batch.items==0 then pcl151741_finish_batch(batch,'No placed anchored builds found. Attach one build to each anchor.');return end
        batch.stack=nil;batch.seen=nil;batch.phase='ready'
        pcl15179_schedule(1,function() pcl151741_next_batch(batch) end)
    end)
    if not ok then pcl151741_finish_batch(batch,tostring(err)) end
end
function pcl151741_next_batch(batch)
    if PCL151741_BATCH~=batch then return end
    local ok,err=pcall(function()
        assert(not PCL151725_UPLOAD_PENDING and not pcl151727_draft(),'Another upload is still active')
        assert(is_valid(batch.panel),'Library closed or replaced; queue stopped')
        local forge=find_forge()
        assert(is_valid(forge) and is_valid(batch.forge) and forge:GetAddress()==batch.forge:GetAddress(),'Forge changed; queue stopped')
        local _,held=current_preview_14()
        assert(not is_valid(held),'A part is held; queue stopped without changing it')
        batch.index=batch.index+1
        local source=batch.items[batch.index]
        if not source then pcl151741_finish_batch(batch,'Uploaded '..batch.completed..' builds; each saved locally with its own Magic Word.');return end
        assert(is_valid(source.anchor),'Queued anchor became unavailable')
        local children=pcl151741_children(source.anchor)
        assert(#children==1 and children[1]:GetAddress()==source.root:GetAddress(),'Queued anchor attachment changed')
        source.nodes=pcl151741_nodes(source.root)
        source.host,source.gm=batch.host,batch.gm
        local draft=pcl151725_snapshot_held('Temporary preconstruction',source)
        batch.host,batch.gm=source.host,source.gm
        local stamp=(tostring(os.time())..tostring(math.floor(os.clock()*1000000))..tostring(batch.index)):gsub('%d',function(c)return string.char(97+tonumber(c)) end)
        draft.code='draft-'..stamp..'-batch';draft.batch=batch
        PCL151727_DRAFT=draft
        local saved,save_err=pcl151726_save(draft.code,draft.piece)
        assert(saved,'Temporary upload save failed: '..tostring(save_err))
        -- This cache is only an upload copy. No recovery manifest and no hand clear:
        -- originals stay placed, so Cancel must never reconstruct a duplicate.
        pcl151733_capture(draft.code,source.root,source.nodes,source.anchor)
        source.nodes=nil;draft.nodes=nil;draft.root=nil
        batch.phase='naming'
        pcl151710_set_menu_visible(true)
        pcl151727_show_form(batch.panel,draft)
        PCL151723_UI[batch.panel:GetAddress()].controls.PCL_MagicWordTitle:SetText(pcl15171_to_text('Name and upload build '..batch.index..' of '..#batch.items))
        pcl151741_message(batch.panel,'Build '..batch.index..' of '..#batch.items..' ('..draft.parts..' parts). Cancel stops the queue; placed builds stay unchanged.')
        PCL151723_UI[batch.panel:GetAddress()].controls.PCL_MagicWordInput:SetKeyboardFocus()
    end)
    if not ok then
        local draft=PCL151727_DRAFT
        if draft and draft.batch==batch then pcl151741_batch_error(draft,tostring(err))
        else pcl151741_finish_batch(batch,tostring(err)) end
    end
end
function pcl151741_batch_completed(draft,code)
    local batch=draft.batch
    if PCL151741_BATCH~=batch then return end
    batch.completed=batch.completed+1;batch.phase='ready'
    log('PCL15_17_41_BATCH_ITEM index='..batch.index..' code='..code)
    if batch.cancel_requested then pcl151741_finish_batch(batch,'Queue stopped. '..batch.completed..' builds uploaded; placed builds unchanged.');return end
    pcl15179_schedule(100,function() pcl151741_next_batch(batch) end)
end
function pcl151741_batch_error(draft,message)
    local batch=draft and draft.batch or PCL151741_BATCH
    if not batch or PCL151741_BATCH~=batch then return end
    if batch.cancel_requested and not PCL151725_UPLOAD_PENDING then pcl151741_cancel_batch(batch.panel);return end
    if draft and is_valid(batch.panel) then pcl151727_show_form(batch.panel,draft) end
    pcl151741_message(batch.panel,message)
end
function pcl151741_cancel_batch(panel)
    local batch=PCL151741_BATCH
    if not batch then return false end
    batch.cancel_requested=true
    if PCL151725_UPLOAD_PENDING then
        pcl151741_message(panel,'Stopping after the current upload reply; no further builds will upload.');return true
    end
    local draft=PCL151727_DRAFT
    if draft and draft.batch==batch then
        local cleaned,err=pcl151727_forget_draft(draft)
        if not cleaned then pcl151741_message(panel,'Upload copy cleanup failed. Cancel again to retry: '..tostring(err));return true end
    end
    pcl151741_finish_batch(batch,'Queue cancelled. '..batch.completed..' builds uploaded; placed builds unchanged.')
    return true
end
function pcl151741_upload_watchdog(request)
    if PCL151725_UPLOAD_PENDING~=request then return end
    if os.clock()-request.started>120 and not request.warned then
        request.warned=true
        pcl151725_upload_status('Upload is still pending; waiting for a reply without submitting a duplicate.',true)
        if request.batch then pcl151741_batch_error(request,'Still waiting for the upload reply. No duplicate upload was sent.') end
    end
    pcl15179_schedule(5000,function() pcl151741_upload_watchdog(request) end)
end
function pcl151741_toggle_carry(panel)
    local old=PCL151741_CARRY_ALL
    local ok,err=pcall(function()
        assert(not PCL151741_BATCH and not PCL151725_UPLOAD_PENDING and not PCL151719_IMPORT and not PCL151729_HANDOFF,'Finish the current operation first')
        local _,held=current_preview_14()
        assert(not is_valid(held),'Place the held item before changing pickup behavior')
        PCL151741_CARRY_ALL=not old
        local applied,apply_err=pcl15170_apply_asset_row()
        assert(applied,tostring(apply_err))
    end)
    if not ok then
        PCL151741_CARRY_ALL=old
        pcall(pcl15170_apply_asset_row)
        pcl151741_message(panel,tostring(err));return false
    end
    local state=PCL151723_UI[panel:GetAddress()]
    state.carry:SetCaption(pcl15171_to_text('Pick up whole build: '..(PCL151741_CARRY_ALL and 'On' or 'Off')))
    pcl151741_message(panel,'Pickup behavior updated for all existing anchors. '..(PCL151741_CARRY_ALL and 'Attached builds stay together.' or 'Normal game pickup behavior restored.'))
    return true
end


-- Native catalogue initialization can complete on the next game tick. Wait for
-- the exact actor in this same handling component, without raw hand reassignment.
function pcl151742_finish_anchor(request)
    if PCL151742_ANCHOR_REQUEST~=request then return end
    local ok,err=pcall(function()
        local forge=find_forge()
        assert(is_valid(forge) and is_valid(request.forge) and forge:GetAddress()==request.forge:GetAddress(),'Forge changed during anchor selection')
        local handling,preview=current_preview_14()
        assert(is_valid(handling) and is_valid(request.handling) and handling:GetAddress()==request.handling:GetAddress(),'Part handling changed during anchor selection')
        request.checks=request.checks+1
        if not is_valid(preview) then
            assert(request.checks<11,'Native catalogue did not return an anchor to the hand')
            pcl15179_schedule(50,function() pcl151742_finish_anchor(request) end)
            return
        end
        assert(pcl15167_is_exact_anchor_actor(preview),'Native catalogue returned a different held part; it was kept')
        local applied,apply_err=pcl15170_apply_mesh_to_actor(preview)
        assert(applied,tostring(apply_err))
        PCL151742_ANCHOR_REQUEST=nil
        log('PCL15_17_42_ANCHOR_HELD actor='..tostring(preview:GetAddress())..' forge='..tostring(forge:GetAddress())..' checks='..request.checks)
        pcl151741_message(request.panel,'Preconstruction Anchor selected.')
        if PCL151710_MENU_STATE and PCL151710_MENU_STATE.open then pcl151710_set_menu_visible(false) end
    end)
    if not ok then
        pcl151742_discard_spawn(request)
        PCL151742_ANCHOR_REQUEST=nil
        pcl151741_message(request.panel,'Place anchor failed: '..tostring(err))
    end
end


function pcl151743_anchor_scope(anchor,scope)
    if not is_valid(anchor) then return false,'invalid' end
    local stack,seen={{actor=anchor,route='self'}},{}
    local checked=0
    while #stack>0 do
        local entry=table.remove(stack)
        local actor=entry.actor
        if is_valid(actor) then
            local address=actor:GetAddress()
            if scope.targets[address] then return true,entry.route end
            if not seen[address] then
                seen[address]=true;checked=checked+1
                if checked>256 then return false,'ownership limit' end
                -- Transferred parts may retain a temp owner but have a live
                -- attachment in the player's Forge. Skip that owner branch;
                -- do not discard an independently valid attachment branch.
                if not pcl151115_is_retained_temp_forge(actor) then
                    local owner,parent,component_parent
                    pcall(function() owner=actor:GetOwner() end)
                    pcall(function() parent=actor:GetAttachParentActor() end)
                    pcall(function()
                        local component=actor:K2_GetRootComponent()
                        if is_valid(component) then
                            local attachment=component:GetAttachParent()
                            if is_valid(attachment) then component_parent=attachment:GetOwner() end
                        end
                    end)
                    if is_valid(owner) then stack[#stack+1]={actor=owner,route='owner'} end
                    if is_valid(parent) then stack[#stack+1]={actor=parent,route='attachment'} end
                    if is_valid(component_parent) then stack[#stack+1]={actor=component_parent,route='component attachment'} end
                end
            end
        end
    end
    return false,'outside current Forge'
end


function pcl151745_open_tick(request)
    if PCL151745_OPEN~=request then return end
    local state=PCL151710_MENU_STATE
    local forge=find_forge()
    if state~=request.state or not state or not is_valid(state.panel) or
       not is_valid(forge) or not is_valid(request.forge) or forge:GetAddress()~=request.forge:GetAddress() then
        PCL151745_OPEN=nil;return
    end
    request.checks=request.checks+1
    local prepare=request.anchor and pcl151761_prepare_parts_stage
        or (request.mode=='blades' and pcl15181_prepare_blade or pcl151717_prepare_hilt)
    local ok,ready=pcall(prepare,forge)
    if not ok or request.checks>=100 then
        PCL151745_OPEN=nil
        local stage=request.mode=='blades' and 'Blade' or 'Hilt'
        pcl151741_message(state.panel,not ok and ('Could not select '..stage..' mode: '..tostring(ready)) or stage..' mode did not become ready.')
        return
    end
    if ready then
        if request.anchor then
            PCL151745_OPEN=nil
            if state.open then pcl15171_click_anchor(state.panel) end
        else
            request.ready=true
            pcl151710_set_menu_visible(true)
        end
    else
        pcl15179_schedule(100,function() pcl151745_open_tick(request) end)
    end
end

-- Red camera line art on the native cube's -X face. One instanced component,
-- local transforms, no actor, collision, shadows, navigation or per-frame tick.
PCL151747_CAMERA_MARKS={}
function pcl151747_camera_segments()
    local segments={
        {-.78,-.18,-.22,-.18},{-.22,-.18,-.22,.16},
        {-.22,.16,-.78,.16},{-.78,.16,-.78,-.18},
        {-.65,.16,-.61,.24},{-.61,.24,-.45,.24},{-.45,.24,-.41,.16}
    }
    for i=0,11 do
        local a,b=i*math.pi/6,(i+1)*math.pi/6
        segments[#segments+1]={-.5+.105*math.cos(a),-.01+.105*math.sin(a),-.5+.105*math.cos(b),-.01+.105*math.sin(b)}
    end
    -- Rotate in the face plane so icon top (+Z before rotation) points
    -- toward the output hardpoint at local -Y.
    for _,segment in ipairs(segments) do
        for index=1,3,2 do
            local y,z=segment[index],segment[index+1]
            segment[index],segment[index+1]=-.5-z,y+.5
        end
    end
    return segments
end
function pcl151747_camera_stroke(segment)
    local dy,dz=segment[3]-segment[1],segment[4]-segment[2]
    local angle=math.atan(dz,dy)
    -- Stock cube spans local Y=-1..0. Place its origin at the segment's end,
    -- so scaling/rotation produces the requested line without a centre offset.
    return {Translation={X=-.509,Y=segment[3],Z=segment[4]},
        Rotation={X=math.sin(angle/2),Y=0,Z=0,W=math.cos(angle/2)},
        Scale3D={X=.012,Y=math.sqrt(dy*dy+dz*dz),Z=.02}}
end
function pcl151747_apply_camera_mark(actor,root)
    assert(pcl15167_is_exact_anchor_actor(actor) and is_valid(root),'Camera mark requires an exact anchor')
    local address=actor:GetAddress()
    local entry=PCL151747_CAMERA_MARKS[address]
    local face=entry and is_valid(entry.actor) and entry.face or 0
    if entry and (not is_valid(entry.actor) or not is_valid(entry.root) or entry.root:GetAddress()~=root:GetAddress()) then
        if is_valid(entry.component) then entry.component:K2_DestroyComponent(actor) end
        entry=nil;PCL151747_CAMERA_MARKS[address]=nil
    end
    if not entry or not is_valid(entry.component) then
        local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
        local class=StaticFindObject('/Script/Engine.InstancedStaticMeshComponent')
        assert(is_valid(class),'Camera mark component class unavailable')
        local component=actor:AddComponentByClass(class,true,identity,true)
        pcl151731_fresh(component)
        assert(is_valid(component),'Camera mark component allocation failed')
        local ok,err=pcall(function()
            component:SetMobility(2)
            component:SetStaticMesh(PCL15170_CUSTOM_MESH)
            component:SetCollisionEnabled(0)
            component:SetGenerateOverlapEvents(false)
            component:SetCastShadow(false)
            component:SetHiddenInSceneCapture(true)
            component:SetComponentTickEnabled(false)
            component.bCanEverAffectNavigation=false
            assert(component:K2_AttachToComponent(root,FName('None',EFindName.FNAME_Find),2,2,2,false),'Camera mark attachment failed')
            actor:FinishAddComponent(component,true,identity)
            local instances={}
            for _,segment in ipairs(pcl151747_camera_segments()) do instances[#instances+1]=pcl151747_camera_stroke(segment) end
            component:AddInstances(instances,false,false,false)
        end)
        if not ok then component:K2_DestroyComponent(actor);error(tostring(err)) end
        entry={actor=actor,root=root,component=component,face=face};PCL151747_CAMERA_MARKS[address]=entry
        log('PCL15_17_47_CAMERA_MARK face=-X local=true instances=19 collision=false capture_hidden=true')
    end
    if not is_valid(entry.mid) then
        local base=pcl15174_load_object('/Engine/EngineMaterials/EmissiveMeshMaterial.EmissiveMeshMaterial')
        assert(is_valid(base),'Camera mark material unavailable')
        entry.mid=entry.component:CreateDynamicMaterialInstance(0,base,FName('None',EFindName.FNAME_Find))
        pcl151731_fresh(entry.mid)
        assert(is_valid(entry.mid),'Camera mark red material unavailable')
        entry.mid:SetVectorParameterValue(pcl15170_existing_fname('Color'),{R=1,G=.005,B=.005,A=1})
    end
    local current=entry.component:GetMaterial(0)
    if not is_valid(current) or current:GetAddress()~=entry.mid:GetAddress() then entry.component:SetMaterial(0,entry.mid) end
    if entry.applied_face~=entry.face then
        entry.component:K2_SetRelativeTransform(pcl151751_face_transform(entry.face),false,{},true)
        entry.applied_face=entry.face
    end
    return true
end
function pcl151747_preview_basis(root,anchor)
    if is_valid(anchor) and pcl15167_is_exact_anchor_actor(anchor) then return anchor end
    local parent
    pcall(function() parent=root:GetAttachParentActor() end)
    if is_valid(parent) and pcl15167_is_exact_anchor_actor(parent) then return parent end
    return nil
end


-- One-shot capture lighting, owned by the transient camera and destroyed with
-- it on success or failure. No persistent Forge lights/materials are changed.
function pcl151748_preview_lights(camera,capture,radius)
    local class=StaticFindObject('/Script/Engine.PointLightComponent')
    assert(is_valid(class),'Thumbnail light class unavailable')
    for _,spec in ipairs({{X=.9,Y=-.8,Z=.7,intensity=4},{X=.7,Y=.8,Z=-.25,intensity=2}}) do
        local transform={Translation={X=radius*spec.X,Y=radius*spec.Y,Z=radius*spec.Z},
            Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
        local light=camera:AddComponentByClass(class,false,transform,true)
        pcl151731_fresh(light)
        assert(is_valid(light),'Thumbnail light allocation failed')
        light:SetMobility(2)
        light:SetUseInverseSquaredFalloff(false)
        light:SetIntensityUnits(0)
        light:SetLightFalloffExponent(2)
        light:SetAttenuationRadius(radius*10)
        light:SetLightColor({R=1,G=1,B=1,A=1},false)
        light:SetIntensity(spec.intensity)
        light:SetCastShadows(false)
        light:SetAffectGlobalIllumination(false)
        light:SetAffectReflection(false)
        light:SetVolumetricScatteringIntensity(0)
        light:SetComponentTickEnabled(false)
        light.bCanEverAffectNavigation=false
        camera:FinishAddComponent(light,false,transform)
    end
    local settings=capture.PostProcessSettings
    settings.bOverride_AutoExposureBias=true;settings.AutoExposureBias=.75
    settings.bOverride_BloomIntensity=true;settings.BloomIntensity=0
    settings.bOverride_VignetteIntensity=true;settings.VignetteIntensity=0
    capture.PostProcessBlendWeight=1
end

-- Camera face cycling moves only the marker component and capture viewpoint.
function pcl151751_face_transform(face)
    local angle=(face or 0)%4*math.pi/2
    return {Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=math.sin(angle/2),Z=0,W=math.cos(angle/2)},Scale3D={X=1,Y=1,Z=1}}
end
function pcl151751_view_axes(anchor)
    local entry=PCL151747_CAMERA_MARKS[anchor:GetAddress()]
    local face=entry and is_valid(entry.actor) and entry.face or 0
    local f,z,side=anchor:GetActorForwardVector(),anchor:GetActorUpVector(),anchor:GetActorRightVector()
    local normal
    if face==1 then normal=z
    elseif face==2 then normal=f
    elseif face==3 then normal={X=-z.X,Y=-z.Y,Z=-z.Z}
    else normal={X=-f.X,Y=-f.Y,Z=-f.Z} end
    return normal,{X=-side.X,Y=-side.Y,Z=-side.Z}
end
function pcl151751_current_context()
    local forge=find_forge()
    if not is_valid(forge) then return nil end
    local frontend=forge.ForgeModeFrontend
    local ui=is_valid(frontend) and frontend.ForgeModeUi or nil
    if not is_valid(ui) or not is_valid(ui.ForgeMode) or ui.ForgeMode:GetAddress()~=forge:GetAddress() then return nil end
    return forge,ui
end
function pcl151751_camera_target(forge,ui)
    local menu=PCL151710_MENU_STATE
    if (menu and menu.open) or PCL151745_OPEN or PCL151719_IMPORT or PCL151729_HANDOFF or PCL151741_BATCH or PCL151725_UPLOAD_PENDING then return nil end
    for _,name in ipairs({'FilterText','EditableText_65'}) do
        local field=ui[name]
        if is_valid(field) and field:HasKeyboardFocus() then return nil end
    end
    if is_valid(ui.ShareWindow) and ui.ShareWindow:IsVisible() then return nil end
    local stage_class=StaticFindObject('/Script/Bladesong.UWSwordmakingStageButton')
    local container=ui.SwordmakingStageButtonContainer
    local hilt=false
    if is_valid(stage_class) and is_valid(container) then
        for i=0,container:GetChildrenCount()-1 do
            local stage=container:GetChildAt(i)
            if is_valid(stage) and stage:IsA(stage_class) and pcl15171_from_text(stage.Title):lower():find('hilt',1,true) and stage:IsStageActive() then hilt=true;break end
        end
    end
    if not hilt then return nil end
    local _,held=current_preview_14()
    if is_valid(held) then
        if pcl15167_is_exact_anchor_actor(held) then return held end
        return nil
    end
    local player=ui:GetOwningPlayer()
    if not is_valid(player) then return nil end
    local hit={}
    -- Visibility channel, same physical cube collision the user points at.
    if not player:GetHitResultUnderCursor(3,true,hit) then return nil end
    local actor=require('UEHelpers').GetActorFromHitResult(hit)
    if not pcl15167_is_exact_anchor_actor(actor) then return nil end
    local targets={[forge:GetAddress()]=true}
    local root,blade=forge:GetRootSwordPartActor(),forge:GetBladeMesh()
    if is_valid(root) then targets[root:GetAddress()]=true end
    if is_valid(blade) then targets[blade:GetAddress()]=true end
    local belongs=pcl151743_anchor_scope(actor,{forge=forge,targets=targets})
    return belongs and actor or nil
end
function pcl151751_rotate_camera()
    if PCL151751_LAST_R and os.clock()-PCL151751_LAST_R<.2 then return end
    local forge,ui=pcl151751_current_context()
    if not forge then return end
    local target=pcl151751_camera_target(forge,ui)
    if not is_valid(target) then return end
    local root=target:K2_GetRootComponent()
    pcl151747_apply_camera_mark(target,root)
    local entry=PCL151747_CAMERA_MARKS[target:GetAddress()]
    local old=entry.face or 0
    entry.face=(old+1)%4
    local ok,err=pcall(pcl151747_apply_camera_mark,target,root)
    if not ok then entry.face=old;pcall(pcl151747_apply_camera_mark,target,root);error(tostring(err)) end
    PCL151751_LAST_R=os.clock()
    log('PCL15_17_51_CAMERA_FACE anchor='..target:GetAddress()..' face='..entry.face..' cube_transform_changed=false')
    pcl151751_update_hint()
end
function pcl151755_restore_hint(entry)
    if not entry then return end
    if is_valid(entry.native) and is_valid(entry.box) and is_valid(entry.stack) then
        local index=entry.box:GetChildIndex(entry.stack)
        if index>=0 then
            entry.native:RemoveFromParent()
            assert(entry.box:ReplaceOverlayChildAt(index,entry.native),'Could not restore native hint layout')
        end
    end
    if is_valid(entry.label) then entry.label:RemoveFromParent() end
end
function pcl151751_update_hint()
    local ok,err=pcall(function()
        local forge,ui=pcl151751_current_context()
        local entry=PCL151752_HINT
        if entry and (not ui or not is_valid(entry.ui) or entry.ui:GetAddress()~=ui:GetAddress()) then
            pcl151755_restore_hint(entry)
            PCL151752_HINT=nil;entry=nil
        end
        if not forge then return end
        local target=pcl151751_camera_target(forge,ui)
        if not is_valid(target) then
            if entry and is_valid(entry.label) then
                entry.label:SetVisibility(1)
                entry.hint_slot:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
            end
            return
        end
        if not entry or not is_valid(entry.label) then
            local native=pcl15171_widget_by_name(ui,'GameplayHintText')
            assert(is_valid(native),'Packed GameplayHintText not found in current Forge tree')
            local box=native:GetParent()
            assert(is_valid(box) and box:GetFName():ToString()=='GameplayHintBox','Unexpected native gameplay hint parent')
            local index=box:GetChildIndex(native)
            assert(index>=0,'Native hint overlay index unavailable')
            local label=pcl151723_new(ui,'RichTextBlock')
            label:SetVisibility(1)
            label:SetTextStyleSet(native:GetTextStyleSet())
            label:SetDefaultFont(native.DefaultTextStyle.Font)
            label:SetDefaultColorAndOpacity(native.DefaultTextStyle.ColorAndOpacity)
            label:SetText(pcl15171_to_text('<key>R</> Rotate preview camera'))
            label:SetAutoWrapText(false)
            local stack=pcl151723_new(ui,'VerticalBox')
            stack:SetVisibility(4)
            local hint_slot=pcl151723_vadd(stack,label,0,10)
            hint_slot:SetHorizontalAlignment(2)
            -- Replace content inside the existing OverlaySlot, preserving its
            -- anchors, alignment and margins. Slate stacks two measured rows;
            -- no guessed height or overlapping Overlay children are involved.
            assert(box:ReplaceOverlayChildAt(index,stack),'Native hint stack insertion failed')
            local attached,attach_error=pcall(pcl151723_vadd,stack,native,0,0)
            if not attached then
                box:ReplaceOverlayChildAt(index,native)
                label:RemoveFromParent()
                error(tostring(attach_error))
            end
            entry={ui=ui,label=label,stack=stack,box=box,native=native,hint_slot=hint_slot}
            PCL151752_HINT=entry
            log('PCL15_17_55_CAMERA_HINT native_overlay_slot_preserved=true vertical_stack=true')
        end
        entry.hint_slot:SetPadding({Left=0,Top=0,Right=0,Bottom=10})
        entry.label:SetVisibility(4)
    end)
    if not ok and not PCL151755_HINT_ERROR then PCL151755_HINT_ERROR=true;log('PCL15_17_55_HINT_ERROR '..tostring(err)) end
end
function pcl151751_image_tooltip(panel,thumbnail,texture)
    local size=pcl151723_new(panel,'SizeBox')
    size:SetWidthOverride(640);size:SetHeightOverride(640)
    local border=pcl151723_new(panel,'Border')
    border:SetBrushColor({R=.008,G=.008,B=.006,A=.98})
    border:SetPadding({Left=10,Top=10,Right=10,Bottom=10})
    local fit=pcl151723_new(panel,'ScaleBox')
    fit:SetStretch(1)
    local image=pcl151723_new(panel,'Image')
    image:SetBrushFromTexture(texture,true)
    fit:SetContent(image);border:SetContent(fit);size:SetContent(border)
    -- Slate provides delayed hover display, edge clamping, dismissal and
    -- lifetime management. This is an image widget, not the old text tooltip.
    thumbnail:SetToolTip(size)
end
__PCL159_REAL_REGISTER_KEY_BIND(Key.R,function()
    run_game_thread(pcl151751_rotate_camera)
end)


-- Bootstrap the saved anchor identity before native Forge reconstruction.
function pcl151756_prepare_anchor(reason)
    if PCL151756_PRELOAD_ACTIVE then return false,'anchor bootstrap already active' end
    local previous=PCL151756_PRELOAD_ACTIVE
    PCL151756_PRELOAD_ACTIVE=true
    local ok,result=pcall(function()
        local dev=pcl15174_load_object(PCL15165_DEV_TABLE_FULL:gsub('^DataTable ',''))
        local main=pcl15174_load_object(PCL15165_MAIN_TABLE_FULL:gsub('^DataTable ',''))
        assert(is_valid(dev) and is_valid(main),'Anchor backing tables unavailable')
        local ready,err=pcl15166_ensure_current_anchor(reason)
        assert(ready,tostring(err))
        PCL151756_WARM_OBJECTS={dev=dev,main=main,mesh=PCL15170_CUSTOM_MESH,class=PCL15170_CUSTOM_BP_CLASS}
        return true
    end)
    PCL151756_PRELOAD_ACTIVE=previous
    if not ok then return false,tostring(result) end
    log('PCL15_17_56_ANCHOR_READY before_rebuild=true reason='..tostring(reason))
    return true,nil
end
function pcl151756_rebind_saved_anchors(piece,context)
    if not is_valid(piece) then return 0 end
    local class=context.class
    if not is_valid(class) or not piece:IsA(class) then return 0 end
    if not PCL151756_REBIND then
        local fn,why=BMF_PCL_NATIVE(pcl151112_script_dir()..'pcl_anchor_reload_151756.dll','pcl_anchor_rebind_piece')
        assert(type(fn)=='function','Anchor reload helper unavailable: '..tostring(why))
        PCL151756_REBIND=fn
    end
    -- Avoid UE4SS nested transient-struct iteration in the synchronous hook.
    -- The guarded native helper touches only the two cached row-handle fields.
    local repaired=PCL151756_REBIND(piece:GetAddress(),piece:GetClass():GetAddress(),
        context.table_address,context.table_class_address,context.name_index)
    assert(type(repaired)=='number' and repaired>=0,'Saved anchor resolution refused: '..tostring(repaired))
    return repaired
end
function pcl151756_before_forge()
    -- Drop the Creative overlays at the start of Forge entry, before the
    -- anchor scan and before the game constructs the Forge viewport.
    PCL151760_HOME_RETURN=nil
    PCL151760_FORGE_ENTRY_UNTIL=os.clock()+0.25
    if PCL151762_HOME then
        local ok,err=pcall(pcl151762_cleanup_home)
        if not ok then log('PCL_CREATIVE_ENTRY_CLEANUP_ERROR '..tostring(err)) end
    end
    local started=os.clock()
    local ok,err=pcall(function()
        local ready,why=pcl151756_prepare_anchor('before_EnterForgeMode')
        assert(ready,tostring(why))
        -- Do not dereference RemoteUnrealParam UObject values in this hook:
        -- this UE4SS build crashes while resolving that wrapper. Enumerate the
        -- actual typed data objects once at the load boundary instead.
        local pieces=FindAllOf('Piece') or {}
        assert(#pieces<=1024,'Too many loaded Piece objects for synchronous anchor resolution')
        if #pieces==0 then return end
        local dst,err=pcl15165_exact_row(PCL15165_DEV_TABLE_FULL,PCL15161_ROW_NAME)
        assert(dst and is_valid(dst.data_table),tostring(err))
        local context={
            class=StaticFindObject('/Script/Bladesong.Piece'),
            table_address=dst.data_table:GetAddress(),
            table_class_address=dst.data_table:GetClass():GetAddress(),
            name_index=pcl15170_existing_fname(PCL15161_ROW_NAME):GetComparisonIndex()
        }
        local repaired=0
        for _,piece in ipairs(pieces) do
            repaired=repaired+pcl151756_rebind_saved_anchors(piece,context)
        end
        log('PCL15_17_56_ANCHOR_REBOUND count='..repaired..' pieces='..#pieces..' topology_unchanged=true seconds='..string.format('%.3f',os.clock()-started))
    end)
    if not ok then log('PCL15_17_56_ANCHOR_BOOTSTRAP_FAILED '..tostring(err)) end
end
function pcl151756_before_button()
    local warm=PCL151756_WARM_OBJECTS
    if warm and is_valid(warm.dev) and is_valid(warm.main) and is_valid(warm.mesh) and is_valid(warm.class) then return end
    -- UI input is on the game thread and occurs before opening a saved sword.
    local ready,err=pcl151756_prepare_anchor('before_UI_action')
    if not ready and err~=PCL151756_LAST_BOOT_ERROR then
        PCL151756_LAST_BOOT_ERROR=err;log('PCL15_17_56_ANCHOR_BOOTSTRAP_WAIT '..tostring(err))
    end
end
function pcl151756_finish_library_import(request)
    local piece=request.temp:GetPiece()
    assert(is_valid(piece),'Downloaded build data unavailable')
    pcl151724_capture_metadata(request)
    local cached,err=pcl151726_save(request.code,piece)
    assert(cached,'Could not save imported build locally: '..tostring(err))
    local panel=request.context
    if is_valid(panel) then
        pcl151727_load_preview(request.code,panel)
        pcl15171_refresh_dynamic(panel)
        pcl151727_queue_previews(panel)
    end
    -- The existing suppressed host retains data only; do not rebuild actors,
    -- switch the active Piece, touch the hand or invoke the placement handoff.
    pcl151719_status('Build saved locally. Choose Place build when ready.')
    log('PCL15_17_56_LIBRARY_IMPORT code='..request.code..' saved_local=true hand_unchanged=true actors_built=0')
end
function pcl151756_install_hooks()
    for _,spec in ipairs({
        {'/Script/CommonUI.CommonButtonBase:HandleButtonClicked',pcl151756_before_button},
        {'/Script/Bladesong.BladesongGameMode:EnterForgeMode',pcl151756_before_forge}
    }) do
        local path,callback=spec[1],spec[2]
        local ok,err=pcall(function() RegisterHook(path,callback,function()end) end)
        log('PCL15_17_56_RELOAD_HOOK path='..path..' installed='..tostring(ok)..(not ok and (' error='..tostring(err)) or ''))
    end
end
pcl151756_install_hooks()

-- A hidden reconstruction Forge must never keep a streamed backdrop or lights.
PCL151757_ENV_HOSTS={}
PCL151757_ENV_FIELDS={'CurrentEnvironment','LoadingEnvironment','CurrentLightEnvironment','LoadingLightEnvironment'}
function pcl151757_track_temp(host,owner)
    if not is_valid(host) or not is_valid(owner) or host:GetAddress()==owner:GetAddress() then return false end
    PCL151757_ENV_HOSTS[host:GetAddress()]={host=host,owner=owner,cleaned={}}
    return true
end
function pcl151757_hide_temp_environments(host)
    if not is_valid(host) then return 0 end
    local record=PCL151757_ENV_HOSTS[host:GetAddress()]
    if not record then return 0 end
    local protected={}
    local function protect(forge)
        if not is_valid(forge) or forge:GetAddress()==host:GetAddress() then return end
        for _,field in ipairs(PCL151757_ENV_FIELDS) do
            local level=pcl151730_field(forge,field)
            if is_valid(level) then protected[level:GetAddress()]=true end
        end
    end
    -- Preserve both the original live Forge and the current GameMode selection.
    protect(record.owner)
    local mode=FindFirstOf('BladesongGameMode')
    local selected=is_valid(mode) and pcl151730_field(mode,'ForgeMode') or nil
    if is_valid(selected) and selected:GetAddress()==host:GetAddress() then return 0 end
    protect(selected)
    local cleaned=0;local seen={}
    for _,field in ipairs(PCL151757_ENV_FIELDS) do
        local level=pcl151730_field(host,field)
        if is_valid(level) then
            local address=level:GetAddress()
            if not protected[address] and not seen[address] and not (record.cleaned[address] and is_valid(record.cleaned[address])) then
                seen[address]=true
                local ok,err=pcall(function()
                    level:SetShouldBeVisible(false)
                    level:SetShouldBeLoaded(false)
                    level:SetIsRequestingUnloadAndRemoval(true)
                end)
                if ok then record.cleaned[address]=level;cleaned=cleaned+1 else log('PCL15_17_57_TEMP_ENV_ERROR field='..field..' error='..tostring(err)) end
            end
        end
    end
    if cleaned>0 then log('PCL15_17_57_TEMP_ENV_CLEANUP levels='..cleaned..' active_environment_preserved=true') end
    return cleaned
end
function pcl151757_streaming_finished(context)
    if context then
        local host=pcl151114_unwrap(context)
        if is_valid(host) and PCL151757_ENV_HOSTS[host:GetAddress()] then pcl151757_hide_temp_environments(host) end
        return
    end
    -- Called only at native environment completion, never from a frame scan.
    for key,record in pairs(PCL151757_ENV_HOSTS) do
        if is_valid(record.host) then
            pcl151757_hide_temp_environments(record.host)
        else PCL151757_ENV_HOSTS[key]=nil end
    end
end
function pcl151757_install_environment_hooks()
    for _,path in ipairs({'/Script/Bladesong.ForgeMode:EnvironmentLoaded','/Script/Bladesong.ForgeMode:LightEnvironmentLoaded'}) do
        local ok,err=pcall(function()RegisterHook(path,function()end,pcl151757_streaming_finished)end)
        log('PCL15_17_57_ENV_HOOK path='..path..' installed='..tostring(ok)..(not ok and (' error='..tostring(err)) or ''))
    end
end
pcl151757_install_environment_hooks()

-- Timings distinguish library UI work from native reconstruction and cleanup.
PCL151758_MENU_BASE=pcl151710_set_menu_visible
function pcl151710_set_menu_visible(visible)
    local started=os.clock()
    PCL151758_MENU_BASE(visible)
    if visible then log('PCL15_17_58_TIMING stage=library_open seconds='..string.format('%.3f',os.clock()-started)) end
end


-- Temporary and active managers can reference the same editor handles. Check
-- the live player's pools before hiding any temporary presentation object.
function pcl151758_active_helpers(active)
    local protected={}
    local function add(obj)if is_valid(obj) then protected[obj:GetAddress()]=true end end
    local function field(obj,name)return pcl151730_field(obj,name)end
    local function pool(obj,name)
        local array=field(obj,name)
        if array then pcall(function()array:ForEach(function(_,v)add(pcl151114_unwrap(v))end)end) end
    end
    add(active)
    local frontend=field(active,'ForgeModeFrontend');add(frontend)
    local handling=field(frontend,'SwordPartHandling');add(handling)
    pool(handling,'SwordPartSlotActorPool')
    for _,name in ipairs({'BendLineRenderer','MaterialPreviewActor','MaterialNotAllowedActor'}) do add(field(handling,name)) end
    local manager=field(frontend,'InteractableManager');add(manager)
    pool(manager,'InteractableElements')
    add(field(manager,'BestInteractableElement'));add(field(manager,'CurrentlyMovingInteractableElement'))
    local interaction=field(frontend,'BladeInteraction');add(interaction)
    pool(interaction,'Interactables')
    for _,name in ipairs({'IntensityLineRenderer','DragLineRenderer','InteractableRangeX','InteractableRangeY','InteractableBlendX','InteractableBlendY'}) do add(field(interaction,name)) end
    return protected
end


-- Library input capture belongs to one Forge visit, never the next build.
function pcl151760_release_input(reason)
    local state=PCL151710_MENU_STATE
    local player=PCL151760_INPUT_PLAYER
    if not is_valid(player) and state and is_valid(state.catalogue) then
        player=state.catalogue:GetOwningPlayer()
    end
    if not is_valid(player) then
        local forge=find_forge()
        local frontend=is_valid(forge) and forge.ForgeModeFrontend or nil
        local ui=is_valid(frontend) and frontend.ForgeModeUi or nil
        if is_valid(ui) then player=ui:GetOwningPlayer() end
    end
    if state then
        state.open=false
        if is_valid(state.panel) then state.panel:SetVisibility(1) end
        if is_valid(state.close) then state.close:SetVisibility(1) end
        if is_valid(state.dismiss) then state.dismiss:SetVisibility(1) end
    end
    PCL151745_OPEN=nil
    local lib=pcl15171_widget_library()
    if not is_valid(player) or not is_valid(lib) then return false end
    lib:SetInputMode_GameAndUIEx(player,nil,0,false,false)
    PCL151760_INPUT_PLAYER=nil;PCL151760_INPUT_LOCKED=false
    log('PCL15_17_60_INPUT_RELEASE reason='..tostring(reason)..' camera_input_restored=true')
    return true
end
function pcl151760_before_leave()
    if PCL151760_INPUT_LOCKED or PCL151710_MENU_STATE then pcl15177_reset_forge_references() end
end
function pcl151760_entered_forge()
    PCL151760_HOME_RETURN=nil
    if not PCL151760_INPUT_LOCKED then return end
    local expected=find_forge()
    if not is_valid(expected) then return end
    local checks=0
    local function refresh()
        local forge=find_forge()
        if not is_valid(forge) or not is_valid(expected) or forge:GetAddress()~=expected:GetAddress() then return end
        -- Do not steal focus if the user deliberately opens the new library.
        if PCL151710_MENU_STATE and PCL151710_MENU_STATE.open then return end
        checks=checks+1
        if not pcl151760_release_input('entered_build') and checks<5 then pcl15179_schedule(50,refresh) end
    end
    pcl15179_schedule(1,refresh)
end
function pcl151760_returned_from_forge()
    PCL151760_FORGE_ENTRY_UNTIL=nil
    local request={}
    PCL151760_HOME_RETURN=request
    local attempts=0
    local function refresh()
        if PCL151760_HOME_RETURN~=request or PCL151762_HOME then return end
        attempts=attempts+1
        local ok,err=pcall(pcl151762_monitor_home)
        if not ok then log('PCL_CREATIVE_RETURN_ERROR '..tostring(err)) end
        if not PCL151762_HOME and attempts<8 then pcl15179_schedule(16,refresh) end
    end
    pcl15179_schedule(1,refresh)
end
function pcl151760_home_shown()
    if not PCL151759_SCRIPT_READY then return end
    -- The game's home transition has just finished. Mount the library before
    -- returning to the frame, with the normal monitor available if UI is late.
    local ok,err=pcall(pcl151762_monitor_home)
    if not ok then log('PCL_CREATIVE_RETURN_ERROR '..tostring(err)) end
end
function pcl151760_install_hooks()
    for _,spec in ipairs({
        {'/Script/Bladesong.BladesongGameMode:GoToHomeScreen',function()end,pcl151760_home_shown},
        {'/Script/Bladesong.BladesongGameMode:LeaveAnyMode',pcl151760_before_leave,pcl151760_returned_from_forge},
        {'/Script/Bladesong.BladesongGameMode:EnterForgeMode',pcl151760_before_leave,pcl151760_entered_forge}
    }) do
        local ok,err=pcall(function()RegisterHook(spec[1],spec[2],spec[3])end)
        log('PCL15_17_60_INPUT_HOOK path='..spec[1]..' installed='..tostring(ok)..(not ok and (' error='..tostring(err)) or ''))
    end
end
pcl151760_install_hooks()


PCL151761_MODE='parts'
PCL151761_PARTS_DIR=PCL15171_LIBRARY_DIR
PCL151761_PARTS_PATH=PCL15171_LIBRARY_PATH
PCL151761_BLADE_DIR=PCL151761_PARTS_DIR..'blades\\'
function pcl151761_bridge()
    if PCL151761_BRIDGE then return PCL151761_BRIDGE end
    local path=pcl151112_script_dir()..'pcl_blade_library_151761.dll'
    local bridge={}
    for _,name in ipairs({'probe','store','restore','rebuild','lines','valid','copy_word'}) do
        local fn,err=BMF_PCL_NATIVE(path,'pcl_cache_'..name)
        assert(type(fn)=='function',tostring(err));bridge[name]=fn
    end
    for _,name in ipairs({'snapshot','apply','refresh','send','mkdir'}) do
        local fn,err=BMF_PCL_NATIVE(path,'pcl_blade_'..name)
        assert(type(fn)=='function',tostring(err));bridge[name]=fn
    end
    local probe,err=BMF_PCL_NATIVE(path,'pcl_blade_probe')
    local status=type(probe)=='function' and probe()
    assert(status==1,'Blade helper refused this executable: status='..tostring(status)..' '..tostring(err))
    PCL151761_BRIDGE=bridge
    return bridge
end
PCL151761_PART_CACHE=pcl151726_bridge
function pcl151726_bridge()
    if PCL151761_MODE=='blades' then return pcl151761_bridge() end
    return PCL151761_PART_CACHE()
end
PCL151761_PART_UPLOAD=pcl151725_bridge
function pcl151725_bridge()
    if PCL151761_MODE=='blades' then return pcl151761_bridge() end
    return PCL151761_PART_UPLOAD()
end
PCL151761_PART_SLOT=pcl151726_slot
function pcl151726_slot(code)
    local slot=PCL151761_PART_SLOT(code)
    return PCL151761_MODE=='blades' and slot:gsub('^PCL26_','PCLB61_') or slot
end
PCL151761_HILT=pcl151717_prepare_hilt
function pcl151761_prepare_parts_stage(forge)
    return PCL151761_HILT(forge)
end
function pcl151717_prepare_hilt(forge)
    if PCL151761_MODE=='blades' then return is_valid(forge) end
    return PCL151761_HILT(forge)
end
function pcl151761_build_tabs(panel,column)
    local state=PCL151723_UI[panel:GetAddress()]
    local row=pcl151723_new(panel,'HorizontalBox')
    state.parts_tab=pcl151723_button(panel,'Parts',48)
    state.blades_tab=pcl151723_button(panel,'Blades',48)
    pcl15171_bind_button(state.parts_tab,{kind='library_parts_tab',panel=panel})
    pcl15171_bind_button(state.blades_tab,{kind='library_blades_tab',panel=panel})
    pcl151723_hadd(row,state.parts_tab,true,12);pcl151723_hadd(row,state.blades_tab,true,0)
    pcl151723_vadd(column,row,0,12)
end
function pcl151761_update_controls(panel)
    local state=is_valid(panel) and PCL151723_UI[panel:GetAddress()]
    if not state then return end
    local blades=PCL151761_MODE=='blades'
    if is_valid(state.parts_tab) then state.parts_tab:SetIsEnabled(blades) end
    if is_valid(state.blades_tab) then state.blades_tab:SetIsEnabled(not blades) end
    for _,widget in ipairs({state.controls.PCL_AnchorButton,state.recovery,state.carry}) do
        if is_valid(widget) then widget:SetVisibility(blades and 1 or 0) end
    end
    if is_valid(state.upload) then state.upload:SetCaption(pcl15171_to_text(blades and 'Upload current blade' or 'Upload')) end
    if is_valid(state.saved_title) then state.saved_title:SetText(pcl15171_to_text(blades and 'BLADES' or 'PARTS')) end
    if is_valid(state.empty) then state.empty:SetText(pcl15171_to_text(blades and 'Import a Magic Word to save its blade here.' or 'Import a Magic Word to add your first build.')) end
end
function pcl15181_prepare_blade(forge)
    local stage_class = StaticFindObject('/Script/Bladesong.UWSwordmakingStageButton')
    if not is_valid(stage_class) then return false end
    local frontend=is_valid(forge) and forge.ForgeModeFrontend or nil
    local active_ui=is_valid(frontend) and frontend.ForgeModeUi or nil
    for _,ui in ipairs(is_valid(active_ui) and {active_ui} or {}) do
        if is_valid(ui) and is_valid(ui.ForgeMode) and
           ui.ForgeMode:GetAddress() == forge:GetAddress() then
            local container = ui.SwordmakingStageButtonContainer
            if is_valid(container) then
                for index=0,container:GetChildrenCount()-1 do
                    local stage = container:GetChildAt(index)
                    if is_valid(stage) and stage:IsA(stage_class) then
                        local title = pcl15171_from_text(stage.Title)
                        if type(title)=='string' and title:lower():find('blade',1,true) then
                            if stage:IsStageActive() then return true end
                            if not is_valid(stage.Button) then return false end
                            stage.Button:HandleButtonClicked()
                            PCL151715_VALIDATION_CACHE = {}
                            log('PCL15_18_1_BLADE_REQUEST stock_stage_button=true')
                            return false
                        end
                    end
                end
            end
        end
    end
    return false
end


function pcl151761_switch(panel,mode)
    local ok,err=pcall(function()
        assert(mode=='parts' or mode=='blades','Unknown library mode')
        if mode==PCL151761_MODE then return end
        local state=PCL151723_UI[panel:GetAddress()]
        assert(not PCL151719_IMPORT and not PCL151725_UPLOAD_PENDING and not PCL151741_BATCH and not PCL151729_HANDOFF,'Finish the current import or upload first.')
        assert(not state.magic_open and not pcl151727_draft(),'Finish or cancel the current form before switching tabs.')
        PCL151761_MODE=mode
        PCL15171_LIBRARY_DIR=mode=='blades' and PCL151761_BLADE_DIR or PCL151761_PARTS_DIR
        PCL15171_LIBRARY_PATH=mode=='blades' and (PCL15171_LIBRARY_DIR..'library.index') or PCL151761_PARTS_PATH
        PCL151727_PREVIEW_QUEUE=nil;PCL151724_PREVIEWS={};PCL151730_PREVIEW_CHECKED={}
        pcl15171_load_library();pcl151724_load_metadata()
        pcl15171_refresh_dynamic(panel);pcl151727_queue_previews(panel)
        pcl15171_set_status(panel,'')
        if mode=='blades' then pcl15181_prepare_blade(find_forge())
        else pcl151717_prepare_hilt(find_forge()) end
        log('PCL15_17_61_LIBRARY_MODE mode='..mode)
    end)
    if not ok then pcl15171_set_status(panel,tostring(err)) end
    return ok
end
function pcl151761_fresh_piece(owner,source)
    local piece=StaticConstructObject(source:GetClass(),owner);pcl151731_fresh(piece)
    assert(is_valid(piece),'Could not allocate blade data')
    piece.CurrentSwordmakingStage=source.CurrentSwordmakingStage
    return piece
end
function pcl151761_capture(code,forge,piece,active,gm,rebuild)
    local ok,err=pcall(function()
        local bridge=pcl151761_bridge()
        if rebuild then
            assert(bridge.rebuild(forge:GetAddress(),piece:GetAddress(),active:GetAddress(),gm:GetAddress())==1,'Blade preview construction failed')
            pcl151113_restore_game_mode_forge(gm,active,'BLADE_PREVIEW')
            assert(bridge.refresh(forge:GetAddress(),piece:GetAddress())==1,'Blade preview refresh failed')
        end
        local blade=forge:GetBladeMesh()
        assert(is_valid(blade) and blade.PolyCount>0,'This design has no visible blade')
        if rebuild then
            blade:SetActorHiddenInGame(false)
            for _,name in ipairs({'ProceduralMeshComponent','TangProceduralMeshComponent'}) do
                local component=blade[name]
                if is_valid(component) then component:SetVisibility(true,false);component:SetHiddenInGame(false,false) end
            end
        end
        assert(pcl151733_capture(code,blade,{blade},nil),'Blade preview capture failed')
    end)
    if rebuild and is_valid(forge) then
        pcall(function()pcl151113_restore_game_mode_forge(gm,active,'BLADE_PREVIEW_DONE');pcl151113_make_temp_inert(forge);pcl151114_quarantine_temp_presentation(forge)end)
    end
    if not ok then log('PCL15_17_61_BLADE_PREVIEW_UNAVAILABLE '..tostring(err)) end
    return ok
end
function pcl151761_cached_piece(code,owner,active)
    local statics=gameplay_statics_15();local class=StaticFindObject('/Script/Bladesong.CreativeModeSave')
    local save=statics:LoadGameFromSlot(pcl151726_slot(code),0)
    assert(is_valid(save) and is_valid(class) and save:GetClass():GetAddress()==class:GetAddress(),'Saved blade unavailable')
    local piece=pcl151761_fresh_piece(owner,active)
    assert(pcl151761_bridge().restore(save:GetAddress(),piece:GetAddress(),class:GetAddress(),active:GetClass():GetAddress())==1,'Blade data restore failed')
    return piece
end
function pcl151761_apply(panel,code,completed_request)
    local ok,err=pcall(function()
        assert((not PCL151719_IMPORT or PCL151719_IMPORT==completed_request) and not PCL151725_UPLOAD_PENDING and not PCL151741_BATCH and not PCL151729_HANDOFF,'Finish the current operation first')
        local forge=find_forge();assert(is_valid(forge),'Open the Forge first')
        local _,held=current_preview_14();assert(not is_valid(held),'Place the held part before changing the blade')
        local active=forge:GetPiece();assert(is_valid(active),'Current build unavailable')
        local root=forge:GetRootSwordPartActor();local blade=forge:GetBladeMesh()
        assert(is_valid(root) and is_valid(blade),'Current Forge geometry unavailable')
        local source=pcl151761_cached_piece(code,panel,active)
        -- Synchronize the current live attachment graph before preserving it.
        forge:SerializeSwordPartActorsToData()
        local count=#active.WeaponDesignDefinition.AppliedSwordParts
        local merged=pcl151761_fresh_piece(panel,active);local backup=pcl151761_fresh_piece(panel,active)
        local status=pcl151761_bridge().apply(forge:GetAddress(),active:GetAddress(),source:GetAddress(),merged:GetAddress(),backup:GetAddress(),active:GetClass():GetAddress())
        assert(status==1,status==-82 and 'Blade replacement stopped; original blade restored.' or ('Blade replacement refused ('..tostring(status)..')'))
        assert(forge:GetPiece():GetAddress()==active:GetAddress() and forge:GetRootSwordPartActor():GetAddress()==root:GetAddress() and forge:GetBladeMesh():GetAddress()==blade:GetAddress(),'Forge identity changed during blade replacement')
        assert(#active.WeaponDesignDefinition.AppliedSwordParts==count,'Attachment count changed during blade replacement')
        local frontend=forge.ForgeModeFrontend
        if is_valid(frontend) then
            frontend:SetAppliedAbilityToEdit(-1,false)
            if is_valid(frontend.ForgeModeUi) then frontend.ForgeModeUi:EnsureCorrectNumAppliedAbilities() end
        end
        pcl151710_set_menu_visible(false)
        log('PCL15_17_61_BLADE_APPLIED code='..code..' preserved_parts='..count..' same_live_actors=true')
    end)
    if not ok then pcl15171_set_status(panel,tostring(err)) end
    return ok,not ok and tostring(err) or nil
end
PCL151761_PART_FINISH_IMPORT=pcl151756_finish_library_import
function pcl151756_finish_library_import(request)
    if PCL151761_MODE~='blades' then return PCL151761_PART_FINISH_IMPORT(request) end
    local source=request.temp:GetPiece()
    local piece=pcl151761_fresh_piece(request.temp,source)
    assert(pcl151761_bridge().snapshot(source:GetAddress(),piece:GetAddress(),source:GetClass():GetAddress())==1,'Could not extract blade data')
    piece.Name=pcl15171_to_text(pcl15171_from_text(source:GetRawPieceName()))
    request.temp.Piece=piece
    pcl151724_capture_metadata(request)
    local saved,why=pcl151726_save(request.code,piece);assert(saved,tostring(why))
    pcl151761_capture(request.code,request.temp,piece,request.forge,request.gm,true)
    pcl15171_refresh_dynamic(request.context)
    pcl151719_status('Blade saved to library. Choose Use blade to replace your current blade.')
    log('PCL15_17_61_BLADE_IMPORTED code='..request.code..' parts=0 creative_inventory=false')
    if request.blade_use then pcl151761_apply(request.context,request.code,request) end
end
PCL151761_PART_DOWNLOAD=pcl15171_download_magic
function pcl15171_download_magic(context,code,refresh,library_only)
    if PCL151761_MODE~='blades' then return PCL151761_PART_DOWNLOAD(context,code,refresh,library_only) end
    if not library_only and pcl151726_has_cache(code) then return pcl151761_apply(context,code) end
    local ok,err=PCL151761_PART_DOWNLOAD(context,code,refresh,true)
    if ok and PCL151719_IMPORT then PCL151719_IMPORT.blade_use=not library_only end
    return ok,err
end
function pcl151761_upload(panel)
    local ok,err=pcall(function()
        assert(not PCL151719_IMPORT and not PCL151725_UPLOAD_PENDING and not PCL151741_BATCH,'Finish the current operation first')
        local previous=pcl151727_draft()
        if previous then assert(previous.blade,'Finish the current part upload first');pcl151727_show_form(panel,previous);return end
        local forge=find_forge();assert(is_valid(forge),'Open the Forge first')
        local source=forge:GetPiece();local blade=forge:GetBladeMesh()
        assert(is_valid(source) and is_valid(blade) and blade.PolyCount>0,'This design has no blade to upload')
        local host,gm,why=pcl151113_spawn_temp_forge(forge,source);assert(is_valid(host),tostring(why))
        PCL151725_UPLOAD_HOSTS[#PCL151725_UPLOAD_HOSTS+1]=host
        local piece=pcl151761_fresh_piece(host,source)
        assert(pcl151761_bridge().snapshot(source:GetAddress(),piece:GetAddress(),source:GetClass():GetAddress())==1,'Blade snapshot failed')
        piece.Name=pcl15171_to_text('Blade');host.Piece=piece
        local stamp=(tostring(os.time())..tostring(math.floor(os.clock()*1000000))):gsub('%d',function(c)return string.char(97+tonumber(c)) end)
        local draft={blade=true,code='draft-'..stamp..'-blade',name='Blade',parts=0,piece=piece,host=host,forge=forge,ui=pcl151723_references()}
        PCL151727_DRAFT=draft
        local saved,why=pcl151726_save(draft.code,piece);assert(saved,tostring(why))
        pcl151761_capture(draft.code,forge,source,forge,gm,false)
        pcl151727_show_form(panel,draft)
        local state=PCL151723_UI[panel:GetAddress()]
        state.controls.PCL_MagicWordTitle:SetText(pcl15171_to_text('Name and upload current blade'))
        state.controls.PCL_SubmitButton:SetCaption(pcl15171_to_text('Upload blade'))
    end)
    if not ok then pcl15171_set_status(panel,tostring(err)) end
end
PCL151761_PART_CANCEL=pcl15171_cancel_magic
function pcl15171_cancel_magic(panel)
    local draft=PCL151727_DRAFT
    if PCL151761_MODE=='blades' and draft and draft.blade then
        if PCL151725_UPLOAD_PENDING then pcl15171_set_status(panel,'Upload is still pending.');return end
        local ok,err=pcl151727_forget_draft(draft)
        if ok then pcl15171_set_magic_visible(panel,false) end
        pcl15171_set_status(panel,ok and 'Blade upload cancelled.' or tostring(err));return
    end
    return PCL151761_PART_CANCEL(panel)
end
function pcl151761_dispatch(action)
    if action.kind=='library_dismiss' then
        local menu=PCL151710_MENU_STATE
        if menu and menu.open and menu.panel==action.panel then pcl151710_set_menu_visible(false);log('PCL15_17_61_LIBRARY_DISMISSED outside_click=true') end
        return true
    end
    if action.kind=='library_parts_tab' or action.kind=='library_blades_tab' then
        pcl151761_switch(action.panel,action.kind=='library_blades_tab' and 'blades' or 'parts');return true
    end
    if PCL151761_MODE=='blades' and action.kind=='batch_upload' then pcl151761_upload(action.panel);return true end
    if PCL151761_MODE=='blades' and (action.kind=='anchor' or action.kind=='carry_toggle' or action.kind=='recover_draft') then return true end
    return false
end
-- The backdrop consumes outside clicks, so closing cannot also place a held
-- part or activate a Forge control behind the library. It has no frame polling.
function pcl151761_dismiss_layer(menu)
    if is_valid(menu.dismiss) then return menu.dismiss end
    local entry=pcl15171_create_widget(menu.catalogue,PCL15171_ENTRY_CLASS_OBJ)
    assert(is_valid(entry),'Library dismissal layer unavailable')
    local root=pcl15171_widget_by_name(entry,'PCL_EntryRoot')
    assert(is_valid(root),'Library dismissal root unavailable')
    local button=pcl151723_button(menu.panel,'',0)
    button:SetRenderOpacity(0)
    button:SetIsFocusable(false)
    pcl15171_bind_button(button,{kind=menu.home_browser and 'home_close' or 'library_dismiss',panel=menu.panel})
    root:ClearWidthOverride();root:ClearMaxDesiredWidth();root:ClearMinDesiredWidth()
    root:ClearHeightOverride();root:ClearMinDesiredHeight();root:ClearMaxDesiredHeight()
    root:SetContent(button)
    entry:AddToViewport(99)
    entry:SetDesiredSizeInViewport({X=0,Y=0})
    entry:SetPositionInViewport({X=0,Y=0},false)
    entry:SetAnchorsInViewport({Minimum={X=0,Y=0},Maximum={X=1,Y=1}})
    entry:SetAlignmentInViewport({X=0,Y=0})
    entry:SetVisibility(1)
    menu.dismiss=entry
    return entry
end
PCL151761_MENU_BASE=pcl151710_set_menu_visible
function pcl151710_set_menu_visible(visible)
    PCL151761_MENU_BASE(visible)
    local menu=PCL151710_MENU_STATE
    if not menu then return end
    if menu.open then
        local ok,err=pcall(function()pcl151761_dismiss_layer(menu):SetVisibility(0)end)
        if not ok then log('PCL15_17_61_DISMISS_UNAVAILABLE '..tostring(err)) end
    elseif is_valid(menu.dismiss) then menu.dismiss:SetVisibility(1) end
end
PCL151761_FORM_BASE=pcl151727_show_form
function pcl151727_show_form(panel,draft)
    PCL151761_FORM_BASE(panel,draft)
    if draft.blade then
        local controls=PCL151723_UI[panel:GetAddress()].controls
        controls.PCL_MagicWordTitle:SetText(pcl15171_to_text('Name and upload current blade'))
        controls.PCL_SubmitButton:SetCaption(pcl15171_to_text(draft.upload_code and 'Save uploaded blade' or 'Upload blade'))
    end
end
PCL151761_OPEN_MAGIC_BASE=pcl15171_open_magic
function pcl15171_open_magic(panel)
    PCL151761_OPEN_MAGIC_BASE(panel)
    if PCL151761_MODE=='blades' then
        PCL151723_UI[panel:GetAddress()].controls.PCL_MagicWordTitle:SetText(pcl15171_to_text('Import blade'))
        pcl15171_set_status(panel,'Import the blade from a Magic Word. Your current build stays unchanged.')
    end
end
-- Creative home only browses/manages libraries; it never places or opens Forge.
-- PCL contributes library data/actions; the framework owns Creative menu UI.
BMF_PCL_CREATIVE=assert(loadfile(BMF_PCL_ROOT..'ui/creative_host.lua'))(
    BMF_PCL_FRAMEWORK,BMF_PCL_ROOT,_G,
    {provider=true,is_valid=is_valid,log=log,safe_full_name=safe_full_name,
     gameplay_statics_15=gameplay_statics_15})
PCL151759_SCRIPT_READY=true
log('PCL15_17_62_SCRIPT_READY native_creative_grid=true')

-- Read-only startup probes: report guard failures before the first user action.
pcl15179_schedule(500,function()
 run_game_thread(function()
  for _,entry in ipairs({
   {'pcl_local_cache_151733.dll','pcl_cache_probe'},
   {'pcl_blade_library_151761.dll','pcl_blade_probe'},
   {'pcl_download_capture_151762.dll','pcl_download_probe'}
  })do
   local fn,why=BMF_PCL_NATIVE(pcl151112_script_dir()..entry[1],entry[2])
   local ok,status=false,why
   if type(fn)=='function'then ok,status=pcall(fn)end
   log('PCL15_18_1_NATIVE_PROBE helper='..entry[1]..' ok='..tostring(ok)..' status='..tostring(status))
  end
 end)
end)
