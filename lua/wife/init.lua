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
---Prompt for `require('wife').interactive_shell()`.
---Can be false to make lazy.nvim `opts` table merging easier.
---You can basically pass `false` to mean `nil`.
---@field prompt string|`false`|nil
---Path to the shell you want `interactive_shell` to use.
---All the other public functions in this plugin don't care about this option.
---(and they use the `shell` option automatically)
---@field shell string?
---If you put *this character* (or string) as the first thing in
---your `require('wife').interactive_shell()` command,
---only errors are going to be displayed;
---Meaning, output on successful execution of the shell command is ignored.
---@field errorer string?
---Amount of lines, after which the output appears in a split.
---If you set it to 3, 3 lines of output will appear in `vim.notify`,
---and 4 and beyond will appear in a split.
---@field cutoff integer?

---@type WifeOpts
local plugin_opts = {
	prompt = '󱕅 ',
	shell = vim.o.shell,
	errorer = ';',
	cutoff = 1
}

---@param opts WifeOpts?
function m.setup(opts)
	if not opts then return end
	plugin_opts = vim.tbl_deep_extend('force', plugin_opts, opts)
	if plugin_opts.prompt == false then plugin_opts.prompt = nil end
end

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ public ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

---@alias InputCompletion
---| nil
---| 'arglist' file names in argument list
---| 'augroup' autocmd groups
---| 'buffer' buffer names
---| 'behave' :behave suboptions
---| 'color' color schemes
---| 'command' Ex command (and arguments)
---| 'compiler' compilers
---| 'dir' directory names
---| 'environment' environment variable names
---| 'event' autocommand events
---| 'expression' Vim expression
---| 'file' file and directory names
---| 'file_in_path' file and directory names in |'path'|
---| 'filetype' filetype names |'filetype'|
---| 'function' function name
---| 'help' help subjects
---| 'highlight' highlight groups
---| 'history' :history suboptions
---| 'keymap' keyboard mappings
---| 'locale' locale names (as output of locale -a)
---| 'lua' Lua expression |:lua|
---| 'mapclear' buffer argument
---| 'mapping' mapping name
---| 'menu' menus
---| 'messages' |:messages| suboptions
---| 'option' options
---| 'packadd' optional package |pack-add| names
---| 'shellcmd' Shell command
---| 'sign' |:sign| suboptions
---| 'syntax' syntax file names |'syntax'|
---| 'syntime' |:syntime| suboptions
---| 'tag' tags
---| 'tag_listfiles' tags, file names are shown when CTRL-D is hit
---| 'user' user names
---| 'var' user variables
---| 'custom' {func} custom completion, defined via {func}
---| 'customlist' {func} custom completion, defined via {func}

---A more convenient api for `:h input()`
---@param prompt string|[string, string]|nil
---@param default string?
---@param completion InputCompletion?
---@return string|nil
function m.input(prompt, default, completion)
	local specified_highlight = type(prompt) == 'table'
	local prompt_text = prompt
	if specified_highlight then
		---@cast prompt -?
		prompt_text = prompt[1]
		vim.cmd.echohl(prompt[2])
	end
	local output = vim.fn.input({
		prompt = prompt_text,
		default = default,
		cancelreturn = '\127',
		completion = completion,
	})
	if specified_highlight then vim.cmd.echohl('None') end
	if output == '\127' then
		return nil
	else
		return output
	end
end

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
---and diplay it using `vim.notify` if it's a single line of output,
---and in a split if it's more than a single line.
---@param output vim.SystemCompleted
---@param only_errors boolean? Only show output if the exitcode is not 0.
function m.display(output, only_errors)
	local successful = output.code == 0
	if only_errors and successful then return end
	local output_lines = {}
	local stdout = output.stdout or ''
	local stderr = output.stderr or ''

	if #vim.trim(stdout) > 0 then
		vim.list_extend(output_lines, split_trim(stdout))
	end
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

---Do `require('wife').shell()`, and display the output in a
---`vim.notify` if it's a single line,
---and in a new split if it's more than that.
---*Has to* be syncronous to be able to create windows.
---So that's why an async version of this can't exist :(
---@param cmd string|string[] Can be string if all you want to run is a single command with no arguments.
---@param only_errors boolean? Only show output if the exitcode is not 0.
---@param opts vim.SystemOpts?
function m.shell_display(cmd, only_errors, opts)
	local output = m.shell(cmd, opts):wait()
	m.display(output, only_errors)
end

---Enter a shell command at a prompt and `require('wife').shell_display()` it.
---If the first character is `;` (configurable with the `errorer` option), `only_errors` is set to true.
function m.interactive_shell()
	local input = m.input({ plugin_opts.prompt, 'WifePrompt' }, nil, 'shellcmd')
	if not input then return end

	local only_errors = false
	if input:sub(1, #plugin_opts.errorer) == plugin_opts.errorer then
		input = input:sub(#plugin_opts.errorer + 1)
		only_errors = true
	end
	local args = { plugin_opts.shell, '-c', input }
	m.shell_display(args, only_errors)
end

return m
