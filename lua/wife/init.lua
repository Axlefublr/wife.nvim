local m = {}

-- ───────────────────────────────────────────── helper ─────────────────────────────────────────────

---@param text string|string[]
---@param start integer? 0 if nil
---@param finish integer? last line in the file if nil. which only works if bufnr is also current buffer.
---@param bufnr integer? 0 if nil
local function set_lines(text, bufnr, start, finish)
	if type(text) == 'string' then text = vim.split(text, '\n') end
	vim.api.nvim_buf_set_lines(bufnr or 0, start or 0, finish or vim.fn.line('$'), false, text)
end

local function split_trim(str)
	str = str:gsub('%s*$', '')
	return vim.split(str, '\n')
end

-- ══════════════════════════════════════════ plugin opts ═══════════════════════════════════════════

---@class WifeOpts
---
---Prompt for `require('wife').interactive_shell()`.
---To disable the prompt, you can set it to an empty string.
---@field prompt string|nil
---
---If you put *this character* (or string) as the first thing in
---your `require('wife').interactive_shell()` command,
---only errors are going to be displayed;
---Meaning, output on successful execution of the shell command is ignored.
---@field errorer string?
---
---Amount of lines, after which the output appears in a split.
---For example, if you set it to 3, 3 or less lines of output
---will appear in `vim.notify`, 4 or more will appear in a split.
---@field cutoff integer?

---@type WifeOpts
local plugin_opts = {
	prompt = 'shell ',
	errorer = ';',
	cutoff = 1,
}

---@param opts WifeOpts?
function m.setup(opts)
	local opts = opts or {}
	plugin_opts = vim.tbl_deep_extend('force', plugin_opts, opts)

	if plugin_opts.prompt and plugin_opts.prompt == '' then plugin_opts.prompt = nil end

	vim.api.nvim_create_autocmd('User', {
		pattern = 'WifeInputAccepted',
		callback = function(event)
			local input = event.data
			local only_errors = false
			if input:sub(1, #plugin_opts.errorer) == plugin_opts.errorer then
				input = input:sub(#plugin_opts.errorer + 1)
				only_errors = true
			end
			local args = { vim.o.shell, '-c', input }
			m.shell_display(args, only_errors)
		end,
	})
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ public ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

---See `:h vim.system()`
---Different from `vim.system()` in that `cwd` is assumed to be the current neovim `cwd`, unless overridden.
---Also, the `text` option is automatically set to `true`.
---@param cmd string|string[] Can be string if all you want to run is a single command with no arguments.
---@param opts vim.SystemOpts?
---@param on_exit fun(obj: vim.SystemCompleted)?
function m.shell(cmd, opts, on_exit)
	if type(cmd) == 'string' then cmd = { cmd } end
	local opts = vim.tbl_deep_extend('force', { text = true }, opts or {})
	if not opts.cwd then opts.cwd = vim.fn.getcwd() end
	return vim.system(cmd, opts, on_exit)
end

---Take a `vim.SystemCompleted`,
---(is an argument in `vim.system`'s on_exit function, and is returned after `:wait()`ing a `vim.system` call)
---and diplay it using `vim.notify` if it's [`plugin_opts.cutoff` or less] lines of output,
---and in a split if it's more than [`plugin_opts.cutoff`].
---@param output vim.SystemCompleted
---@param only_errors boolean? Only show output if the exitcode is not 0.
function m.display(output, only_errors)
	local successful = output.code == 0
	if only_errors and successful then return end
	local output_lines = {}
	local stdout = output.stdout or ''
	local stderr = output.stderr or ''

	if #vim.trim(stdout) > 0 then vim.list_extend(output_lines, split_trim(stdout)) end
	if #vim.trim(stderr) > 0 then vim.list_extend(output_lines, split_trim(stderr)) end

	if #output_lines == 0 then
		if not successful then vim.notify('exitcode: ' .. output.code, vim.log.levels.ERROR) end
		return
	end

	if #output_lines <= plugin_opts.cutoff then
		vim.notify(vim.fn.join(output_lines, '\n'), successful and vim.log.levels.OFF or vim.log.levels.ERROR)
		return
	end

	vim.cmd('new')
	set_lines(output_lines)
end

-- ╔════════════════════════════════════════════════════════════════════════════════╗
-- ║ Callbacks don't allow you to do a lot of things, like create buffers, windows, ║
-- ║ change options, execute vimscript, etc.                                        ║
-- ║ nvim_exec_autocmds() is also not allowed, so because of all those reasons,     ║
-- ║ shell_display_async and interactive_shell_async are both impossible            ║
-- ╚════════════════════════════════════════════════════════════════════════════════╝

---Do `require('wife').shell():wait()`, and display the output
---with `require('wife').display()`
---Syncronous.
---@param cmd string|string[] Can be string if all you want to run is a single command with no arguments.
---@param only_errors boolean? Only show output if the exitcode is not 0.
---@param opts vim.SystemOpts?
function m.shell_display(cmd, only_errors, opts)
	local output = m.shell(cmd, opts):wait()
	m.display(output, only_errors)
end

---Enter a shell command at a prompt and `require('wife').shell_display()` it.
---If the first character is `;` (configurable with the `errorer` option), `only_errors` is set to true.
---Input getting is asyncronous using `vim.ui.input`, shell command execution is syncronous.
function m.interactive_shell()
	vim.ui.input({ prompt = plugin_opts.prompt }, function(input)
		if not input then return end
		vim.api.nvim_exec_autocmds('User', { pattern = 'WifeInputAccepted', data = input })
	end)
end

return m
