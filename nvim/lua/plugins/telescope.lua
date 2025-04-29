return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-file-browser.nvim",
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
    },
  },
  keys = {
    {
      "<leader>pf",
      function()
        require("telescope.builtin").find_files {
          hidden = true,
          find_command = {
            "rg",
            "--files",
            "--hidden",
            "--glob=!.git/**",
            "--glob=!node_modules/**",
            "--glob=!tmp/**",
          },
        }
      end,
      { noremap = true, silent = true },
    },
    {
      "<C-p>",
      function()
        require("telescope.builtin").git_files()
      end,
      { noremap = true, silent = true },
    },
    {
      "<leader>ps",
      function()
        require("telescope.builtin").grep_string { search = vim.fn.input "Grep > " }
      end,
      { noremap = true, silent = true },
    },
    {
      "<C-s>",
      function()
        require("telescope.builtin").live_grep()
      end,
      { noremap = true, silent = true },
    },
    {
      "<leader>fm",
      function()
        require("telescope.builtin").live_grep {
          search_dirs = {
            "supabase/migrations",
          },
          additional_args = {
            "--sortr=path",
          },
        }
      end,
      { noremap = true, silent = true },
    },
    -- used by toggleterm now
    -- try to use quickfix lists
    -- {
    --   "<C-t>",
    --   "<cmd>Telescope resume<cr>",
    --   { noremap = true, silent = true },
    -- },
    {
      "<leader>gb",
      function()
        require("telescope.builtin").git_branches()
      end,
      { noremap = true, silent = true },
    },
  },
  cmd = { "Telescope" },
  config = function()
    -- stolen from https://github.com/nvim-telescope/telescope.nvim/issues/2201
    -- select directory
    local ts_select_dir_for_grep = function(prompt_bufnr)
      local action_state = require "telescope.actions.state"
      local fb = require("telescope").extensions.file_browser
      local live_grep = require("telescope.builtin").live_grep
      local current_line = action_state.get_current_line()

      fb.file_browser {
        files = false,
        depth = false,
        attach_mappings = function(prompt_bufnr)
          require("telescope.actions").select_default:replace(function()
            local entry_path = action_state.get_selected_entry().Path
            local dir = entry_path:is_dir() and entry_path or entry_path:parent()
            local relative = dir:make_relative(vim.fn.getcwd())
            local absolute = dir:absolute()

            live_grep {
              results_title = relative .. "/",
              cwd = absolute,
              default_text = current_line,
            }
          end)

          return true
        end,
      }
    end

    require("telescope").load_extension "file_browser"

    require("telescope").setup {
      pickers = {
        live_grep = {
          mappings = {
            i = {
              ["<C-f>"] = ts_select_dir_for_grep,
            },
            n = {
              ["<C-f>"] = ts_select_dir_for_grep,
            },
          },
        },
      },
    }

    require("telescope").load_extension "fzf"
  end,
}
