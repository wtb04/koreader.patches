--[[
This user patch is primarily for use with the Project: Title plugin. It requires
Project: Title v3.5 or higher.

It replaces buttons in the top toolbar and (using Project: Title's optional
slot 4) adds an extra button on each side.

You can choose a new icon and new actions for tap and long-press. If you set
icon, tap, or hold to nil then the original value is kept. In this way you
could keep an button's icon and tap action and add only a long-press action
to it.

Icons are set by using their filename without extension, eg: "check" will use
the image file /koreader/resources/icons/mdlite/check.svg

Icons can be any of the ones bundled with KOReader in /koreader/resources/icons
or you can add your own to /koreader/icons

You can manually program a button to do absolutely anything, but the fastest
method is to use the functions defined by, and added to, Dispatcher.

You can find all predefined functions at the link below. For functions added
by plugins, you'll have to go digging into their code to find them.

https://github.com/koreader/koreader/blob/master/frontend/dispatcher.lua
--]]

-- Final layout (file manager titlebar, left -> right):
--   left1  : home                       (Project: Title default)
--   left2  : History                    (tap -> show history)
--   left3  : Calibre wireless toggle    (icon reflects state)
--   left4  : Wi-Fi toggle               (icon reflects state)
--   center : Project: Title hero logo   (untouched)
--   right4 : WireGuard VPN toggle       (icon reflects state)
--   right3 : OPDS catalog               (tap -> custom catalog, hold -> catalog list)
--   right2 : go up                      (Project: Title default)
--   right1 : plus menu                  (Project: Title default)
--
-- Source: https://github.com/joshuacant/KOReader.patches/blob/main/2-toolbar-replace-button.lua
-- License: AGPL-3.0-or-later (derived work)
-- Additional source: https://github.com/joshuacant/KOReader.patches/blob/main/2-toolbar-add-buttons.lua

-- === CONFIGURE YOUR OPDS CATALOG HERE ===
local OPDS_CATALOG_URL   = "http://10.1.0.40:8081/opds"
local OPDS_CATALOG_TITLE = "Calibre OPDS"
-- ========================================

local userpatch = require("userpatch")

local function patchCoverBrowser(plugin)
    local has_pt, TitleBar  = pcall(require, "titlebar")
    if not has_pt or TitleBar._jd_patched_buttons then return end
    TitleBar._jd_patched_buttons = true

    local Dispatcher      = require("dispatcher")
    local PluginLoader    = require("pluginloader")
    local UIManager       = require("ui/uimanager")
    local IconButton      = require("ui/widget/iconbutton")
    local LeftContainer   = require("ui/widget/container/leftcontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan  = require("ui/widget/horizontalspan")

    -- Generic helper: refresh the icon of one slot on the active titlebar.
    local function updateSlotIcon(titlebar, slot, icon)
        local button = titlebar and titlebar[slot .. "_button"]
        if button then
            button:setIcon(icon)
            UIManager:setDirty(titlebar.show_parent, "ui")
        end
    end

    local function scheduleIconRefresh(titlebar, slot, iconFn)
        local function refresh() updateSlotIcon(titlebar, slot, iconFn()) end
        UIManager:scheduleIn(1, refresh)
        UIManager:scheduleIn(3, refresh)
        UIManager:scheduleIn(6, refresh)
    end

    -- ---------------- Wi-Fi ----------------

    local function getWifiOn()
        local NetworkMgr = package.loaded["ui/network/manager"]
        return NetworkMgr and NetworkMgr:isWifiOn() or false
    end

    local function wifiIcon()
        return getWifiOn() and "wifi.open.100" or "wifi.open.0"
    end

    -- ---------------- WireGuard ----------------

    local function getWireGuardConnected()
        local wg = PluginLoader:getPluginInstance("wireguard")
        return wg and wg:isUp() or false
    end

    local function hasWireGuardPlugin()
        return PluginLoader:getPluginInstance("wireguard") ~= nil
    end

    local function wireguardIcon()
        return getWireGuardConnected() and "wifi.secure.100" or "wifi.secure.0"
    end

    -- ---------------- Calibre ----------------

    local function getCalibreConnected()
        local CW = package.loaded["wireless"]
        return CW and CW.calibre_socket ~= nil
    end

    local function calibreIcon()
        return getCalibreConnected() and "star.full" or "star.empty"
    end

    -- ---------------- OPDS ----------------

    local function openOPDSCatalog()
        -- Access the OPDS plugin via the FileManager singleton
        local FileManager = require("apps/filemanager/filemanager")
        local fm = FileManager.instance
        local opds = fm and fm.opds
        if not opds then return end

        -- Use the plugin's own method to create the browser properly
        opds:onShowOPDSCatalog()

        -- Navigate directly into the specific catalog
        local browser = opds.opds_browser
        if browser then
            browser:onMenuSelect({
                text = OPDS_CATALOG_TITLE,
                url  = OPDS_CATALOG_URL,
            })
        end
    end

    -- ---------------- History ----------------

    local function openHistory()
        local FileManager = require("apps/filemanager/filemanager")
        local fm = FileManager.instance
        if fm and fm.history then fm.history:onShowHist() end
    end

    local orig_TitleBar_init = TitleBar.init
    TitleBar.init = function(self)
        -- =========================================================
        -- Tighten the toolbar a bit: smaller side icons + less gap,
        -- so the centered hero gets a little more breathing room.
        -- These are read by the original init when it builds the
        -- buttons and computes paddings.
        -- =========================================================
        self.icon_size              = math.floor(self.icon_size * 0.95)
        self.icon_margin_lr         = math.floor(self.icon_margin_lr * 0.65)
        self.icon_padding_top       = self.icon_padding_top    + math.floor(self.icon_size * 0.12)
        self.icon_padding_bottom    = self.icon_padding_bottom + math.floor(self.icon_size * 0.12)
        self.center_icon_size_ratio = 1.5

        -- =========================================================
        -- Slots 1-3: set icons + callbacks BEFORE the original init,
        -- so the original IconButton constructor picks them up.
        -- =========================================================

        -- Left2: History (replaces "favorites")
        self["left2_icon"] = "history"
        self["left2_icon_tap_callback"] = openHistory
        self["left2_icon_hold_callback"] = nil

        -- Left3: Calibre wireless toggle (replaces "history")
        self["left3_icon"] = calibreIcon()
        self["left3_icon_tap_callback"] = function()
            if getCalibreConnected() then
                Dispatcher:execute({ "calibre_close_connection" })
            else
                Dispatcher:execute({ "calibre_start_connection" })
            end
            scheduleIconRefresh(self, "left3", calibreIcon)
        end
        self["left3_icon_hold_callback"] = function()
            Dispatcher:execute({ "calibre_close_connection" })
            scheduleIconRefresh(self, "left3", calibreIcon)
        end

        -- Right3: Open specific OPDS catalog (replaces "last_document")
        self["right3_icon"] = "book.opened"
        self["right3_icon_tap_callback"] = function()
            openOPDSCatalog()
        end
        self["right3_icon_hold_callback"] = function()
            Dispatcher:execute({ "opds_show_catalog" })
        end

        -- Run the original init to build all the standard slots and the
        -- OverlapGroup. After this returns, self.dimen / self.width /
        -- self.icon_size etc. are populated and we can build slot 4.
        orig_TitleBar_init(self)

        -- =========================================================
        -- Slot 4: extra button on each side, appended after init.
        -- =========================================================

        local icon_total_width = self.icon_size + self.icon_margin_lr
        local padding4 = self.titlebar_margin_lr + (icon_total_width * 3)

        local function buildSlot(side, slot, icon, tap_cb, hold_cb)
            local button = IconButton:new{
                icon = icon,
                width = self.icon_size,
                height = self.icon_size,
                padding = 0,
                padding_bottom = self.icon_padding_bottom,
                padding_top = self.icon_padding_top,
                callback = tap_cb,
                hold_callback = hold_cb,
                show_parent = self.show_parent,
            }
            local btn_w = button:getSize().w
            local pre_padding, post_padding
            if side == "left" then
                pre_padding = padding4
                post_padding = self.width - padding4 - btn_w
            else
                pre_padding = self.width - padding4 - btn_w
                post_padding = padding4
            end
            local container = LeftContainer:new{
                dimen = self.dimen,
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = pre_padding },
                    button,
                    HorizontalSpan:new{ width = post_padding },
                },
            }
            self[slot .. "_button"] = button
            self[slot .. "_button_container"] = container
            table.insert(self, container)
        end

        -- Left4: Wi-Fi toggle (closest to the center on the left)
        buildSlot("left", "left4", wifiIcon(),
            function()
                Dispatcher:execute({ "toggle_wifi" })
                scheduleIconRefresh(self, "left4", wifiIcon)
            end,
            function()
                Dispatcher:execute({ "show_network_info" })
            end)

        -- Right4: WireGuard toggle (closest to the center on the right)
        buildSlot("right", "right4", wireguardIcon(),
            function()
                if hasWireGuardPlugin() then
                    Dispatcher:execute({ "wireguard_toggle" })
                    scheduleIconRefresh(self, "right4", wireguardIcon)
                end
            end,
            function()
                if hasWireGuardPlugin() then
                    Dispatcher:execute({ "wireguard_status" })
                    scheduleIconRefresh(self, "right4", wireguardIcon)
                end
            end)
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
