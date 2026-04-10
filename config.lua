Config = {}

-- ═══════════════════════════════════════════════════════════
--  Auto-Config: Filled from httpmanager at startup
-- ═══════════════════════════════════════════════════════════
Config.WebcomBaseUrl = nil
Config.ServerId      = nil

-- ═══════════════════════════════════════════════════════════
--  Permission Mode
--  'config'    → Uses ace permissions, job names, citizenid lists below
--  'dashboard' → Uses Dashboard roles/groups via httpmanager license-auth
-- ═══════════════════════════════════════════════════════════
Config.PermissionMode = 'config'

Config.Permissions = {
    admin = { aces = { 'webcom.elevator.admin' }, jobs = { 'police' }, citizenids = {} },
}

Config.DashboardPermissions = {
    admin  = 'elevator.admin',
    manage = 'elevator.manage',
    view   = 'elevator.view',
}

-- ═══════════════════════════════════════════════════════════
--  Admin UI
-- ═══════════════════════════════════════════════════════════
Config.AdminCommand = 'elevatoradmin'

-- ═══════════════════════════════════════════════════════════
--  Interaction Method
--  'target' = ox_target sphere zones
--  'marker' = draw marker + [E] key
-- ═══════════════════════════════════════════════════════════
Config.InteractionMethod = 'target'
Config.MarkerType   = 36
Config.MarkerColor  = { r = 59, g = 130, b = 246, a = 120 }
Config.MarkerScale  = vector3(0.8, 0.8, 0.5)

-- ═══════════════════════════════════════════════════════════
--  3D DUI (Passive Elevator Label)
-- ═══════════════════════════════════════════════════════════
Config.DUI = {
    Enabled      = true,
    ShowDistance  = 10.0,
    FadeDistance  = 15.0,
    Scale        = 0.25,
}

-- ═══════════════════════════════════════════════════════════
--  Interactive Floor DUI (Floor Selection Panel)
-- ═══════════════════════════════════════════════════════════
Config.InteractiveDUI = {
    Enabled      = true,
    ShowDistance  = 6.0,
    Scale        = 0.30,
    Height       = 1.8,
}

-- ═══════════════════════════════════════════════════════════
--  Teleport Settings
-- ═══════════════════════════════════════════════════════════
Config.Teleport = {
    FadeDurationMs  = 800,
    HoldDurationMs  = 500,
    ArrivalSound    = true,
    SoundName       = 'FLIGHT_SCHOOL_LESSON_PASSED',
    SoundRef        = 'HUD_AWARDS',
}

-- ═══════════════════════════════════════════════════════════
--  Cooldown
-- ═══════════════════════════════════════════════════════════
Config.Cooldown = {
    DefaultMs = 5000,
}

-- ═══════════════════════════════════════════════════════════
--  Defaults
-- ═══════════════════════════════════════════════════════════
Config.DefaultColor       = '#3B82F6'
Config.DefaultNavigation  = 'list'

-- ═══════════════════════════════════════════════════════════
--  Network Event Throttling
-- ═══════════════════════════════════════════════════════════
Config.Throttle = {
    MinEventInterval = 500,
    NuiDebounce      = 300,
}

-- ═══════════════════════════════════════════════════════════
--  Dashboard Widget Tokens (optional)
-- ═══════════════════════════════════════════════════════════
Config.Widgets = {
    ['elevator-stats'] = 'PASTE_TOKEN_HERE',
}
Config.PushIntervalMs = 30000
