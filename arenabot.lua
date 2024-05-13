-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
-- Determines proximity between two points.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Strategically decides on the next move based on proximity, energy, and game dynamics.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange = false
  local closestTargetDistance = math.huge
  local closestTarget = nil

  -- Find the closest target within range
  for target, state in pairs(LatestGameState.Players) do
      if target ~= ao.id then
          local distance = math.sqrt((player.x - state.x)^2 + (player.y - state.y)^2)
          if distance < closestTargetDistance then
              closestTargetDistance = distance
              closestTarget = target
          end
      end
  end

  -- If a target is within immediate range, attack
  if player.energy > 5 and inRange(player.x, player.y, LatestGameState.Players[closestTarget].x, LatestGameState.Players[closestTarget].y, 1) then
    print("Player in range. Attacking.")
    ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy)})
  -- If no target is in immediate range but a target is close, move towards it
  elseif closestTarget and closestTargetDistance > 1 and closestTargetDistance <= 3 then
    local directionToTarget = getDirectionToTarget(player.x, player.y, LatestGameState.Players[closestTarget].x, LatestGameState.Players[closestTarget].y)
    print("Moving towards target.")
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionToTarget})
  -- Otherwise, move randomly
  else
    print("No player in immediate range. Moving randomly.")
    local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local randomIndex = math.random(#directionMap)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex]})
  end
end

-- Helper function to determine the direction to a target
function getDirectionToTarget(x1, y1, x2, y2)
  local directionMap = {
      Up = {x = 0, y = -1}, Down = {x = 0, y = 1},
      Left = {x = -1, y = 0}, Right = {x = 1, y = 0},
      UpRight = {x = 1, y = -1}, UpLeft = {x = -1, y = -1},
      DownRight = {x = 1, y = 1}, DownLeft = {x = -1, y = 1}
  }
  local bestDirection = "Up"
  local minDistance = math.huge

  -- Determine the best direction that minimizes the distance to the target
  for direction, offset in pairs(directionMap) do
      local newX = x1 + offset.x
      local newY = y1 + offset.y
      local distance = math.sqrt((newX - x2)^2 + (newY - y2)^2)
      if distance < minDistance then
          minDistance = distance
          bestDirection = direction
      end
  end

  return bestDirection
end
-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)
-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local playerEnergy = LatestGameState.Players[ao.id].energy
      local cooldown = LatestGameState.Players[ao.id].cooldown or 0
      local currentTime = os.time()

      -- Check if the cooldown has passed
      if currentTime >= cooldown then
        if playerEnergy == nil then
          print(colors.red .. "Unable to read energy." .. colors.reset)
          ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
        elseif playerEnergy == 0 then
          print(colors.red .. "Player has insufficient energy." .. colors.reset)
          ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
        else
          print(colors.green .. "Returning attack." .. colors.reset)
          ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
          -- Set a new cooldown time to prevent spamming
          LatestGameState.Players[ao.id].cooldown = currentTime + 5 -- Cooldown of 5 seconds
        end
      else
        print(colors.yellow .. "Attack on cooldown. Waiting to retaliate." .. colors.reset)
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

