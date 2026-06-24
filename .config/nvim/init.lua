-- =========================
-- 🧠 Opciones básicas
-- =========================
vim.cmd [[
  hi Normal guibg=NONE ctermbg=NONE
  hi NormalNC guibg=NONE ctermbg=NONE
  hi EndOfBuffer guibg=NONE ctermbg=NONE
]]
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"
vim.g.mapleader = " "
vim.g.terminal_emulator = "kitty"


-- =========================
-- 🚀 Lazy.nvim setup
-- =========================
local lazypath = vim.fn.stdpath("config") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- Explorador de archivos
  { "nvim-tree/nvim-tree.lua", config = function() require("nvim-tree").setup() end },
  { "nvim-tree/nvim-web-devicons" },

  -- Barra de estado
  { "nvim-lualine/lualine.nvim", config = function() require("lualine").setup() end },

  -- Tema
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
  },

  -- Syntax highlighting mejorado
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },

  -- Autocompletado
  { "hrsh7th/nvim-cmp" },
  { "hrsh7th/cmp-nvim-lsp" },
  { "L3MON4D3/LuaSnip" },
  { "huy-hng/anyline.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = true,
    event = "VeryLazy",
    config = {  
        -- visual stuff
        indent_char = '▏', -- character to use for the line
        highlight = 'NonText', -- color of non active indentation lines
        context_highlight = 'ModeMsg', -- color of the context under the cursor
        -- animation stuff / fine tuning
        animation = 'from_cursor', -- 'from_cursor' | 'to_cursor' | 'top_down' | 'bottom_up' | 'none'
        debounce_time = 30, -- how responsive to make to make the cursor movements (in ms, very low debounce time is kinda janky at the moment)
        fps = 30, -- changes how many steps are used to transition from one color to another
        fade_duration = 200, -- color fade speed (only used when lines_per_second is 0)
        length_acceleration = 0.02, -- increase animation speed depending on how long the context is

        lines_per_second = 50, -- how many lines/seconds to show
        trail_length = 20, -- how long the trail / fade transition should be

        -- other stuff
        max_lines = 1024, -- if the buffer exceeds this number of lines, anyline will be disabled
        priority = 19, -- extmark priority
        priority_context = 20,
        ft_ignore = {
            'NvimTree',
            'TelescopePrompt',
            'alpha',
        },
     }
  },
  -- LSP
  { "neovim/nvim-lspconfig" },
  { "sphamba/smear-cursor.nvim",
    opts = {
        cursor_color = "#FFFFFF",
        smear_between_buffers = true,
        smear_between_neighbor_lines = true,
        smear_insert_mode = true,
        legacy_computing_symbols_support = true

    }
  },
  { "karb94/neoscroll.nvim",
    config = function()
      require("neoscroll").setup()
    end
  },
  -- Gestor de LSPs
  {
    "williamboman/mason.nvim",
    build = ":MasonUpdate",
    config = function()
      require("mason").setup()
    end
  },
  { "williamboman/mason-lspconfig.nvim" },

  -- Terminal flotante
  { "akinsho/toggleterm.nvim" },
})

-- =========================
-- 🎨 Tema y apariencia
-- =========================
require("catppuccin").setup({
  flavour = "mocha",
  transparent_background = true,
})
vim.cmd.colorscheme "catppuccin"

-- =========================
-- 🌳 Treesitter
-- =========================
require("nvim-treesitter.configs").setup({
  highlight = { enable = true },
})

require("smear_cursor").setup()

-- =========================
-- 🗂️ Mapeos
-- =========================
vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", { noremap = true, silent = true })

-- =========================
-- ⚙️ Autocompletado
-- =========================
local cmp = require("cmp")
cmp.setup({
  mapping = {
    ['<Tab>'] = cmp.mapping.select_next_item(),
    ['<S-Tab>'] = cmp.mapping.select_prev_item(),
    ['<CR>'] = cmp.mapping.confirm({ select = true }),
  },
  sources = {
    { name = "nvim_lsp" },
  },
})

require("toggleterm").setup({
    open_mapping = [[<c-\>]],
    higlights = {
        Normal = {
            guibg = "#1e1e2e",
        },
        NormalFloat = {
            link = 'Normal'
        },
        FloatBorder = {
            guibg = "#1e1e2e",
	    },
    },
    direction = 'float',
    float_opts = {
        border = 'curved',
        winblend = 0, -- 0 es totalmente opaco
    },
})

-- =========================
-- 🧩 Configuración LSP moderna con Mason (Neovim 0.10+)
-- =========================

-- Obtenemos las capabilities necesarias para la integración con nvim-cmp
local capabilities = require("cmp_nvim_lsp").default_capabilities()

-- Usamos mason-lspconfig.nvim para gestionar la instalación e iniciar los LSPs
require("mason-lspconfig").setup({
    -- 1. Asegura que estos LSPs estén instalados por Mason:
    ensure_installed = { "pyright", "clangd" },

    -- 2. Define la configuración para cada servidor a través de 'handlers':
    handlers = {
        -- Manejador universal: aplica esta configuración a CUALQUIER LSP listado.
        ["*"] = function(server_name)
            -- Llama a lspconfig.setup() para el servidor actual (pyright, clangd, etc.)
            require("lspconfig")[server_name].setup({
                capabilities = capabilities,
                -- Aquí podrías añadir un 'on_attach' si lo necesitaras
            })
        end,
    },
})
