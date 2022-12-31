vim.g.mapleader = " "
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

-- move highlighted
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- join lines while preversing cursor position
vim.keymap.set("n", "J", "mzJ`z")
-- keep cursor in middle while jumping
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
-- keep cursor in the middle when searching
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- keep pasted word in the register
vim.keymap.set("x", "<leader>p", [["_dP]])

-- leader y to yank into system clipboard
vim.keymap.set({"n", "v"}, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])

-- deleting to void register
vim.keymap.set({"n", "v"}, "<leader>d", [["_d]])

-- better escaping
vim.keymap.set("i", "<C-c>", "<Esc>")

-- never press capital q
vim.keymap.set("n", "Q", "<nop>")
-- ctrl f to switch projects, ctrl a + L to go back
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")
-- format
vim.keymap.set("n", "<leader>f", vim.lsp.buf.format)

-- quick fix navigation
vim.keymap.set("n", "<C-k>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-j>", "<cmd>cprev<CR>zz")
vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz")

-- leader s to replace the work that I was on
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])
