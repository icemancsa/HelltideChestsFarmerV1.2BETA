local menu = require("menu")
local automindcage = {}

local last_use_time = 0
local cooldown = 0.2 -- 1 segundo de cooldown, ajuste conforme necessário
local uses_remaining = 0

local function check_for_player_buff(buffs, option)
  for _, buff in ipairs(buffs) do
    if buff:name() == option then
      return true
    end
  end
  return false
end

local function use_profane_mindcage(consumable_items)
  local count = menu.profane_mindcage_slider:get()
  for _, item in ipairs(consumable_items) do
    if item:get_name() == "Helltide_ProfaneMindcage" then
      for i = 1, count do
        use_item(item)
      end
      break
    end
  end
end

local function is_in_helltide(local_player)
  local buffs = local_player:get_buffs()
  for _, buff in ipairs(buffs) do
    if buff.name_hash == 1066539 then -- ID do buff de Helltide
      return true
    end
  end
  return false
end

function automindcage.update()
  local local_player = get_local_player()

  if menu.profane_mindcage_toggle:get() then
    local player_position = get_player_position()
    local buffs = local_player:get_buffs()
    local consumable_items = local_player:get_consumable_items()

    local closest_target = target_selector.get_target_closer(player_position, 10)

    local current_time = os.clock()
    if closest_target then
      if uses_remaining == 0 then
        uses_remaining = menu.profane_mindcage_slider:get()
      end

      if uses_remaining > 0 and is_in_helltide(local_player) and not check_for_player_buff(buffs, "Helltide_ProfaneMindcageConsumable") and (current_time - last_use_time) >= cooldown then
        use_profane_mindcage(consumable_items)
        uses_remaining = uses_remaining - 1
        last_use_time = current_time
      end
    end
  end
end

return automindcage