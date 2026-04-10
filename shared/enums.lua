-- ═══════════════════════════════════════════════════════════
--  Shared Enums – Available on client and server
-- ═══════════════════════════════════════════════════════════

ProtectionType = {
    NONE     = 'none',
    PIN      = 'pin',
    PASSWORD = 'password',
    JOB      = 'job',
    ITEM     = 'item',
}

NavigationMode = {
    LIST   = 'list',
    UPDOWN = 'updown',
}

InteractionType = {
    TARGET = 'target',
    DUI    = 'dui',
}

AdminTab = {
    OVERVIEW = 'overview',
    GROUPS   = 'groups',
    CREATOR  = 'creator',
    EDITOR   = 'editor',
}

CreatorStep = {
    GROUP      = 1,
    BASIC_INFO = 2,
    FLOORS     = 3,
    REVIEW     = 4,
}
