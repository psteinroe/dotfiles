return {
	"mfussenegger/nvim-dap",
	dependencies = {
		{ "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
		{ "theHamsta/nvim-dap-virtual-text" },
		{ "nvim-telescope/telescope-dap.nvim" },
	},
	config = function()
		local dap = require("dap")
		local dapui = require("dapui")

		-- Setup UI
		dapui.setup({
			icons = { expanded = "▾", collapsed = "▸", current_frame = "▸" },
			mappings = {
				-- Use a table to apply multiple mappings
				expand = { "<CR>", "<2-LeftMouse>" },
				open = "o",
				remove = "d",
				edit = "e",
				repl = "r",
				toggle = "t",
			},
			layouts = {
				{
					elements = {
						{ id = "scopes", size = 0.25 },
						"breakpoints",
						"stacks",
						"watches",
					},
					size = 40,
					position = "left",
				},
				{
					elements = {
						"repl",
						"console",
					},
					size = 0.25,
					position = "bottom",
				},
			},
		})

		-- Virtual text setup
		require("nvim-dap-virtual-text").setup()

		-- Automatically open/close UI
		dap.listeners.before.attach.dapui_config = function()
			dapui.open()
		end
		dap.listeners.before.launch.dapui_config = function()
			dapui.open()
		end
		dap.listeners.before.event_terminated.dapui_config = function()
			dapui.close()
		end
		dap.listeners.before.event_exited.dapui_config = function()
			dapui.close()
		end

		-- Rust configuration
		dap.adapters.codelldb = {
			type = "server",
			port = "${port}",
			executable = {
				command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
				args = { "--port", "${port}" },
			},
		}

		dap.configurations.rust = {
			{
				name = "Launch file",
				type = "codelldb",
				request = "launch",
				program = function()
					return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
				end,
				cwd = "${workspaceFolder}",
				stopOnEntry = false,
			},
		}

		-- Go configuration
		dap.adapters.delve = {
			type = "server",
			port = "${port}",
			executable = {
				command = "dlv",
				args = { "dap", "-l", "127.0.0.1:${port}" },
			},
		}

		dap.configurations.go = {
			{
				type = "delve",
				name = "Debug",
				request = "launch",
				program = "${file}",
			},
			{
				type = "delve",
				name = "Debug test",
				request = "launch",
				mode = "test",
				program = "${file}",
			},
			{
				type = "delve",
				name = "Debug test (go.mod)",
				request = "launch",
				mode = "test",
				program = "./${relativeFileDirname}",
			},
		}

		-- Keymaps
		vim.keymap.set("n", "<leader>b", function() dap.toggle_breakpoint() end, { desc = "Debug: Toggle Breakpoint" })
		vim.keymap.set("n", "<leader>B", function() dap.set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, { desc = "Debug: Set Conditional Breakpoint" })
		vim.keymap.set("n", "<leader>dc", function() dap.continue() end, { desc = "Debug: Start/Continue" })
		vim.keymap.set("n", "<leader>dj", function() dap.step_over() end, { desc = "Debug: Step Over" })
		vim.keymap.set("n", "<leader>dk", function() dap.step_into() end, { desc = "Debug: Step Into" })
		vim.keymap.set("n", "<leader>do", function() dap.step_out() end, { desc = "Debug: Step Out" })
		vim.keymap.set("n", "<leader>dd", function() dap.disconnect() end, { desc = "Debug: Disconnect" })
		vim.keymap.set("n", "<leader>dt", function() dap.terminate() end, { desc = "Debug: Terminate" })
		vim.keymap.set("n", "<leader>dr", function() dap.repl.toggle() end, { desc = "Debug: Toggle REPL" })
		vim.keymap.set("n", "<leader>dl", function() dap.run_last() end, { desc = "Debug: Run Last" })
		vim.keymap.set("n", "<leader>di", function() dap.step_back() end, { desc = "Debug: Step Back" })
		vim.keymap.set("n", "<leader>drc", function() dap.run_to_cursor() end, { desc = "Debug: Run to Cursor" })
		vim.keymap.set("n", "<leader>du", function() dapui.toggle() end, { desc = "Debug: Toggle UI" })
		vim.keymap.set("n", "<leader>de", function() dapui.eval() end, { desc = "Debug: Evaluate" })
		vim.keymap.set("v", "<leader>de", function() dapui.eval() end, { desc = "Debug: Evaluate" })

		-- Set breakpoint log message
		vim.keymap.set("n", "<leader>dpl", function()
			dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
		end, { desc = "Debug: Set Log Point" })

		-- Clear all breakpoints
		vim.keymap.set("n", "<leader>dpc", function()
			dap.clear_breakpoints()
		end, { desc = "Debug: Clear All Breakpoints" })

		-- List breakpoints
		vim.keymap.set("n", "<leader>dbl", function()
			dap.list_breakpoints()
		end, { desc = "Debug: List Breakpoints" })
	end,
}

