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

FactoryInput.ItemChecks = {}
FactoryInput.FluidChecks = {}

local orders = {}

local function receiveItems()
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

    orders = {}
end

function FactoryDelivery.FactoryInput.QueryAllFactories() 
    local res = {}

    local results = rednet.lookup(factoryOutputProtocol)
    assert(type(results) == "table" or type(results) == "nil", factoryOutputProtocol.." lookup did not return a table")
    if results then
        for i, v in ipairs(results) do
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

    return res
end

return function(event, ...)
    if event == "peripheral_detach" then 
        local peri = ...
        
        if peri == outputInventory or peri == outputFluid then 
            if (os.clock() - lastOrderPlaced) < 2 then
                return
            end
            lastOrderPlaced = os.clock()
            
            for factoryHost, products in FactoryDelivery.FactoryInput.QueryAllFactories() do
                for ii, item in ipairs(products.items) do
                    for index, checker in ipairs(FactoryDelivery.FactoryInput.ItemChecks) do
                        if type(checker) == "function" then
                            if checker(factoryHost, item) then
                                orders[factoryHost] = true -- We simply need to append the host, we'll ask it later what belongs to us and what doesn't
                            end
                        end
                    end
                end
                for ii, fluid in ipairs(products.fluids) do
                    for index, checker in ipairs(FactoryDelivery.FactoryInput.FluidChecks) do
                        if type(checker) == "function" then
                            if checker(factoryHost, fluid) then
                                orders[factoryHost] = true -- We simply need to append the host, we'll ask it later what belongs to us and what doesn't
                            end
                        end
                    end
                end
            end
        end
    elseif event == "peripheral" then
        local side = ...
        if side == outputInventory or side == outputFluid then
            receiveItems()
        end
    end
end