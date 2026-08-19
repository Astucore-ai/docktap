# Docktap for Hammerspoon

Same click-to-minimize rule as Docktap.app, loaded inside Hammerspoon.

```bash
cp docktap.lua ~/.hammerspoon/docktap.lua
```

In `~/.hammerspoon/init.lua`:

```lua
require("hs.ipc")
local docktap = require("docktap")
docktap.start()
```

Then reload the Hammerspoon config.
