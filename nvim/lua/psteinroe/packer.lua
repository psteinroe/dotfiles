-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer configured as `opt`
vim.cmd.packadd "packer.nvim"

return require("packer").startup(function(use)
  -- Packer can manage itself
  use "wbthomason/packer.nvim"

  use {
    "nvim-telescope/telescope.nvim",
    requires = { { "nvim-lua/plenary.nvim" } },
  }
  use { "nvim-telescope/telescope-file-browser.nvim" }

  use "sainnhe/gruvbox-material"

  use "vim-airline/vim-airline"

  use "lukas-reineke/indent-blankline.nvim"

  -- use "mrcjkb/rustaceanvim"

  use {
    "nvim-treesitter/nvim-treesitter",
    run = function()
        local ts_update = require('nvim-treesitter.install').update({ with_sync = true })
        ts_update()
    end
  }
  use "nvim-treesitter/playground"
  use "nvim-treesitter/nvim-treesitter-context"
  use "theprimeagen/harpoon"
  use "mbbill/undotree"
  use "tpope/vim-fugitive"

  use {
    "VonHeikemen/lsp-zero.nvim",
    branch = 'v1.x',
    requires = {
      -- LSP Support
      { "neovim/nvim-lspconfig" },
      { "williamboman/mason.nvim" },
      { "williamboman/mason-lspconfig.nvim" },

      -- Autocompletion
      { "hrsh7th/nvim-cmp" },
      { "hrsh7th/cmp-buffer" },
      { "hrsh7th/cmp-path" },
      { "saadparwaiz1/cmp_luasnip" },
      { "hrsh7th/cmp-nvim-lsp" },
      { "hrsh7th/cmp-nvim-lua" },
      { "js-everts/cmp-tailwind-colors" },

      -- Snippets
      { "L3MON4D3/LuaSnip" },
      { "rafamadriz/friendly-snippets" },
    },
  }


  use {
    "jose-elias-alvarez/null-ls.nvim",
    requires = { "nvim-lua/plenary.nvim" },
  }
  use "jayp0521/mason-null-ls.nvim"
  use "folke/zen-mode.nvim"

  use {
    "folke/trouble.nvim",
    requires = "kyazdani42/nvim-web-devicons",
  }

  use "chaoren/vim-wordmotion"

  use {
    "numToStr/Comment.nvim",
    config = function()
      require("Comment").setup()
    end,
  }

  use {
    "kylechui/nvim-surround",
    tag = "*", -- Use for stability; omit to use `main` branch for the latest features
    config = function()
      require("nvim-surround").setup {
        -- Configuration here, or leave empty to use defaults
      }
    end,
  }

  -- copilot
  use "github/copilot.vim"

  -- use("sainnhe/gruvbox-material")
  -- markdown
  use "godlygeek/tabular"
  use "elzr/vim-json"
  use "plasticboy/vim-markdown"

  use {
    "andrewferrier/wrapping.nvim",
    config = function()
      require("wrapping").setup {
        -- Configuration here, or leave empty to use defaults
      }
    end,
  }

  use "wakatime/vim-wakatime"

  use {
    "ggandor/leap.nvim",
    requires = "tpope/vim-repeat"
  }

  use "tpope/vim-dotenv"

  use({
      "jackMort/ChatGPT.nvim",
      config = function()
          require("chatgpt").setup({
              openai_params = {
                model = "gpt-4",
                max_tokens = 8192,
              },
              openai_edit_params = {
                model = "gpt-4-1106-preview",
                max_tokens = 128000,
              },
          })
      end,
      requires = {
          "MunifTanjim/nui.nvim",
          "nvim-lua/plenary.nvim",
          "nvim-telescope/telescope.nvim"
      }
  })
end)
