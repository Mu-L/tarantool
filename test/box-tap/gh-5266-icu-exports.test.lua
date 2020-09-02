#!/usr/bin/env tarantool

local tap = require('tap')
local ffi = require('ffi')

local test = tap.test('icu_exports')
test:plan(2)

-- Detect icu version suffix by grabbing information about `u_strlen` symbol
-- (by nm) from tarantool binary and further parsing it
local tnt_path = arg[-1]
local pipe = io.popen(string.format('nm %s | grep u_strlen', tnt_path))
local u_strlen_info = pipe:read('*all')
pipe:close()

test:ok(u_strlen_info ~= '', "Couldn't find u_strlen symbol (it's missing) to get icu versions")
local icu_version = u_strlen_info:gsub('.*u_strlen', ''):gsub('\n', '')


ffi.cdef([[
    void *dlsym(void *handle, const char *symbol);
]])

local RTLD_DEFAULT
-- See `man 3 dlsym`:
-- RTLD_DEFAULT
--   Find  the  first occurrence of the desired symbol using the default
--   shared object search order.  The search will include global symbols
--   in the executable and its dependencies, as well as symbols in shared
--   objects that were dynamically loaded with the RTLD_GLOBAL flag.
if jit.os == "OSX" then
    RTLD_DEFAULT = ffi.cast("void *", -2LL)
else
    RTLD_DEFAULT = ffi.cast("void *", 0LL)
end

local icu_symbols = {
    'u_strlen',
    'u_uastrcpy',
    'u_austrcpy',
    'u_errorName',
    'udat_open',
    'udat_setLenient',
    'udat_close',
    'udat_parseCalendar',
    'udat_formatCalendar',
    'ucal_open',
    'ucal_close',
    'ucal_get',
    'ucal_set',
    'ucal_add',
    'ucal_clear',
    'ucal_clearField',
    'ucal_getMillis',
    'ucal_setMillis',
    'ucal_getAttribute',
    'ucal_setAttribute',
    'ucal_getTimeZoneID',
    'ucal_setTimeZone',
    'ucal_getNow',
}

test:test('icu_symbols', function(t)
    t:plan(#icu_symbols)
    for _, sym in ipairs(icu_symbols) do
        local version_sym = sym .. icu_version
        t:ok(
            ffi.C.dlsym(RTLD_DEFAULT, version_sym) ~= nil,
            ('Symbol %q found'):format(version_sym)
        )
    end
end)

os.exit(test:check() and 0 or 1)
