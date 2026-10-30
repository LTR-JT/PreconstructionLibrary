-- Wait for exact executable identity before any PCL native helper can load.
if PCL15181_BOOT then return end
PCL15181_BOOT=true
local scripts=assert(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[\\/])'))
local root=scripts..'../../shared/BladesongFramework/'
local ok,framework=pcall(function()return assert(loadfile(root..'api.lua'))(root)end)
if not ok then print('[PCL] Framework required: '..tostring(framework)..'\n');return end
framework.Ready(function()assert(loadfile(scripts..'pcl_runtime.lua'))()end)
