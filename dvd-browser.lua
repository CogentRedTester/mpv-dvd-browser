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

    --by default the player enters an infinite loop, usually of the DVD menu screen, after moving
    --past the last second of the file. If this option is enabled, then the script will
    --automatically configure mpv to end playback before entering the loop
    escape_loop = true,

    --changes default mpv behaviour and loads the first title instead of the longest when
    --the title isn't specified
    start_from_first_title = true,

    ---------------------
    --playlist options:
    ---------------------

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

--if the script name includes file_browser, then the script is being loaded
--as an addon, and hence we can skip loading several things
local STANDALONE = not mp.get_script_name():find("file_browser")

local list = {}
if STANDALONE then
    package.path = mp.command_native( {"expand-path", "~~/script-modules/?.lua;" } ) .. package.path
    list = require "scroll-list"

    list.header_style = o.ass_header
    list.list_style = o.ass_body
    list.wrapper_style = o.ass_footerheader
    list.empty_text = "insert DVD"
end

local dvd = {}
local state = {
    playing_disc = false,
    selected = 1,
    flag_update = false
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

local function get_header_str()
    local title
    if dvd == nil then title = ""
    else title = dvd.title end
    return '📀 dvd://'..title
end

local function get_line_str(v)
    return "Title "..(v.ix-1)..o.ass_length.."   ["..v.length.."]   "..v.num_chapters.." chapters"
end

function list:format_header()
    self.ass.data = o.ass_header..get_header_str().."\\N ---------------------------------------------------- \\N"
end

--simple function to append to the ass string
function list:format_line(i, v)
        self:append(o.ass_body)

        --the below text contains unicode whitespace characters
        if i == list.selected then self:append(o.ass_cursor..[[➤\h]]..o.ass_selected)
        else self:append([[\h\h\h\h]]) end

        --prints the currently-playing icon and style
        if mp.get_property('filename', "0") == tostring(i-1) then
            self:append(o.ass_playing)
        end

        self:append(get_line_str(v))
        self:newline()
end

--sends a call to lsdvd to read the contents of the disc
local function read_disc()
    msg.verbose('reading contents of ' .. o.dvd_device)

    local args
    if o.wsl then
        msg.verbose('wsl compatibility mode enabled')

        --if wsl password is not set then we'll assume the user has mounted manually
        if o.wsl_password ~= "" then
            local dvd_device = mp.get_property('dvd-device', ''):gsub([[\]], [[/]])
            msg.verbose('mounting '..dvd_device..' at '..o.dvd_device)

            mp.command_native({
                name = 'subprocess',
                playback_only = false,
                args = {'wsl', 'echo', o.wsl_password, '|', 'sudo', '-S', 'mount', '-t', 'drvfs', dvd_device, o.dvd_device}
            })
        end

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
    for i = 1, #dvd.track do
        local v = dvd.track[i]

        --saving the chapter count
        v.num_chapters = #v.chapter

        --modifying the length
        local l = v.length
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
        v.length = str
    end

    state.playing_disc = true
    list.list = dvd.track
end

--this function updates dvd information and updates the browser
local function update()
    read_disc()
    list:update()
end

--appends the specified playlist item along with the desired options
local function load_dvd_title(title, flag)
    local i = title.ix-1

    if o.escape_loop then 
        mp.commandv("loadfile", "dvd://"..i, flag, "end=#"..title.num_chapters)
    else
        mp.commandv("loadfile", "dvd://"..i, flag)
    end
end

--handles actions when dvd:// paths are played directly
--updates dvd information and inserts disc titles into the playlist
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
        mp.set_property('stream-open-filename', "dvd://0")
        curr_title = 0

    --otherwise if just dvd:// was sent we need to find the longest title
    else
        curr_title = dvd.longest_track
    end

    mp.set_property('file-local-options/title', dvd.title.." - Title "..curr_title)

    --if o.create_playlist is false then the function can end here
    if not o.create_playlist then return end

    --offsetting curr_title by one to account for lua arrays being 1-based
    curr_title = curr_title+1
    local length = mp.get_property_number('playlist-count', 1)

    --load files in the playlist under the specified conditions
    if (path == "dvd://" and o.treat_root_as_playlist) or length == 1 then
        local pos = mp.get_property_number('playlist-pos', 1)

        --add all of the files to the playlist
        for i = 1, #dvd.track do
            if i ~= curr_title then
                load_dvd_title(dvd.track[i], "append")
                length = length + 1

                --we need slightly different behaviour when prepending vs appending a playlist entry
                if (i < curr_title) then
                    mp.commandv("playlist-move", length-1, pos)
                    pos = pos+1
                elseif (i > curr_title) then
                    mp.commandv("playlist-move", length-1, pos+(i-curr_title))
                end
            end
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

--opens the currently selected file
local function open_file(flag)
    load_dvd_title(dvd.track[list.selected], flag)

    if flag == 'replace' then
        list:close()
    end
end

--opens the browser and declares dynamic keybinds
function list:open()
    self.hidden = false
    if not state.playing_disc then
        update()
    else
        self:open_list()
    end
    self:add_keybinds()
end

list.keybinds = {
    {"ESC", "exit", function() list:close() end, {}},
    {"ENTER", "open", function() open_file('replace') end, {}},
    {"Shift+ENTER", "append_playlist", function() open_file('append') end, {}},
    {'DOWN', 'scroll_down', function() list:scroll_down() end, {repeatable = true}},
    {'UP', 'scroll_up', function() list:scroll_up() end, {repeatable = true}},
    {'Ctrl+r', 'reload', function() read_disc() ; list:update() end, {}}
}

--modifies track length to escape infinite loop
if o.escape_loop then
    mp.add_hook('on_preloaded', 50, function()
        if mp.get_property("path", ""):find("dvd://") ~= 1 then return end
        if mp.get_property('end', 'none') ~= 'none' then return end

        local filename = mp.get_property("filename", "1")
        local num_chapters = dvd.track[tonumber(filename)+1].num_chapters
        msg.verbose('modifying end of the title to escape infinite loop')
        mp.set_property('file-local-options/end', "#"..num_chapters)
    end)
end

--if we're playing a disc then read it and modify playlist appropriately
mp.add_hook('on_load', 50, load_disc)

--if these events are disabled then the list gui functions are never called
if STANDALONE then
    mp.observe_property('path', 'string', function(_,path)
        if state.playing_disc then list:update() end
    end)

    mp.register_script_message('browse-dvd', function() list:open() end)

    mp.add_key_binding('MENU', 'dvd-browser', function() list:toggle() end)
end

--module functions when loading as file_browser addon
local dvd_module = {
    priority = 50
}

function dvd_module:can_parse(directory)
    return directory:sub(1,6) == "dvd://" or directory == self.get_dvd_device()
end

function dvd_module:parse()
    read_disc()
    local list = {}

    if dvd then
        for i = 1, #dvd.track do
            list[i] = {
                ass = get_line_str(dvd.track[i]),
                name = tostring(dvd.track[i].ix-1),
                path = "dvd://"..(dvd.track[i].ix-1),
                type = "file"
            }
        end
    end

    return list, {
        empty_text = "insert DVD",
        directory_label = get_header_str(),
        filtered = true,
        sorted = true
    }
end

return dvd_module
