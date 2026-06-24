local mainMod = "SUPER"
local terminal = "kitty"
local browser = "firefox"
local fileManager = "dolphin"
local menu = "qs ipc call shell toggleLauncher"
local wallpaper = "qs ipc call shell toggleWallpaper"
local screenshot = "qs ipc call shell launchScreenshot"
local overview = "qs ipc call shell toggleOverview"
local scripts = "~/.config/hypr/scripts_hypr/launcher.sh --script"
local screenrec = '/home/luisp/.config/quickshell/optional/screenrec/wl_screenrec_ctl.sh open-selector -- --audio --audio-device "alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Headphones__sink.monitor"'

hl.config({
    binds = {
        movefocus_cycles_fullscreen	= true
    },
})

-- Binds generales

hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(wallpaper))
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("pidof hypremoji || hypremoji"))
hl.bind(mainMod .. " + T", hl.dsp.window.float({action = "toggle"}))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({mode = "maximized"}))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({mode = "fullscreen"}))
hl.bind(mainMod .. "+ SHIFT + S", hl.dsp.exec_cmd(screenshot))
hl.bind(mainMod .. " + backslash", hl.dsp.exec_cmd(scripts))
hl.bind(mainMod .. " + space", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("clipse-gui"))
hl.bind("ALT + Tab", hl.dsp.exec_cmd(overview))
hl.bind("CTRL + SHIFT + E", hl.dsp.exec_cmd(screenrec))

-- Binds move focus
hl.bind(mainMod .. " + right",  hl.dsp.focus({ direction = "right"}))
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Binds move windows
hl.bind(mainMod .. "+ SHIFT + right",  hl.dsp.window.move({ direction = "right"}))
hl.bind(mainMod .. "+ SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. "+ SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. "+ SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- Switch Workspaces
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- touchscreen gestures
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})




