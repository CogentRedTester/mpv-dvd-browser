local mp = require 'mp'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

local o = {
    lsdvd = 'lsdvd',
    dvd_device = mp.get_property('dvd-device', '/dev/dvd'),

    wsl = false,
    wsl_password = ""
}

opt.read_options(o, 'dvd_browser')

if (o.dvd_device == "") then o.dvd_device = '/dev/dvd' end

local dvd_structure = {}
local titles = {}
local ov = mp.create_osd_overlay('ass-events')
ov.hidden = true
local state = {
    disc = false
}

local function append(str)
    ov.data = ov.data .. str .. "\\N"
end

--sends a call to lsdvd to read the contents of the disc
local function read_disc()
    local args
    if o.wsl then
        local r = mp.command_native({
            name = 'subprocess',
            playback_only = false,
            args = {'wsl', 'echo', o.wsl_password, '|', 'sudo', '-S', 'mount', '-t', 'drvfs', 'G:', '/mnt/dvd'}
        })

        --settings wsl arguments
        args = {'wsl', 'lsdvd', o.dvd_device, '-Oy'}
    else
        args = {'lsdvd', o.dvd_device, '-Oy'}
    end

    local cmd, error = mp.command_native({
        name = 'subprocess',
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = args
    })

    -- msg.verbose(utils.to_string(result))

    local result = cmd.stdout:gsub("'", '"')

    result = result:gsub('lsdvd = ', '')
    dvd_structure = utils.parse_json(result)

    if (not dvd_structure) then
        msg.error(cmd.stderr)
        state.disc = false
        return
    end
    msg.debug(utils.to_string(dvd_structure))
    state.disc = true
end

--update the DVD browser
function update_browser()
    ov.data = ""
    for _,value in ipairs(dvd_structure.track) do
        append("track "..value.ix.." ["..value.length.."]")
    end
end

--if we're playing a disc then read it
mp.observe_property('file-format', 'string', function(_, format)
    if format ~= "disc" then
        state.disc = false
        return
    end
    read_disc()
end)

mp.add_key_binding('Shift+browser', 'dvd-browser', function()
    update_browser()

    if ov.hidden then
        ov.hidden = false
        ov:update()
    else
        ov.hidden = true
        ov:remove()
    end
end)
