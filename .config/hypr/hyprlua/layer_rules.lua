hl.layer_rule({ match = { namespace = "power-menu" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "selection" }, blur = false, ignore_alpha = 1, animation="fade" })
hl.layer_rule({ match = { namespace = "rofi" }, blur = false, ignore_alpha = 0.1, animation = "popin 80%" })
hl.layer_rule({ match = { class = "dolphin" }, blur = true })
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, blur = false })
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, blur = false })
hl.layer_rule({ match = { namespace = "quickshell" }, blur = false }) 
hl.layer_rule({ match = { namespace = "quickshell-dock" }, blur = false }) 

hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })

hl.window_rule({
     name  = "no-gaps-wtv1",
     match = { float = false, workspace = "w[tv1]" },
     border_size = 1,
     rounding    = 5,
})
 
 hl.window_rule({
     name  = "no-gaps-f1",
     match = { float = false, workspace = "f[1]" },
     border_size = 0,
     rounding    = 0,
})

hl.workspace_rule({workspace = "f[1]", gaps_out = 10, gaps_in = 5})
hl.workspace_rule({workspace = "w[tv1]", gaps_out = 10, gaps_in = 5})









