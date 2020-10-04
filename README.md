# mpv-dvd-browser

![browser image](screenshots/browser.png)

This script uses the `lsdvd` commandline utility to allow users to view and select titles for DVDs from directly within mpv.
The browser is interractive and allows for both playing the selected title, or appending it to the playlist.

## Browser
The browser provides useful information to help choose which title to play.
Currently it just shows track length and the number of chapters, but this may be expanded in the future to show track information as well.

While in the browser you can move the cursor to directly select which title to play or append to the playlist. Using the default settings this acts similar to an interactive playlist, see [Playlists](#playlists).

## Keybinds
The following keybind is set by default

    Shift+MENU            toggles the browser

The following keybinds are only set while the browser is open:

    ESC             closes the browser
    ENTER           plays the currently selected title
    Shift+ENTER     appends the current title to the playlist
    DOWN            move cursor down the list
    UP              move cursor up the list
    Ctrl+r          rescan dvd and refresh the browser

## Menu Loop
Normally when mpv is playing a DVD title it enters an infinite loop of the menu screen after playback moves beyond the last chapter of track.
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
Since `lsdvd` is only available for Linux this script cannot support windows directly. However, since I myself am forced to use windows, I have added special compatibility for using `lsdvd` on [wsl](https://docs.microsoft.com/en-us/windows/wsl/about).
This requires that the script be able to automatically mount the DVD drive within the linux filesystem.

The following options are required to get wsl working:

    wsl=yes                 enables wsl compatibility mode
    wsl_password=password   wsl user password for running `sudo mount`
    dvd_device=/mnt/dvd     the desired mount point on the linux filesystem

For reference the exact command that will be sent to mount the DVD drive is:
    
    wsl echo "[password]" | sudo -S mount drvfs {dvd-device} [dvd_device]

where `dvd-device` is the contents of the --dvd-device option

## Configuration
The full list of options and their default values are available in [dvd_browser.conf](dvd_browser.conf)
