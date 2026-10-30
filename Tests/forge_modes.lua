local path=(os.getenv('PCL_TEST_ROOT')or '.')..'/Source/PreconstructionLibraryProbe/Scripts/pcl_runtime.lua'
local file=assert(io.open(path,'rb'));local source=file:read('*a'):gsub('\r\n','\n');file:close()
local code=assert(source:match('(function pcl15181_prepare_blade%(forge%).-)\nfunction pcl151761_switch'))
local class={};function StaticFindObject()return class end
function is_valid(o)return type(o)=='table'and o.valid~=false end
function pcl15171_from_text(v)return v end
function log()end
local forge={GetAddress=function()return 42 end}
local other={GetAddress=function()return 99 end}
local clicks=0
local function stage(title,active)
 return {Title=title,IsA=function(_,c)return c==class end,IsStageActive=function()return active end,Button={HandleButtonClicked=function()clicks=clicks+1 end}}
end
local entries={stage('Hilt',false),stage('Blade',false)}
local ui={ForgeMode=forge,SwordmakingStageButtonContainer={GetChildrenCount=function()return #entries end,GetChildAt=function(_,i)return entries[i+1]end}}
forge.ForgeModeFrontend={ForgeModeUi=ui}
assert(load(code))()
assert(not pcl15181_prepare_blade(forge)and clicks==1) -- stock stage transition requested
entries[2]=stage('Blade',true)
assert(pcl15181_prepare_blade(forge)and clicks==1) -- no redundant stage transition
ui.ForgeMode=other
assert(not pcl15181_prepare_blade(forge)and clicks==1) -- never touch a different Forge's UI
assert(not pcl15181_prepare_blade(nil)and clicks==1)
assert(source:find("if mode=='blades' then pcl15181_prepare_blade(find_forge())\n        else pcl151717_prepare_hilt(find_forge()) end",1,true))
-- Exercise the real Hilt helper after the mode has switched back to Parts.
local hilt=assert(source:match('(function pcl151717_prepare_hilt%(forge%).-)\nfunction '))
assert(load(hilt))()
ui.ForgeMode=forge
assert(not pcl151717_prepare_hilt(forge)and clicks==2)
entries[1]=stage('Hilt',true)
assert(pcl151717_prepare_hilt(forge)and clicks==2)
ui.ForgeMode=other
assert(not pcl151717_prepare_hilt(forge)and clicks==2)
print('PASS: Blades selects Blade stage and Parts selects Hilt stage through current Forge native buttons; active/different/missing Forge guarded')
