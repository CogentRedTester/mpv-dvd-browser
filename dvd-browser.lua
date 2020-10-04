--[[
    mpv-dvd-browser

    This script uses the `lsdvd` commandline utility to allow users to view and select titles
    for DVDs from directly within mpv. The browser is interractive and allows for both playing
    the selected title, or appending it to the playlist.

    For full documentation see: https://github.com/CogentRedTester/mpv-dvd-browser
]]--

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

    --number of titles to display on the screen at once
    num_entries = 20,

    --by default the player enters an infinite loop of the dvd menu screen after moving past
    --the final chapter of the title. If this is true, then the script will automatically configure
    --mpv to end playback before entering the loop
    skip_menu = true,

    ---------------------
    --playlist options:
    ---------------------

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

    ------------------------------------------
    --wsl options for limitted windows support
    ------------------------------------------
    wsl = false,
    drive_letter = "",
    wsl_password = "",

    --------------
    --ass options
    ---------------
    ass_header = "{\\q2\\fs35\\c&00ccff&}",
    ass_body = "{\\q2\\fs25\\c&Hffffff&}",
    ass_selected = "{\\c&Hfce788&}",
    ass_playing = "{\\c&H33ff66&}",
    ass_footerheader = "{\\c&00ccff&\\fs16}",
    ass_cursor = "{\\c&00ccff&}",
    ass_length = "{\\fs20\\c&aaaaaa&}"
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
            num_chapters = length of chapters array (added by me)
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
    {'Ctrl+r', 'reload', function() read_disc() ; update_ass() end, {}},
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
local function append(str, newline)
    ov.data = ov.data .. str
    if newline then ov.data = ov.data.."\\N" end
end

--sends a call to lsdvd to read the contents of the disc
function read_disc()
    msg.verbose('reading contents of ' .. o.dvd_device)

    local args
    if o.wsl then
        msg.verbose('wsl compatibility mode enabled')
        msg.verbose('mounting '..o.drive_letter..':'..' at '..o.dvd_device)

        mp.command_native({
            name = 'subprocess',
            playback_only = false,
            args = {'wsl', 'echo', o.wsl_password, '|', 'sudo', '-S', 'mount', '-t', 'drvfs', o.drive_letter..":", o.dvd_device}
        })

        --setting wsl arguments
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

    --making the python string JSON compatible
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

    --making modifications to all the entries
    for i = 2, #dvd.track do
        --saving the chapter count
        dvd.track[i].num_chapters = #dvd.track[i].chapter

        --modifying the length
        local l = dvd.track[i].length
        local lstr = tostring(l)

        --adding the microseconds as is
        local index = tostring(l):find([[.[^.]*$]])
        local str
        if index == 1 then str = "00"
        else
            str = tostring(lstr:sub(index+1))
            str = string.format('%02d', str)
        end
        l = math.floor(l)

        local seconds = l%60
        str = string.format('%02d', seconds) .. '.' .. str
        l = (l - seconds)/60

        local mins = l%60
        str = string.format('%02d', mins) .. ':' .. str
        l = (l-mins)/60

        local hours = l%24
        str = string.format('%02d', hours) .. ':' .. str

        msg.debug('changing length string for title '..(i-1)..' to '..str)
        dvd.track[i].length = str

        --the first entry is always the menu, which mpv can't play. So we'll remove it from
        --the track list now to simplify things
        dvd.track[i-1] = dvd.track[i]
    end

    --we need to remove the last entry in the array since it's been moved forward one
    dvd.track[#dvd.track] = nil

    state.playing_disc = true
end

--appends the specified playlist item along with the desired options
local function load_dvd_title(title, flag)
    local i = title.ix-1
    local optionstr = "title="..dvd.title.." - Title "..i
    if o.skip_menu then
        optionstr = optionstr..',end=#'..title.num_chapters
    end
    mp.commandv("loadfile", "dvd://"..i, flag, optionstr)
end

--loads disc information into mpv player and inserts disc titles into the playlist
local function load_disc()
    local path = mp.get_property('stream-open-filename', '')

    if path:find('dvd://') ~= 1 then
        state.playing_disc = false
        return
    end
    msg.verbose('playing dvd')

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
        for i = 1, #dvd.track do
            if i == curr_title then goto continue end

            load_dvd_title(dvd.track[i], "append")
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
            msg.verbose('replacing dvd:// with playlist')

            load_dvd_title(dvd.track[curr_title], "append")
            length = length+1
            mp.commandv('playlist-move', length-1, pos+1)
            mp.commandv('playlist-remove', 'current')
        end
    end
end

--update the DVD browser
function update_ass()
    local list = dvd.track
    local length = #list

    ov.data = o.ass_header..'📀 dvd://'..dvd.title.."\\N ---------------------------------------------------- \\N"

    local start = 1
    local finish = start+o.num_entries-1

    --handling cursor positioning
    local mid = math.ceil(o.num_entries/2)+1
    if state.selected+mid > finish then
        local offset = state.selected - finish + mid

        --if we've overshot the end of the list then undo some of the offset
        if finish + offset > length then
            offset = offset - ((finish+offset) - length)
        end

        start = start + offset
        finish = finish + offset
    end

    --making sure that we don't overstep the boundaries
    if start < 1 then start = 1 end
    local overflow = finish < length
    --this is necessary when the number of items in the dir is less than the max
    if not overflow then finish = length end

    --adding a header to show there are items above in the list
    if start > 1 then append(o.ass_footerheader..(start-1)..' items above\\N\\N') end

    for i=start, finish do
        local v = dvd.track[i]
        append(o.ass_body)

        --the below text contains unicode whitespace characters
        if i == state.selected then append(o.ass_cursor..[[➤  ]]..o.ass_selected)
        else append([[   ]]) end

        append("Title "..(v.ix-1)..o.ass_length.."   ["..v.length.."]")
        append("   "..v.num_chapters.." chapters", true)
    end

    if overflow then ov.data = ov.data..'\\N'..o.ass_footerheader..#list-finish..' items remaining' end
    ov:update()
end

function scroll_up()
    if state.selected <= 1 then return end
    state.selected = state.selected - 1
    update_ass()
end

function scroll_down()
    if state.selected >= #dvd.track then return end
    state.selected = state.selected + 1
    update_ass()
end

function open_file(flag)
    load_dvd_title(dvd.track[state.selected], flag)

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
