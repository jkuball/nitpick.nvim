-- Neovim for trying nitpick: the suggested mappings and a statusline.

vim.g.mapleader = " "
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.statusline = "%f %m%=%{v:lua.require'nitpick'.status()}  %l:%c "

local map = vim.keymap.set
map({ "n", "x" }, "gb", "<Plug>(nitpick-annotate)") -- gbb: this line
map({ "n", "x", "o" }, "]n", "<Plug>(nitpick-next)")
map({ "n", "x", "o" }, "[n", "<Plug>(nitpick-prev)")
map("n", "<leader>nn", "<Plug>(nitpick-annotate-line)")
map("x", "<leader>nn", "<Plug>(nitpick-annotate)")
map("n", "<leader>no", "<Plug>(nitpick-note)")
map("n", "<leader>nf", "<Plug>(nitpick-file)")
map({ "n", "x" }, "<leader>ne", "<Plug>(nitpick-edit)")
map({ "n", "x" }, "<leader>nd", "<Plug>(nitpick-delete)")
map("n", "<leader>nq", "<Plug>(nitpick-qflist)")
map("n", "<leader>nl", "<Plug>(nitpick-loclist)")
map("n", "<leader>nr", "<Plug>(nitpick-review)")
map("n", "<leader>ns", "<Plug>(nitpick-send)")
map("n", "<leader>nc", "<Plug>(nitpick-clear)")
map("n", "<leader>nt", "<Plug>(nitpick-to)")
