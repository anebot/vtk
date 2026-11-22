# VTK — Vorland TermKit

A standalone V port of [AholyC's HTK](https://github.com/trufae/aholyc), the Borland-style terminal widget
toolkit. The original HolyC library is retained separately. VTK uses V's
standard library and native OS bindings; it does not invoke aholyc, link
HolyC-generated code, or depend on `lib/term`.

<center><img border=0 alt=screenshot width="400px" src=vtk.jpg></img></center>

Install the library with V's package manager:

```sh
v install https://github.com/trufae/vtk
```

Then use `import vtk` in your application. Library sources and tests live in
`lib/`; the root `v.mod` selects that directory with `base_url: 'lib'`.

From a checkout's root directory:

```sh
make
make test
./build/draw
```

`make` builds all six examples in `build/`. You can also run them directly:

```sh
v run examples/htk.v
v run examples/word.v README.md
v run examples/vim.v README.md
v run examples/draw.v
v run examples/widgets.v
v run examples/terminal.v
v test .
```

V 0.5.2 and a C compiler are sufficient. There are no VPM dependencies.
Copying the entire checkout into a V module search path as `vtk` works too.

```v
import vtk

fn pressed(mut button vtk.Ctl, mut app vtk.App) {
    app.notify('Hello from V', 2000)
}

fn main() {
    mut app := vtk.new_app()
    mut window := app.window('Hello', 40, 12)
    mut body := vtk.box(true)
    mut text := vtk.label('Tab changes focus; Ctrl-C quits.')
    mut button := vtk.button('Press me')
    button.changed = pressed
    body.add(mut text)
    body.add(mut button)
    window.add(mut body)
    app.run() or { eprintln(err) }
}
```

## Controls and layout

`Ctl` is the shared control model. Public fields correspond to HTK's control
fields; constructors and methods use V naming conventions. `App` contains
the window stack, theme, focus, clipboard, hooks and desktop settings.

| HTK concept | VTK API |
| --- | --- |
| Init / main / fini | `app.init()!`, `app.run()!`, `app.fini()` |
| Custom loop | `app.step(timeout_ms)` and `app.dispatch(event)` |
| Window | `app.window(title, width, height)` |
| Add / set text | `parent.add(mut child)`, `control.set_text(text)` |
| Label / separator | `label(text)`, `separator()` |
| Buttons | `button(text)`, `toolbutton(text)`, `button_bar()` |
| Text fields | `entry(text, byte_limit)`, `multiline(text)` |
| Markdown | `markdown(text)`, `control.markdown_mode(mode)` |
| Boolean controls | `checkbox(text, checked)`, `switch_ctl(text, on)` |
| Value controls | `slider(low, high)`, `spin(low, high)`, `progress()`, `spinner(text)` |
| Choices | `combo()`, `radio()`, `control.add_item(text)` |
| Table | `table(cell_callback)`, `control.table_column(title)`, `control.high` row count |
| Tree | `tree()`, `control.tree_add(parent, text)`, `control.link` selection |
| Tabs / group | `tabs()`, `control.add_tab(title, mut child)`, `group(title)` |
| Linear / grid / flow | `box(vertical)`, `grid()`, `flow()` |
| Split / scroll | `split(vertical, share)`, `scroll()` |
| Bars | `toolbar()`, `statusbar(text)` |
| Canvas | `canvas(width, height, paint_callback)` |
| Menus | `window.add_menu(title)`, `menu.menu_item(title, callback)` |
| Context menu | `context_menu()`, `control.menu`, `app.open_menu(menu, x, y)` |

Grid children use `row` and `col`, both in `0..64`. Expanding children share
spare space; horizontal boxes leave one cell between children. Button bars
are right-aligned and bottom-docked. A split's `value` in `1..999` specifies
the first pane's share in thousandths; zero uses its preferred size. Layout
and hit testing exclude hidden controls and inactive tab pages.

Comboboxes support `control.text_align = .left`, `.center`, or `.right` for
the selected value and dropdown choices; left is the default. Alignment uses
terminal cell widths and keeps the dropdown arrow fixed at the right edge.
Overlong text is clipped to the content area. The Theme selector in Settings
uses centered text.

Callbacks receive `mut Ctl` and `mut App`. `changed` handles activation and
edits, `submit` handles Enter, and `user`/`data` hold application state.
`keyfn`, `mousefn` and `scrollfn` return true to consume an event. A window's
`closing` callback can veto closing or application quit; `destroy` is called
by `app.destroy_ctl`. Controls use V-managed memory.

## Mouse cursor and hover

VTK requests xterm any-event mouse tracking (1003) with SGR coordinates (1006),
so compatible terminals report movement even when no button is held. Hover
tracking is enabled by default; the optional software cursor is independent
of the keyboard caret:

```v
app.set_mouse_cursor(vtk.MouseCursor{
    enabled: true
    glyph: `█`
    fg: vtk.bright_white
    bg: vtk.black
})
button.mouse_enter = on_hover
button.mouse_leave = on_hover
```

Both callbacks have the usual `fn (mut vtk.Ctl, mut vtk.App)` signature.
`control.hovered` is already updated when they run. Enter and leave fire once
per transition on the deepest eligible control, without bubbling to parents
or changing keyboard focus. Existing `mousefn` callbacks receive movement
events too; these have `motion == true`, `button == .none`, and `pressed == false`
when no button is held. `app.hovered_ctl()` returns the hovered control or nil,
and `app.mouse_position()` returns zero-based terminal cells.

The cursor supports a single-cell glyph, foreground/background colors and
`attr`; `set_mouse_cursor` returns false for a wide, combining or control glyph.
ASCII themes translate its glyph using the normal fallback. Disable it with
`app.set_mouse_cursor(vtk.MouseCursor{})`. `app.set_mouse_motion(false)` restores
button/drag-only reporting when the software cursor is disabled. These settings
can change while the app runs. Settings includes a **Block mouse cursor**
checkbox: Apply changes visibility, Save persists it, and Reset disables it.
The widgets demo shows the block cursor and hover feedback in its status bar.

`MouseCursor.hide_pointer` defaults to true: VTK asks the terminal whether
OSC 22 supports a `none` pointer shape. After an affirmative reply, it hides
the desktop pointer while the block cursor is visible. Disabling the block
cursor, losing terminal focus, moving outside the viewport or exiting VTK
restores the previous pointer shape with OSC 22 push/pop. Set
`hide_pointer: false` to keep the desktop pointer. Unsupported terminals and
terminals that do not answer the query keep their normal pointer;
`app.mouse_pointer_supported()` exposes the detected capability. Detection
runs asynchronously and does not delay startup.

SwiftTerm 1.99.3 keeps the native pointer visible. Support for the queried
`none` extension on macOS is proposed in
[SwiftTerm PR #855](https://github.com/migueldeicaza/SwiftTerm/pull/855).
Once the host application includes that change, VTK can detect and use it.

Hover respects clipping, window stacking, modality and overlays, and is
rechecked after layout changes. Closing, minimizing or destroying a hovered
control clears its hover state. Terminal focus loss clears hover and hides
the pointer until the next mouse report. Coordinates are limited to cells
inside the terminal; native pointer hiding requires the capability above.
Terminals without motion reporting cannot provide idle movement or hover,
and the protocol has no portable pointer-exit notification: leaving the
terminal while it retains focus can leave the last pointer position visible.

## Windows, desktop and dialogs

Windows drag by their title, resize from the frame and support minimize,
maximize, restore, tile, cascade, size limits and always-on-top ordering.
The minimum window size is 16 columns by 3 rows, including the frame.
Opening, moving, resizing and arranging windows keep their full frames inside
the workspace, respecting their size limits and the app bar at either edge.
Changing the bar's position or visibility and resizing the terminal also move
windows back inside the workspace and shrink oversized windows to fit.
Windows retain their minimum sizes even in smaller terminals.
The title controls are selected with `window_menu`, `window_minimize`,
`window_maximize`, `window_close`, or their bitwise combination.
Window buttons in the app bar use `[= AppName]`: click `=` for the window's
actions menu, or its name to raise it and restore it from minimized state.

Tab / Shift-Tab cycle focus; Ctrl-Tab / Ctrl-Shift-Tab cycle windows.
F10 or Alt-M opens the window menubar. Ctrl-G opens the system menu and
Alt-A / Alt-F10 opens App. Ctrl-O opens App when the focused control does
not handle it. Menus also accept h/j/k/l. Escape closes dismissable windows.
Alt-F7 and Alt-F8 enter keyboard Move and Resize; arrows move one cell,
Shift-arrows five, Enter accepts and Escape restores the original rectangle.
`parse_binding` and `app.set_keys` configure these shortcuts atomically.

`app.register(name, callback, data)` adds a desktop launcher and keeps the
desktop alive after its windows close. `app.notify(text, timeout_ms)` posts
a dismissable notification; zero leaves it visible until closed.

`msgbox_for`, `confirm_for`, `prompt_for`, `choice_for`, `list_choice_for`,
`file_pick_for`, `color_pick`, `emoji_pick` and `history_for` implement the
dialogs. Explicit owners provide window modality; a nil owner provides
application modality. Results live in each dialog. `prompt`, `msgbox` and
`confirm_quit` provide common shortcuts. File picking never changes cwd.
Settings is application-modal and blocks both existing and newly opened windows.

Settings use **`~/vtk.ini`**, with a `[vtk]` section. `app.settings_file(path)`
overrides the location. Enable **Window bar at top** to place the `[App]` bar
on the first screen line, with its menus opening downward. The default is the
bottom line; `app.bar_top` (or `bar_top = 1` in the INI file) controls placement.
Settings persist theme colors, the bar position, visibility and clock,
shadows, inactive dimming, mouse cursor visibility, Vim mode, and move/resize
bindings. Theme presets are Borland, Light Borland, Dark, Light, Teal, Modern
and Serial. `app.theme`
can be edited directly. Window titlebars use `title` and `title_bg`; dimmed
inactive titlebars use `inactive_title` and `inactive_title_bg`. The title and
window buttons share a solid background, separate from the body and frame.
Focused controls use the `focus_fg` and `focus_bg` pair. Dark and Modern use
RGB palettes for consistent contrast across terminal color schemes.
`color_rgb` and `color_256` provide extended colors;
Serial uses basic ANSI colors and ASCII fallbacks.

## Editing and rendering

Editor positions and selection anchors are UTF-8 byte offsets. Navigation
and editing preserve character boundaries. Entries enforce optional byte
limits before replacing selections and support password masking. Multiline
and Markdown views support selection, undo/redo, line numbers, wrapping,
scrollbars and manual scrolling that leaves the caret stationary.
`replace_range`, `replace_selection`, `undo`, `redo`, `begin_edit_group` and
`end_edit_group` expose the edit model.

Markdown modes independently select source/rendered and editable/read-only
presentation. The V renderer handles headings, emphasis, inline code, links,
lists, task checkboxes, quotes and fenced code. Fences retain source rows.
Task clicks in View, double-clicks in Edit, and Space in View change only
the task's state byte as one undo entry. Code blocks are inert. Set
`md.task_interactive = false` for strict source viewers. `md.linkfn` receives
clicked links in read-only views or with Ctrl-click. Rulers, column width,
page separators and current-section layout are configurable through `md`.

`control.vim_mode(true)` or `app.vim_set(true)` enables per-editor Normal,
Insert, Visual and Visual-line modes. Motions include h/j/k/l, w/b/W/B,
0/^/$ and gg/G; edits include i/a/I/A, o/O, J, x, dd/yy, dw/cw, p/P, undo
and redo. Insert mode also supports Emacs-style movement, cuts, paste and
transpose. Insert sessions and changes group into one undo step. Cursor
shape follows the focused editor's mode.

Clipboard strings preserve explicit lengths, including NUL. `app.ctrl_c`
selects quit, ignore, copy, or callback behavior. Set `native_clipboard`
to additionally send copies through OSC 52. Ctrl-C and Tab are forwarded
to a focused terminal control; Ctrl-Tab still switches windows.

Drawing composes clipped cells and emits a single ANSI diff. Wide Unicode
characters occupy two cells and combining marks attach to the preceding
glyph. ASCII fallback changes display only. `Screen` exposes text, fill,
frame and line primitives; canvas callbacks draw in absolute cell coordinates.
`app.redraw()` and `app.screen.snapshot()` work without opening a terminal.
Timers (`after`, `every`, `cancel_hook`) run on the event-loop thread.

The terminal control uses a Unix PTY or Windows ConPTY and an incremental
xterm subset: cursor movement, erasing, insert/delete, scroll regions, SGR,
16/256/RGB colors and UTF-8. Output is polled in bounded batches. Closing
the window releases the child process and PTY. It is not a full VT emulator.

## Examples and validation

`htk.v` translates `examples/htk.hc`. `draw.v` translates the HTK path of
`examples/ui/draw.hc`. `word.v` and `vim.v` translate their editor workflows;
the HolyC applications' `lib/text` document exporters and font services are
outside this module. `widgets.v` and `terminal.v` are additional native demos.

The regression suite covers layout, focus, window lifecycle, modal ownership,
input chunking, Unicode, clipboard/edit history, Vim, Markdown source mapping,
settings, terminal parsing and actual Unix PTY I/O. All six examples have
been built and exercised under pseudo terminals on macOS, including resize,
UTF-8 file saving and terminal restoration. Windows code has been V type-checked;
ConPTY runtime behavior still needs validation on Windows 10 or newer.

The port follows the repository's public-domain dedication; see [COPYING](COPYING).
