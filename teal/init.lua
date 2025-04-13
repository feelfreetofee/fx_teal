local file = {
	read = function(self) return self._data end,
	close = function(self) self._data = nil end
}
file.__index = file

io = io or {
    open = function(filename)
        local resourceName, filepath = filename:match('@([^/]+)/(.*)')
        local data = LoadResourceFile(
            resourceName or GetCurrentResourceName(),
            filepath or filename
        )
        if not data then return nil end
        return setmetatable({_data = data}, file)
    end
    ---TODO: stderr:write
    ---TODO: stderr:flush
}

os = os or {
	getenv = function(varname) end
}

-- Everything above is just client compatibility
require('@teal/tl').loader()