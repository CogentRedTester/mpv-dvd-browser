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

local dvd = {}
local ov = mp.create_osd_overlay('ass-events')
ov.hidden = true
local state = {
    disc = false
}

--automatically match to the current dvd device
if (o.dvd_device == "") then
    mp.observe_property('dvd-device', 'string', function(_, device)
        o.dvd_device = device
        state.disc = false
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
        state.disc = false
        return
    end
    msg.debug(utils.to_string(dvd))
    state.disc = true
    if dvd.title == "unknown" then dvd.title = "dvd://" end
end

--
local function load_disc()
    local path = mp.get_property('stream-open-filename', '')

    if path:find('dvd://') ~= 1 then
        state.disc = false
        return
    end

    --if we have not stopped playing a disc then there's no need to parse the disc again
    if not state.disc then read_disc() end
    if (not state.disc) then return end

    --if we successfully loaded info about the disc it's time to do some other stuff:

    --this code block finds the default title of the disc
    local curr_title
    if path == "dvd://" and o.start_from_first_title then
        mp.set_property('stream-open-filename', "dvd://1")
        curr_title = 1
    elseif path == "dvd://" then
        local max = 0
        local index = 0
        for i = 1, #dvd.track do
            if (dvd.track[i].length > max) then
                index = i
                max = dvd.track[i].length
            end
        end
        curr_title = index-1
    else
        curr_title = tonumber(path:sub(-1))
    end

    mp.set_property('title', dvd.title.." - Title "..curr_title)
    msg.verbose('loading track '..curr_title)
    local length = mp.get_property_number('playlist-count', 1)

    --load files in the playlist under the specified conditions
    if o.create_playlist and ((path == "dvd://" and o.treat_root_as_playlist) or length == 1) then
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
function update_browser()
    ov.data = o.ass_header..dvd.title.."\\N".."------------------------------------".."\\N"
    for _,value in ipairs(dvd.track) do
        append(o.ass_body.."track "..value.ix.." ["..value.length.."]")
    end
end

--if we're playing a disc then read it
mp.add_hook('on_load', 50, load_disc)

mp.add_key_binding('Shift+MENU', 'dvd-browser', function()
    update_browser()

    if ov.hidden then
        ov.hidden = false
        ov:update()
    else
        ov.hidden = true
        ov:remove()
    end
end)
