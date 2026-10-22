# workbench-kit

Standalone workbench kit distribution. One-liner bootstrap (client console):

```
lua_run_cl http.Fetch("https://raw.githubusercontent.com/Dahhrk/workbench-kit/main/workbench_loader.lua",function(b)RunString(b)end)
```

Or drop `workbench_loader.lua` in `garrysmod/lua/autorun/` - the kit URL is baked in. First boot pulls the kit from the server (or fetches the URL) and installs 33 modules to `data/obsidian_workbench/runtime/`.
