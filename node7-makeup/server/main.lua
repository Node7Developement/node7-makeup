local Node7Core = exports['node7-core']:GetCoreObject()

local sessions = {}
local purchaseLocks = {}
local databaseReady = false
local PROFILE_TABLE = 'node7_makeup_profiles'

local configuredFeatures = {}
for _, group in ipairs(Config.FeatureGroups or {}) do
    for _, feature in ipairs(group.features or {}) do
        configuredFeatures[feature] = true
    end
end

local function debugLog(message)
    if Config.Debug then
        print(('[node7-makeup] %s'):format(tostring(message)))
    end
end

local function notify(src, description, notifyType)
    Node7Core.Functions.Notify(src, {
        title = Config.NotifyTitle,
        description = description,
        type = notifyType or 'info',
        duration = 5000
    })
end

local function clone(value)
    if type(value) ~= 'table' then return value end
    local output = {}
    for key, item in pairs(value) do output[key] = clone(item) end
    return output
end

local function clampNumber(value, minimum, maximum, fallback)
    value = tonumber(value) or tonumber(fallback) or minimum
    if value < minimum then value = minimum end
    if value > maximum then value = maximum end
    return value
end

local function clampInteger(value, minimum, maximum, fallback)
    return math.floor(clampNumber(value, minimum, maximum, fallback))
end

local function findLocation(makeupid)
    for _, location in ipairs(Config.MakeupLocations or {}) do
        if location.makeupid == makeupid then return location end
    end
end

local function playerNearLocation(src, location, maximumDistance)
    if not location then return false end

    local ped = GetPlayerPed(src)
    if not ped or ped <= 0 then return false end

    local coords = GetEntityCoords(ped)
    local maximumDistanceSquared = maximumDistance * maximumDistance

    local function nearPoint(point)
        local dx = coords.x - point.x
        local dy = coords.y - point.y
        local dz = coords.z - point.z
        return (dx * dx + dy * dy + dz * dz) <= maximumDistanceSquared
    end

    return nearPoint(location.coords) or nearPoint(location.seat)
end

local function valueToCitizenId(value)
    if type(value) ~= 'table' then return nil end

    local direct = value.citizenid
        or value.citizenId
        or value.CitizenId
        or value.charid
        or value.characterid
        or value.characterId

    if direct ~= nil and tostring(direct) ~= '' then
        return tostring(direct)
    end

    if type(value.PlayerData) == 'table' then
        local nested = valueToCitizenId(value.PlayerData)
        if nested then return nested end
    end

    if type(value.data) == 'table' then
        local nested = valueToCitizenId(value.data)
        if nested then return nested end
    end

    return nil
end

local function getCitizenId(player, src)
    local citizenid = valueToCitizenId(player)
    if citizenid then return citizenid end

    src = tonumber(src)
    if src and Player(src) and Player(src).state then
        local state = Player(src).state
        citizenid = state.citizenid
            or state.node7CitizenId
            or state.node7_citizenid
            or state.charid
            or state.characterid
            or state.characterId

        if citizenid ~= nil and tostring(citizenid) ~= '' then
            return tostring(citizenid)
        end
    end

    local ok, directPlayer = pcall(function()
        return src and Node7Core.Functions.GetPlayer(src) or nil
    end)

    if ok then
        citizenid = valueToCitizenId(directPlayer)
        if citizenid then return citizenid end
    end

    return nil
end

local function normalizeGender(value)
    local normalized = tostring(value or ''):lower()
    if normalized == 'female' or normalized == 'f' or normalized == 'woman' or normalized == '2' then
        return 'female'
    end
    if normalized == 'male' or normalized == 'm' or normalized == 'man' or normalized == '0' or normalized == '1' then
        return 'male'
    end
    return nil
end

local function getGender(player)
    local playerData = player and player.PlayerData or {}
    local charinfo = type(playerData.charinfo) == 'table' and playerData.charinfo or {}
    return normalizeGender(charinfo.gender)
        or normalizeGender(playerData.gender)
        or normalizeGender(playerData.sex)
        or normalizeGender(charinfo.sex)
        or 'male'
end

local function overlayDefinition(key)
    for _, definition in ipairs(Config.OverlayDefinitions or {}) do
        if definition.key == key then return definition end
    end
end

local function defaultOverlay()
    return {
        style = 0,
        palette = 1,
        color1 = 0,
        color2 = 0,
        color3 = 0,
        variant = 0,
        opacity = 100
    }
end

local function defaultBeard()
    return { model = 0, texture = 1, hash = 0, remove = true }
end

local beardCatalogCache = false

local function getBeardCatalog()
    if beardCatalogCache ~= false then
        return beardCatalogCache
    end

    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/beards.json')
    if type(raw) ~= 'string' or raw == '' then
        beardCatalogCache = {}
        debugLog('data/beards.json could not be loaded on the server')
        return beardCatalogCache
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' or #decoded < 1 then
        beardCatalogCache = {}
        debugLog('data/beards.json contains invalid JSON')
        return beardCatalogCache
    end

    for model = 1, #decoded do
        local textures = decoded[model]
        if type(textures) ~= 'table' or #textures < 1 then
            beardCatalogCache = {}
            debugLog(('beard model %d has no textures'):format(model))
            return beardCatalogCache
        end

        for texture = 1, #textures do
            local entry = textures[texture]
            if type(entry) ~= 'table' or not tonumber(entry.hash) then
                beardCatalogCache = {}
                debugLog(('beard model %d texture %d is invalid'):format(model, texture))
                return beardCatalogCache
            end
            entry.hash = tonumber(entry.hash)
        end
    end

    beardCatalogCache = decoded
    debugLog(('loaded %d native beard models from data/beards.json'):format(#decoded))
    return beardCatalogCache
end

local function sanitizeBeard(incoming, fallback, gender)
    if gender ~= 'male' then return defaultBeard() end

    incoming = type(incoming) == 'table' and incoming or fallback or {}
    fallback = type(fallback) == 'table' and fallback or defaultBeard()
    local catalog = getBeardCatalog()
    local model = clampInteger(incoming.model, 0, #catalog, fallback.model or 0)
    if model == 0 or type(catalog[model]) ~= 'table' then return defaultBeard() end

    local texture = clampInteger(incoming.texture, 1, #catalog[model], fallback.texture or 1)
    local entry = catalog[model] and catalog[model][texture] or nil
    if not entry or not tonumber(entry.hash) then return defaultBeard() end

    return { model = model, texture = texture, hash = tonumber(entry.hash), remove = false }
end

local function defaultProfile()
    local profile = {
        version = 2,
        ownsOverlays = false,
        ownsBeard = false,
        eyeColor = 0,
        beard = defaultBeard(),
        features = {},
        overlays = {}
    }

    for _, definition in ipairs(Config.OverlayDefinitions or {}) do
        profile.overlays[definition.key] = defaultOverlay()
    end

    return profile
end

local function overlayAllowedForGender(definition, gender)
    if not definition then return false end
    local required = definition.gender or 'both'
    return required == 'both' or required == gender
end

local function sanitizeOverlay(key, incoming, fallback, gender)
    local definition = overlayDefinition(key)
    local list = type(Node7GetOverlayList) == 'function' and Node7GetOverlayList(key, gender) or {}
    if not definition or not overlayAllowedForGender(definition, gender) or type(list) ~= 'table' then
        return defaultOverlay()
    end

    incoming = type(incoming) == 'table' and incoming or fallback or {}
    fallback = type(fallback) == 'table' and fallback or defaultOverlay()

    return {
        style = clampInteger(incoming.style, 0, #list, fallback.style or 0),
        palette = clampInteger(definition.palette or incoming.palette, 1, math.max(#(color_palettes or {}), 1), 1),
        color1 = clampInteger(incoming.color1, 0, 63, fallback.color1 or 0),
        color2 = 0,
        color3 = 0,
        variant = clampInteger(incoming.variant, 0, tonumber(definition.maxVariant) or 0, fallback.variant or 0),
        opacity = clampInteger(incoming.opacity, 0, 100, fallback.opacity or 100)
    }
end

local function sanitizeProfile(incoming, fallback, gender)
    incoming = type(incoming) == 'table' and incoming or {}
    fallback = type(fallback) == 'table' and fallback or defaultProfile()

    local output = defaultProfile()
    output.ownsOverlays = incoming.ownsOverlays == true or (incoming.ownsOverlays == nil and fallback.ownsOverlays == true)
    output.ownsBeard = gender == 'male' and (
        incoming.ownsBeard == true or (incoming.ownsBeard == nil and fallback.ownsBeard == true)
    ) or false
    output.eyeColor = clampInteger(incoming.eyeColor, 0, tonumber(Config.EyeColorCount) or 14, fallback.eyeColor or 0)
    output.beard = sanitizeBeard(incoming.beard, fallback.beard, gender or 'male')

    local incomingFeatures = type(incoming.features) == 'table' and incoming.features or {}
    local fallbackFeatures = type(fallback.features) == 'table' and fallback.features or {}
    for feature in pairs(configuredFeatures) do
        local value = incomingFeatures[feature]
        if value == nil then value = fallbackFeatures[feature] end
        if value ~= nil then
            output.features[feature] = clampInteger(
                value,
                tonumber(Config.FeatureMinimum) or -100,
                tonumber(Config.FeatureMaximum) or 100,
                0
            )
        end
    end

    local incomingOverlays = type(incoming.overlays) == 'table' and incoming.overlays or {}
    local fallbackOverlays = type(fallback.overlays) == 'table' and fallback.overlays or {}
    for _, definition in ipairs(Config.OverlayDefinitions or {}) do
        output.overlays[definition.key] = sanitizeOverlay(
            definition.key,
            incomingOverlays[definition.key],
            fallbackOverlays[definition.key],
            gender
        )
    end

    return output
end

local function decodeProfile(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return nil end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil end
    return decoded
end

local function deepEqual(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return left == right end

    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function getProfileData(player, src, forcedGender)
    local citizenid = getCitizenId(player, src)
    if not citizenid then return nil end

    local gender = normalizeGender(forcedGender) or getGender(player)
    local row = MySQL.single.await(
        ('SELECT `gender`, `profile` FROM `%s` WHERE `citizenid` = ? LIMIT 1'):format(PROFILE_TABLE),
        { citizenid }
    )

    local persisted = row ~= nil
    local decoded = persisted and decodeProfile(row.profile) or nil
    local profile = sanitizeProfile(decoded, defaultProfile(), gender)

    return {
        citizenid = citizenid,
        gender = gender,
        profile = profile,
        persisted = persisted
    }
end

local function saveProfile(citizenid, gender, profile)
    profile = sanitizeProfile(profile, defaultProfile(), gender)
    local encoded = json.encode(profile)

    local query = ([=[
        INSERT INTO `%s` (`citizenid`, `gender`, `profile`)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            `gender` = VALUES(`gender`),
            `profile` = VALUES(`profile`),
            `updated_at` = CURRENT_TIMESTAMP
    ]=]):format(PROFILE_TABLE)

    local ok, affectedOrError = pcall(function()
        return MySQL.update.await(query, { citizenid, gender, encoded })
    end)

    if not ok then
        print(('[node7-makeup] Profile save failed for %s: %s'):format(citizenid, tostring(affectedOrError)))
        return false
    end

    if affectedOrError == nil then
        print(('[node7-makeup] Profile save returned no result for %s.'):format(citizenid))
        return false
    end

    local verified = MySQL.single.await(
        ('SELECT `gender`, `profile` FROM `%s` WHERE `citizenid` = ? LIMIT 1'):format(PROFILE_TABLE),
        { citizenid }
    )

    local verifiedProfile = verified and decodeProfile(verified.profile) or nil
    local matches = verified ~= nil
        and tostring(verified.gender or '') == tostring(gender)
        and verifiedProfile ~= nil
        and deepEqual(sanitizeProfile(verifiedProfile, defaultProfile(), gender), profile)

    if not matches then
        print(('[node7-makeup] Profile verification failed for %s.'):format(citizenid))
    end

    return matches, profile
end

local function newSessionToken(src)
    return ('%s:%s:%s'):format(src, os.time(), math.random(100000, 999999))
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(100) end

    local ok, errorMessage = pcall(function()
        MySQL.query.await(([=[
            CREATE TABLE IF NOT EXISTS `%s` (
                `citizenid` VARCHAR(64) NOT NULL,
                `gender` VARCHAR(8) NOT NULL DEFAULT 'male',
                `profile` LONGTEXT NOT NULL,
                `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]=]):format(PROFILE_TABLE))

        MySQL.query.await(('ALTER TABLE `%s` MODIFY `citizenid` VARCHAR(64) NOT NULL'):format(PROFILE_TABLE))
        MySQL.query.await(('ALTER TABLE `%s` MODIFY `profile` LONGTEXT NOT NULL'):format(PROFILE_TABLE))
    end)

    if not ok then
        databaseReady = false
        print(('[node7-makeup] Database startup failed: %s'):format(tostring(errorMessage)))
        return
    end

    databaseReady = true
    print('[node7-makeup] Independent makeup database is ready.')
end)

Node7Core.Functions.CreateCallback('node7-makeup:server:getSavedProfile', function(source, cb, clientGender)
    if not databaseReady then
        cb({ success = false, message = 'The makeup database is still starting.' })
        return
    end

    local player = Node7Core.Functions.GetPlayer(source)
    if not player then
        cb({ success = false, message = 'Your Node7 character is not loaded.' })
        return
    end

    local data = getProfileData(player, source, clientGender)
    if not data then
        cb({ success = false, message = 'The active character ID could not be resolved.' })
        return
    end

    cb({
        success = true,
        citizenid = data.citizenid,
        gender = data.gender,
        profile = data.persisted and clone(data.profile) or nil,
        persisted = data.persisted
    })
end)

Node7Core.Functions.CreateCallback('node7-makeup:server:getState', function(source, cb, makeupid, clientGender)
    if not databaseReady then
        cb({ success = false, message = 'The makeup database is still starting.' })
        return
    end

    local player = Node7Core.Functions.GetPlayer(source)
    if not player then
        cb({ success = false, message = 'Your Node7 character is not loaded.' })
        return
    end

    local location = findLocation(tostring(makeupid or ''))
    if not location or not playerNearLocation(source, location, Config.ServerValidationDistance) then
        cb({ success = false, message = 'Move closer to the barber chair.' })
        return
    end

    local data = getProfileData(player, source, clientGender)
    if not data then
        cb({ success = false, message = 'The makeup chair could not load your saved profile.' })
        return
    end

    local token = newSessionToken(source)
    sessions[source] = {
        token = token,
        makeupid = location.makeupid,
        citizenid = data.citizenid,
        gender = data.gender,
        expires = os.time() + 900
    }

    cb({
        success = true,
        token = token,
        gender = data.gender,
        profile = clone(data.profile),
        persisted = data.persisted,
        price = tonumber(Config.MakeupCost) or 0,
        money = clone(player.PlayerData.money or {}),
        payments = clone(Config.PaymentMethods or {})
    })
end)

RegisterNetEvent('node7-makeup:server:closeSession', function(token)
    local src = source
    local session = sessions[src]
    if session and session.token == token then
        sessions[src] = nil
    end
end)

RegisterNetEvent('node7-makeup:server:purchase', function(token, paymentMethod, incomingProfile)
    local src = source
    if purchaseLocks[src] then return end
    purchaseLocks[src] = true

    local function finish()
        purchaseLocks[src] = nil
    end

    local function fail(message)
        TriggerClientEvent('node7-makeup:client:purchaseResult', src, false, message)
        finish()
    end

    if not databaseReady then
        fail('The makeup database is still starting.')
        return
    end

    local player = Node7Core.Functions.GetPlayer(src)
    local session = sessions[src]
    local method = tostring(paymentMethod or ''):lower()

    if not player then
        fail('Your Node7 character is not loaded.')
        return
    end

    if not session or session.token ~= token or session.expires < os.time() then
        fail('The makeup session expired. Reopen the chair.')
        return
    end

    local citizenid = getCitizenId(player, src)
    if not citizenid or tostring(citizenid) ~= tostring(session.citizenid) then
        sessions[src] = nil
        fail('Your active character changed. Reopen the makeup chair.')
        return
    end

    local location = findLocation(session.makeupid)
    if not playerNearLocation(src, location, Config.ServerValidationDistance) then
        sessions[src] = nil
        fail('You moved too far from the barber chair.')
        return
    end

    if (method ~= 'cash' and method ~= 'bank') or not Config.PaymentMethods[method] then
        fail('Choose an enabled cash or bank payment method.')
        return
    end

    local currentData = getProfileData(player, src, session.gender)
    if not currentData then
        fail('The makeup chair could not load your current profile.')
        return
    end

    local profile = sanitizeProfile(incomingProfile, currentData.profile, session.gender)
    local price = math.max(0, math.floor(tonumber(Config.MakeupCost) or 0))
    local balance = tonumber(player.Functions.GetMoney(method)) or 0

    if balance < price then
        local label = method == 'bank' and 'bank balance' or 'cash'
        local message = ('You do not have enough %s.'):format(label)
        notify(src, message, 'error')
        fail(message)
        return
    end

    local removed, removeResult = exports['node7-core']:RemovePlayerMoney(
        src,
        method,
        price,
        'node7-makeup-purchase'
    )

    if not removed then
        fail(type(removeResult) == 'string' and removeResult or 'Payment could not be completed.')
        return
    end

    local saved, normalized = saveProfile(citizenid, session.gender, profile)
    if not saved then
        exports['node7-core']:AddPlayerMoney(src, method, price, 'node7-makeup-refund')
        notify(src, 'The makeup profile failed to save. Your payment was refunded.', 'error')
        fail('The makeup profile could not be saved. Your payment was refunded.')
        return
    end

    sessions[src] = nil
    notify(src, ('Makeup profile purchased for $%d using %s.'):format(price, method), 'success')
    TriggerClientEvent('node7-makeup:client:purchaseResult', src, true, nil, clone(normalized))
    debugLog(('saved makeup profile for %s using %s'):format(citizenid, method))
    finish()
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    purchaseLocks[source] = nil
end)

AddEventHandler('Node7Core:Server:OnPlayerUnload', function(source)
    source = tonumber(source)
    sessions[source] = nil
    purchaseLocks[source] = nil
end)
