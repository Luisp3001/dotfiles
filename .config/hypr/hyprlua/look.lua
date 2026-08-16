local wal = require("colors")

local function check_power()
    local f = io.open("/sys/class/power_supply/AC/online", "r")
    if f then
        local status = f:read("*all"):gsub("%s+", "")
        f:close()
        return status == "1"
    end
    return true
end

local is_on_ac = check_power()

if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    hg.config({
        enabled = true,
        default_theme = "light",
        default_preset = "apple",
        layers = { enabled = 0 },
    })

    -- Presets
    hg.preset("clear", {
        glass_opacity = 0.6,
        blur_strength = 1.5,
        dark = { brightness = 0.9 },
    })

    hg.preset("contrasted", {
        inherits = "high_contrast",
        contrast = 1.2,
        adaptive_dim = 1.5,
        dark = { tint_color = 0x02142aa9 },
    })

    hg.preset("apple", {
        blur_strength = 0,
        blur_iterations = 0,
        refraction_strength = 0.6,
        chromatic_aberration = 0.7,
        fresnel_strength = 0.8,
        specular_strength = 0.8,
        edge_thickness = 0.08,
        lens_distortion = 0.9,
        dark = { brightness = 0.82, contrast = 0.90, saturation = 0.80, vibrancy = 0.15, adaptive_dim = 0.4 },
        light = { brightness = 1, contrast = 1.5, saturation = 0.80, vibrancy = 0.12 },
    })
end

hl.config({
    general = {
        gaps_in = 10,
        gaps_out = 10,
        border_size = 3,

        col = {
            active_border = { colors = { wal.colors.color1, wal.colors.color2 }, angle = 90 },
            inactive_border = wal.colors.bg
        },

        resize_on_border = true,
        allow_tearing = true,
        layout = "dwindle",
    },

    decoration = {
        active_opacity = 1,
        -- Si está en AC (corriente), usa los valores originales, si no (batería), usa valores reducidos.
        rounding = is_on_ac and 12 or 5,
        rounding_power = is_on_ac and 3 or 2,

        blur = {
            size = is_on_ac and 10 or 3,
            passes = is_on_ac and 2 or 1,
            enabled = true,
            new_optimizations = true,
            ignore_opacity = false,
        },

        shadow = {
            enabled = is_on_ac,
            range = 30,
            render_power = 2,
            offset = { 3, 3 },
            color = wal.bg,
        },

    },

    animations = {
        enabled = is_on_ac
    },

    dwindle = {
        preserve_split = true
    },

    master = {
        new_status = "master",
    },

   scrolling = {
        fullscreen_on_one_column = true,
    },
})

hl.curve("iosEaseInOut",   { type = "bezier", points = { {0.25, 0.1},    {0.25, 1}    } })
hl.curve("iosSlide", { type = "bezier", points = { {0.33, 1}, {0.68, 1}    } })

hl.animation({ leaf = "windows", enabled = true,  speed = 6, bezier = "iosEaseInOut", style = "popin 50%" })
hl.animation({ leaf = "workspaces", enabled = true,  speed = 7, bezier = "iosSlide", style = "slide" })
hl.animation({ leaf = "fade", enabled = true,  speed = 8, bezier = "iosEaseInOut" })
hl.animation({ leaf = "border", enabled = true,  speed = 10, bezier = "iosEaseInOut" })
hl.animation({ leaf = "borderangle", enabled = true,  speed = 100, bezier = "iosEaseInOut", style = "loop" })
hl.animation({ leaf = "layersIn", enabled = true,  speed = 6, bezier = "default", style = "slide right" })
hl.animation({ leaf = "layersOut", enabled = true,  speed = 6, bezier = "default", style = "slide right" })


