local overrides = require "custom.plugins.overrides"

return {

    -- ["goolord/alpha-nvim"] = { disable = false } -- enables dashboard

    -- Override plugin definition options
    ["neovim/nvim-lspconfig"] = {
        config = function()
            require "plugins.configs.lspconfig"
            require "custom.plugins.lspconfig"
        end
    },

    ["hrsh7th/nvim-cmp"] = {
        override_options = {
            sources = {
                { name = "luasnip" },
                { name = "nvim_lsp" },
                { name = "buffer" },
                { name = "nvim_lua" },
                { name = "path" },
                { name = "vim-dadbod-completion" }
            }

        }

    },

    -- overrde plugin configs
    ["nvim-treesitter/nvim-treesitter"] = {
        override_options = overrides.treesitter
    },

    ["williamboman/mason.nvim"] = {
        override_options = overrides.mason
    },

    ["kyazdani42/nvim-tree.lua"] = {
        override_options = overrides.nvimtree
    },

    -- Install a plugin
    ["max397574/better-escape.nvim"] = {
        event = "InsertEnter",
        config = function()
            require("better_escape").setup()
        end
    },

    ["yasuhiroki/github-actions-yaml.vim"] = {},

    ["junegunn/fzf"] = {
        run = ":call fzf#install()"
    },

    ["junegunn/fzf.vim"] = {},

    -- code formatting, linting etc
    ["jose-elias-alvarez/null-ls.nvim"] = {
        after = "nvim-lspconfig",
        config = function()
            require "custom.plugins.null-ls"
        end
    },

    -- Load .env files
    ["tpope/vim-dotenv"] = {},

    ["kdheepak/lazygit.nvim"] = {},

    -- DB Support
    ["tpope/vim-dadbod"] = {},
    ["kristijanhusak/vim-dadbod-ui"] = {},
    ["kristijanhusak/vim-dadbod-completion"] = {}
}
