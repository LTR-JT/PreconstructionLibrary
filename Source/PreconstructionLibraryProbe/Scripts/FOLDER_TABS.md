# Creative library folder tabs

`pcl_folder_tabs.lua` owns the tab registry. The host draws one consistent folder
lip for each definition, handles click events, and updates selected height and
text brightness. Built-ins are `creative` (Creative library, order 0) , `story` (Story swords, order 5), and
`preconstruction` (order 10).

Register an additional tab from an adapter loaded in PCL's Lua environment:

```lua
return function(tabs)
    tabs.register {
        id = 'my_mod',
        label = 'My mod',
        order = 20,
        width = 400, -- optional, 180..800 UI units
        on_select = function(host)
            -- Restore the Creative inventory before showing your own view.
            pcl151762_close(host)
            MyModLibrary.show(host)
        end,
        -- Optional; otherwise host.active_tab_id determines selection.
        is_active = function(host) return host.active_tab_id == 'my_mod' end,
    }
end
```

Place the adapter beside main.lua. Copy pcl_folder_tabs_config.example.lua to
pcl_folder_tabs_config.lua and add the adapter's module name (without .lua) to
the returned list. Definitions are sorted by order, then registration order;
registering the same id updates that definition. Register before Creative home
is constructed; restart the game after adding adapters. Different UE4SS mods
have separate Lua environments, so their integration adapter must be loaded by
PCL through this configuration. Copying an independent mod into UE4SS does not
implicitly register it. Preserve the local config when updating PCL.

The callback owns its view's display and cleanup; the registry supplies the tab
navigation and presentation. Use only unique ids. The three built-in ids are reserved
for the host. A callback failure is reported by the library status message.
