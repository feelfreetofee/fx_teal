local function checkargs(...)
    local args = {}
    for index, argument in ipairs({...}) do
        local expected, value, default = table.unpack(argument)
        if value == nil and default then
            value = default
        end
        local received = type(value)
        if received ~= expected then
            error(('bad argument #%d (%s)'):format(index,
                    ('%s expected, got %s'):format(expected, received)), 2)
        end
        table.insert(args, value)
    end
    return table.unpack(args)
end

---@param filename string
---@return string?
---@return string?
---@nodiscard
local function readfile(filename)
    if filename == '' then
        return nil, 'Invalid argument'
    end
    local resourceName, filepath =
        filename:match('@([^/]+)/(.*)')
    local file = LoadResourceFile(
        resourceName or GetCurrentResourceName(),
        filepath or filename
    )
    if not file then
        return nil, 'No such file or directory'
    end
    return file
end

---https://www.lua.org/source/5.4/lauxlib.c.html#luaL_loadfilex
---@param filename string
---@return function?
---@return string? error_message
---@nodiscard
local function loadfile(filename)
    checkargs({'string', filename})
    local status, readstatus = readfile(filename)
    if not status then
        return nil, ('cannot open %s: %s'):format(filename, readstatus)
    end
    return load(status, filename)
end
_G.loadfile = loadfile

--- https://www.lua.org/source/5.4/lua.c.html#dofile
---@param filename string
---@return any
function dofile(filename)
    if filename == nil then
        return
    end
    local loader, err = loadfile(filename)
    if not loader then
        error(err)
    end
    return loader()
end

---https://www.lua.org/source/5.4/loadlib.c.html#searchpath
---@param name string
---@param path string
---@param sep string
---@param rep string
---@return string? filename
---@return string? errmsg
local function searchpath(name, path, sep, rep)
    if sep ~= '' and name:find(sep) then
        name = name:gsub(sep, rep)
    end
    local errmsg = {}
    for filename in path:gsub('?', name):gmatch('[^;]+') do
        if readfile(filename) then
            return filename
        end
        table.insert(errmsg, ('no file \'%s\''):format(filename))
    end
    return nil, table.concat(errmsg, '\n')
end

local package = {}
_G.package = package

---https://www.lua.org/source/5.4/loadlib.c.html#ll_searchpath
---@param name string
---@param path string
---@param sep string?
---@param rep string?
---@return string? filename
---@return string? errmsg
function package.searchpath(name, path, sep, rep)
    return searchpath(checkargs(
        {'string', name},
        {'string', path},
        {'string', sep, '%.'},
        {'string', rep, '/'}
    ))
end

local fx_require = require

---@type table<string, function>
local preload = {
    lmprof = fx_require,
    glm = fx_require
}
package.preload = preload

---@alias package_searcher fun(name: string): loader: function|string?, loaderdata: string?

---https://www.lua.org/source/5.4/loadlib.c.html#searcher_preload
---@type package_searcher
local function searcher_preload(name)
    checkargs({'string', name})
    local loader = preload[name]
    if type(loader) ~= 'function' then
        return ('no field package.preload[\'%s\']'):format(name)
    end
    return loader, ':preload:'
end

---https://www.lua.org/source/5.4/loadlib.c.html#findfile
---@param name string
---@param pname string
---@param dirsep string
---@return string? filename
---@return string? errmsg
local function findfile(name, pname, dirsep)
    local path = package[pname]
    if type(path) ~= 'string' then
        error(('\'package.%s\' must be a string'):format(pname), 2)
    end
    return searchpath(name, path, '%.', dirsep)
end

package.path = '?.lua;?/init.lua'

---https://www.lua.org/source/5.4/loadlib.c.html#searcher_Lua
---@type package_searcher
local function searcher_Lua(name)
    checkargs({'string', name})
    local filename, err = findfile(name, 'path', '/')
    if not filename then
        return err
    end
    return loadfile(filename)
end

---@type package_searcher[]
package.searchers = {
    searcher_preload,
    searcher_Lua
}

---https://www.lua.org/source/5.4/loadlib.c.html#findloader
---@param name string
---@return function loader
---@return any loaderdata
local function findloader(name)
    if type(package.searchers) ~= 'table' then
        error('\'package.searchers\' must be a table', 2)
    end
    local msg = {}
    for index = 1, #package.searchers do
        local loader, loaderdata =
            package.searchers[index](name)
        local result = type(loader)
        if result == 'function' then
            return loader, loaderdata
        elseif result == 'string' then
            table.insert(msg, loader)
        end
    end
    error(('module \'%s\' not found:\n%s')
        :format(name, table.concat(msg, '\n')), 2)
end

---https://www.lua.org/source/5.4/linit.c.html#loadedlibs
---https://github.com/citizenfx/fivem/blob/476f550dfb5d35b53ff9db377445be76db7c28bc/code/components/citizen-scripting-lua/src/LuaScriptRuntime.cpp#L164
---@type table<string, any>
local loaded = {
    _G = _G,
    coroutine = coroutine,
    table = table,
    string = string,
    math = math,
    utf8 = utf8,

    debug = debug,

    io = io,
    os = os,

    msgpack = msgpack,
    json = json,

    package = package
}
package.loaded = loaded

---https://www.lua.org/source/5.4/loadlib.c.html#ll_require
---@param name string
---@return any module
---@return any loaderdata
function require(name)
    checkargs({'string', name})
	local module = loaded[name]
	if module ~= nil then
		return module
	end
	local loader, loaderdata = findloader(name)
	module = loader(name, loaderdata)
	if module == nil then
		module = true
	end
	loaded[name] = module
	return module, loaderdata
end