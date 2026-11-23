# API design smells

Keep IDs stable when updating statuses. Follow [RULES.md](RULES.md) when addressing an item.

| ID | Status | Smell | Short description |
|---|---|---|---|
| API-01 | ✅ Fixed | 🧭 [Misplaced `Ctl.close()`](lib/window.v) | Removed `Ctl.close()`; window closing belongs to `app.close(mut window)`. |
| API-02 | ✅ Fixed | 🪪 [Inconsistent ownership checks](lib/core.v) | Shared checks reject foreign-app operations and discard stale input after ownership transfers. |
| API-03 | 🔎 Open | 🔓 [Exposed mutable internals](lib/core.v) | Public fields let callers bypass tree, ownership, focus and redraw rules. |
| API-04 | ✅ Fixed | 🧩 [Overloaded fields](lib/core.v) | Explicit fields separate entry limits, row counts, tree state, dialog results and popup ownership; `link` holds callback context. |
| API-05 | 🔎 Open | ✏️ [Inconsistent text mutation](lib/core.v) | `set_text()` bypasses editing checks, resets history and emits no change callback. |
| API-06 | 🔎 Open | 🧹 [Fragmented lifecycle](lib/window.v) | Closing, destroying and shutting down have different cleanup contracts. |
| API-07 | 🔎 Open | 🧨 [Unsafe callback state](lib/core.v) | Ordinary callbacks recover application state through unchecked `voidptr` casts. |
| API-08 | 🔎 Open | 🔔 [Attachment-dependent notifications](lib/core.v) | Mutations deliver callbacks only while controls have an owning app. |
| API-09 | 🔎 Open | 🔄 [Hidden modal reentrancy](lib/dialog.v) | Blocking dialogs run another event loop before the initiating callback returns. |
| API-10 | 🔎 Open | 🕳️ [Hidden nullable references](lib/window.v) | APIs return `&Ctl` even when the result can be nil. |
| API-11 | 🔎 Open | 🤐 [Ambiguous failure results](lib/editor.v) | Rejection and unchanged state share `false`; some invalid operations silently return. |
| API-12 | 🔎 Open | 🎨 [Mixed color encodings](lib/desktop.v) | Raw RGB and tagged toolkit colors share `int`, requiring manual conversions. |
| API-13 | 🔎 Open | ⚙️ [Implicit startup settings](lib/loop.v) | Initialization loads shared settings, potentially overriding configuration and hiding errors. |
