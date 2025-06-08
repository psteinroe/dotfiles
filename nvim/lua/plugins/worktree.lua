return {
  "polarmutex/git-worktree.nvim",
  version = "^2",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    local git_worktree = require "git-worktree"

    -- Configure hooks
    local Hooks = require "git-worktree.hooks"

    -- Update current buffer when switching worktrees
    Hooks.register(Hooks.type.SWITCH, Hooks.builtins.update_current_buffer_on_switch)

    -- Optional: Add notification when switching
    Hooks.register(Hooks.type.SWITCH, function(path, prev_path)
      vim.notify("Switched from " .. prev_path .. " to " .. path)
    end)

    -- Run pnpm install when switching to a worktree with pnpm-lock.yaml
    Hooks.register(Hooks.type.SWITCH, function(path, prev_path)
      local pnpm_lock = path .. "/pnpm-lock.yaml"
      if vim.fn.filereadable(pnpm_lock) == 1 then
        vim.notify("Running pnpm install in " .. path)
        vim.fn.system("cd " .. path .. " && pnpm install")
      end
    end)

    -- Custom telescope picker for worktrees
    local function telescope_git_worktree()
      local pickers = require "telescope.pickers"
      local finders = require "telescope.finders"
      local conf = require("telescope.config").values
      local actions = require "telescope.actions"
      local action_state = require "telescope.actions.state"

      -- Get list of worktrees
      local worktrees = vim.fn.systemlist "git worktree list"
      local results = {}

      for _, worktree in ipairs(worktrees) do
        local parts = vim.split(worktree, "%s+")
        if #parts >= 3 then
          table.insert(results, {
            path = parts[1],
            branch = parts[3]:gsub("[%[%]]", ""),
            line = worktree,
          })
        end
      end

      pickers
        .new({}, {
          prompt_title = "Git Worktrees",
          finder = finders.new_table {
            results = results,
            entry_maker = function(entry)
              return {
                value = entry,
                display = entry.branch .. " → " .. entry.path,
                ordinal = entry.branch .. " " .. entry.path,
              }
            end,
          },
          sorter = conf.generic_sorter {},
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if selection then
                git_worktree.switch_worktree(selection.value.path)
              end
            end)

            map("i", "<C-d>", function()
              local selection = action_state.get_selected_entry()
              if selection then
                local confirm = vim.fn.input("Delete worktree " .. selection.value.branch .. "? (y/N): ")
                if confirm:lower() == "y" then
                  actions.close(prompt_bufnr)
                  git_worktree.delete_worktree(selection.value.path)
                end
              end
            end)

            return true
          end,
        })
        :find()
    end

    -- Create worktree with telescope
    local function telescope_create_worktree()
      vim.ui.input({ prompt = "Branch name: " }, function(branch)
        if not branch or branch == "" then
          return
        end

        vim.ui.input({ prompt = "Base branch (default: main): " }, function(base)
          base = base and base ~= "" and base or "main"
          git_worktree.create_worktree(branch, base)
        end)
      end)
    end

    -- Keymaps
    vim.keymap.set("n", "<leader>ww", telescope_git_worktree, { desc = "Switch worktree" })
    vim.keymap.set("n", "<leader>wc", telescope_create_worktree, { desc = "Create worktree" })
    vim.keymap.set("n", "<leader>wd", function()
      local worktree = vim.fn.input "Worktree to delete: "
      if worktree ~= "" then
        git_worktree.delete_worktree(worktree)
      end
    end, { desc = "Delete worktree" })
  end,
}
