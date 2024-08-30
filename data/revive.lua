-- revive.lua
local revive = {}

local revive_start_time = nil

-- Função para verificar se o jogador está morto e iniciar o temporizador de revive
function revive.check_and_revive()
    local local_player = get_local_player()
    if local_player and local_player:is_dead() then
        if not revive_start_time then
            revive_start_time = os.clock()
            console.print("Player will be revived in 6 seconds.")
        elseif os.clock() - revive_start_time >= 6 then
            revive_at_checkpoint()
            console.print("Player revived at checkpoint.")
            -- Teleporta para a cidade inicial e reinicia os waypoints
            teleport_to_waypoint(helltide_tps[current_city_index].id)
            ni = 1 -- Reinicia o índice dos waypoints
            is_moving = true -- Reinicia o movimento
            revive_start_time = nil -- Reseta o temporizador
        end
    else
        revive_start_time = nil -- Reseta o temporizador se o jogador não estiver morto
    end
end

return revive