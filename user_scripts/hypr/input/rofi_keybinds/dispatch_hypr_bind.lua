#!/usr/bin/env luajit
-- ==============================================================================
-- Hyprland 0.56+ Keybinding Dispatch Helper
-- Resolves keybinding descriptions from ~/.config/hypr to exact actions.
-- Handles dsp proxies (hl.dsp.*), exec/exec_cmd and function-based binds
-- (cond_bind, zoom, DPMS timers, notifications) via a working `hl` stub env.
-- ==============================================================================

local target_desc = arg[1] or ""
local fallback_dsp = arg[2] or ""
local fallback_arg = arg[3] or ""

-- If fallback is direct exec or exec_cmd with non-empty arg, run immediately
if (fallback_dsp == "exec" or fallback_dsp == "exec_cmd") and fallback_arg ~= "" then
    os.execute(fallback_arg .. " >/dev/null 2>&1 &")
    os.exit(0)
end

local HOME = os.getenv("HOME") or ("/home/" .. (os.getenv("USER") or ""))
dusky_scripts = HOME .. "/user_scripts/"

-- Include Hyprland config dir in package path dynamically
package.path = HOME .. "/.config/hypr/?.lua;" ..
               HOME .. "/.config/hypr/?/init.lua;" ..
               HOME .. "/.config/hypr/source/?.lua;" ..
               HOME .. "/.config/hypr/edit_here/source/?.lua;" ..
               package.path

local binds = {}

-- ---------------------------------------------------------------------------
-- Working `hl` stub environment
-- ---------------------------------------------------------------------------

local function sh(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "" end
    local out = f:read("*a") or ""
    f:close()
    return out
end

local function run_async(cmd)
    if cmd == "" then return false end
    return os.execute(cmd .. " >/dev/null 2>&1 &")
end

local function make_dsp_proxy(path)
    return setmetatable({}, {
        __index = function(_, k)
            return make_dsp_proxy(path .. "." .. k)
        end,
        __call = function(_, ...)
            return { _type = "dsp", path = path, args = {...} }
        end
    })
end

local function dispatch_proxy(dsp)
    if type(dsp) ~= "table" or dsp._type ~= "dsp" or not dsp.path then
        return false
    end

    if (dsp.path == "hl.dsp.exec_cmd" or dsp.path == "hl.dsp.exec") and dsp.args[1] then
        return run_async(tostring(dsp.args[1]))
    end

    -- Build Lua dispatcher call string e.g. hl.dsp.window.close()
    local arg_strs = {}
    for _, a in ipairs(dsp.args) do
        if type(a) == "string" then
            table.insert(arg_strs, string.format("%q", a))
        elseif type(a) == "number" or type(a) == "boolean" then
            table.insert(arg_strs, tostring(a))
        elseif type(a) == "table" then
            local kv = {}
            for k, v in pairs(a) do
                if type(v) == "string" then
                    table.insert(kv, string.format("%s = %q", k, v))
                else
                    table.insert(kv, string.format("%s = %s", k, tostring(v)))
                end
            end
            table.insert(arg_strs, "{ " .. table.concat(kv, ", ") .. " }")
        end
    end

    local res = os.execute("hyprctl dispatch " .. string.format("%q", dsp.path .. "(" .. table.concat(arg_strs, ", ") .. ")"))
    return res == 0
end

hl = {}
hl.notification = {}
hl.dsp = setmetatable({}, {
    __index = function(_, k)
        return make_dsp_proxy("hl.dsp." .. k)
    end
})

function hl.bind(key, dsp, opts)
    if opts and opts.description then
        binds[opts.description] = dsp
    end
end

function hl.dispatch(dsp)
    if type(dsp) == "function" then
        pcall(dsp)
    else
        dispatch_proxy(dsp)
    end
end

-- Config state: merged during load, only flushed to hyprctl at runtime so
-- loading config modules never mutates the running session.
local loading = true
local config_state = {}

local function apply_keywords(tbl)
    local function render(t)
        local parts = {}
        for k, v in pairs(t) do
            if type(v) == "table" then
                parts[#parts + 1] = k .. " = " .. render(v)
            elseif type(v) == "string" then
                parts[#parts + 1] = k .. " = " .. string.format("%q", v)
            elseif type(v) == "boolean" then
                parts[#parts + 1] = k .. " = " .. (v and "true" or "false")
            else
                parts[#parts + 1] = k .. " = " .. tostring(v)
            end
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end

    local expr = "hl.config(" .. render(tbl) .. ")"
    os.execute("hyprctl eval '" .. expr:gsub("'", "'\\''") .. "' >/dev/null 2>&1")
end

function hl.config(tbl)
    local t = type(tbl) == "table" and tbl or {}
    for k, v in pairs(t) do
        if type(v) == "table" and type(config_state[k]) == "table" then
            for kk, vv in pairs(v) do config_state[k][kk] = vv end
        else
            config_state[k] = v
        end
        if not loading then
            apply_keywords({ [k] = v })
        end
    end
end

local function live_zoom_factor()
    local out = sh("hyprctl -j getoption cursor:zoom_factor")
    local f = out:match('"float":%s*(%d+%.?%d*)')
    return f and tonumber(f) or 1.0
end

function hl.get_config(path)
    if path == "cursor.zoom_factor" then
        return live_zoom_factor()
    end
    return nil
end

function hl.get_active_window()
    local out = sh("hyprctl -j activewindow")
    local class = out:match('"class":%s*"([^"]*)"')
    if not class then return nil end
    return { class = class }
end

function hl.notification.create(opts)
    local t = opts or {}
    local text = tostring(t.text or "")
    local timeout = math.floor(tonumber(t.timeout) or 5000)
    local safe = text:gsub("'", "'\\''")
    run_async("notify-send -t " .. timeout .. " 'Dusky Keybinds' '" .. safe .. "'")
end

function hl.timer(fn, opts)
    -- One-shot timers: run immediately (worst case a few ms early).
    if type(fn) == "function" then
        pcall(fn)
    end
end

function hl.define_submap(name, fn)
    if type(fn) == "function" then
        pcall(fn)
    end
end

function cond_bind(key, default_dsp, flags)
    if flags and flags.description then
        binds[flags.description] = default_dsp
    end
end

-- Load Hyprland configuration files
pcall(require, "edit_here.source.default_apps")
pcall(require, "source.keybinds")
pcall(require, "edit_here.source.keybinds")
loading = false

-- ---------------------------------------------------------------------------
-- Resolve the selected bind
-- ---------------------------------------------------------------------------

local action = binds[target_desc]

if type(action) == "table" and action._type == "dsp" then
    if not dispatch_proxy(action) then
        run_async("notify-send -u critical 'Keybind Error' 'Failed to dispatch: " .. tostring(target_desc or ""):gsub("'", "'\\''") .. "'")
        os.exit(1)
    end
    os.exit(0)
elseif type(action) == "function" then
    local ok, err = pcall(action)
    if not ok then
        local msg = tostring(err or "unknown error"):gsub("'", "'\\''")
        run_async("notify-send -u critical 'Keybind Error' '" .. msg .. "'")
        os.exit(1)
    end
    os.exit(0)
end

-- Unknown description or non-dsp bind: fall back to plain hyprctl dispatch.
if fallback_dsp ~= "" and fallback_dsp ~= "__lua" then
    local cmd = "hyprctl dispatch " .. string.format("%q", fallback_dsp)
    if fallback_arg ~= "" then
        cmd = cmd .. " " .. string.format("%q", fallback_arg)
    end
    local res = os.execute(cmd)
    os.exit(res == 0 and 0 or 1)
end