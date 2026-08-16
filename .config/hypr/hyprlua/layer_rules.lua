hl.layer_rule({ match = { namespace = "power-menu" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "freeze_screen" }, blur = false, ignore_alpha = 1, animation="fade" })
hl.layer_rule({ match = { namespace = "selection" }, blur = false, ignore_alpha = 1, animation="fade" })
hl.layer_rule({ match = { namespace = "minerva_orb" }, blur = true, animation="fade"})
hl.layer_rule({ match = { namespace = "rofi" }, blur = false, ignore_alpha = 0.1, animation = "popin 80%" })
hl.layer_rule({ match = { class = "dolphin" }, blur = true })
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, blur = false })
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, blur = false })
hl.layer_rule({ match = { namespace = "quickshell" }, blur = false }) 
hl.layer_rule({ match = { namespace = "quickshell-dock" }, blur = false }) 




