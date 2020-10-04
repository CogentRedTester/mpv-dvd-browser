local mp = require 'mp'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

local o = {
    lsdvd = 'lsdvd',

    --path to the dvd device to send to lsdvd, leaving this blank will set the script to
    --use the --dvd-device option.
    --It is recommended that this be left blank unless using wsl
    dvd_device = "",

    --changes default mpv behaviour and loads the first title instead of the longest when
    --the title isn't specified
    start_from_first_title = true,

    --adds the previous and subsequent titles to the playlist when playing a dvd
    --only does this when there is only one item in the playlist
    create_playlist = true,

    --when dvd:// (no specified title) is loaded the script will always insert all of the
    --titles into the playlist, regardless of the playlist length
    --similar to loading a directory or playlist file
    treat_root_as_playlist = true,

    --wsl options for limitted windows support
    wsl = false,
    drive_letter = "",
    wsl_password = "",

    --ass options
    ass_header = "{\\q2\\fs35\\c&00ccff&}",
    ass_body = "{\\q2\\fs25\\c&Hffffff&}",
}

opt.read_options(o, 'dvd_browser')

--[[
    lsdvd returns a JSON object with a number of details about the dvd
    some notable values are:
        title = title of the dvd
        longest_track = longest track on the dvd
        device = path to the dvd mount point
        track = array of 'titles'/tracks on the disc
            length = length of each title
            ix = numerical id of the title starting from 1
            chapter = array of chapters in the title
]]--
local dvd = {}
local ov = mp.create_osd_overlay('ass-events')
ov.hidden = true
local state = {
    playing_disc = false,
    selected = 1,

}

local keybinds = {
    {"ESC", "exit", function() close_browser() end, {}},
    {"ENTER", "open", function() open_file('replace') end, {}},
    {"Shift+ENTER", "append_playlist", function() open_file('append') end, {}},
    {'DOWN', 'scroll_down', function() scroll_down() end, {repeatable = true}},
    {'UP', 'scroll_up', function() scroll_up() end, {repeatable = true}},
}

--automatically match to the current dvd device
if (o.dvd_device == "") then
    mp.observe_property('dvd-device', 'string', function(_, device)
        if device == "" then device = "/dev/dvd" end
        o.dvd_device = device

        --we set this to false to force a dvd rescan
        state.playing_disc = false
    end)
end

--simple function to append to the ass string
local function append(str)
    ov.data = ov.data .. str .. "\\N"
end

--sends a call to lsdvd to read the contents of the disc
local function read_disc()
    local args
    if o.wsl then
        mp.command_native({
            name = 'subprocess',
            playback_only = false,
            args = {'wsl', 'echo', o.wsl_password, '|', 'sudo', '-S', 'mount', '-t', 'drvfs', o.drive_letter..":", o.dvd_device}
        })

        --settings wsl arguments
        args = {'wsl', o.lsdvd, o.dvd_device, '-Oy', '-c'}
    else
        args = {o.lsdvd, o.dvd_device, '-Oy', '-c'}
    end

    local cmd = mp.command_native({
        name = 'subprocess',
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = args
    })

    -- msg.verbose(utils.to_string(result))

    local result = cmd.stdout:gsub("'", '"')

    result = result:gsub('lsdvd = ', '')
    dvd = utils.parse_json(result)

    if (not dvd) then
        msg.error(cmd.stderr)
        state.playing_disc = false
        return
    end
    msg.trace(utils.to_string(dvd))

    --creating a fallback for the title
    -- if dvd.title == "unknown" then dvd.title = "dvd://" end
    for i = 2, #dvd.track do
        local l = dvd.track[i].length
        local lstr = tostring(l)

        --adding the microseconds as is
        local index = tostring(l):find([[.[^.]*$]])
        local str
        if index == nil then str = ""
        else str = lstr:sub(index) end
        l = math.floor(l)

        local seconds = l%60
        str = string.format('%02d', seconds) .. str
        l = (l - seconds)/60

        local mins = l%60
        str = string.format('%02d', mins) .. ':' .. str
        l = (l-mins)/60

        local hours = l%24
        str = string.format('%02d', hours) .. ':' .. str

        msg.debug('changing length string for title '..(i-1)..' to '..str)
        dvd.track[i].length = str
    end

    state.playing_disc = true
end

--loads disc information into mpv player and inserts disc titles into the playlist
local function load_disc()
    local path = mp.get_property('stream-open-filename', '')

    if path:find('dvd://') ~= 1 then
        state.playing_disc = false
        return
    end

    --if we have not stopped playing a disc then there's no need to parse the disc again
    if not state.playing_disc then read_disc() end

    --if we still can't detect a disc then return
    if (not state.playing_disc) then return end

    --if we successfully loaded info about the disc it's time to do some other stuff:
    --this code block finds the default title of the disc
    local curr_title

    --if the user specified a title number we use that
    if path ~= "dvd://" then
        --treating whatever comes after "dvd://" as the title number
        curr_title = tonumber(path:sub(7))

    --if dvd:// was sent and this option is set we set the default ourselves
    elseif o.start_from_first_title then
        mp.set_property('stream-open-filename', "dvd://1")
        curr_title = 1

    --otherwise if just dvd:// was sent we need to find the longest title
    else
        curr_title = dvd.longest_track-1
    end

    --if o.create_playlist is false then the function can end here
    if not o.create_playlist then
        mp.set_property('title', dvd.title.." - Title "..curr_title)
        return
    end
    local length = mp.get_property_number('playlist-count', 1)

    --load files in the playlist under the specified conditions
    if (path == "dvd://" and o.treat_root_as_playlist) or length == 1 then
        local pos = mp.get_property_number('playlist-pos', 1)

        --add all of the files to the playlist
        for i = 1, #dvd.track-1 do
            if i == curr_title then goto continue end

            mp.commandv("loadfile", "dvd://"..i, "append", "title="..dvd.title.." - Title "..i)
            length = length + 1

            --we need slightly different behaviour when prepending vs appending a playlist entry
            if (i < curr_title) then
                mp.commandv("playlist-move", length-1, pos)
                pos = pos+1
            elseif (i > curr_title) then
                mp.commandv("playlist-move", length-1, pos+(i-curr_title))
            end

            ::continue::
        end

        --if the path is dvd, then we actually need to fully replace this entry in the playlist,
        --otherwise the whole disc will be added to the playlist again if moving back to this entry
        if (path == "dvd://") then
            mp.commandv("loadfile", "dvd://"..curr_title, "append", "title="..dvd.title.." - Title "..curr_title)
            length = length+1
            mp.commandv('playlist-move', length-1, pos+1)
            mp.commandv('playlist-remove', 'current')
        end
    end
end

--update the DVD browser
function update_ass()
    ov.data = o.ass_header..'📀 dvd://'..dvd.title.."\\N ---------------------------------------------------- \\N"
    for i=2, #dvd.track do
        local v = dvd.track[i]
        append(o.ass_body.."track "..(v.ix-1).." ["..v.length.."]")
    end
end

function open_file(flag)
    mp.commandv('loadfile', 'dvd://'..state.selected, flag, "title="..dvd.title.." - Title "..state.selected)

    if flag == 'replace' then
        close_browser()
    end
end

--opens the browser and declares dynamic keybinds
function open_browser()
    for i = 1, #keybinds do
        local v = keybinds[i]
        mp.add_forced_key_binding(v[1], 'dynamic/'..v[2], v[3], v[4])
    end

    ov.hidden = false
    ov:update()
end

--closes the browser and removed dynamic keybinds
function close_browser()
    for i = 1, #keybinds do
        mp.remove_key_binding('dynamic/'..keybinds[i][2])
    end

    ov.hidden = true
    ov:remove()
end

--if we're playing a disc then read it and modify playlist appropriately
mp.add_hook('on_load', 50, load_disc)

mp.add_key_binding('Shift+MENU', 'dvd-browser', function()
    if not state.playing_disc then return end
    update_ass()

    if ov.hidden then
        open_browser()
    else
        close_browser()
    end
end)
