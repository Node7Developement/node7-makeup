Config = {}

Config.Debug = false
Config.InteractionDistance = 2.0
Config.ServerValidationDistance = 4.0
Config.PromptKey = 'K'
Config.PromptVirtualKey = 0x4B -- Raw Windows virtual-key code for K
Config.PromptLabel = '[K] Use Makeup Chair'
Config.MakeupCost = 5
Config.PaymentMethods = {
    cash = true,
    bank = true
}

Config.CameraTransitionMs = 750
Config.ExitTransitionMs = 500
Config.NotifyTitle = 'NODE7 Makeup'
Config.FeatureMinimum = -100
Config.FeatureMaximum = 100
Config.EyeColorCount = 14
Config.BeardCategory = 0xF8016BCA

Config.Persistence = {
    BootstrapAttempts = 120,
    BootstrapRetryMs = 1000,
    PedReadyTimeoutMs = 15000,
    PedStableSamples = 8,
    PedStableSampleMs = 125,
    SettlePasses = 6,
    SettleIntervalMs = 1250,
    WatchdogIntervalMs = 5000
}

-- Makeup layers are composed on the character current native head assets.
-- The chair never changes head, skin tone, or base complexion. Style 0 disables a layer.
Config.OverlayDefinitions = {
    -- Both multiplayer sexes use their own native eyebrow catalog.
    { key = 'eyebrows',  label = 'Eyebrows',  group = 'eyes',   gender = 'both',   tint = true,  palette = 1, maxVariant = 0 },

    -- Native female cosmetic layers only.
    { key = 'eyeliners', label = 'Eyeliner',  group = 'makeup', gender = 'female', tint = true,  palette = 1, maxVariant = 15 },
    { key = 'shadows',   label = 'Eyeshadow', group = 'makeup', gender = 'female', tint = true,  palette = 1, maxVariant = 5 },
    { key = 'lipsticks', label = 'Lipstick',  group = 'makeup', gender = 'female', tint = true,  palette = 1, maxVariant = 6 },
    { key = 'blush',     label = 'Blush',     group = 'makeup', gender = 'female', tint = true,  palette = 1, maxVariant = 0 },

    -- Native non-tinted head-detail layers supported by the game stack.
    { key = 'scars',     label = 'Scars',     group = 'details',   gender = 'both',   tint = false, palette = 1, maxVariant = 0 },
    { key = 'ageing',    label = 'Ageing',    group = 'details',   gender = 'both',   tint = false, palette = 1, maxVariant = 0 },
    { key = 'freckles',  label = 'Freckles',  group = 'details',   gender = 'both',   tint = false, palette = 1, maxVariant = 0 },
    { key = 'moles',     label = 'Moles',      group = 'details',   gender = 'both',   tint = false, palette = 1, maxVariant = 0 },
    { key = 'spots',     label = 'Spots',      group = 'details',   gender = 'both',   tint = false, palette = 1, maxVariant = 0 }
}

Config.FeatureGroups = {
    { id = 'brows', label = 'Brow Shape', features = { 'eyebrow_height', 'eyebrow_width', 'eyebrow_depth' } },
    { id = 'eyes', label = 'Eyes', features = { 'eyelid_height', 'eyelid_width', 'eyes_depth', 'eyes_angle', 'eyes_distance', 'eyes_height' } },
    { id = 'nose', label = 'Nose', features = { 'nose_width', 'nose_size', 'nose_height', 'nose_angle', 'nose_curvature', 'nostrils_distance' } },
    { id = 'mouth', label = 'Mouth & Lips', features = {
        'mouth_width', 'mouth_depth', 'mouth_y_pos', 'mouth_x_pos',
        'upper_lip_height', 'upper_lip_width', 'upper_lip_depth',
        'lower_lip_height', 'lower_lip_width'
    } },
    { id = 'jaw', label = 'Jaw & Chin', features = { 'jaw_height', 'jaw_width', 'jaw_depth', 'chin_height', 'chin_width', 'chin_depth' } },
    { id = 'cheeks', label = 'Cheeks', features = { 'cheekbones_height', 'cheekbones_width', 'cheekbones_depth' } }
}

Config.FeatureLabels = {
    head_width = 'Head Width', face_width = 'Face Width', face_depth = 'Face Depth',
    forehead_size = 'Forehead Size', neck_width = 'Neck Width', neck_depth = 'Neck Depth',
    eyebrow_height = 'Brow Height', eyebrow_width = 'Brow Width', eyebrow_depth = 'Brow Depth',
    eyelid_height = 'Eyelid Height', eyelid_width = 'Eyelid Width', eyes_depth = 'Eye Depth',
    eyes_angle = 'Eye Angle', eyes_distance = 'Eye Distance', eyes_height = 'Eye Height',
    nose_width = 'Nose Width', nose_size = 'Nose Size', nose_height = 'Nose Height',
    nose_angle = 'Nose Angle', nose_curvature = 'Nose Curve', nostrils_distance = 'Nostril Distance',
    mouth_width = 'Mouth Width', mouth_depth = 'Mouth Depth', mouth_y_pos = 'Mouth Height', mouth_x_pos = 'Mouth Position',
    upper_lip_height = 'Upper Lip Height', upper_lip_width = 'Upper Lip Width', upper_lip_depth = 'Upper Lip Depth',
    lower_lip_height = 'Lower Lip Height', lower_lip_width = 'Lower Lip Width',
    jaw_height = 'Jaw Height', jaw_width = 'Jaw Width', jaw_depth = 'Jaw Depth',
    chin_height = 'Chin Height', chin_width = 'Chin Width', chin_depth = 'Chin Depth',
    cheekbones_height = 'Cheekbone Height', cheekbones_width = 'Cheekbone Width', cheekbones_depth = 'Cheekbone Depth',
    ears_width = 'Ear Width', ears_angle = 'Ear Angle', ears_height = 'Ear Height', ears_size = 'Ear Size'
}

-- Same physical barber chairs as node7-barbers. No blips are created.
Config.MakeupLocations = {
    {
        name = 'Valentine', makeupid = 'val-makeup',
        coords = vector3(-307.96, 814.16, 118.99),
        seat = vector4(-306.62, 813.56, 118.75, 90.60),
        camPos = vector3(-307.35, 813.45, 119.61),
        camRot = vector3(-18.29, 0.0, -79.42),
        lighting = vector3(-307.39, 813.43, 119.51)
    },
    {
        name = 'Saint Denis', makeupid = 'std-makeup',
        coords = vector3(2656.16, -1180.87, 53.28),
        seat = vector4(2655.38, -1180.92, 53.00, 182.8),
        camPos = vector3(2655.38, -1181.69, 53.87),
        camRot = vector3(-16.55, 0.0, 2.01),
        lighting = vector3(2655.35, -1182.23, 54.07)
    },
    {
        name = 'Blackwater', makeupid = 'blk-makeup',
        coords = vector3(-815.88, -1364.72, 43.75),
        seat = vector4(-815.17, -1368.75, 43.50, 95.5),
        camPos = vector3(-816.06, -1368.76, 44.26),
        camRot = vector3(-10.98, 0.0, -88.66),
        lighting = vector3(-816.46, -1368.77, 44.26)
    }
}
