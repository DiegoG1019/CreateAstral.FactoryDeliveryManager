local function print(...)
  _G.print("Startup::", ...)
end

do
  local monitor = peripheral.find("monitor")
  if monitor then
    term.redirect(monitor)
  end
end

do
  local m = peripheral.find("modem", function(name, modem) if modem.isWireless() then rednet.open(name) return true end return false end)
  assert(m, "This computer does not have a wireless modem attached")
end

do
  
  local hasFailed = settings.get("factoryDelivery.failed")
  
  if not hasFailed and not FactoryDeliveryHasInit then
    FactoryDeliveryHasInit = true
    
    local success = pcall(require, 'factoryDelivery.startup.lua')
    if success then return end
    
    -- not success
    settings.set("factoryDelivery.failed", true)
    settings.save()
  end
  
  if hasFailed then
    print("Defaulting to original startup.lua as previous one failed")
	os.sleep(3)
  end
  
end

local modules = {}
local repoUser = "DiegoG1019"
local repoName = "CreateAstral.FactoryDeliveryManager"
local ghDownloadAddr = "https://raw.githubusercontent.com/"..repoUser.."/"..repoName.."/refs/heads/main/"
local ghQueryAddr = "https://api.github.com/repos/"..repoUser.."/"..repoName.."/git/trees/main?recursive=true"

FactoryDelivery = {}
FactoryDelivery.AstralNetHandlers = {}

local json = require 'json'

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start)) == Start
end

local function getFilesRecursively(path, tab)
  path = path or ""
  tab = tab or {}
  
  local pendingDirs = {}
  for i,v in ipairs(path) do
    if fs.isDir(v) then
      table.insert(pendingDirs, path.."/"..v)
    else
      table.insert(tab, path.."/"..v, true)
    end
  end
  
  for i,v in ipairs(pendingDirs) do
    getFilesRecursively(v, tab)
  end
  
  return tab;
end

local function inner_update(silent)
  
  local function update_print(str)
    if not silent then print(str) end
  end
  
  local manifest;
	local manifestFile = fs.open("manifest.json", "r")
	if not manifestFile then
		manifest = {}
	else
    manifest = json.decode(manifestFile.readAll())
    manifestFile.close()
  end

	local r, statusMsg = http.get(ghQueryAddr)
  if not r then
    update_print("Failed to GET from "..ghQueryAddr..": "..statusMsg)
    return false
  end
	
	local contents = json.decode(r.readAll());
  r.close();
	
	if not contents.tree or #(contents.tree) == 0 then return false end
	
  for i,v in ipairs(contents.tree) do
    if v.path == "startup.lua" then v.path = "factoryDelivery.startup.lua"; v.dlpath = "startup.lua" end
  end
  
  update_print("Parsed git tree info")
  
  local pendingDownload = {}
  
  local pendingDeletion = {}
  getFilesRecursively(pendingDeletion)  
  
  update_print("Iterating over git tree")
	for i,v in ipairs(contents.tree) do
    pendingDeletion[v.path] = nil
    update_print("Removed file "..v.path.." from deletion")
    
		if v.path ~= "LICENSE" and not string.starts(v.path, ".") then 
      
			if not manifest[v.path] or v.sha ~= manifest[v.path] then
        manifest[v.path] = v.sha
        if not v.size then
          if not fs.isDir(v.path) then
            fs.makeDir(v.path)
          end
        else
          table.insert(pendingDownload, v)
        end
      end
		end
	end
  
  if (#pendingDownload == 0) and (#pendingDeletion == 0) then return false end
  
  update_print("Deleting upstream-removed files")
  for k,v in pairs(pendingDeletion) do
    if v == true then
      update_print("Deleting file" ..k)
      fs.delete(k)
    end
  end
  
  update_print("Downloading outdated files")
  for i,v in ipairs(pendingDownload) do
    update_print("Downloading file "..v.path)
    local response, statusStr = http.get(ghDownloadAddr..(v.dlpath or v.path))
    if not response then
      print("ERROR: Could not get file "..v.path.." :"..statusStr)
    else
      local downfile = assert(fs.open(v.path, "w"))
      downfile.write(response.readAll())
      downfile.close()
      response.close()
    end
  end
  
  update_print("Updating manifest")
  manifestFile = assert(fs.open("manifest.json", "w"))
  manifestFile.write(json.encode(manifest))
  manifestFile.close()
  
  return true
end

local function update(silent)

  local function update_print(str)
    if not silent then print(str) end
  end

  update_print("Updating...")
  local r = inner_update(silent)
  
  if r then 
    update_print("Updated!")
    os.reboot()
  end
  
  update_print("No updates found")
  os.sleep(2)
end

local function dumpError(msg)
  local dump = assert(fs.open("error.log", "w"))
  dump.write(msg)
  dump.close()
end

local function loadModules()
  
  print("Loading Modules")
  local moduleInfo = {}
  
  table.insert(moduleInfo, { require 'modules.astralnet' })
  table.insert(moduleInfo, { require 'modules.factory_output' })
  table.insert(moduleInfo, { require 'modules.factory_input' })
  table.insert(moduleInfo, { require 'modules.ui' })
  
  local awaitingInit = {}
  
  for i,v in ipairs(moduleInfo) do
    
    if type(v) == "function" then
      table.insert(modules, v)
    else
      assert(type(v) == "table")
      local moduleFunc, init = v[1], v[2]
      assert(type(moduleFunc) == "function")
      assert(type(init) == "function" or not init)
      table.insert(modules, moduleFunc)
      if init then
        table.insert(awaitingInit, init)
      end
    end
  end
  
  print("Registered "..#modules.." module listeners")
  
  for i,v in pairs(awaitingInit) do
	print("Initializing module layer "..i)
    for ii, iv in pairs(v) do
	  print("Executing init sequence "..ii.." in layer "..i)
      local success, retval = xpcall(iv, debug.traceback)
      if not success then
        dumpError(tostring(success)..":::"..tostring(retval))
        error("Failed to load a module")
      end
    end
  end
  
  print("Initialized modules")
  os.sleep(2)
end

update()
loadModules()

local timerId = os.startTimer(60)

while true do
  local event = { os.pullEvent() }
  
  if event[0] == "alarm" and timerId == event[1] 
  then 
    update(true)
  else
    for i,v in ipairs(modules) do
      local success, retval = pcall(v, unpack(event))
      if retval == true then break end
    end
  end
  
  os.sleep(0.1)
end
