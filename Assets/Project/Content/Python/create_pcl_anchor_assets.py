import unreal
import json
import os
import traceback

PROJECT_DIR = unreal.Paths.project_dir()
CONFIG_FILE = os.path.join(PROJECT_DIR, "PCLAnchorConfig.json")
OBJ_FILE = os.path.join(PROJECT_DIR, "Content", "PCL", "Source", "PCL_PreconstructionAnchor.obj")

def log(msg):
    unreal.log("[PCLAssets] " + str(msg))

def safe_set(obj, prop, value):
    try:
        obj.set_editor_property(prop, value)
        return True
    except Exception as exc:
        log("property skipped {}.{} = {} ({})".format(
            obj.get_name() if obj else "None", prop, value, exc))
        return False

def as_vec(v):
    return unreal.Vector(float(v[0]), float(v[1]), float(v[2]))

def as_rot(v):
    # Config order: Pitch, Yaw, Roll.
    return unreal.Rotator(roll=float(v[2]), pitch=float(v[0]), yaw=float(v[1]))

def replace_socket(mesh, scfg):
    name = str(scfg["name"])
    old = mesh.find_socket(unreal.Name(name))
    if old:
        mesh.remove_socket(old)

    socket = unreal.StaticMeshSocket(outer=mesh)
    socket.set_editor_property("socket_name", unreal.Name(name))
    socket.set_editor_property("relative_location", as_vec(scfg["location"]))
    socket.set_editor_property("relative_rotation", as_rot(scfg["rotation"]))
    socket.set_editor_property("relative_scale", unreal.Vector(1.0, 1.0, 1.0))
    mesh.add_socket(socket)
    log("socket {} location={} rotation(P,Y,R)={}".format(
        name, scfg["location"], scfg["rotation"]))

def create_anchor_material(cfg):
    path = cfg["asset_path"]
    name = cfg["material_name"]
    material = unreal.load_asset(path + "/" + name)
    if not material:
        material = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
            name, path, unreal.Material, unreal.MaterialFactoryNew())
    if not material:
        raise RuntimeError("Could not create anchor material")
    unreal.MaterialEditingLibrary.delete_all_material_expressions(material)
    def color(values, prop, x, y):
        node = unreal.MaterialEditingLibrary.create_material_expression(material, unreal.MaterialExpressionConstant3Vector, x, y)
        node.set_editor_property("constant", unreal.LinearColor(*values, 1.0))
        unreal.MaterialEditingLibrary.connect_material_property(node, "", prop)
    color((0.005, 0.85, 1.0), unreal.MaterialProperty.MP_BASE_COLOR, -300, -100)
    color((0.002, 0.20, 0.30), unreal.MaterialProperty.MP_EMISSIVE_COLOR, -300, 100)
    rough = unreal.MaterialEditingLibrary.create_material_expression(material, unreal.MaterialExpressionConstant, -300, 250)
    rough.set_editor_property("r", 0.7)
    unreal.MaterialEditingLibrary.connect_material_property(rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    unreal.MaterialEditingLibrary.recompile_material(material)
    unreal.EditorAssetLibrary.save_loaded_asset(material, only_if_is_dirty=False)
    return material

def import_anchor_mesh(cfg):
    path = cfg["asset_path"]
    name = cfg["mesh_name"]
    full = path + "/" + name

    task = unreal.AssetImportTask()
    task.set_editor_property("filename", OBJ_FILE)
    task.set_editor_property("destination_path", path)
    task.set_editor_property("destination_name", name)
    task.set_editor_property("automated", True)
    task.set_editor_property("replace_existing", True)
    task.set_editor_property("save", True)

    options = unreal.FbxImportUI()
    options.set_editor_property("import_mesh", True)
    options.set_editor_property("import_as_skeletal", False)
    options.set_editor_property("import_materials", False)
    options.set_editor_property("import_textures", False)

    smi = options.get_editor_property("static_mesh_import_data")
    if smi:
        smi.set_editor_property("combine_meshes", True)
        smi.set_editor_property("transform_vertex_to_absolute", True)
        smi.set_editor_property("auto_generate_collision", True)
        smi.set_editor_property("generate_lightmap_u_vs", False)

    task.set_editor_property("options", options)
    unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])

    mesh = unreal.load_asset(full)
    if not mesh:
        raise RuntimeError("Failed to import " + full)

    mesh.set_material(0, create_anchor_material(cfg))
    bounds = mesh.get_bounding_box()
    if abs(bounds.min.x) > 0.0001 or abs(bounds.max.x - 1.0) > 0.0001:
        raise RuntimeError("Mesh import changed the authored back-face pivot")
    subsystem = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
    subsystem.remove_collisions(mesh)
    if subsystem.add_simple_collisions(mesh, unreal.ScriptCollisionShapeType.BOX) < 0:
        raise RuntimeError("Could not rebuild anchor box collision")

    # This owned mesh exposes exactly one connector. Remove obsolete sockets
    # from earlier imports so reimporting cannot retain PCL_Primary.
    # PCL-created sockets use the default empty tag. The Sockets property is
    # protected in UE5.7 Python; use the public Blueprint-callable query.
    for old in list(mesh.get_sockets_by_tag("")):
        mesh.remove_socket(old)
    replace_socket(mesh, cfg["attach_socket"])
    sockets = list(mesh.get_sockets_by_tag(""))
    if len(sockets) != 1:
        raise RuntimeError("Anchor mesh must have exactly one socket")
    socket = mesh.find_socket(unreal.Name(cfg["attach_socket"]["name"]))
    if not socket:
        raise RuntimeError("Anchor socket readback failed")
    loc = socket.get_editor_property("relative_location")
    rot = socket.get_editor_property("relative_rotation")
    wanted = cfg["attach_socket"]
    actual = (loc.x, loc.y, loc.z, rot.pitch, rot.yaw, rot.roll)
    expected = tuple(wanted["location"] + wanted["rotation"])
    if any(abs(a-b) > 0.0001 for a,b in zip(actual, expected)):
        raise RuntimeError("Anchor socket transform readback mismatch: " + str(actual))
    log("PCL_ANCHOR_SOCKET_OK count=1 name={} loc={} rotation={}".format(
        wanted["name"], wanted["location"], wanted["rotation"]))
    mesh.modify()
    unreal.EditorAssetLibrary.save_loaded_asset(mesh, only_if_is_dirty=False)
    log("mesh saved: " + full)
    return mesh

def create_real_blueprint(cfg):
    parent = unreal.load_class(None, "/Script/Bladesong.SwordPartStaticMeshActor")
    if not parent:
        raise RuntimeError("Mirror SwordPartStaticMeshActor class did not load.")

    bp_path = cfg["asset_path"] + "/" + cfg["blueprint_name"]
    if unreal.EditorAssetLibrary.does_asset_exist(bp_path):
        unreal.EditorAssetLibrary.delete_asset(bp_path)

    bp = unreal.BlueprintEditorLibrary.create_blueprint_asset_with_parent(bp_path, parent)
    if not bp:
        raise RuntimeError("Failed to create " + bp_path)

    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    unreal.EditorAssetLibrary.save_loaded_asset(bp, only_if_is_dirty=False)
    log("Blueprint saved: {} parent={}".format(bp_path, parent.get_path_name()))
    return bp

def create_mod_actor():
    path = "/Game/Mods/PCLAnchor/ModActor"
    unreal.EditorAssetLibrary.make_directory("/Game/Mods/PCLAnchor")

    if unreal.EditorAssetLibrary.does_asset_exist(path):
        unreal.EditorAssetLibrary.delete_asset(path)

    bp = unreal.BlueprintEditorLibrary.create_blueprint_asset_with_parent(
        path, unreal.Actor)
    if not bp:
        raise RuntimeError("Failed to create UE4SS Blueprint ModLoader ModActor")

    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    unreal.EditorAssetLibrary.save_loaded_asset(bp, only_if_is_dirty=False)
    log("UE4SS ModActor saved: " + path)
    return bp

def create_widget_blueprint(asset_path):
    asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
    package_path, asset_name = asset_path.rsplit("/", 1)

    if unreal.EditorAssetLibrary.does_asset_exist(asset_path):
        unreal.EditorAssetLibrary.delete_asset(asset_path)

    factory = unreal.WidgetBlueprintFactory()
    safe_set(factory, "parent_class", unreal.UserWidget)

    bp = asset_tools.create_asset(
        asset_name,
        package_path,
        unreal.WidgetBlueprint,
        factory
    )

    if not bp:
        raise RuntimeError("Failed to create WidgetBlueprint: " + asset_path)

    safe_set(bp, "can_call_initialized_without_player_context", True)
    log("WidgetBlueprint created: " + asset_path)
    return bp

def add_widget(bp, cls, name, parent="None"):
    widget = unreal.EditorUtilityLibrary.add_source_widget(
        bp,
        cls,
        unreal.Name(name),
        unreal.Name(parent)
    )
    if not widget:
        raise RuntimeError(
            "AddSourceWidget failed: {} parent={}".format(name, parent))
    # Different engine revisions expose this designer flag differently.
    safe_set(widget, "is_variable", True)
    safe_set(widget, "b_is_variable", True)
    return widget

def set_text(widget, text):
    try:
        widget.set_text(unreal.Text(text))
        return
    except Exception:
        pass
    safe_set(widget, "text", unreal.Text(text))

def build_library_panel():
    path = "/Game/PCL/UI/WBP_PCL_PreconstructionLibrary"
    unreal.EditorAssetLibrary.make_directory("/Game/PCL/UI")
    bp = create_widget_blueprint(path)

    root = add_widget(bp, unreal.SizeBox, "PCL_Root")
    safe_set(root, "width_override", 720.0)
    safe_set(root, "min_desired_width", 620.0)

    background = add_widget(bp, unreal.Border, "PCL_Background", "PCL_Root")
    safe_set(background, "padding", unreal.Margin(12.0, 10.0, 12.0, 10.0))

    column = add_widget(bp, unreal.VerticalBox, "PCL_MainColumn", "PCL_Background")

    header = add_widget(bp, unreal.TextBlock, "PCL_HeaderText", "PCL_MainColumn")
    set_text(header, "Preconstruction Library")
    safe_set(header, "auto_wrap_text", False)

    hint = add_widget(bp, unreal.TextBlock, "PCL_HeaderHint", "PCL_MainColumn")
    set_text(hint, "Saved preconstructions and PCL tools")
    safe_set(hint, "auto_wrap_text", True)

    fixed = add_widget(bp, unreal.HorizontalBox, "PCL_FixedEntries", "PCL_MainColumn")

    plus = add_widget(bp, unreal.Button, "PCL_PlusButton", "PCL_FixedEntries")
    safe_set(plus, "tool_tip_text", unreal.Text("Add a preconstruction by Magic Word"))
    plus_text = add_widget(bp, unreal.TextBlock, "PCL_PlusText", "PCL_PlusButton")
    set_text(plus_text, "+")

    anchor = add_widget(bp, unreal.Button, "PCL_AnchorButton", "PCL_FixedEntries")
    safe_set(anchor, "tool_tip_text", unreal.Text("Place the Preconstruction Anchor"))
    anchor_text = add_widget(bp, unreal.TextBlock, "PCL_AnchorText", "PCL_AnchorButton")
    set_text(anchor_text, "Preconstruction Anchor")

    tools = add_widget(bp, unreal.HorizontalBox, "PCL_LocalTools", "PCL_MainColumn")
    for name, label, tooltip in (
        ("SaveLocal", "Save current", "Save the current design as latest.json and a timestamped snapshot"),
        ("ValidateLocal", "Validate saved", "Validate latest.json using Bladesong's native validator"),
        ("LoadLocal", "Load latest", "Load latest.json into an empty Forge in Hilt mode"),
    ):
        button = add_widget(bp, unreal.Button, "PCL_" + name + "Button", "PCL_LocalTools")
        safe_set(button, "tool_tip_text", unreal.Text(tooltip))
        text = add_widget(bp, unreal.TextBlock, "PCL_" + name + "Text", "PCL_" + name + "Button")
        set_text(text, label)

    dynamic = add_widget(bp, unreal.WrapBox, "PCL_DynamicEntries", "PCL_MainColumn")
    safe_set(dynamic, "inner_slot_padding", unreal.Vector2D(5.0, 5.0))

    magic_border = add_widget(bp, unreal.Border, "PCL_MagicWordPanel", "PCL_MainColumn")
    safe_set(magic_border, "visibility", unreal.SlateVisibility.COLLAPSED)
    safe_set(magic_border, "padding", unreal.Margin(8.0, 8.0, 8.0, 8.0))

    magic_column = add_widget(
        bp, unreal.VerticalBox, "PCL_MagicWordColumn", "PCL_MagicWordPanel")

    magic_title = add_widget(
        bp, unreal.TextBlock, "PCL_MagicWordTitle", "PCL_MagicWordColumn")
    set_text(magic_title, "Add Preconstruction")

    magic_label = add_widget(
        bp, unreal.TextBlock, "PCL_MagicWordLabel", "PCL_MagicWordColumn")
    set_text(magic_label, "Magic Word")

    magic_input = add_widget(
        bp, unreal.EditableTextBox, "PCL_MagicWordInput", "PCL_MagicWordColumn")
    safe_set(magic_input, "hint_text", unreal.Text("Enter Magic Word..."))

    magic_buttons = add_widget(
        bp, unreal.HorizontalBox, "PCL_MagicWordButtons", "PCL_MagicWordColumn")

    submit = add_widget(
        bp, unreal.Button, "PCL_SubmitButton", "PCL_MagicWordButtons")
    submit_text = add_widget(
        bp, unreal.TextBlock, "PCL_SubmitText", "PCL_SubmitButton")
    set_text(submit_text, "Add")

    cancel = add_widget(
        bp, unreal.Button, "PCL_CancelButton", "PCL_MagicWordButtons")
    cancel_text = add_widget(
        bp, unreal.TextBlock, "PCL_CancelText", "PCL_CancelButton")
    set_text(cancel_text, "Cancel")

    status = add_widget(bp, unreal.TextBlock, "PCL_StatusText", "PCL_MainColumn")
    set_text(status, "")
    safe_set(status, "auto_wrap_text", True)

    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    unreal.EditorAssetLibrary.save_loaded_asset(bp, only_if_is_dirty=False)
    log("Preconstruction Library widget saved: " + path)
    return bp

def build_library_entry():
    path = "/Game/PCL/UI/WBP_PCL_LibraryEntry"
    bp = create_widget_blueprint(path)

    root = add_widget(bp, unreal.SizeBox, "PCL_EntryRoot")
    safe_set(root, "min_desired_width", 190.0)
    safe_set(root, "min_desired_height", 46.0)

    button = add_widget(bp, unreal.Button, "PCL_EntryButton", "PCL_EntryRoot")
    label = add_widget(bp, unreal.TextBlock, "PCL_EntryLabel", "PCL_EntryButton")
    set_text(label, "Preconstruction")
    safe_set(label, "auto_wrap_text", True)

    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    unreal.EditorAssetLibrary.save_loaded_asset(bp, only_if_is_dirty=False)
    log("Library entry widget saved: " + path)
    return bp

def main():
    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    unreal.EditorAssetLibrary.make_directory(cfg["asset_path"])
    import_anchor_mesh(cfg)
    if cfg.get("build_scope") == "anchor":
        for path in (cfg["asset_path"] + "/" + cfg["blueprint_name"],
                     "/Game/Mods/PCLAnchor/ModActor", "/Game/PCL/UI/WBP_PCL_PreconstructionLibrary",
                     "/Game/PCL/UI/WBP_PCL_LibraryEntry"):
            if not unreal.EditorAssetLibrary.does_asset_exist(path):
                raise RuntimeError("Anchor-only update requires existing asset: " + path)
        log("Anchor-only update: existing Blueprint and UI assets preserved")
    else:
        create_real_blueprint(cfg)
        create_mod_actor()
        build_library_panel()
        build_library_entry()

    marker = os.path.join(PROJECT_DIR, "PCLAnchorAssets_BUILD_OK.txt")
    with open(marker, "w", encoding="utf-8") as f:
        f.write("mesh=/Game/PCL/Anchor/SM_PCL_PreconstructionAnchor\n")
        f.write("blueprint=/Game/PCL/Anchor/BP_PCL_PreconstructionAnchor\n")
        f.write("ui=/Game/PCL/UI/WBP_PCL_PreconstructionLibrary\n")
        f.write("entry_ui=/Game/PCL/UI/WBP_PCL_LibraryEntry\n")
        f.write("mod_actor=/Game/Mods/PCLAnchor/ModActor\n")
        f.write("attach=PCL_Attach\n")
        f.write("socket_count=1\n")
        f.write("slot_offset=0,0,0\n")
        f.write("revision=" + cfg.get("revision", "unknown") + "\n")

    log("BUILD_OK")

try:
    main()
except Exception:
    unreal.log_error("[PCLAssets] FAILED\n" + traceback.format_exc())
    raise
