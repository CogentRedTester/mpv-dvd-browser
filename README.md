# mpv-dvd-browser

![browser image](screenshots/browser.png)

This script uses the `lsdvd` commandline utility to allow users to view and select titles for DVDs from directly within mpv.
The browser is interractive and allows for both playing the selected title, or appending it to the playlist.

This script requires [mpv-scroll-list](https://github.com/CogentRedTester/mpv-scroll-list) to work, simply place `scroll-list.lua` into the `~~/scripts` folder.

## Browser
The browser provides useful information to help choose which title to play.
Currently it just shows track length and the number of chapters, but this may be expanded in the future to show track information as well.

While in the browser you can move the cursor to directly select which title to play or append to the playlist. Using the default settings this acts similar to an interactive playlist, see [Playlists](#playlists).

## Keybinds
The following keybind is set by default

    MENU            toggles the browser

The following keybinds are only set while the browser is open:

    ESC             closes the browser
    ENTER           plays the currently selected title
    Shift+ENTER     appends the current title to the playlist
    DOWN            move cursor down the list
    UP              move cursor up the list
    Ctrl+r          rescan dvd and refresh the browser

## File Browser
While this script works perfectly well on its own, I have also designed it to interface with my script [mpv-file-browser](https://github.com/CogentRedTester/mpv-file-browser).
If you use both scripts and enable the option `dvd_browser` inside file_browser, then this script will act as an addon to file browser and send file browser the contents of the dvd.
File browser will automatically detect when playing a dvd, or when entering the dvd directory, and will query dvd browser for the titles.
All functionality from the dvd-browser page is supported in file browser, plus many more features.

Make sure that you are using just the file-browser keybind to open the browser instead of dvd-browser's keybind. Both scripts have the same binding by default, so you may need to overwrite the keybind for this script by putting `MENU script-binding browse-files` in input.conf.

## Infinite Loop
Normally when mpv is playing a DVD title it enters an infinite loop after playback moves beyond the last second of the title.
Since this is rarely desired bahaviour dvd-browser will automatically configure mpv to ignore this section of the file, which allows proper playlist support for dvd titles.

This can be disabled in the [configuration file](dvd_browser.conf).

## Playlists
By default the script will populate the current playlist with the other titles on the DVD to make automatically moving between titles easier.

Previous titles in the disc will be prepended before the current file, and later tracks will be appended after.
When the title is specified in the path, i.e. `dvd://2`, then the playlist will only be populated when it is the sole entry in the playlist.
However, if `dvd://` is passed, then that entry in the playlist will always be replaced with the whole DVD, similar to when a playlist file is loaded in the playlist.
To make this a little smoother the script changes the default mpv behaviour and always loads the first track on the disc, as opposed to the longest.

All of these modifications can be disabled in the [configuration file](dvd_browser.conf).

## Windows Support
Since `lsdvd` is only available for Linux this script cannot support windows directly. However, since I myself am forced to use windows, I have added special compatibility for using `lsdvd` on [wsl](https://docs.microsoft.com/en-us/windows/wsl/about). This requires that the windows DVD drive be mounted inside the linux filesystem.

The following options are required to get wsl working:

    wsl=yes                 enables wsl compatibility mode
    dvd_device=/mnt/dvd     the dvd mount point on the linux filesystem

Additionally if you set the option `wsl_password` to your user password then the script will automatically mount the windows DVD directory
to the directory specified by the `dvd_device` script-opt.

For reference the exact command that will be sent to mount the DVD is:
    
    wsl echo "[wsl_password]" | sudo -S mount -t drvfs {dvd-device} [dvd_device]

where `dvd-device` is the contents of mpv's --dvd-device option

## Configuration
The full list of options and their default values are available in [dvd_browser.conf](dvd_browser.conf)
