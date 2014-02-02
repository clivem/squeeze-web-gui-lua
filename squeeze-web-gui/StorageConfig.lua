-- StorageConfig

-- Web Configuration and Control Interface (lua version) for a 
-- Wandboard Squeeze Player
--
-- Copyright (C) 2014 Adrian Smith <triode1@btinternet.com>
--
-- This file is part of squeeze-web-gui-lua.
--
-- squeeze-web-gui-lua is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- squeeze-web-gui-lua is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with squeeze-web-gui-lua. If not, see <http://www.gnu.org/licenses/>.

local io, string, os, lfs, ipairs, pairs, table, tonumber, tostring = io, string, os, lfs, ipairs, pairs, table, tonumber, tostring
local util, log = util, log

module(...)

local fstabLocation = "/etc/fstab"
local fstabTmp      = "/tmp/fstab.tmp"

local local_disks    = "/dev/"
local mount_points   = "/storage"

function _mounts()
	local mounts = {}

	local cap = util.capture('mount | grep ' .. mount_points)
	cap = cap .. "\n"
	for line in string.gmatch(cap, "(.-)\n") do
		local spec, mountp, type, opts = string.match(line, "(.-) on (.-) type (.-) %((.-)%)")
		if spec and mountp and type and opts then
			mounts[#mounts+1] = { spec = spec, mountp = mountp, type = type, opts = opts, perm = false } 
		end
	end
	return mounts
end

function get()
	-- get current active mounts
	local mounts = _mounts()

	-- update with whether they are in fstab and add other non active fstab entries from our section of fstab
	local fstab = io.open(fstabLocation, "r")
	if fstab then
		local ours = false
		for line in fstab:lines() do
			if string.match(line, "^# start added by squeeze%-web%-gui") then
				ours = true
			elseif string.match(line, "^# end added by squeeze%-web%-gui") then
				ours = false
			elseif ours then
				local spec, mountp, type, opts = string.match(line, "(.-)%s+(.-)%s+(.-)%s+(.-)%s")
				if spec and mountp and type and opts then
					local found = false
					for _, v in ipairs(mounts) do
						if spec == v.spec and mountp == v.mountp and type == v.type then
							found = true
							v.perm = true
							v.opts = opts -- use opts from fstab as more complete
							break
						end
					end
					if not found then
						mounts[#mounts+1] = { spec = spec, mountp = mountp, type = type, opts = opts, perm = true }
					end
				end
			end
		end
		fstab:close()
	else
		log.debug("unable to open: " .. fstabLocation)
	end

	return mounts
end

function status()
	return util.capture('mount | grep ' .. mount_points)
end

function mountpoints()
	return { mount_points }
end

function localdisks()
	local t = {}
	for file in lfs.dir(local_disks) do
		if string.match(file, "sd%l%d") then
			t[#t+1] = local_disks .. file
		end
	end
	table.sort(t)
	return t
end

function set(mounts)
	local fstab = io.open(fstabLocation, "r")
	local tmp   = io.open(fstabTmp, "w")

	if fstab and tmp then
		-- copy over file excluding portion marked as ours
		local ours = false
		for line in fstab:lines() do
			if string.match(line, "^# start added by squeeze%-web%-gui") then
				ours = true
			elseif string.match(line, "^# end added by squeeze%-web%-gui") then
				ours = false
			elseif not ours then
				tmp:write(line .. "\n")
			end
		end
		-- add our new section
		tmp:write("# start added by squeeze-web-gui-lua\n")
		for _, v in ipairs(mounts) do
			if v.perm then
				tmp:write(v.spec .. "\t" .. v.mountp .. "\t" .. v.type .. "\t" .. (v.opts or "defaults") .. "\t0\t0\n")
			end
		end
		tmp:write("# end added by squeeze-web-gui-lua\n")

		tmp:close()
		fstab:close()

		util.execute("sudo csos-fstabUpdate " .. fstabTmp)
		util.execute("rm " .. fstabTmp)

		log.debug("wrote and updated fstab")
	else
		if not fstab then
			log.error("unable to open: " .. fstabLocation)
		end
		if not tmp then
			log.error("unable to open: " .. fstabTmp)
		end
	end
end

