--[[local menus = {}

print("Initializing UI Module")

local outputMode = settings.get("ui.output")
if not outputMode then print("UI is disabled"); return end


if not fs.exists("basalt.lua") then
    os.run({}, "/rom/programs/http/wget", "run", "https://raw.githubusercontent.com/Pyroxenium/Basalt2/main/install.lua", "-r")
end

local basalt = require 'basalt'

if outputMode ~= "!default" then
    local newOut = assert(peripheral.wrap(outputMode))
    if newOut.blit then
    ---@diagnostic disable-next-line: param-type-mismatch
        term.redirect(newOut)
    end
    print("Redirected Output")
end

local frame = basalt.getMainFrame()

return {
    
}]]