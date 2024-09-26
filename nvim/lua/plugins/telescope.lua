return {
  "nvim-telescope/telescope.nvim",
  lazy = false,
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope-file-browser.nvim",
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release",
    },
  },
  config = function()
    local builtin = require "telescope.builtin"

    vim.keymap.set("n", "<leader>pf", builtin.find_files, {})
    vim.keymap.set("n", "<C-p>", builtin.git_files, {})
    vim.keymap.set("n", "<leader>ps", function()
      builtin.grep_string { search = vim.fn.input "Grep > " }
    end)
    vim.keymap.set("n", "<C-s>", builtin.live_grep, {})
    vim.keymap.set("n", "<C-t>", "<cmd>Telescope resume<cr>", {})

    -- git
    vim.keymap.set("n", "<leader>gb", builtin.git_branches, {})

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
  end,
}
