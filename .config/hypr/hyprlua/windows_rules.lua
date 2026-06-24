hl.window_rule({
  name = "spawn kitty as float",
  match = {
    class = "kitty"
  },
  float = true,
  size = "1024 600",
  center = true
})

hl.window_rule({
  name = "Spotify",
  match = {
    class = "Spotify"
  },
  opacity = "1"
})

hl.window_rule({
  name = "clipse",
  match = {
    class = "clipse-gui",
  },
  float = true,
  size = "600 800",
  center = true
})

hl.window_rule({
  name = "PiP",
  match = {
    title = "Picture-in-Picture"
  },
  float = true,
  size = "450 250",
  pin = true,
  move = "1450 815"
})

hl.window_rule({
  name = "satty",
  match = {
    title = "satty"
  },
  float = true,
  size = "800 600",
  center = true
})

hl.window_rule({
  name = "EverCal",
  match = {
    title = "EverCal"
  },
  float = true,
  size = "800 600",
  center = true
})

hl.window_rule({
  name = "onlyoffice",
  match = {
    class = "DesktopEditors"
  },
  center = true
})

hl.window_rule({
  name = "HyprEmoji",
  match = {
    title = "HyprEmoji"
  },
  border_size = 1,
  rounding = 20,
  move = "cursor_x cursor_y",
  float = true,
  border_color = "rgba(ffffffff)",
  no_shadow = true
})


hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})


local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

