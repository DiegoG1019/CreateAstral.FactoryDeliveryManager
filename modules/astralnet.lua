-- Basically just receive a rednet request and return the requested item from queryable info

print("Initializing AstralNet Module")

AstralNet = {}

local protocolHandlers = {}

settings.define("astralnet.host", { description = "The hostname of this factory controller", default = nil, type = "string" })
AstralNet.Hostname = tostring(settings.get("astralnet.host") or "astralnet")..":"..tostring(os.getComputerID())

--- Adds a protocol hosting in AstralNet
---@param protocolName string The name of the protocol, used when receiving new rednet requests
---@param messageInterceptor? function A function that captures a message before further processing and validates it. If it returns 'true' or the function is nil the message is processed
---@param responseProtocolName? string The name of the protocol used to respond; if nil, (protocolName.."-response") is used
function AstralNet.AddProtocol(protocolName, messageInterceptor, responseProtocolName)
  assert(type(protocolName) == "string", "Invalid argument #1, protocolName is expected to be a non-nil string")
  assert(type(messageInterceptor) == "function" or type(messageInterceptor) == "nil", "Invalid argument #2, messageInterceptor is expected to be nil or a function")
  assert(type(responseProtocolName) == "string" or type(responseProtocolName) == "nil", "Invalid argument #3, responseProtocolName is expected to be nil or a string")
  assert(protocolName ~= "astralnet-query", "Cannot register a new protocol named as the default protocol")
  assert(not protocolHandlers[protocolName], "Cannot register a new protocol named "..protocolName.." as one already exists")

  local t = {}
  protocolHandlers[protocolName] = t

  t.dat = {
    ["protocol-name"] = protocolName,
    ["protocol-response"] = responseProtocolName or protocolName.."-response",
    ["interceptor"] = messageInterceptor
  }
  t.requestHandlers = {}
  
  t.handler = function(event, sender_id, message, protocol)
    local protocolResponse = t.dat["protocol-response"]

    if event == "rednet_message" and sender_id and sender_id ~= os.getComputerID() and type(message) == "table" then

      local interceptor = t.dat["interceptor"]
      if interceptor and not interceptor(sender_id, message, protocol) then return end
      
      local uri = message.uri or ""
      local info = t.requestHandlers[message.uri]
      if info then
        if type(info) == "function" then
          local resp, code = info(sender_id, message.body, protocol, uri)
          rednet.send(sender_id, { ["body"] = resp, ["code"] = code, ["tstamp"] = os.time() }, protocolResponse)
        end
          
        rednet.send(sender_id, { ["body"] = info, ["code"] = 200, ["tstamp"] = os.time() }, protocolResponse)
      else
        rednet.send(sender_id, { ["code"] = 404, ["tstamp"] = os.time() }, protocolResponse)
      end
    end
  end

  --- Queries the recipient computer through the AstralNet protocol
  --- @param uri string
  --- @param message any
  --- @param recipient number
  --- @param timeout? number
  --- @return number|nil
  --- @return table|nil
  --- @return string|nil
  t.Query = function(uri, message, recipient, timeout)
    rednet.send(recipient, { ["uri"] = uri, ["body"] = message }, t.dat["protocol-name"])
    local sender, received, protocol =  rednet.receive(t.dat["protocol-response"], timeout)
    if sender then
      assert(type(received) == "table")
      return sender, received, protocol
    end

    return nil
  end
end

AstralNet.AddProtocol("astralnet-query", nil, nil)

--- Queries the recipient computer through the AstralNet protocol
--- @param uri string
--- @param message any
--- @param recipient number
--- @param protocol? string The protocol to use when making the query
--- @param timeout? number
--- @return number|nil senderId The id of the computer who sent the reply
--- @return table|nil responseMessage The table containing the result 
--- @return string|nil protocol protocol used for the reply
function AstralNet.Query(uri, message, recipient, protocol, timeout)
  assert(type(uri) == "string", "Invalid argument #1, expected a string, got "..type(uri))
  assert(type(message) ~= "nil", "Invalid argument #2, expected a value, got nil")
  assert(type(recipient) == "number", "Invalid argument #3, expected a number, got "..type(recipient))
  protocol = protocol or "astralnet-query"

  local t = protocolHandlers[protocol]
  assert(t, "Could not find a registered protocol for "..protocol)

  return t.Query(uri, message, recipient, timeout)
end

---Registers an AstralNet Handler for the given protocol
---@param protocol string|nil The protocol that the handler is for. If nil or empty, it will be assigned to "astralnet-query"
---@param handlerUri string The uri of the handler
---@param handler any The actual handler. If a function is passed, it will be called with the senderId, message, protocol and uri in that order. If anything else, it will be returned
function AstralNet.AddHandler(protocol, handlerUri, handler)
  assert(type(protocol) == "string" or type(protocol) == "nil", "Invalid argument #1, expected a string or nil, got "..type(protocol))
  assert(type(handlerUri) == "string", "Invalid argument #2, expected a string, got "..type(handlerUri))
  assert(handler, "Invalid argument #3, expected a non-nil value")
  assert(protocolHandlers[protocol], "There is no protocol registered under "..protocol)

  protocolHandlers[protocol].requestHandlers[handlerUri] = handler
end

return { 
  function(event, senderId, message, protocol)
    local handler = protocolHandlers[protocol]
    if handler then
      handler(event, senderId, message, protocol)
      return true
    end
  end,

  nil,

  function()
    
    for protocol, data in pairs(protocolHandlers) do
      local endpoints = {}
      
      for uri, handler in pairs(data.requestHandlers) do
        table.insert(endpoints, uri)
      end
      
      if #endpoints > 0 then  
        table.insert(endpoints, endpoints)
        data.requestHandlers.Endpoints = endpoints
        data.requestHandlers[""] = endpoints
        
        rednet.host(protocol, AstralNet.Hostname)
        print("Started hosting '"..protocol.."' under hostname "..AstralNet.Hostname)
      end
    end
  end
}
