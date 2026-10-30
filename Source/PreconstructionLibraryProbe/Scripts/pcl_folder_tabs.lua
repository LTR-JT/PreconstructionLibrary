-- UI-independent tab registry. Loaded once by the Creative library host.
local M={definitions={},sequence=0}
function M.register(def)
    assert(type(def)=='table'and type(def.id)=='string'and def.id:match('^[%w_%-]+$'),'Tab needs a stable id')
    assert(type(def.label)=='string'and #def.label>0,'Tab needs a label')
    assert(type(def.on_select)=='function','Tab needs an on_select callback')
    assert(def.width==nil or(type(def.width)=='number'and def.width>=180 and def.width<=800),'Invalid tab width')
    local old=M.definitions[def.id];M.sequence=M.sequence+1
    M.definitions[def.id]={id=def.id,label=def.label,order=def.order or 100,width=def.width or 400,on_select=def.on_select,is_active=def.is_active,sequence=old and old.sequence or M.sequence}
end
function M.list()
    local list={};for _,def in pairs(M.definitions)do list[#list+1]=def end
    table.sort(list,function(a,b)if a.order==b.order then return a.sequence<b.sequence end;return a.order<b.order end)
    return list
end
function M.select(id,context)
    local def=assert(M.definitions[id],'Unknown folder tab')
    assert(not context.busy and not context.confirm and not PCL151762_IMPORT,'Finish the current operation first')
    def.on_select(context);context.active_tab_id=id
end
function M.is_active(id,context)
    local def=M.definitions[id];if not def then return false end
    if def.is_active then return not not def.is_active(context)end
    return context.active_tab_id==id
end
return M
