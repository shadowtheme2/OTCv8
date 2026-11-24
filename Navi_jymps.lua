-- NAVI MINI ONLINE v7 - VPS
setDefaultTab("Main")
UI.Separator()
UI.Label("NAVI MINI"):setColor("green")

-- CONEXIÓN A LA VPS
local SERVER_URL = "wss://195.62.47.245/"

local myName = player:getName()
local ws = nil
local connected = false
local connectionWanted = false
local isLeader = false
local clientId = nil
local leaderClientId = nil
local roster = {}
local playerStatus = {} 
local targetId = nil
local attackActive = false
local followerPaused = false
local leaderEscapeStopped = false
local lastSentTarget = false
local markedCreature = nil
local attackMacro = nil
local leaderMonitor = nil
local connectionSwitch = nil
local connectionGeneration = 0
local issuingFollowerAttack = false
local lastFollowerAttackAt = 0

-- 1. GUARDAMOS EL ESTADO EN STORAGE
storage.naviMiniOnline = storage.naviMiniOnline or { enabled = false }
local config = storage.naviMiniOnline

-- 2. DEFINIMOS EL ESTILO DE LA CRUZ
local STYLES = [[
MinimapCrossAnen < UIWidget
  focusable: false
  image-source: /images/game/minimap/cross
  color: green
  image-color: green
  size: 16 16
]]

g_ui.loadUIFromString(STYLES)

local statusLabel = UI.Label("Estado: desconectado")
local roleLabel = UI.Label("Rol: sin asignar")
local countLabel = UI.Label("Conectados: 0")

-- Ventana de conectados: mismos widgets compatibles que NAVI_LEADER (OTCv8).
-- MainWindow + VerticalScrollBar + ScrollablePanel, sin ScrollArea ni estilos personalizados.
local rosterWindow = setupUI([[
MainWindow
  id: naviMiniRosterWindow
  text: NAVI MINI - Conectados
  size: 355 420
  visible: false
  padding: 8
  background-color: #101622
  border: 1 #3A4D69

  Label
    id: rosterWindowCount
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: rosterCloseButton.left
    margin-top: 6
    margin-left: 5
    text: Conectados: 0
    color: #62E7A6
    font: verdana-11px-rounded

  Button
    id: rosterCloseButton
    anchors.top: parent.top
    anchors.right: parent.right
    margin-top: 3
    margin-right: 3
    width: 25
    height: 23
    text: X
    color: #FFB0B0
    background-color: #3C2733

  Panel
    id: rosterDivider
    anchors.top: rosterWindowCount.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 8
    height: 1
    background-color: #33445D

  VerticalScrollBar
    id: rosterScrollbar
    anchors.top: rosterDivider.bottom
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    margin-top: 7
    margin-right: 3
    margin-bottom: 5
    width: 13
    step: 22
    pixels-scroll: true
    visible: false

  ScrollablePanel
    id: rosterList
    anchors.top: rosterDivider.bottom
    anchors.left: parent.left
    anchors.right: rosterScrollbar.left
    anchors.bottom: parent.bottom
    margin-top: 7
    margin-left: 5
    margin-bottom: 5
    vertical-scrollbar: rosterScrollbar
    auto-focus: none
    layout:
      type: verticalBox
      spacing: 2
]], g_ui.getRootWidget())

local rosterListWidget = rosterWindow and rosterWindow:recursiveGetChildById('rosterList')
local rosterWindowCount = rosterWindow and rosterWindow:recursiveGetChildById('rosterWindowCount')
local rosterCloseButton = rosterWindow and rosterWindow:recursiveGetChildById('rosterCloseButton')
if rosterWindow then
  rosterWindow:hide()
  if rosterCloseButton then
    rosterCloseButton.onClick = function() rosterWindow:hide() end
  end
  rosterWindow.onEscape = function() rosterWindow:hide() end
end

UI.Button('Ver conectados', function()
  if not rosterWindow then return end
  if rosterWindow:isVisible() then
    rosterWindow:hide()
  else
    rosterWindow:show()
    rosterWindow:raise()
    rosterWindow:focus()
  end
end)

local listCross = {}
local rosterRows = {}

local function updateConnectedList()
  local names = {}
  if connected then
    for _, entry in ipairs(roster) do
      local name = tostring(entry.name or 'Desconocido')
      local leader = (leaderClientId ~= nil and tostring(entry.id) == tostring(leaderClientId))
        or entry.is_leader == true
      table.insert(names, { name = name, leader = leader })
    end
  end
  table.sort(names, function(a, b)
    if a.leader ~= b.leader then return a.leader end
    return a.name:lower() < b.name:lower()
  end)

  if rosterWindowCount then rosterWindowCount:setText('Conectados: ' .. #names) end
  for i, entry in ipairs(names) do
    local label = rosterRows[i]
    if not label and rosterListWidget then
      label = g_ui.createWidget('Label', rosterListWidget)
      if label then
        label:setHeight(20)
        label:setWidth(305)
        rosterRows[i] = label
      end
    end
    if label then
    label:setText((entry.leader and '[LIDER] ' or '  -  ') .. entry.name)
    label:setColor(entry.leader and 'green' or 'white')
    label:show()
    end
  end
  for i = #names + 1, #rosterRows do
    rosterRows[i]:hide()
  end
end

local function refreshUI()
  statusLabel:setText("Estado: " .. (connected and "conectado" or "desconectado"))
  roleLabel:setText("Rol: " .. (isLeader and "LIDER" or (connected and "SEGUIDOR" or "sin asignar")))
  
  local count = 0
  for _ in pairs(roster) do count = count + 1 end
  countLabel:setText("Conectados: " .. count)
  updateConnectedList()
end

local function sendPacket(topic, message)
  if not connected or not ws then return false end
  local payload = { type = "message", name = myName, topic = topic }
  if message ~= nil then payload.message = message end
  local ok, err = pcall(function() ws.send(payload) end)
  return ok
end

local function clearTargetMark()
  if markedCreature then pcall(function() markedCreature:setMarked("") end); markedCreature = nil end
end

local function markTargetRed(creature)
  if not creature then clearTargetMark(); return end
  if markedCreature and markedCreature ~= creature then pcall(function() markedCreature:setMarked("") end) end
  markedCreature = creature
  local function keepMark(target)
    if g_game.getAttackingCreature() == target then
      pcall(function() target:setMarked("red") end)
      schedule(333, function() keepMark(target) end)
    else
      pcall(function() target:setMarked("") end)
      if markedCreature == target then markedCreature = nil end
    end
  end
  keepMark(creature)
end

local function clearFollowerAttack()
  targetId = nil; attackActive = false; followerPaused = false
  if attackMacro then attackMacro.setOn(false) end
  clearTargetMark()
  if not isLeader and g_game.isOnline() then
    if g_game.cancelAttackAndFollow then g_game.stop(); g_game.cancelAttackAndFollow()
    elseif g_game.cancelAttack then g_game.cancelAttack() end
  end
end

local function sendLeaderTarget(creature)
  if not connected or not isLeader then return end
  if leaderEscapeStopped then if not creature then return end; leaderEscapeStopped = false end
  if not creature then
    if lastSentTarget ~= false then lastSentTarget = false; sendPacket("attack", { action = "stop" }) end
    return
  end
  local id = creature:getId()
  if id == lastSentTarget then return end
  lastSentTarget = id
  sendPacket("attack", { action = "attack", creature = id })
end

local function disconnectFromServer()
  local wasLeader = isLeader
  connectionWanted = false
  connectionGeneration = connectionGeneration + 1
  if wasLeader and connected then sendPacket("attack", { action = "stop" }) end
  if not isLeader then clearFollowerAttack() end
  local old = ws
  ws = nil; connected = false; isLeader = false; clientId = nil; leaderClientId = nil; roster = {}; playerStatus = {}
  leaderEscapeStopped = false; lastSentTarget = false
  refreshUI()
  
  for _, w in pairs(listCross) do w:destroy() end
  listCross = {}

  if old then pcall(function() old.close() end) end
end

local function connectToServer()
  if connected or ws then return end
  if not connectionWanted then return end

  connectionGeneration = connectionGeneration + 1
  local thisGeneration = connectionGeneration
  statusLabel:setText("Estado: conectando...")

  local ok, socketOrError = pcall(function()
    return HTTP.WebSocketJSON(SERVER_URL, {
      onOpen = function()
        if thisGeneration ~= connectionGeneration or not connectionWanted then return end
        connected = true; refreshUI()
        schedule(100, function()
          if thisGeneration == connectionGeneration and connected and connectionWanted then sendPacket("connect", {}) end
        end)
      end,
      onMessage = function(message)
        if thisGeneration ~= connectionGeneration or type(message) ~= "table" then return end
        if message.type == "ping" then if ws then pcall(function() ws.send({ type = "ping" }) end) end; return end
        if message.type ~= "message" then return end

        if message.topic == "welcome" then clientId = tonumber((message.message or {}).client_id); return end
        
        if message.topic == "roster" then
          local data = message.message or {}
          local wasLeader = isLeader
          roster = {}
          
          -- NUEVO: Buscar si YO soy el líder en la lista
          local iAmLeaderInList = false
          for _, entry in ipairs(data.players or {}) do
            table.insert(roster, { id = tostring(entry.id), name = tostring(entry.name), is_leader = entry.is_leader == true })
            if tostring(entry.id) == tostring(clientId) and entry.is_leader then
                iAmLeaderInList = true
            end
          end
          
          leaderClientId = tonumber(data.leader_id)
          
          isLeader = (clientId ~= nil and leaderClientId == clientId) or iAmLeaderInList

          if isLeader and not wasLeader then
            leaderEscapeStopped = false; lastSentTarget = false; targetId = nil; attackActive = false
            followerPaused = false; if attackMacro then attackMacro.setOn(false) end
          elseif wasLeader and not isLeader then clearFollowerAttack() end
          
          refreshUI()
          if isLeader and not wasLeader and g_game.isOnline() then sendLeaderTarget(g_game.getAttackingCreature()) end
          return
        end

        if message.topic == "status" then
            local st = message.message or {}
            local name = st.name
            if name and st.data then playerStatus[name] = st.data end
            return
        end

        if message.topic == "attack" then
          local data = message.message or {}
          if data.action == "stop" or not data.creature then
            if isLeader then
              if message.name == "NaviMiniServer" then leaderEscapeStopped = true; lastSentTarget = false end
            else clearFollowerAttack() end
            return
          end
          if isLeader then return end
          local id = tonumber(data.creature)
          if id and (targetId ~= id or followerPaused) then
            if getCreatureById(id) then
                followerPaused = false; targetId = id; attackActive = true; attackMacro.setOn(true)
            end
          end
        end
      end,
      onClose = function(reason)
        if thisGeneration ~= connectionGeneration then return end
        connectionGeneration = connectionGeneration + 1
        local wasLeader = isLeader
        ws = nil; connected = false; isLeader = false; clientId = nil; leaderClientId = nil; roster = {}; playerStatus = {}
        targetId = nil; attackActive = false; followerPaused = false; leaderEscapeStopped = false; lastSentTarget = false
        if attackMacro then attackMacro.setOn(false) end
        clearTargetMark()
        if not wasLeader and g_game.isOnline() then
          if g_game.cancelAttackAndFollow then g_game.stop(); g_game.cancelAttackAndFollow()
          elseif g_game.cancelAttack then g_game.cancelAttack() end
        end
        refreshUI()
        
        for _, w in pairs(listCross) do w:destroy() end
        listCross = {}
        
        if connectionWanted and config.enabled then
            schedule(3000, function()
                if connectionWanted and not ws then connectToServer() end
            end)
        end
      end,
      onError = function(reason)
        if thisGeneration ~= connectionGeneration then return end
        statusLabel:setText("Estado: error")
      end
    }, 60)
  end)

  if not ok or not socketOrError then
    ws = nil; connected = false; connectionWanted = false
    if connectionSwitch then connectionSwitch:setOn(false) end
    refreshUI()
    return
  end
  ws = socketOrError
end

macro(1000, function()
    if connected and g_game.isOnline() then
        local pos = player:getPosition()
        if pos then
            sendPacket("status", { name = myName, x = pos.x, y = pos.y, z = pos.z, mana = math.floor(player:getMana()), maxMana = math.floor(player:getMaxMana()) })
        end
    end
end)

attackMacro = macro(100, function()
  if not connected or isLeader or not attackActive or followerPaused or not targetId or not g_game.isOnline() then return end
  local target = getCreatureById(targetId)
  if not target then return end
  if g_game.getAttackingCreature() ~= target then
    issuingFollowerAttack = true; g_game.attack(target); lastFollowerAttackAt = now; issuingFollowerAttack = false
  end
end)
attackMacro.setOn(false)

leaderMonitor = macro(100, function()
  if not connected or not isLeader or not g_game.isOnline() or leaderEscapeStopped then return end
  sendLeaderTarget(g_game.getAttackingCreature())
end)
leaderMonitor.setOn(true)

connectionSwitch = addSwitch("NaviMiniOnlineConnection", "Navi Mini - Conectar", function(widget)
  widget:setOn(not widget:isOn())
  config.enabled = widget:isOn()
  if widget:isOn() then 
    connectionWanted = true
    connectToServer()
  else 
    disconnectFromServer() 
  end
end)

connectionSwitch:setOn(config.enabled)
if config.enabled then 
  connectionWanted = true
  schedule(2000, function() 
    if connectionWanted and not ws then connectToServer() end 
  end)
end

onKeyDown(function(keyCode)
  if not connected or not isLeader or type(keyCode) ~= "string" then return end
  if keyCode:lower() == "escape" then
    leaderEscapeStopped = true; lastSentTarget = false; sendPacket("attack", { action = "stop" })
  end
end)

onAttackingCreatureChange(function(creature)
  markTargetRed(creature)
  if not connected then return end
  if isLeader then
    if creature then leaderEscapeStopped = false end
    sendLeaderTarget(creature); return
  end
  if attackActive and not followerPaused and not issuingFollowerAttack then
    if not creature then
      if now - lastFollowerAttackAt > 300 then
        followerPaused = true; if attackMacro then attackMacro.setOn(false) end
      end
    elseif targetId and creature:getId() ~= targetId then
      followerPaused = true; if attackMacro then attackMacro.setOn(false) end
    end
  end
end)

-- ==========================================
-- DIBUJADO DE CRUCES EN EL MINIMAPA
-- ==========================================
local minimap = modules.game_minimap.minimapWidget

local function drawTeammates()
    for name, st in pairs(playerStatus) do
        if name ~= myName then
            local pos = { x = st.x, y = st.y, z = st.z }
            
            if not listCross[name] then
                listCross[name] = g_ui.createWidget('MinimapCrossAnen', minimap)
                listCross[name]:breakAnchors()
            end
            
            local zOffset = pos.z - posz()
            if zOffset > 0 then zOffset = "+" .. tostring(zOffset) else zOffset = tostring(zOffset) end
            
            listCross[name]:setTooltip(name .. "  " .. zOffset)
            listCross[name]:setImageColor(posz() == pos.z and "gray" or posz() > pos.z and "red" or "green")
            
            minimap:centerInPosition(listCross[name], { x = pos.x, y = pos.y, z = posz() })
        end
    end
    
    for name, widget in pairs(listCross) do
        if not playerStatus[name] then
            widget:destroy()
            listCross[name] = nil
        end
    end
end

macro(200, function()
    if connected and g_game.isOnline() then
        drawTeammates()
    end
end)

refreshUI()
print("Navi Mini VPS cargado para " .. myName)