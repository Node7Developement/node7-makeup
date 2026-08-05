local Node7Core = exports['node7-core']:GetCoreObject()

Node7Makeup = Node7Makeup or {}
Node7Makeup.PlayerLoaded = false

local activeSession = false
local openingSession = false
local purchasePending = false
local currentLocation = nil
local sessionToken = nil
local originalProfile = nil
local workingProfile = nil
local savedProfile = nil
local savedProfilePersisted = false
local activeCharacterKey = nil
local camera = nil
local lighting = nil
local promptNames = {}
local worldInteractionsReady = false
local bootstrapRevision = 0
local restoreRevision = 0
local callbackPending = false
local reapplyingSaved = false
local previewPed = 0
local playerHiddenForPreview = false
local playerReturnCoords = nil
local playerReturnHeading = nil
local previewSeated = false
local sessionGender = nil
local textureCache = {}

local EYES_CATEGORY = 0xEA24B45E
local BEARD_CATEGORY = tonumber(Config.BeardCategory) or 0xF8016BCA
local HEADS_CATEGORY = GetHashKey('heads')
local MP_MALE_MODEL = GetHashKey('mp_male')
local MP_FEMALE_MODEL = GetHashKey('mp_female')

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

local function notify(description, notifyType)
    Node7Core.Functions.Notify({
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

local function persistenceConfig(key, fallback)
    local settings = type(Config.Persistence) == 'table' and Config.Persistence or {}
    return tonumber(settings[key]) or fallback
end

local function resolveLocalCharacterKey()
    local state = LocalPlayer and LocalPlayer.state or nil
    if state then
        local citizenid = state.citizenid
            or state.node7CitizenId
            or state.node7_citizenid
            or state.charid
            or state.characterid
            or state.characterId

        if citizenid ~= nil and tostring(citizenid) ~= '' then
            return tostring(citizenid)
        end
    end

    local ok, playerData = pcall(function()
        if Node7Core.Functions and type(Node7Core.Functions.GetPlayerData) == 'function' then
            return Node7Core.Functions.GetPlayerData()
        end
        return nil
    end)

    if ok and type(playerData) == 'table' then
        local citizenid = playerData.citizenid
            or playerData.citizenId
            or playerData.CitizenId
            or playerData.charid
            or playerData.characterid
            or playerData.characterId

        if citizenid ~= nil and tostring(citizenid) ~= '' then
            return tostring(citizenid)
        end
    end

    return nil
end

local function hasLoadedCharacter()
    if Node7Makeup.PlayerLoaded == true
        and activeCharacterKey ~= nil
        and tostring(activeCharacterKey) ~= '' then
        return true
    end

    local citizenid = resolveLocalCharacterKey()
    if citizenid then
        activeCharacterKey = citizenid
        Node7Makeup.PlayerLoaded = true
        return true
    end

    return false
end

local function normalizeGender(value)
    value = tostring(value or ''):lower()
    if value == 'male' or value == 'm' or value == 'man' or value == '0' or value == '1' then return 'male' end
    if value == 'female' or value == 'f' or value == 'woman' or value == '2' then return 'female' end
    return nil
end

local function detectGenderForPed(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    -- Match the native Node7 appearance/barber behavior first. IsPedModel is
    -- used instead of comparing raw signed/unsigned model hashes.
    local maleModel = false
    local femaleModel = false
    pcall(function()
        maleModel = IsPedModel(ped, MP_MALE_MODEL) == true
        femaleModel = IsPedModel(ped, MP_FEMALE_MODEL) == true
    end)

    if maleModel then return 'male' end
    if femaleModel then return 'female' end
    if IsPedMale(ped) == true then return 'male' end

    -- node7-makeup only supports the two native multiplayer freemode peds.
    -- Never expose female cosmetics merely because an unsupported/custom ped
    -- returned false from IsPedMale.
    return 'male'
end

local function getGenderForPed(ped)
    -- The chair session gender comes from the real character/server state and
    -- must win over ClonePed detection during initial preview construction.
    if sessionGender then return sessionGender end
    return detectGenderForPed(ped) or 'male'
end

local function getTargetPed()
    return PlayerPedId()
end

local function findLocation(makeupid)
    for _, location in ipairs(Config.MakeupLocations or {}) do
        if location.makeupid == makeupid then return location end
    end
end

local function isNearLocation(location, maximumDistance)
    if not location then return false end
    local coords = GetEntityCoords(PlayerPedId())
    local dx = coords.x - location.coords.x
    local dy = coords.y - location.coords.y
    local dz = coords.z - location.coords.z
    return (dx * dx + dy * dy + dz * dz) <= (maximumDistance * maximumDistance)
end

local function findNearestLocation(maximumDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local nearest = nil
    local nearestDistanceSquared = (maximumDistance or Config.InteractionDistance) ^ 2

    for _, location in ipairs(Config.MakeupLocations or {}) do
        local dx = coords.x - location.coords.x
        local dy = coords.y - location.coords.y
        local dz = coords.z - location.coords.z
        local distanceSquared = dx * dx + dy * dy + dz * dz
        if distanceSquared <= nearestDistanceSquared then
            nearest = location
            nearestDistanceSquared = distanceSquared
        end
    end

    return nearest
end

local function nativeHasPedComponentLoaded(ped)
    local loaded = Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
    return loaded == true or loaded == 1
end

local function waitForStablePed(revision)
    local timeoutAt = GetGameTimer() + persistenceConfig('PedReadyTimeoutMs', 15000)
    local requiredSamples = math.max(1, math.floor(persistenceConfig('PedStableSamples', 8)))
    local sampleDelay = math.max(50, math.floor(persistenceConfig('PedStableSampleMs', 125)))
    local stableSamples = 0
    local lastPed = 0
    local lastModel = 0

    while GetGameTimer() < timeoutAt do
        if revision and revision ~= restoreRevision then return nil end
        if not hasLoadedCharacter() or activeSession or openingSession then return nil end

        local ped = PlayerPedId()
        local model = DoesEntityExist(ped) and GetEntityModel(ped) or 0
        local ready = ped > 0
            and DoesEntityExist(ped)
            and model ~= 0
            and nativeHasPedComponentLoaded(ped)

        if ready and ped == lastPed and model == lastModel then
            stableSamples = stableSamples + 1
            if stableSamples >= requiredSamples then return ped end
        elseif ready then
            lastPed = ped
            lastModel = model
            stableSamples = 1
        else
            stableSamples = 0
            lastPed = 0
            lastModel = 0
        end

        Wait(sampleDelay)
    end

    debugLog('timed out waiting for a stable player MetaPed')
    return nil
end

local function nativeUpdatePedVariation(ped)
    if not DoesEntityExist(ped) then return false end

    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true)

    local timeout = GetGameTimer() + 3000
    while DoesEntityExist(ped)
        and not nativeHasPedComponentLoaded(ped)
        and GetGameTimer() < timeout do
        Wait(0)
    end

    return DoesEntityExist(ped)
end

local function refreshFace(ped, waitForComponents)
    if not DoesEntityExist(ped) then return false end

    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true)

    if waitForComponents == true then
        local timeout = GetGameTimer() + 3000
        while DoesEntityExist(ped)
            and not nativeHasPedComponentLoaded(ped)
            and GetGameTimer() < timeout do
            Wait(0)
        end
    end

    return DoesEntityExist(ped)
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
        debugLog('data/beards.json could not be loaded on the client')
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
    if gender and gender ~= 'male' then return defaultBeard() end
    incoming = type(incoming) == 'table' and incoming or fallback or {}
    fallback = type(fallback) == 'table' and fallback or defaultBeard()

    local catalog = getBeardCatalog()
    local model = clampInteger(incoming.model, 0, #catalog, fallback.model or 0)
    if model == 0 or type(catalog[model]) ~= 'table' then
        return defaultBeard()
    end

    local texture = clampInteger(incoming.texture, 1, #catalog[model], fallback.texture or 1)
    local entry = catalog[model] and catalog[model][texture] or nil
    if not entry or not tonumber(entry.hash) then return defaultBeard() end

    return {
        model = model,
        texture = texture,
        hash = tonumber(entry.hash),
        remove = false
    }
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

local function overlayDefinition(key)
    for _, definition in ipairs(Config.OverlayDefinitions or {}) do
        if definition.key == key then return definition end
    end
end

local function overlayAllowedForGender(definition, gender)
    if not definition then return false end
    local required = definition.gender or 'both'
    return required == 'both' or required == gender
end

local function sanitizeOverlay(key, incoming, fallback, gender)
    local definition = overlayDefinition(key)
    gender = gender or getGenderForPed(getTargetPed())
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
    gender = gender or getGenderForPed(getTargetPed())
    fallback = type(fallback) == 'table' and fallback or defaultProfile()

    local output = defaultProfile()
    output.ownsOverlays = incoming.ownsOverlays == true or (incoming.ownsOverlays == nil and fallback.ownsOverlays == true)
    output.ownsBeard = gender == 'male' and (
        incoming.ownsBeard == true or (incoming.ownsBeard == nil and fallback.ownsBeard == true)
    ) or false
    output.eyeColor = clampInteger(incoming.eyeColor, 0, tonumber(Config.EyeColorCount) or 14, fallback.eyeColor or 0)
    output.beard = sanitizeBeard(incoming.beard, fallback.beard, gender)

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

local function releaseTextureForPed(ped)
    local cache = textureCache[ped]
    if not cache then return end

    pcall(function()
        Citizen.InvokeNative(0xB63B9178D0F58D82, cache.id)
        Citizen.InvokeNative(0x6BEFAA907B076859, cache.id)
    end)

    textureCache[ped] = nil
end

local function releaseAllTextures()
    local peds = {}
    for ped in pairs(textureCache) do peds[#peds + 1] = ped end
    for _, ped in ipairs(peds) do releaseTextureForPed(ped) end
end

local function bindTexture(ped, textureId)
    if not DoesEntityExist(ped) or not textureId or textureId == -1 then return false end

    -- Keep the same completion and bind order as the proven barber overlay
    -- routine. A seated preview does not receive a MetaPed rebuild.
    Citizen.InvokeNative(0x92DAABA2C1C10B0E, textureId)
    Citizen.InvokeNative(0x8472A1789478F82F, textureId)
    Citizen.InvokeNative(0x0B46E25761519058, ped, HEADS_CATEGORY, textureId)

    -- Binding a new texture handle is not enough to swap eyebrow styles on an
    -- already-built MetaPed. Commit the component variation once after every
    -- bind. This is the same final step used by the working barber eyebrow
    -- routine. It does not restart the chair scenario.
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)

    return true
end

local function overlaySignature(profile, gender)
    local parts = { gender, tostring(profile.ownsOverlays == true) }
    for _, definition in ipairs(Config.OverlayDefinitions or {}) do
        local layer = profile.overlays[definition.key] or defaultOverlay()
        parts[#parts + 1] = table.concat({
            definition.key,
            layer.style or 0,
            layer.palette or 1,
            layer.color1 or 0,
            layer.color2 or 0,
            layer.color3 or 0,
            layer.variant or 0,
            layer.opacity or 0
        }, ':')
    end
    return table.concat(parts, '|')
end

local function getComponentIndexByCategory(ped, categoryHash)
    if not DoesEntityExist(ped) then return nil end

    local ok, count = pcall(function()
        return Citizen.InvokeNative(0x90403E8107B60E81, ped, Citizen.ResultAsInteger())
    end)
    count = ok and tonumber(count) or 0
    if not count or count <= 0 then return nil end

    for index = 0, count - 1 do
        local category = Citizen.InvokeNative(
            0x9B90842304C938A7,
            ped,
            index,
            0,
            Citizen.ResultAsInteger()
        )
        if tonumber(category) == tonumber(categoryHash) then
            return index
        end
    end

    return nil
end

local function getCurrentHeadTextureBase(ped)
    local componentIndex = getComponentIndexByCategory(ped, HEADS_CATEGORY)
    if componentIndex == nil then
        debugLog('current heads component could not be resolved; refusing an unsafe texture override')
        return nil
    end

    -- GET_META_PED_ASSET_GUIDS returns exactly four values:
    -- drawable, albedo, normal and material. pcall adds only the leading
    -- success boolean. The previous five-value unpack shifted every hash and
    -- always left material nil, which made every eyebrow layer fail.
    local ok, drawable, albedo, normal, material = pcall(function()
        return Citizen.InvokeNative(
            0xA9C28516A6DC9D56,
            ped,
            componentIndex,
            Citizen.PointerValueInt(),
            Citizen.PointerValueInt(),
            Citizen.PointerValueInt(),
            Citizen.PointerValueInt()
        )
    end)

    if not ok then
        debugLog(('failed reading current heads assets: %s'):format(tostring(drawable)))
        return nil
    end

    drawable = tonumber(drawable)
    albedo = tonumber(albedo)
    normal = tonumber(normal)
    material = tonumber(material)
    if not albedo or albedo == 0 or not normal or normal == 0 or not material or material == 0 then
        debugLog('current heads assets were incomplete; refusing an unsafe texture override')
        return nil
    end

    return {
        drawable = tonumber(drawable) or 0,
        albedo = albedo,
        normal = normal,
        material = material
    }
end

local function applyOverlayStack(ped, profile, forceRebuild)
    if not DoesEntityExist(ped) or profile.ownsOverlays ~= true then return true end
    if type(overlays_info) ~= 'table' or type(color_palettes) ~= 'table' then return false end

    local gender = getGenderForPed(ped)
    local textureSettings = Node7MakeupCosmetics
        and Node7MakeupCosmetics.texture
        and Node7MakeupCosmetics.texture[gender]
        or nil

    if not textureSettings
        or not tonumber(textureSettings.albedo)
        or not tonumber(textureSettings.normal)
        or not tonumber(textureSettings.material) then
        debugLog(('missing native %s head texture settings'):format(tostring(gender)))
        return false
    end

    local hasActiveLayer = false
    for _, definition in ipairs(Config.OverlayDefinitions or {}) do
        local layer = profile.overlays[definition.key] or defaultOverlay()
        if overlayAllowedForGender(definition, gender)
            and tonumber(layer.style) and tonumber(layer.style) > 0
            and tonumber(layer.opacity) and tonumber(layer.opacity) > 0 then
            hasActiveLayer = true
            break
        end
    end

    if not hasActiveLayer then
        releaseTextureForPed(ped)
        return true
    end

    local signature = overlaySignature(profile, gender)
    local existing = textureCache[ped]
    if forceRebuild ~= true and existing and existing.signature == signature then
        return bindTexture(ped, existing.id)
    end

    releaseTextureForPed(ped)

    local pendingTextureId = nil
    local ok, errorMessage = pcall(function()
        -- This is the exact native texture base used by the working NODE7
        -- barber eyebrow implementation. Do not attempt to read or replace the
        -- character's current head asset GUIDs here; that path produced invalid
        -- texture handles on multiplayer MetaPeds.
        local textureId = Citizen.InvokeNative(
            0xC5E7204F322E49EB,
            tonumber(textureSettings.albedo),
            tonumber(textureSettings.normal),
            tonumber(textureSettings.material)
        )

        if textureId == nil or tonumber(textureId) == -1 then
            error('unable to create native head overlay texture')
        end
        pendingTextureId = textureId

        for _, definition in ipairs(Config.OverlayDefinitions or {}) do
            local layer = profile.overlays[definition.key] or defaultOverlay()
            if overlayAllowedForGender(definition, gender)
                and tonumber(layer.style) and tonumber(layer.style) > 0
                and tonumber(layer.opacity) and tonumber(layer.opacity) > 0 then
                local list = type(Node7GetOverlayList) == 'function'
                    and Node7GetOverlayList(definition.key, gender)
                    or {}
                local overlayData = list[tonumber(layer.style)]

                if not overlayData or not tonumber(overlayData.id) or tonumber(overlayData.id) == 0 then
                    error(('invalid native %s style %s'):format(
                        tostring(definition.key),
                        tostring(layer.style)
                    ))
                end

                -- Match the proven barber sequence exactly: the game's native
                -- facial-overlay identifier is supplied as the layer texture
                -- argument and all unused layer asset slots remain zero.
                local layerId = Citizen.InvokeNative(
                    0x86BB5FF45F193A02,
                    textureId,
                    tonumber(overlayData.id),
                    0,
                    0,
                    0,
                    1.0,
                    0
                )

                if layerId == nil or tonumber(layerId) == nil or tonumber(layerId) < 0 then
                    error(('unable to add native %s layer style %s'):format(
                        tostring(definition.key),
                        tostring(layer.style)
                    ))
                end

                if definition.tint == true then
                    local paletteIndex = clampInteger(
                        layer.palette,
                        1,
                        math.max(#color_palettes, 1),
                        tonumber(definition.palette) or 1
                    )
                    local palette = color_palettes[paletteIndex]
                    if type(palette) ~= 'table' or not tonumber(palette[1]) then
                        error(('invalid native palette for %s'):format(tostring(definition.key)))
                    end

                    Citizen.InvokeNative(0x1ED8588524AC9BE1, textureId, layerId, tonumber(palette[1]))
                    Citizen.InvokeNative(
                        0x2DF59FFE6FFD6044,
                        textureId,
                        layerId,
                        clampInteger(layer.color1, 0, 63, 0),
                        0,
                        0
                    )
                end

                Citizen.InvokeNative(
                    0x3329AAE2882FC8E4,
                    textureId,
                    layerId,
                    clampInteger(layer.variant, 0, tonumber(definition.maxVariant) or 0, 0)
                )
                Citizen.InvokeNative(
                    0x6C76BC24F8BB709A,
                    textureId,
                    layerId,
                    clampInteger(layer.opacity, 0, 100, 100) / 100.0
                )
            end
        end

        local timeout = GetGameTimer() + 5000
        while not Citizen.InvokeNative(0x31DC8D3F216D8509, textureId) do
            if GetGameTimer() >= timeout then
                error('native eyebrow/makeup texture loading timed out')
            end
            Wait(0)
        end

        -- Exact completion order from the working barber resource.
        Citizen.InvokeNative(0x92DAABA2C1C10B0E, textureId)
        Citizen.InvokeNative(0x8472A1789478F82F, textureId)
        Citizen.InvokeNative(0x0B46E25761519058, ped, HEADS_CATEGORY, textureId)

        -- A fresh texture handle will not visually replace the previous
        -- eyebrow style until the MetaPed component variation is committed.
        -- Run this once per successful preview; never restart the chair task.
        Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)

        textureCache[ped] = { id = textureId, signature = signature }
        pendingTextureId = nil
    end)

    if not ok then
        debugLog(('native eyebrow/makeup apply failed: %s'):format(tostring(errorMessage)))
        if pendingTextureId and tonumber(pendingTextureId) ~= -1 then
            pcall(function()
                Citizen.InvokeNative(0xB63B9178D0F58D82, pendingTextureId)
                Citizen.InvokeNative(0x6BEFAA907B076859, pendingTextureId)
            end)
        end
        textureCache[ped] = nil
        return false
    end

    return true
end

local function setNativeComponent(ped, componentHash, deferVariation)
    componentHash = tonumber(componentHash)
    if not DoesEntityExist(ped) or not componentHash or componentHash == 0 then return false end

    local ok, errorMessage = pcall(function()
        local categoryHash = Citizen.InvokeNative(
            0x5FF9A878C3D115B8,
            componentHash,
            not IsPedMale(ped),
            true
        )
        if categoryHash and categoryHash ~= 0 then
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, categoryHash)
        end
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, false, true, true)
        if not deferVariation then nativeUpdatePedVariation(ped) end
    end)

    if not ok then
        debugLog(('native component apply failed: %s'):format(tostring(errorMessage)))
    end
    return ok
end

local function applyEyeColor(ped, value, deferVariation)
    if not DoesEntityExist(ped) then return false end

    local gender = getGenderForPed(ped)
    local list = Node7MakeupCosmetics
        and Node7MakeupCosmetics.eyes
        and Node7MakeupCosmetics.eyes[gender]
        or nil
    if type(list) ~= 'table' or #list < 1 then return false end

    local normalized = clampInteger(value, 1, #list, 1)
    Citizen.InvokeNative(0xD710A5007C2AC539, ped, EYES_CATEGORY, 0)
    local applied = setNativeComponent(ped, list[normalized], true)
    if applied and not deferVariation then nativeUpdatePedVariation(ped) end
    return applied, normalized
end


local function applyBeard(ped, selection, skipVariation, immediate)
    if not DoesEntityExist(ped) or getGenderForPed(ped) ~= 'male' then return false end

    local normalized = sanitizeBeard(selection, defaultBeard(), 'male')
    local ok, errorMessage = pcall(function()
        if normalized.model == 0 or normalized.remove == true then
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, BEARD_CATEGORY, 0)
        else
            local categoryHash = Citizen.InvokeNative(
                0x5FF9A878C3D115B8,
                normalized.hash,
                not IsPedMale(ped),
                true
            )
            if categoryHash and categoryHash ~= 0 then
                Citizen.InvokeNative(0x59BD177A1A48600A, ped, categoryHash)
            end
            Citizen.InvokeNative(
                0xD3A7B003ED343FD9,
                ped,
                normalized.hash,
                immediate == true,
                true,
                true
            )
        end

        if not skipVariation then refreshFace(ped) end
    end)

    if not ok then
        debugLog(('beard apply failed: %s'):format(tostring(errorMessage)))
        return false
    end

    return true, normalized
end

local function applyFeature(ped, feature, value, deferRefresh)
    local featureHash = configuredFeatures[feature]
        and Node7MakeupFeatures
        and Node7MakeupFeatures[feature]
        or nil
    if not featureHash or not DoesEntityExist(ped) then return false end

    local normalized = clampInteger(
        value,
        tonumber(Config.FeatureMinimum) or -100,
        tonumber(Config.FeatureMaximum) or 100,
        0
    )

    Citizen.InvokeNative(0x5653AB26C82938CF, ped, featureHash, normalized / 100.0)
    if not deferRefresh then refreshFace(ped) end
    return true, normalized
end

local function applyFeatureSet(ped, features)
    if not DoesEntityExist(ped) or type(features) ~= 'table' then return false end
    local applied = false
    for feature, value in pairs(features) do
        if configuredFeatures[feature] and Node7MakeupFeatures and Node7MakeupFeatures[feature] then
            local success = applyFeature(ped, feature, value, true)
            applied = applied or success == true
        end
    end
    if applied then refreshFace(ped) end
    return applied
end

local function applyProfileToPed(ped, profile, forceOverlayRebuild)
    if not DoesEntityExist(ped) or type(profile) ~= 'table' then return false end
    profile = sanitizeProfile(profile, profile, getGenderForPed(ped))

    local featuresApplied = applyFeatureSet(ped, profile.features)
    local eyeApplied = true
    if tonumber(profile.eyeColor) and tonumber(profile.eyeColor) > 0 then
        eyeApplied = applyEyeColor(ped, profile.eyeColor, true) == true
    end
    if featuresApplied or (profile.eyeColor or 0) > 0 then
        nativeUpdatePedVariation(ped)
    end
    local overlaysApplied = applyOverlayStack(ped, profile, forceOverlayRebuild)

    local beardApplied = true
    if getGenderForPed(ped) == 'male' and profile.ownsBeard == true then
        beardApplied = applyBeard(ped, profile.beard, true, true) == true
    end

    return eyeApplied == true and overlaysApplied == true and beardApplied == true
end

local function buildCatalog(profile, forcedGender)
    local gender = forcedGender == 'female' and 'female' or 'male'
    local overlayCatalog = {}
    for _, definition in ipairs(Config.OverlayDefinitions or {}) do
        if overlayAllowedForGender(definition, gender) then
            local list = type(Node7GetOverlayList) == 'function'
                and Node7GetOverlayList(definition.key, gender)
                or {}
            overlayCatalog[#overlayCatalog + 1] = {
                key = definition.key,
                label = definition.label,
                group = definition.group,
                styles = #list,
                palettes = 1,
                tint = definition.tint == true,
                maxVariant = tonumber(definition.maxVariant) or 0
            }
        end
    end

    local featureGroups = {}
    for _, group in ipairs(Config.FeatureGroups or {}) do
        local features = {}
        for _, feature in ipairs(group.features or {}) do
            if configuredFeatures[feature] and Node7MakeupFeatures and Node7MakeupFeatures[feature] then
                features[#features + 1] = {
                    key = feature,
                    label = (Config.FeatureLabels and Config.FeatureLabels[feature]) or feature,
                    value = profile.features[feature] or 0,
                    min = tonumber(Config.FeatureMinimum) or -100,
                    max = tonumber(Config.FeatureMaximum) or 100
                }
            end
        end
        featureGroups[#featureGroups + 1] = {
            id = group.id,
            label = group.label,
            features = features
        }
    end

    local beardStyles = {}
    if gender == 'male' then
        local catalog = getBeardCatalog()
        for model = 1, #catalog do
            local textures = catalog[model]
            if type(textures) == 'table' and #textures > 0 then
                local colors = {}
                for texture = 1, #textures do
                    local item = textures[texture]
                    if type(item) == 'table' and tonumber(item.hash) then
                        colors[#colors + 1] = {
                            texture = texture,
                            label = item.color or ('Color %d'):format(texture)
                        }
                    end
                end

                if #colors > 0 then
                    beardStyles[#beardStyles + 1] = {
                        model = model,
                        label = ('Native Beard %02d'):format(model),
                        colors = colors
                    }
                end
            end
        end
    end

    return {
        gender = gender,
        isMale = gender == 'male',
        eyeColors = tonumber(Config.EyeColorCount) or 14,
        beard = {
            models = #beardStyles,
            styles = beardStyles
        },
        overlays = overlayCatalog,
        featureGroups = featureGroups
    }
end

local function deletePrompts()
    promptNames = {}
end

local function setupWorldInteractions()
    -- Interaction is drawn and handled directly by this resource. No commands,
    -- key mappings, core key table entries, or fallback bindings are created.
    worldInteractionsReady = true
    return true
end

local function stopCamera()
    if not camera then return end
    RenderScriptCams(false, true, Config.ExitTransitionMs, true, true)
    SetCamActive(camera, false)
    DestroyCam(camera, true)
    camera = nil
end

local function deletePreviewPed()
    -- Preview is performed on the real multiplayer MetaPed. No clone is
    -- created or hidden, so native eye and head-overlay components apply to
    -- the same ped that the game and Node7 appearance system own.
    previewPed = 0
    previewSeated = false
    playerHiddenForPreview = false
    playerReturnCoords = nil
    playerReturnHeading = nil
end

local function exitChair(restoreSaved, notifyServer)
    if not activeSession and not openingSession then return end

    local token = sessionToken
    activeSession = false
    openingSession = false
    purchasePending = false

    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
    pcall(function() SetNuiFocusKeepInput(false) end)

    local ped = PlayerPedId()
    if restoreSaved and originalProfile and DoesEntityExist(ped) then
        applyProfileToPed(ped, originalProfile, true)
    end

    stopCamera()
    lighting = nil
    deletePreviewPed()

    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
        ClearPedTasks(ped)
        ClearPedSecondaryTask(ped)
    end

    if notifyServer and token then
        TriggerServerEvent('node7-makeup:server:closeSession', token)
    end

    currentLocation = nil
    sessionToken = nil
    originalProfile = nil
    workingProfile = nil
    sessionGender = nil
end

local function seatPlayerAtChair(location, profile)
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return nil end

    -- Ensure the current saved profile is on the real ped before seating.
    if profile then applyProfileToPed(ped, profile, true) end

    local seatScenario = GetHashKey('PROP_PLAYER_BARBER_SEAT')
    Citizen.InvokeNative(0x4D1F61FC34AF3CD1, ped, seatScenario, location.seat, 0, 0, 1)
    Wait(600)
    FreezeEntityPosition(ped, true)
    previewSeated = true
    return ped
end

local function startChairSession(location, state)
    if activeSession or not location or not state or not state.success then return end

    -- Character sex is locked from the server/real player before cloning and is
    -- never recalculated from the preview clone.
    sessionGender = normalizeGender(state.gender)
        or detectGenderForPed(PlayerPedId())
        or 'male'

    local profile = sanitizeProfile(state.profile, defaultProfile(), sessionGender)
    originalProfile = clone(profile)
    workingProfile = clone(profile)
    currentLocation = location
    sessionToken = state.token

    local targetPed = seatPlayerAtChair(location, workingProfile)
    if not targetPed then
        local token = sessionToken
        openingSession = false
        currentLocation = nil
        sessionToken = nil
        originalProfile = nil
        workingProfile = nil
        sessionGender = nil
        deletePreviewPed()
        if token then TriggerServerEvent('node7-makeup:server:closeSession', token) end
        notify('The makeup chair could not seat the character. Move away and reopen it.', 'error')
        return
    end

    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(camera, GetGameplayCamFov())
    SetCamCoord(camera, location.camPos)
    SetCamRot(camera, location.camRot, 2)
    SetCamActive(camera, true)
    RenderScriptCams(true, true, Config.CameraTransitionMs, true, true)
    lighting = location.lighting

    activeSession = true
    openingSession = false

    SendNUIMessage({
        action = 'open',
        shop = location.name,
        profile = workingProfile,
        catalog = buildCatalog(workingProfile, sessionGender),
        isMale = sessionGender == 'male',
        price = state.price or Config.MakeupCost,
        money = state.money or {},
        payments = state.payments or Config.PaymentMethods
    })

    Wait(0)
    SetNuiFocus(true, true)
    pcall(function() SetNuiFocusKeepInput(false) end)
end

local function applyCachedProfile(revision)
    if not hasLoadedCharacter() or not savedProfilePersisted or not savedProfile then return true end
    if reapplyingSaved or activeSession or openingSession then return false end

    local ped = waitForStablePed(revision)
    if not ped or ped ~= PlayerPedId() then return false end

    reapplyingSaved = true
    local ok, result = pcall(function()
        return applyProfileToPed(ped, savedProfile, false)
    end)
    reapplyingSaved = false

    if not ok then
        debugLog(('saved makeup restore failed: %s'):format(tostring(result)))
        return false
    end

    return result == true
end

local function queueProfileRestore()
    restoreRevision = restoreRevision + 1
    local revision = restoreRevision
    local passes = math.max(1, math.floor(persistenceConfig('SettlePasses', 6)))
    local interval = math.max(500, math.floor(persistenceConfig('SettleIntervalMs', 1250)))

    CreateThread(function()
        for _ = 1, passes do
            if revision ~= restoreRevision
                or not hasLoadedCharacter()
                or activeSession
                or openingSession then
                return
            end

            applyCachedProfile(revision)
            Wait(interval)
        end
    end)
end

local function requestAndApplySavedData(delay, maximumAttempts)
    bootstrapRevision = bootstrapRevision + 1
    local revision = bootstrapRevision
    maximumAttempts = math.max(tonumber(maximumAttempts) or persistenceConfig('BootstrapAttempts', 120), 1)
    local retryDelay = math.max(250, math.floor(persistenceConfig('BootstrapRetryMs', 1000)))

    CreateThread(function()
        Wait(delay or 0)
        local attempts = 0

        while revision == bootstrapRevision and attempts < maximumAttempts do
            if activeSession or openingSession then
                Wait(500)
            elseif callbackPending then
                Wait(250)
            else
                attempts = attempts + 1
                callbackPending = true

                local callbackFinished = false
                local callbackResult = nil

                Node7Core.Functions.TriggerCallback('node7-makeup:server:getSavedProfile', function(result)
                    callbackResult = result
                    callbackFinished = true
                    callbackPending = false
                end, detectGenderForPed(PlayerPedId()))

                local timeout = GetGameTimer() + 5000
                while revision == bootstrapRevision
                    and not callbackFinished
                    and GetGameTimer() < timeout do
                    Wait(50)
                end

                if not callbackFinished then
                    callbackPending = false
                elseif revision ~= bootstrapRevision then
                    return
                elseif callbackResult and callbackResult.success and callbackResult.citizenid then
                    local citizenid = tostring(callbackResult.citizenid)
                    local characterChanged = activeCharacterKey and tostring(activeCharacterKey) ~= citizenid

                    if characterChanged then
                        restoreRevision = restoreRevision + 1
                        savedProfile = nil
                        savedProfilePersisted = false
                        releaseAllTextures()
                    end

                    activeCharacterKey = citizenid
                    Node7Makeup.PlayerLoaded = true

                    if not worldInteractionsReady then
                        worldInteractionsReady = setupWorldInteractions()
                    end

                    savedProfilePersisted = callbackResult.persisted == true
                    savedProfile = savedProfilePersisted
                        and sanitizeProfile(callbackResult.profile, defaultProfile(), normalizeGender(callbackResult.gender))
                        or nil

                    debugLog(('loaded makeup persistence for %s (saved=%s)'):format(
                        citizenid,
                        tostring(savedProfilePersisted)
                    ))

                    queueProfileRestore()
                    return
                end

                Wait(retryDelay)
            end
        end

        if revision == bootstrapRevision then
            debugLog(('active Node7 character was unavailable after %d makeup bootstrap attempts'):format(attempts))
        end
    end)
end

local function activateForPlayer()
    requestAndApplySavedData(250, persistenceConfig('BootstrapAttempts', 120))
end

local function deactivateForPlayer()
    if activeSession or openingSession then exitChair(true, true) end
    Node7Makeup.PlayerLoaded = false
    activeCharacterKey = nil
    savedProfile = nil
    savedProfilePersisted = false
    bootstrapRevision = bootstrapRevision + 1
    restoreRevision = restoreRevision + 1
    callbackPending = false
    reapplyingSaved = false
    sessionGender = nil
    deletePrompts()
    releaseAllTextures()
    worldInteractionsReady = false
end

RegisterNetEvent('node7-makeup:client:open', function(makeupid)
    if not hasLoadedCharacter() then
        notify('Load a character before using the makeup chair.', 'error')
        return
    end

    if activeSession or openingSession then return end

    local location = findLocation(tostring(makeupid or ''))
    if not location or not isNearLocation(location, Config.InteractionDistance + 0.5) then
        notify('Move closer to the barber chair.', 'error')
        return
    end

    openingSession = true
    Node7Core.Functions.TriggerCallback('node7-makeup:server:getState', function(state)
        if not openingSession then return end

        if not state or not state.success then
            openingSession = false
            notify(state and state.message or 'The makeup chair could not be opened.', 'error')
            return
        end

        if not isNearLocation(location, Config.InteractionDistance + 0.75) then
            openingSession = false
            TriggerServerEvent('node7-makeup:server:closeSession', state.token)
            return
        end

        startChairSession(location, state)
    end, location.makeupid, detectGenderForPed(PlayerPedId()))
end)

RegisterNUICallback('focus', function(_, cb)
    if activeSession and not purchasePending then
        SetNuiFocus(true, true)
        pcall(function() SetNuiFocusKeepInput(false) end)
        cb({ success = true })
        return
    end
    cb({ success = false })
end)

RegisterNUICallback('previewFeature', function(data, cb)
    if not activeSession or purchasePending or type(data) ~= 'table' then
        cb({ success = false, message = 'No active makeup session.' })
        return
    end

    local feature = tostring(data.feature or '')
    local success, normalized = applyFeature(getTargetPed(), feature, data.value, true)
    if not success then
        cb({ success = false, message = 'Invalid facial adjustment.' })
        return
    end

    workingProfile.features[feature] = normalized
    cb({ success = true, value = normalized })
end)

RegisterNUICallback('previewEye', function(data, cb)
    if not activeSession or purchasePending or type(data) ~= 'table' then
        cb({ success = false, message = 'No active makeup session.' })
        return
    end

    local ped = getTargetPed()
    local success, normalized = applyEyeColor(ped, data.value, false)
    if not success then
        cb({ success = false, message = 'Invalid eye color.' })
        return
    end

    workingProfile.eyeColor = normalized

    -- A MetaPed variation commit is required for eye components. Rebuild the
    -- owned overlay stack afterward, then put the beard back last.
    if workingProfile.ownsOverlays == true then
        applyOverlayStack(ped, workingProfile, true)
    end
    if getGenderForPed(ped) == 'male' and workingProfile.ownsBeard == true then
        applyBeard(ped, workingProfile.beard, true, true)
    end

    cb({ success = true, value = normalized })
end)

RegisterNUICallback('previewOverlay', function(data, cb)
    if not activeSession or purchasePending or type(data) ~= 'table' then
        cb({ success = false, message = 'No active makeup session.' })
        return
    end

    local key = tostring(data.overlay or '')
    local definition = overlayDefinition(key)
    local gender = getGenderForPed(getTargetPed())
    if not definition or not overlayAllowedForGender(definition, gender) then
        cb({ success = false, message = 'This option is not available for this character.' })
        return
    end

    local previousSelection = clone(workingProfile.overlays[key] or defaultOverlay())
    local previousOwnership = workingProfile.ownsOverlays == true
    workingProfile.overlays[key] = sanitizeOverlay(key, data.selection, workingProfile.overlays[key], gender)
    workingProfile.ownsOverlays = true

    if not applyOverlayStack(getTargetPed(), workingProfile, true) then
        workingProfile.overlays[key] = previousSelection
        workingProfile.ownsOverlays = previousOwnership
        applyOverlayStack(getTargetPed(), workingProfile, true)
        cb({ success = false, message = 'The native eyebrow/makeup texture could not be built.' })
        return
    end

    -- MetaPed variation commits can temporarily remove facial-hair components.
    -- Keep beard as the final native component without rebuilding the chair task.
    local targetPed = getTargetPed()
    if getGenderForPed(targetPed) == 'male' and workingProfile.ownsBeard == true then
        applyBeard(targetPed, workingProfile.beard, true, true)
    end

    cb({ success = true, selection = workingProfile.overlays[key], ownsOverlays = true })
end)

RegisterNUICallback('previewBeard', function(data, cb)
    if not activeSession or purchasePending or type(data) ~= 'table' then
        cb({ success = false, message = 'No active makeup session.' })
        return
    end

    local ped = getTargetPed()
    if getGenderForPed(ped) ~= 'male' then
        cb({ success = false, message = 'Beards are only available for male characters.' })
        return
    end

    local success, normalized = applyBeard(ped, data.selection, true, true)
    if not success then
        cb({ success = false, message = 'The beard could not be applied.' })
        return
    end

    workingProfile.beard = normalized
    workingProfile.ownsBeard = true
    cb({ success = true, selection = normalized, ownsBeard = true })
end)

RegisterNUICallback('purchase', function(data, cb)
    if not activeSession or purchasePending then
        cb({ success = false, message = 'A purchase is already processing.' })
        return
    end

    local method = type(data) == 'table' and tostring(data.method or ''):lower() or ''
    if method ~= 'cash' and method ~= 'bank' then
        cb({ success = false, message = 'Choose cash or bank.' })
        return
    end

    purchasePending = true
    TriggerServerEvent('node7-makeup:server:purchase', sessionToken, method, workingProfile)
    cb({ success = true })
end)

RegisterNUICallback('close', function(_, cb)
    exitChair(true, true)
    cb({ success = true })
end)

RegisterNetEvent('node7-makeup:client:purchaseResult', function(success, message, profile)
    purchasePending = false
    if not activeSession then return end

    if not success then
        SendNUIMessage({
            action = 'purchaseResult',
            success = false,
            message = message or 'Payment failed.'
        })
        return
    end

    local saved = sanitizeProfile(profile, workingProfile or defaultProfile(), getGenderForPed(PlayerPedId()))
    workingProfile = clone(saved)
    originalProfile = clone(saved)
    savedProfile = clone(saved)
    savedProfilePersisted = true

    SendNUIMessage({ action = 'purchaseResult', success = true })
    Wait(200)
    exitChair(false, false)
    Wait(0)

    local applied = applyProfileToPed(PlayerPedId(), savedProfile, true)
    if not applied then
        debugLog('saved profile could not be applied safely to the live ped')
        notify('The profile saved, but the native face stack could not be applied. Rejoin to retry.', 'error')
    end
end)

RegisterNetEvent('node7-makeup:client:restore', function()
    queueProfileRestore()
end)

RegisterNetEvent('node7-makeup:client:restoreAll', function()
    queueProfileRestore()
end)

RegisterNetEvent('Node7Core:Client:OnPlayerLoaded', function()
    activateForPlayer()
end)

RegisterNetEvent('Node7Core:Client:OnPlayerUnload', function()
    deactivateForPlayer()
end)

exports('RestoreMakeupNow', function()
    if not savedProfilePersisted or not savedProfile then return false end
    return applyProfileToPed(PlayerPedId(), savedProfile, true)
end)

exports('RestoreMakeup', function()
    queueProfileRestore()
    return true
end)

exports('GetSavedMakeup', function()
    return savedProfilePersisted and clone(savedProfile) or nil
end)

local function drawChairInteraction(text)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 235)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 180)
    DisplayText(CreateVarString(10, 'LITERAL_STRING', text), 0.5, 0.86)
end

CreateThread(function()
    while true do
        local sleep = 750

        if hasLoadedCharacter() and not activeSession and not openingSession then
            local location = findNearestLocation((tonumber(Config.InteractionDistance) or 2.0) + 0.15)
            if location then
                sleep = 0
                drawChairInteraction(Config.PromptLabel or '[K] Use Makeup Chair')

                local virtualKey = tonumber(Config.PromptVirtualKey) or 0x4B
                if IsRawKeyReleased(virtualKey) then
                    TriggerEvent('node7-makeup:client:open', location.makeupid)
                    Wait(350)
                end
            end
        end

        Wait(sleep)
    end
end)

local observedPed = 0
local observedModel = 0
local observedComponentsReady = false

CreateThread(function()
    while true do
        if hasLoadedCharacter() and not activeSession and not openingSession then
            local ped = PlayerPedId()
            local model = DoesEntityExist(ped) and GetEntityModel(ped) or 0
            local componentsReady = ped > 0
                and DoesEntityExist(ped)
                and model ~= 0
                and nativeHasPedComponentLoaded(ped)

            if ped ~= observedPed
                or model ~= observedModel
                or (componentsReady and not observedComponentsReady) then
                if observedPed ~= 0 and observedPed ~= ped then releaseTextureForPed(observedPed) end
                observedPed = ped
                observedModel = model
                observedComponentsReady = componentsReady
                if componentsReady then queueProfileRestore() end
            else
                observedComponentsReady = componentsReady
            end

            Wait(500)
        else
            observedPed = 0
            observedModel = 0
            observedComponentsReady = false
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(2000, math.floor(persistenceConfig('WatchdogIntervalMs', 5000))))
        if hasLoadedCharacter()
            and savedProfilePersisted
            and savedProfile
            and not activeSession
            and not openingSession
            and not reapplyingSaved then
            local ped = PlayerPedId()
            if DoesEntityExist(ped) and nativeHasPedComponentLoaded(ped) then
                applyProfileToPed(ped, savedProfile, false)
            end
        end
    end
end)



AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() and resourceName ~= 'node7-core' then return end

    if resourceName == 'node7-core' then
        worldInteractionsReady = false
        promptNames = {}
    end

    CreateThread(function()
        Wait(resourceName == GetCurrentResourceName() and 750 or 1500)

        if not worldInteractionsReady then
            worldInteractionsReady = setupWorldInteractions()
        end

        activateForPlayer()
    end)
end)

CreateThread(function()
    Wait(1000)

    if not worldInteractionsReady then
        worldInteractionsReady = setupWorldInteractions()
    end

    activateForPlayer()
end)

CreateThread(function()
    while true do
        if activeSession and camera and currentLocation then
            DrawLightWithRange(lighting, 255, 255, 255, 2.5, 50.0)
            SetCamCoord(camera, currentLocation.camPos)
            SetCamRot(camera, currentLocation.camRot, 2)
            DisableControlAction(0, 0x4A903C11, true)
            DisableControlAction(0, 0x07CE1E61, true)
            DisableControlAction(0, 0xF84FA74F, true)
            Wait(0)
        else
            Wait(750)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if activeSession or openingSession then exitChair(true, true) end
    deletePrompts()
    releaseAllTextures()
end)
