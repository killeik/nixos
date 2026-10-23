-- The packaged Lua exporter has no filesystem collector in OpenWrt 24.10.
local function scrape()
  local size = metric("node_filesystem_size_bytes", "gauge")
  local avail = metric("node_filesystem_avail_bytes", "gauge")
  local free = metric("node_filesystem_free_bytes", "gauge")
  local types = {}
  for line in io.lines("/proc/mounts") do
    local _, mountpoint, fstype = line:match("^(%S+) (%S+) (%S+)")
    types[mountpoint] = fstype
  end

  local df = assert(io.popen("df -Pk"))
  for line in df:lines() do
    local device, blocks, used, available, mountpoint =
      line:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+%d+%%%s+(%S+)$")
    if device then
      local labels = {device = device, mountpoint = mountpoint, fstype = types[mountpoint]}
      size(labels, tonumber(blocks) * 1024)
      avail(labels, tonumber(available) * 1024)
      free(labels, (tonumber(blocks) - tonumber(used)) * 1024)
    end
  end
  assert(df:close())
end

return { scrape = scrape }
