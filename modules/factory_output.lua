local function print(...)
  _G.print("Factory_Output::", ...)
end

if pocket then return end

print("Initializing Factory Output Module")

local inventories;
local energyStorage;
local fluidStorage;
local spreadPosting = {}

local placedOrders = {}

settings.define("factory.outputInventory", {
  ["type"] = "string",
  ["description"] = "The peripheral the computer will take as the inventory to push items being shipped out into, and shipped in from"
})

settings.define("factory.outputFluid", {
  ["type"] = "string",
  ["description"] = "The peripheral the computer will take as the inventory to push fluids being shipped out into, and shipped in from"
})

settings.save()

local outputInventory = settings.get("factory.outputInventory")
local outputFluid = settings.get("factory.outputFluid")

local itemsOutbuffer, fluidsOutbuffer, energyOutbuffer;

assert(outputInventory, "Factory Output Module cannot initialize if the setting 'factory.outputInventory' is not set")
assert(outputFluid, "Factory Output Module cannot initialize if the setting 'factory.outputFluid' is not set")

print("outputInventory: ", outputInventory)
print("outputFluid: ", outputFluid)

local function setItems(items)
  itemsOutbuffer = items
end

local function setFluids(fluids)
  fluidsOutbuffer = fluids;
end

local function setEnergy(energy)
  energyOutbuffer = energy;
end

local function readItems() 
  print("Reading items")
  local items = {}
  for i, inv in ipairs(inventories) do
    for slot, item in ipairs(inv.list()) do
      local itemc = items[item.name] or 0
      items[item.name] = itemc + item.count
    end
  end

  print("Reading fluids")
  local fluids = {}
  for i, storage in ipairs(fluidStorage) do
    for j, tank in ipairs(storage.tanks()) do
      if tank.name ~= "minecraft:empty" then
        local fluidc = fluids[tank.name] or 0
        fluids[tank.name] = fluidc + (tank.amount or 0)
      end
    end
  end
  
  print("Reading energy")
  local energy = {}
  local tce = 0
  local tme = 0
  for i, en in ipairs(energyStorage) do
    tce = tce + en.getEnergy()
    tme = tme + en.getEnergyCapacity()
  end
  energy.TotalCurrentEnergy = tce
  energy.TotalMaxEnergy = tme
  
  print("Posting results")
  setItems(items)
  setFluids(fluids)
  setEnergy(energy)
end

local function reloadPeripherals()
  print("Reloading peripherals")
  inventories = {}
  energyStorage = {}
  fluidStorage = {}
  
  for i,v in ipairs(peripheral.getNames()) do
    if v ~= outputInventory and v ~= outputFluid then
      local inv = assert(peripheral.wrap(v))
      if inv.getItemDetail then 
        print("Found inventory:", i)
        table.insert(inventories, inv)
      end
      
      if inv.getEnergy then
        print("Found energy sensor:", i)
        table.insert(energyStorage, inv)
      end
      
      if inv.tanks then
        print("Found fluid storage:", i)
        table.insert(fluidStorage, inv)
      end
    end
  end
  
end

local lastShipped = 0

local function broadcastProducts(productList, spreadPosting)

end

local function prepareProductsForShipping(productList, requester, productOutput, productReadings, spread, finalized)

  for index, product in ipairs(productList) do

    local availableProduct = productReadings[product]
    if availableProduct then

      local outp = productOutput[product]
      if not outp then
        outp = {}
        productOutput[product] = outp
      end

      table.insert(outp, requester)
      spread[product] = 0

      finalized[product] = true
      
    end
  end

end

local function shipItems()
  
  if (os.clock() - lastShipped) < 2 then
    return
  end
  lastShipped = os.clock()

  print("Shipping items")
  local orders = placedOrders
  placedOrders = {}

  reloadPeripherals()
  readItems()

  -- We graph who needs what
  
  local totalOutput = {
    ["items"] = {},
    ["fluids"] = {}
  }
  
  spreadPosting = {}
  local finalizedList = {
    ["items"] = {},
    ["fluids"] = {}
  }

  print("Sorting out orders and deliveries")
  for requester, order in pairs(placedOrders) do

    spreadPosting[requester] = {
      ["items"] = {},
      ["fluids"] = {}
    }

    print("Preparing products for shipping to ", requester)

    if order.items then
      prepareProductsForShipping(order.items, requester, totalOutput.items, itemsOutbuffer, spreadPosting[requester].items, finalizedList.items)
    end

    if order.fluids then
      prepareProductsForShipping(order.fluids, requester, totalOutput.fluids, fluidsOutbuffer, spreadPosting[requester].fluids, finalizedList.fluids)
    end

  end

  -- Now we take the total of each product and broadcast how much each requester can take
    -- To do this, we take the total from the reading then take the spreadPosting table and go through each requester, and check on the product output for the amount of requests, then we put that amount into the broadcast for each requester

  print("Sorting out product postings for each requester")

  local itemReadings = itemsOutbuffer
  for item, requesterTable in pairs(totalOutput.items) do
    local totalItems = itemReadings[item] or 0
    local spread = totalItems / #requesterTable
    for _, requester in ipairs(requesterTable) do
      spreadPosting[requester].items[item] = spread
    end
  end

  local fluidReadings = fluidsOutbuffer
  for fluid, requesterTable in pairs(totalOutput.fluids) do
    local totalFluids = fluidReadings[fluid] or 0
    local spread = totalFluids / #requesterTable
    for _, requester in ipairs(requesterTable) do
      spreadPosting[requester].fluids[fluid] = spread
    end
  end

  -- After, we push out the entirety of only the requested products out
  print("Pushing out products")
  for item, enabled in pairs(finalizedList.items) do
    if enabled then
      print("\tPushing out ", item)
      for i, inv in ipairs(inventories) do
        for slot, stored in ipairs(inv.list()) do
          if stored.name == item then
            inv.pushItems(outputInventory, slot)
          end
        end
      end
    end
  end
  
  for fluid, enabled in pairs(finalizedList.fluids) do
    if enabled then
      for i, inv in ipairs(fluidStorage) do
        for slot, stored in ipairs(inv.list()) do
          if stored.name == fluid then
            inv.pushFluid(outputFluid, nil, stored.name)
          end
        end 
      end
    end
  end

end

local function orderItemsHandler(sender, itemsList)

  if type(itemsList) ~= "table" then return nil, 400 end
  if not itemsList.items and not itemsList.fluids then return nil, 400 end

  print("Receiving new product order from " .. tostring(sender) .. " with " .. tostring(#itemsList) .. "items")
  placedOrders[sender] = itemsList
  return nil, 202

-- the recipient factory is allowed to assume their request can be honored. Otherwise we'd need to get 
-- funky with the logistics of what's the total amount at the time the train arrives and then broadcast back
-- and whatnot

-- Factories need to continually make requests -- If a request has not yet been fulfilled
-- (The train hasn't picked up anything) then the request will be overwritten
-- other factories should place new orders around the same time the train delivers their goods

end

local function queryInboundHandler(sender)
  local res = spreadPosting[sender]
  if not res then return nil, 404 else return res, 200 end
end

reloadPeripherals()
readItems()

return 
{
  function(event, ...)
    if event == "peripheral" then
      print("Peripheral connection signal received")
      local side = ...
      if side == outputInventory or side == outputFluid then
        print("Peripheral connection is from an output peripheral")
        shipItems()
      end
    end
  end,

  function ()
    local factoryOutputProtocol = "factory-output"
    AstralNet.AddProtocol(factoryOutputProtocol)

    AstralNet.AddHandler(factoryOutputProtocol, "queryItems", function() return itemsOutbuffer, 200 end)
    AstralNet.AddHandler(factoryOutputProtocol, "queryFluids", function() return fluidsOutbuffer, 200 end)
    AstralNet.AddHandler(factoryOutputProtocol, "queryEnergy", function() return energyOutbuffer, 200 end)
    
    AstralNet.AddHandler(factoryOutputProtocol, "orderItems", orderItemsHandler)
    AstralNet.AddHandler(factoryOutputProtocol, "queryInbound", queryInboundHandler)
  end
  
}
