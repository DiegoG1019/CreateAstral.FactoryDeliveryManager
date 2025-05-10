local function print(...)
    _G.print("Factory_Input::", ...)
end

-- Enable signals, maybe through a redstone extension (that can later be used with redstone links)
-- These signals will trigger the request of certain items
-- The items need to be listed manually somehow first

-- Allow for generic updating?
-- Receives functions to check, the functions return boolean values (or truthy values)
-- These functions come from external modules (For example, could be an UI module or a module for the aforementioned redstone extension)

FactoryDelivery.FactoryInput = {}

local factoryOutputProtocol = "factory-output"

settings.define("factory.inputInventory", {
    ["type"] = "string",
    ["description"] = "The side from which the computer will deposit received items"
})

settings.define("factory.inputFluid", {
    ["type"] = "string",
    ["description"] = "The side from which the computer will deposit fluids"
})
    
local outputInventory = settings.get("factory.outputInventory")
local outputFluid = settings.get("factory.outputFluid")

local inputInventory = settings.get("factory.inputInventory")
local inputFluid = settings.get("factory.inputFluid")

local lastOrderPlaced = 0

FactoryInput = {}

local orders = {}

local function receiveItems()
    print("Receiving items")
    local fluidsToTake = {}
    local itemsToTake = {}

    for host, _ in pairs(orders) do
        local sender, response, protocol = AstralNet.Query("queryInbound", nil, host, factoryOutputProtocol)

        if sender and assert(response).code == 200 then
            for item, amount in pairs(assert(response).body.items) do
                itemsToTake[item] = (itemsToTake[item] or 0) + amount
            end
            for fluid, amount in pairs(assert(response).body.fluids) do
                fluidsToTake[fluid] = (fluidsToTake[fluid] or 0) + amount
            end
        end

    end

    local oinv = peripheral.wrap(outputInventory);
    assert(oinv, "Output inventory is not connected")

    for slot, item in pairs(oinv.list()) do
        local amount = itemsToTake[item.name]
        if amount and amount > 0 then
            itemsToTake[item.name] = amount - oinv.pushItems(inputInventory, slot, amount);
        end
    end

    local oflu = peripheral.wrap(outputFluid);
    assert(oflu, "Output fluids tank is not connected")

    for slot, tank in pairs(oflu.tanks()) do
        if tank.name ~= "minecraft:empty" then
            local amount = fluidsToTake[tank.name]
            if amount and amount > 0 then
                fluidsToTake[tank.name] = amount - oflu.pushFluid(inputFluid, amount, tank.name);
            end
        end
    end

    print("Succesfully retrieved items")
    orders = {}
end

function FactoryDelivery.FactoryInput.QueryAllFactories() 
    local res = {}

    print("Querying all factories with protocol "..factoryOutputProtocol)
    local results = rednet.lookup(factoryOutputProtocol)
    assert(type(results) == "table" or type(results) == "nil", factoryOutputProtocol.." lookup did not return a table")
    if results then
        for i, v in ipairs(results) do
            print("Sorting results from factory "..i)
            local lres = {["items"] = {}, ["fluids"] = {}}
            res[v] = lres
            local sender, qresult = AstralNet.Query("queryItems", nil, v, factoryOutputProtocol)
            if qresult and qresult.code == 200 then
                lres["items"] = qresult.body
            end
            local sender, qresult = AstralNet.Query("queryFluids", nil, v, factoryOutputProtocol)
            if qresult and qresult.code == 200 then
                lres["fluids"] = qresult.body
            end
        end
    end

    return pairs(res)
end

return function(event, ...)
    if event == "peripheral_detach" then 
        print("Received a peripheral disconnection signal")
        local peri = ...
        
        if peri == outputInventory or peri == outputFluid then 
            if (os.clock() - lastOrderPlaced) < 2 then
                return
            end
            lastOrderPlaced = os.clock()
            print("Peripheral disconnection was from an output side, ordering new batch of items")
            
            assert(fs.exists("inputScripts"), "inputScripts folder does not exist")
            assert(fs.exists("inputScripts/fluidChecks"), "inputScripts/fluidChecks folder does not exist")
            assert(fs.exists("inputScripts/itemChecks"), "inputScripts/itemChecks folder does not exist")

            local itemChecks = {}
            local fluidChecks = {}
            
            print("Loading item checks")
            for index, checkerScript in ipairs(fs.list("inputScripts/itemChecks")) do
                print("Found item check script: "..checkerScript)
                local script = loadfile(checkerScript)
                if script then table.insert(itemChecks, script) end
            end

            for index, checkerScript in ipairs(fs.list("inputScripts/fluidhecks")) do
                print("Found fluid check script: "..checkerScript)
                local script = loadfile(checkerScript)
                if script then table.insert(fluidChecks, script) end
            end
            
            for factoryHost, products in FactoryDelivery.FactoryInput.QueryAllFactories() do
                for ii, item in ipairs(products.items) do
                    for index, script in ipairs(itemChecks) do
                        if script(factoryHost, item) then
                            orders[factoryHost] = true -- We simply need to append the host, we'll ask it later what belongs to us and what doesn't
                        end
                    end
                end
                for ii, fluid in ipairs(products.fluids) do
                    for index, script in ipairs(fluidChecks) do
                        if script(factoryHost, fluid) then
                            orders[factoryHost] = true -- We simply need to append the host, we'll ask it later what belongs to us and what doesn't
                        end
                    end
                end
            end
        end
        
    elseif event == "peripheral" then
        local side = ...
        print("Received a peripheral connection signal")
        if side == outputInventory or side == outputFluid then
            print("Received a peripheral connection from an output side")
            receiveItems()
        end
    end
end