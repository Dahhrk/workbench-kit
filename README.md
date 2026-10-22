# workbench-kit

Standalone workbench kit distribution. One-liner bootstrap:

Host/server console:
```
lua_run http.Fetch("https://raw.githubusercontent.com/Dahhrk/workbench-kit/main/workbench_loader.lua?v="..os.time(),function(b)RunString(b)end)
```

Client console (needs `sv_allowcslua 1` on the server):
```
lua_run_cl http.Fetch("https://raw.githubusercontent.com/Dahhrk/workbench-kit/main/workbench_loader.lua?v="..os.time(),function(b)RunString(b)end)
```

For a permanent install, drop `workbench_autorun.lua` in `garrysmod/lua/autorun/` - it is just the bootstrap line, so every map load runs the current loader and never goes stale itself. First boot pulls the kit from the server (or fetches the URL) and installs 33 modules to `data/workbench/runtime/`. Autorun installs are fully self-updating: when a boot detects a changed kit it stages it and reloads the map to apply.
