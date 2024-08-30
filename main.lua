-- Import menu elements
local menu = require("menu")
local revive = require("data.revive")
local explorer = require("data.explorer")
local automindcage = require("data.automindcage")
local actors = require("data.actors")

-- Função para randomizar waypoints
local function randomize_waypoint(waypoint, max_offset)
    max_offset = max_offset or 1.5 -- Valor padrão de 1.5 metros
    local random_x = math.random() * max_offset * 2 - max_offset
    local random_y = math.random() * max_offset * 2 - max_offset
    
    local randomized_point = vec3:new(
        waypoint:x() + random_x,
        waypoint:y() + random_y,
        waypoint:z()
    )
    
    -- Garante que o ponto randomizado seja caminhável
    randomized_point = set_height_of_valid_position(randomized_point)
    if utility.is_point_walkeable(randomized_point) then
        return randomized_point
    else
        return waypoint -- Retorna o waypoint original se o ponto randomizado não for caminhável
    end
end

-- Inicializa as variáveis
local waypoints = {}
local plugin_enabled = false
local initialMessageDisplayed = false
local doorsEnabled = false
local loopEnabled = false -- Variável para armazenar o estado do loop
local interactedObjects = {}
local is_interacting = false
local interaction_end_time = 0
local ni = 1
local start_time = 0
local check_interval = 120 -- Tempo que ele vai entrar no mapa para explorar e ver se consegue cinders
local current_city_index = 1
local is_moving = false
local teleporting = false
local next_teleport_attempt_time = 0 -- Variável para a próxima tentativa de teleporte
local loading_start_time = nil -- Variável para marcar o início da tela de carregamento
local unvisited_chests = {} -- Tabela para armazenar pontos de baús não abertos
local returning_to_failed = false -- Variável para indicar se está retornando a um waypoint falhado
local previous_cinders_count = 0 -- Variável para armazenar o valor de cinders antes da interação
local moving_backwards = false -- Variável para indicar se o movimento é para trás
local graphics_enabled = false -- Variável para habilitar/desabilitar gráficos
local stuck_check_time = 0
local stuck_threshold = 10 -- Tempo parado para ativar o explorer
local explorer_active = false
local stuck_check_time = os.clock()
local moveThreshold = 12 -- Valor padrão

-- Novas variáveis para controle de movimento
local last_movement_time = 0
local force_move_cooldown = 0
local previous_player_pos = nil -- Variável para armazenar a posição anterior do jogador

local function update_explorer_target()
    if explorer and current_waypoint then
        explorer.set_target(current_waypoint)
    end
end

-- Define padrões para nomes de objetos interativos e seus custos em cinders
local interactive_patterns = {
    usz_rewardGizmo_1H = 125,
    usz_rewardGizmo_2H = 125,
    usz_rewardGizmo_ChestArmor = 75,
    usz_rewardGizmo_Rings = 125,
    usz_rewardGizmo_infernalsteel = 175,
    usz_rewardGizmo_Uber = 175,
    usz_rewardGizmo_Amulet = 125,
    usz_rewardGizmo_Gloves = 75,
    usz_rewardGizmo_Legs = 75,
    usz_rewardGizmo_Boots = 75,
    usz_rewardGizmo_Helm = 75,
}

-- Tempo de expiração em segundos
local expiration_time = 10

-- Lista de cidades e waypoints
local helltide_tps = {
    {name = "Frac_Tundra_S", id = 0xACE9B, file = "menestad"},
    {name = "Scos_Coast", id = 0x27E01, file = "marowen"},
    {name = "Kehj_Oasis", id = 0xDEAFC, file = "ironwolfs"},
    {name = "Hawe_Verge", id = 0x9346B, file = "wejinhani"},
    {name = "Step_South", id = 0x462E2, file = "jirandai"}
}

-- Função para carregar waypoints do arquivo selecionado
local function load_waypoints(file)
    if file == "wejinhani" then
        waypoints = require("waypoints.wejinhani")
        console.print("Loaded waypoints: wejinhani")
    elseif file == "marowen" then
        waypoints = require("waypoints.marowen")
        console.print("Loaded waypoints: marowen")
    elseif file == "menestad" then
        waypoints = require("waypoints.menestad")
        console.print("Loaded waypoints: menestad")
    elseif file == "jirandai" then
        waypoints = require("waypoints.jirandai")
        console.print("Loaded waypoints: jirandai")
    elseif file == "ironwolfs" then
        waypoints = require("waypoints.ironwolfs")
        console.print("Loaded waypoints: ironwolfs")
    else
        console.print("No waypoints loaded")
    end
end

local function randomize_waypoint(waypoint, max_offset)
    max_offset = max_offset or 1.5 -- Valor padrão de 1.5 metros
    local random_x = math.random() * max_offset * 2 - max_offset
    local random_y = math.random() * max_offset * 2 - max_offset
    
    return vec3:new(
        waypoint:x() + random_x,
        waypoint:y() + random_y,
        waypoint:z()
    )
end

-- Função para verificar se o nome do objeto corresponde a algum padrão de interação
local function matchesAnyPattern(name)
    return interactive_patterns[name] ~= nil
end

-- Função para mover o jogador até o objeto e interagir com ele
local function moveToAndInteract(obj)
    local player_pos = get_player_position()
    local obj_pos = obj:get_position()
    local distanceThreshold = 2.0 -- Distancia para interagir com o objeto

    -- Verifica se o slider está disponível e obtém o valor
    if menu.move_threshold_slider then
        moveThreshold = menu.move_threshold_slider:get()
    else
        console.print("Warning: move_threshold_slider is not initialized. Using default value.")
    end

    local distance = obj_pos:dist_to(player_pos)
    
    if distance < distanceThreshold then
        is_interacting = true
        local obj_name = obj:get_skin_name()
        interactedObjects[obj_name] = os.clock() + expiration_time
        interact_object(obj)
        console.print("Interacting with " .. obj_name)
        interaction_end_time = os.clock() + 5
        previous_cinders_count = get_helltide_coin_cinders() -- Armazena o valor de cinders antes da interaÃ§Ã£o
        return true
    elseif distance < moveThreshold then
        pathfinder.request_move(obj_pos)
        return false
    end
end

-- Função para interagir com objetos
local function interactWithObjects()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    local objects = actors_manager.get_ally_actors()

    for _, obj in ipairs(objects) do
        if obj then
            local obj_name = obj:get_skin_name()

            if obj_name and matchesAnyPattern(obj_name) then
                if doorsEnabled and (not interactedObjects[obj_name] or os.clock() > interactedObjects[obj_name]) then
                    if moveToAndInteract(obj) then
                        return
                    end
                end
            end
        end
    end
end

-- Função para verificar se o jogador ainda está interagindo e retomar o movimento se necessário
local function checkInteraction()
    if is_interacting and os.clock() > interaction_end_time then
        is_interacting = false
        local new_cinders_count = get_helltide_coin_cinders()
        local obj_name = nil

        -- Encontra o nome do objeto que está sendo interagido
        for key, expiration in pairs(interactedObjects) do
            if os.clock() < expiration then
                obj_name = key
                break
            end
        end

        if obj_name then
            if new_cinders_count < previous_cinders_count then
                console.print("Interaction successful: Cinders decreased.")
            else
                console.print("Interaction failed: Cinders did not decrease.")
                local required_cinders = interactive_patterns[obj_name]
                if required_cinders then
                    table.insert(unvisited_chests, {index = ni, cinders = required_cinders})
                    console.print("Chest not opened, marking waypoint index for return with required cinders: " .. required_cinders)
                else
                    console.print("Chest not opened, marking waypoint index for return with required cinders: unknown")
                end
            end
        end
        console.print("Interaction complete, resuming movement.")
    end
end

-- Função para verificar a cidade atual e carregar os waypoints
local function check_and_load_waypoints()
    local world_instance = world.get_current_world()
    if world_instance then
        local zone_name = world_instance:get_current_zone_name()

        for _, tp in ipairs(helltide_tps) do
            if zone_name == tp.name then
                load_waypoints(tp.file)
                current_city_index = tp.id -- Atualiza o índice da cidade atual
                return
            end
        end
        console.print("No matching city found for waypoints")
    end
end

-- Função para obter a distância entre o jogador e um ponto
local function get_distance(point)
    return get_player_position():dist_to(point)
end

-- Função para retornar aos waypoints não visitados e tentar interagir novamente
local function moveToUnvisitedChests()
    if #unvisited_chests > 0 then
        ni = table.remove(unvisited_chests, 1).index
        moving_backwards = true
        return true
    end
    moving_backwards = false
    return false
end

-- Função de movimento principal modificada
local function pulse()
    if not plugin_enabled or is_interacting or not is_moving then
        return
    end

    if moveToUnvisitedChests() then
        return
    end

    if type(waypoints) ~= "table" then
        console.print("Error: waypoints is not a table")
        return
    end

    if type(ni) ~= "number" then
        console.print("Error: ni is not a number")
        return
    end

    if ni > #waypoints or ni < 1 or #waypoints == 0 then
        if loopEnabled then
            ni = 1
        else
            return
        end
    end

    current_waypoint = waypoints[ni]
    if current_waypoint then
        local current_time = os.clock()
        local player_pos = get_player_position()
        local distance = get_distance(current_waypoint)
        
        if distance < 2 then
            if moving_backwards then
                ni = ni - 1
            else
                ni = ni + 1
            end
            last_movement_time = current_time
            force_move_cooldown = 0
            previous_player_pos = player_pos
            stuck_check_time = current_time
        else
            if not explorer_active then
                if current_time - stuck_check_time > stuck_threshold then
                    console.print("Player stuck for 15 seconds, calling explorer module")
                    explorer.set_target(current_waypoint)
                    explorer.enable()
                    explorer_active = true
                    return
                end

                if previous_player_pos and player_pos:dist_to(previous_player_pos) < 3 then -- estava 0.1 coloquei 3
                    if current_time - last_movement_time > 5 then
                        console.print("Player stuck, using force_move_raw")
                    local randomized_waypoint = randomize_waypoint(current_waypoint)
                    pathfinder.force_move_raw(randomized_waypoint)
                    last_movement_time = current_time
                end
                else
                    previous_player_pos = player_pos
                    last_movement_time = current_time
                    stuck_check_time = current_time -- Reset stuck_check_time when moving
                end

                if current_time > force_move_cooldown then
                    local randomized_waypoint = randomize_waypoint(current_waypoint)
                    pathfinder.request_move(randomized_waypoint)
                end
            end
        end
    end
end

-- Função para verificar se o jogo está na tela de carregamento
local function is_loading_screen()
    local world_instance = world.get_current_world()
    if world_instance then
        local zone_name = world_instance:get_current_zone_name()
        return zone_name == nil or zone_name == ""
    end
    return true
end

-- Função para verificar se está na Helltide
local function is_in_helltide(local_player)
    local buffs = local_player:get_buffs()
    for _, buff in ipairs(buffs) do
        if buff.name_hash == 1066539 then -- ID do buff de Helltide
            return true
        end
    end
    return false
end

-- Função para iniciar a contagem de cinders e teletransporte
local function start_movement_and_check_cinders()
    if not is_moving then
        start_time = os.clock()
        is_moving = true
    end

    if os.clock() - start_time > check_interval then
        is_moving = false
        local cinders_count = get_helltide_coin_cinders()

        if cinders_count == 0 then
            console.print("No cinders found. Stopping movement to teleport.")
            local player_pos = get_player_position() -- Pega a posição atual do jogador
            pathfinder.request_move(player_pos) -- Move o jogador para sua posição atual para interromper o movimento
            
            if not is_loading_screen() then -- Verifica se não está na tela de carregamento antes de teleportar
                current_city_index = (current_city_index % #helltide_tps) + 1
                teleport_to_waypoint(helltide_tps[current_city_index].id)
                teleporting = true
                next_teleport_attempt_time = os.clock() + 15 -- Define a próxima tentativa de teleporte em 15 segundos
            else
                console.print("Currently in loading screen. Waiting before attempting teleport.")
                next_teleport_attempt_time = os.clock() + 10 -- Ajuste o tempo de espera se necessário
            end
        else
            console.print("Cinders found. Continuing movement.")
        end
    end

    pulse()
end

-- Função chamada periodicamente para interagir com objetos
on_update(function()
    if plugin_enabled then
        if teleporting then
            local current_time = os.clock()
            local current_world = world.get_current_world()
            if not current_world then
                return
            end

            -- Verifica se estamos na tela de loading (Limbo)
            if current_world:get_name():find("Limbo") then
                -- Se estamos no Limbo, define o início da tela de carregamento
                if not loading_start_time then
                    loading_start_time = current_time
                end
                return
            else
                -- Se estávamos no Limbo, mas agora não estamos, verifica se 4 segundos se passaram desde o início da tela de carregamento
                if loading_start_time and (current_time - loading_start_time) < 4 then
                    return
                end
                -- Reseta o tempo de início da tela de carregamento após esperar
                loading_start_time = nil
            end

            if not is_loading_screen() then -- Verifica se não está na tela de carregamento antes de tentar teletransportar
                local world_instance = world.get_current_world()
                if world_instance then
                    local zone_name = world_instance:get_current_zone_name()
                    if zone_name == helltide_tps[current_city_index].name then
                        load_waypoints(helltide_tps[current_city_index].file)
                        ni = 1 -- Resetar o índice do waypoint ao teletransportar
                        teleporting = false
                    elseif os.clock() > next_teleport_attempt_time then -- Verifica se é hora de tentar teleporte novamente
                        console.print("Teleport failed, retrying...")
                        teleport_to_waypoint(helltide_tps[current_city_index].id)
                        next_teleport_attempt_time = os.clock() + 30 -- Ajuste o tempo de espera se necessário
                    end
                end
            end
        else
            local local_player = get_local_player()
            if is_in_helltide(local_player) then
                if explorer_active then
                    if not _G.explorer_active then
                        explorer_active = false
                        console.print("Explorer module finished, resuming normal movement")
                    end
                else
                    if menu.profane_mindcage_toggle:get() then
                        automindcage.update()
                    end
                    checkInteraction()
                    interactWithObjects()
                    start_movement_and_check_cinders()
                    if menu.revive_enabled:get() then -- Verifica se o módulo de revive está habilitado
                        revive.check_and_revive() -- Chama a função de revive
                    end
                    actors.update() -- Chamada Actors
                end
            else
                console.print("Not in Helltide zone. Attempting to teleport.")
                current_city_index = (current_city_index % #helltide_tps) + 1
                teleport_to_waypoint(helltide_tps[current_city_index].id)
                teleporting = true
                next_teleport_attempt_time = os.clock() + 15 -- Define a próxima tentativa de teleporte em 15 segundos
            end
        end
    end
end)

-- Função para converter a tabela de waypoints para uma string
local function waypoints_to_string(waypoints)
    local result = ""
    for i, waypoint in ipairs(waypoints) do
        result = result .. "Waypoint " .. i .. ": " .. waypoint:to_string() .. "\n"
    end
    return result
end

-- Função para renderizar os waypoints
local function render_waypoints()
    if not graphics_enabled then
        return
    end

    -- Define a cor e a espessura da linha -- disabled
    local circle_color = color.new(0, 0, 255) -- Azul
    local line_color = color.new(0, 255, 0) -- Verde
    local text_color = color.new(255, 255, 255) -- Branco
    local thickness = 2.0
    local font_size = 12

    -- Desenha os círculos nos waypoints -- disabled
    for _, waypoint in ipairs(waypoints) do
        graphics.circle_2d(waypoint, 5, circle_color)
    end

    -- Desenha as linhas conectando os waypoints - disabled
    for i = 1, #waypoints - 1 do
        graphics.line(waypoints[i], waypoints[i + 1], line_color, thickness)
    end

    -- Desenha o texto 3D nos waypoints -- disabled
    for i, waypoint in ipairs(waypoints) do
        local text = "Waypoint " .. i  -- Linha modificada
        graphics.text_3d(text, waypoint, font_size, text_color)
    end
end

-- Função chamada periodicamente para renderizar os gráficos -- Disabled
--on_render(function()
    --render_waypoints()
--end)

-- Função para renderizar o menu
on_render_menu(function()
    if menu.main_tree:push("HellChest Farmer (EletroLuz)-V1.2") then
        -- Renderiza o checkbox para habilitar o plugin de movimento
        local enabled = menu.plugin_enabled:get()
        if enabled ~= plugin_enabled then
            plugin_enabled = enabled
            if plugin_enabled then
                console.print("Movement Plugin enabled")
                check_and_load_waypoints()
                stuck_check_time = os.clock()
            else
                console.print("Movement Plugin disabled")
            end
        end
        menu.plugin_enabled:render("Enable Movement Plugin", "Enable or disable the movement plugin")

        -- Renderiza o checkbox para habilitar o plugin de abertura de baus
        local enabled_doors = menu.main_openDoors_enabled:get() or false
        if enabled_doors ~= doorsEnabled then
            doorsEnabled = enabled_doors
            console.print("Open Chests Plugin " .. (doorsEnabled and "enabled" or "disabled"))
        end
        menu.main_openDoors_enabled:render("Open Chests", "Enable or disable the chest plugin")

        -- Renderiza o checkbox para habilitar o loop dos waypoints
        local enabled_loop = menu.loop_enabled:get() or false
        if enabled_loop ~= loopEnabled then
            loopEnabled = enabled_loop
            console.print("Loop Waypoints " .. (loopEnabled and "enabled" or "disabled"))
        end
        menu.loop_enabled:render("Enable Loop", "Enable or disable looping waypoints")

        -- Renderiza o checkbox para habilitar/desabilitar o módulo de revive
        local enabled_revive = menu.revive_enabled:get() or false
        if enabled_revive ~= revive_enabled then
            revive_enabled = enabled_revive
            console.print("Revive Module " .. (revive_enabled and "enabled" or "disabled"))
        end
        menu.revive_enabled:render("Enable Revive Module", "Enable or disable the revive module")

        -- Cria um submenu para as configurações do Profane Mindcage
        if menu.profane_mindcage_tree:push("Profane Mindcage Settings") then
            -- Renderiza o checkbox para habilitar/desabilitar o Profane Mindcage
            local enabled_profane = menu.profane_mindcage_toggle:get() or false
            if enabled_profane ~= profane_mindcage_enabled then
                profane_mindcage_enabled = enabled_profane
                console.print("Profane Mindcage " .. (profane_mindcage_enabled and "enabled" or "disabled"))
            end
            menu.profane_mindcage_toggle:render("Enable Profane Mindcage Auto Use", "Enable or disable automatic use of Profane Mindcage")

            -- Renderiza o slider para o número de Profane Mindcages
            local profane_count = menu.profane_mindcage_slider:get()
            if profane_count ~= profane_mindcage_count then
                profane_mindcage_count = profane_count
                console.print("Profane Mindcage count set to " .. profane_mindcage_count)
            end
            menu.profane_mindcage_slider:render("Profane Mindcage Count", "Number of Profane Mindcages to use")

            menu.profane_mindcage_tree:pop()
        end

        -- Cria um submenu para as configurações do Move Threshold
        if menu.move_threshold_tree:push("Chest Move Range Settings") then
            if menu.move_threshold_slider then
                local move_threshold = menu.move_threshold_slider:get()
                if move_threshold ~= moveThreshold then
                    moveThreshold = move_threshold
                    console.print("Move Threshold set to " .. moveThreshold)
                end
                menu.move_threshold_slider:render("Move Range", "maximum distance the player can detect and move towards a chest in the game")
            else
                console.print("Error: move_threshold_slider is not initialized")
            end
            menu.move_threshold_tree:pop()
        end

        menu.main_tree:pop()
    end
end)