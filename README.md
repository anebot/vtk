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

Controls acquire app ownership when added to an app's window, including nested
controls built before attachment. Moving a subtree to another window updates its
ownership automatically; detached controls can be initialized without an app.
Attach context menus with `control.set_menu(mut menu)` so their items inherit
ownership too. Standalone menus acquire ownership when opened.

Window management, focus, scrolling, destruction and dialogs reject controls
owned by another app before changing state or invoking callbacks. They keep
their usual failure or cancellation result. Explicit attachment and `app.dialog`
can transfer subtrees between apps; `raise` can adopt detached windows, and
standalone menus bind to the app that opens them.
After a transfer, stale focus, capture and popups are discarded before the next
input event. Hover leave callbacks run before ownership changes.

Tree links, control identity, geometry, lifecycle flags, app stacks and focus,
and render/history storage are toolkit-owned. Read them through `rect()`,
`parent_ctl()`, `owner_window()`, `children()`, `window_list()`, `focused_ctl()`
and the state queries. Returned arrays are copies. Use `add`, `detach`, `clear`
and `replace` for tree changes; `clear` detaches children, while `destroy_ctl`
also releases their resources. Detaching removes stale selections, default
buttons and input capture. Use `app.move` for window positions and `app.layout()`
to calculate geometry before a redraw. `app.invalidate()` schedules an app redraw.

Lookups such as `top_window()`, `owner_window()`, `parent_ctl()`, `tree_selection()`,
`hovered_ctl()` and `hit()` return `?&Ctl`. Handle absence with an `if` guard or
`or` block. Use `none` for a root tree node or an application-modal dialog owner:

```v
tree.tree_add(none, 'Root')
if mut window := app.top_window() {
    app.raise(mut window)
}
```

Widget mutations no longer take `mut app`: use `control.set_value(42)`,
`control.replace_selection(text)`, `control.undo()`, `control.redo()`,
`control.toggle_task(at)` and `control.fire()`. Value changes and edits notify
`changed` with the owning app; detached mutations update state without invoking
app callbacks, and attachment does not replay those callbacks.

`set_text`, `markdown_mode`, `vim_mode`, item/tab/tree additions, scrolling,
size limits and attachment/detachment schedule redraws without emitting `changed`.
After changing public fields directly, call `control.invalidate()` to schedule a
redraw. Callbacks still receive `mut app` for application operations.

```v
mut bar := vtk.progress()
window.add(mut bar)
bar.set_value(42)
```

`Ctl` is the shared control model. Widget-specific state has explicit field
names; constructors and methods use V naming conventions. `App` contains
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
| Date picker | `date_picker(initial)`, `control.date()`, `control.set_date(date)` |
| Value controls | `slider(low, high)`, `spin(low, high)`, `progress()`, `spinner(text)` |
| Choices | `combo()`, `radio()`, `control.add_item(text)` |
| Table | `table(cell_callback, row_count)`, `control.table_column(title)`, `control.row_count` |
| Tree | `tree()`, `control.tree_add(parent, text)`, `control.tree_selection()`, `control.tree_select(node)` |
| Tabs / group | `tabs()`, `control.add_tab(title, mut child)`, `group(title)` |
| Linear / grid / flow | `box(vertical)`, `grid()`, `flow()` |
| Split / scroll | `split(vertical, share)`, `scroll()` |
| Bars | `toolbar()`, `statusbar(text)` |
| Canvas | `canvas(width, height, paint_callback)` |
| Menus | `window.add_menu(title)`, `menu.menu_item(title, callback)` |
| Context menu | `context_menu()`, `control.set_menu(mut menu)`, `app.open_menu(menu, x, y)` |

`low` and `high` are numeric range bounds; `value` holds a widget value or
selection index. Entries use `byte_limit` (zero means unlimited) and `min_w`
for minimum preferred width. Tables use `row_count`. Trees expose selection through
`tree_selection()` and each node's `expanded` flag. `tree_select(node)` schedules a
redraw without emitting `changed`. Dialogs use `dialog_result`; set their default
button with `app.set_default_button(mut window, button)` and query it with
`window.get_default_button()`. Popup relationships are managed internally. `link`
is an optional associated-control reference used by callbacks; unwrap it before
use. `user` and `data` hold application state.

Grid children use `row` and `col`, both in `0..64`. Expanding children share
spare space; horizontal boxes leave one cell between children. Button bars
are right-aligned and bottom-docked. A split's `value` in `1..999` specifies
the first pane's share in thousandths; zero uses its preferred size. Layout
and hit testing exclude hidden controls and inactive tab pages.

Tabs use a two-row header with rounded UTF-8 outlines (ASCII borders in
Serial mode). The selected tab opens into its page and uses bold accent text,
keeping the page's background even when focused. Narrow strips keep the
selected header visible, clipping long titles inside their outlines.

Comboboxes support `control.text_align = .left`, `.center`, or `.right` for
the selected value and dropdown choices; left is the default. Alignment uses
terminal cell widths and keeps the dropdown arrow fixed at the right edge.
Overlong text is clipped to the content area. The Theme selector in Settings
uses centered text.

Callbacks receive `mut Ctl` and `mut App`. `changed` handles activation and
edits, `submit` handles Enter, and `user`/`data` hold application state.
`keyfn`, `mousefn` and `scrollfn` return true to consume an event. A window's
`closing` callback can veto `app.close(mut window)` or application quit.
`destroy` is called by `app.destroy_ctl`. Controls use V-managed memory.

`app.close(mut window)` returns false if closing is vetoed or the control is not
a window owned by that app. Closing an already closed window owned by the app
succeeds.

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
`control.is_hovered()` is already updated when they run. Enter and leave fire once
per transition on the deepest eligible control, without bubbling to parents
or changing keyboard focus. Existing `mousefn` callbacks receive movement
events too; these have `motion == true`, `button == .none`, and `pressed == false`
when no button is held. `app.hovered_ctl()` returns the hovered control or `none`,
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

## Virtual desktops and progress blocks

The appbar starts with **Start** and a slot for each configured virtual desktop.
The active slot shows its one-based desktop number; the others show underscores:
`[Start] [1][_][_][_]`. Click a slot to switch. New windows open on the active
desktop; inactive windows are absent from drawing, input, window cycling and the
window buttons. Focus is remembered separately on each desktop.

In **Start > Settings**, **Virtual desktops** has **-** and **+** buttons around a
block-style progress bar and a numeric count. It allows 1 through 4 desktops.
**Apply** changes the count, **Save** also persists it in `vtk.ini`, and **Reset**
returns to one. Reducing the count moves windows from removed desktops to the
last remaining desktop; windows are kept open.

The window's `[=]` menu, also available from its appbar button, has a **Move to
desktop** submenu when multiple desktops exist. Moving a window leaves the
current desktop active. Raising an existing window on another desktop switches
to it. Owned modal dialogs follow their owner; application-modal dialogs prevent
switching until dismissed. Tiling, cascading and shared-edge resizing keep
desktops independent.

```v
app.set_desktop_count(4)
app.switch_desktop(2)
app.move_window_to_desktop(mut window, 3)
```

`app.get_desktop_count()`, `app.get_active_desktop()` and `window.get_desktop_id()` expose the
current state. Use the methods above to change it so focus, menus and capture
are updated together. Desktop numbers are one-based; invalid switch/move
requests return false. The default count is one.

Set `bar.blocky = true` to draw a progress bar as two-cell square blocks with
one-cell empty gaps. The default remains continuous. Both styles respect
`low` and `high`; the Settings count uses a 0..4 range so one desktop fills one
block, with the buttons enforcing a minimum count of one.

## Clock actions and dates

Set `app.clock_clicked` to handle clock presses in the desktop bar. The callback
receives the mouse event and app; left, middle and right presses are reported once,
with zero-based screen coordinates. Releases, motion and wheel events do not
activate it. It works at either bar position, only while the clock is visible,
and respects application-modal dialogs. With no callback, clicks have no action.

```v
app.clock_clicked = fn (event vtk.Event, mut app vtk.App) {
    mut menu := vtk.context_menu()
    menu.menu_item('Calendar...', fn (mut _ vtk.Ctl, mut app vtk.App) {
        if date := app.date_pick(app.top_window(), 'Choose date', time.now()) {
            app.notify('Selected ${date.year:04}-${date.month:02}-${date.day:02}', 1500)
        }
    })
    app.open_menu(menu, event.x, event.y)
}
```

The examples in this section also need `import time`. A clock callback can launch
an application directly instead of opening a menu. The widgets demo opens the
calendar on a left click and its menu on a right click.

`date_picker(initial time.Time)` is an embeddable Gregorian calendar, with Monday
as the first weekday. `control.date()` returns the selected date at midnight,
without a timezone. `control.text` contains its ISO `YYYY-MM-DD` representation.
`set_date(date)` updates the selection, schedules a redraw and invokes `changed`
when the date changes. Detached controls can be initialized safely. Time-of-day
and timezone fields are ignored; invalid components are clamped to valid dates
in years 1 through 9999, including leap years.

Click a day to select it. The header arrows or Page Up/Down select the previous
or next month, preserving the day where possible. Shift-click the arrows, or use
Shift/Ctrl with Page Up/Down, to move a year. Arrow keys move one day or week;
Home/End select the first/last day of the month. Click **Today** or press **T**
to return to today. Read-only and disabled calendars ignore selection input.

Use `app.date_pick(owner, title, initial)` for an OK/Cancel dialog. Enter/Space
accept from the calendar; Escape, Cancel or closing the dialog return `none`.
The inline widget uses the usual `changed` and `submit` callbacks.

## Windows, desktop and dialogs

Windows drag by their title, resize from the frame and support minimize,
maximize, restore, tile, cascade, size limits and always-on-top ordering.
Double-click a title to maximize the window; double-click again to restore it.
Drag a maximized window's frame edge or corner to resize it from its current bounds.
The minimum window size is 16 columns by 3 rows, including the frame.
Opening, moving, resizing and arranging windows keep their full frames inside
the workspace, respecting their size limits and the app bar at either edge.
Changing the bar's position or visibility moves windows back inside the workspace.
Terminal resizing preserves screen-edge attachments and touching window borders,
including manually arranged tiles. Shared borders follow the workspace proportions;
windows attached along only one edge retain their size where space permits.
Unattached axes preserve the proportional gaps to opposite workspace edges without
resizing the window, so centered windows stay centered. Window size limits take
precedence, and windows are clamped to fit when space is limited.
Repeated resizes retain the original layout without rounding drift, even
after a terminal temporarily becomes too small to contain the minimum sizes.
The title controls are selected with `window_menu`, `window_minimize`,
`window_maximize`, `window_close`, or their bitwise combination.
Window buttons in the app bar use `[= AppName]`: click `=` for the window's
actions menu, or its name to raise it and restore it from minimized state.
Buttons keep their creation order when windows are raised, minimized or pinned.

Tab / Shift-Tab cycle focus; Ctrl-Tab / Ctrl-Shift-Tab cycle windows.
F10 or Alt-M opens the window menubar. Ctrl-G opens the system menu and
Alt-S / Alt-F10 opens Start (Alt-A still works). Ctrl-O opens Start when the focused control does
not handle it. Menus also accept h/j/k/l. Escape closes dismissable windows.
Alt-F7 and Alt-F8 enter keyboard Move and Resize; arrows move one cell,
Shift-arrows five, Enter accepts and Escape restores the original rectangle.
`parse_binding` and `app.set_keys` configure these shortcuts atomically.

`app.register(name, callback, data)` adds a desktop launcher and keeps the
desktop alive after its windows close. `app.notify(text, timeout_ms)` posts
a dismissable notification; zero leaves it visible until closed.

`msgbox_for`, `confirm_for`, `prompt_for`, `choice_for`, `list_choice_for`,
`file_pick_for`, `color_pick`, `emoji_pick` and `history_for` implement the
dialogs. Explicit owners provide window modality; `none` provides
application modality. Results live in each dialog. `prompt`, `msgbox` and
`confirm_quit` provide common shortcuts. File picking never changes cwd.
Settings is application-modal and blocks both existing and newly opened windows.

Settings use **`~/vtk.ini`**, with a `[vtk]` section. `app.settings_file(path)`
overrides the location. Enable **Window bar at top** to place the `[Start]` bar
on the first screen line, with its menus opening downward. The default is the
bottom line; `app.bar_top` (or `bar_top = 1` in the INI file) controls placement.
Settings include a desktop background color picker with live color swatches and
optional window title gradients. Active and inactive titles have separate gradient
colors. Apply previews changes; Save also keeps them for future sessions.
Enable **macOS window buttons** to place Close, the window menu (`[=]`) and Minimize
on the left, in that order, without a Maximize button. `app.macos_buttons` (or
`macos_buttons = 1` in the INI file) controls this layout; Reset restores the
default layout.
Settings persist theme colors, the bar position, visibility and clock,
shadows, inactive dimming, mouse cursor visibility, Vim mode, and move/resize
bindings. Theme presets are Borland, Light Borland, Dark, Light, Teal, Modern,
Serial and `wineight`. Selecting `wineight` enables title gradients and uses a
Windows 98-style RGB palette: teal desktop, silver controls, white fields, navy
selections and blue active titles. Inactive titles fade from gray to silver.
`app.theme` can be edited directly. Window titlebars use `title`, `title_bg` and
`title_bg_end`; dimmed inactive titles use `inactive_title`, `inactive_title_bg`
and `inactive_title_bg_end`. Gradients span the title and its window buttons.
Focused controls use the `focus_fg` and `focus_bg` pair. Dark and Modern use
RGB palettes for consistent contrast across terminal color schemes.
`color_rgb` and `color_256` provide extended colors;
Serial uses basic ANSI colors and ASCII fallbacks when gradients are off.

## Editing and rendering

Editor positions and selection anchors are UTF-8 byte offsets. Navigation
and editing preserve character boundaries. Entries enforce optional byte
limits before replacing selections and support password masking. Multiline
and Markdown views support selection, undo/redo, line numbers, wrapping,
scrollbars and manual scrolling that leaves the caret stationary.
`replace_range`, `replace_selection`, `undo`, `redo`, `begin_edit_group` and
`end_edit_group` expose the edit model.

Set a multiline control's `syntax = .diff` to highlight unified diffs with
red deletions, green additions, cyan hunks and bold file headers. Scrolling,
wrapping and selection preserve the highlighting; `.plain` is the default.

Terminal widths are measured per Unicode grapheme: default emoji, emoji presentation
selectors, skin tones, flags and ZWJ sequences occupy their shared display cells.
Drawing, alignment, wrapping and hit testing use the same widths. The terminal
parser also joins sequences delivered across separate PTY reads. Unicode emoji
properties are generated into `lib/emoji_data.v`; optional regeneration uses
`tools/unicode-width.swift`, with no Swift dependency at build time.

Mouse wheel reports keep all four directions distinct. Horizontal wheel or
trackpad travel is ignored by vertical panels, rather than becoming vertical
scrolling. Wrapped editors scroll by display rows, preserve their caret and
selection, and retain mouse capture when a wheel event arrives during a drag.

Markdown modes independently select source/rendered and editable/read-only
presentation. The V renderer handles headings, emphasis, inline code, links,
lists, task checkboxes, quotes, fenced code and pipe tables. Tables support
left/center/right alignment, inline formatting and links, escaped pipes and
code spans containing pipes. Short columns keep their natural widths while
long cells wrap to the available width; resizing recomputes the layout. Set
`md.no_wrap` for natural table widths and horizontal scrolling. Table borders
are display glyphs: selection, mouse hit testing and copying retain the original
UTF-8 Markdown source. Fenced examples and source modes stay literal.
Inline code accepts matching runs of multiple backticks. Fences retain source rows.
Code blocks use a small single-pass tokenizer for common keywords, strings,
numbers and comments, including unknown or omitted language tags. `diff` and
`patch` fences use unified diff colors; untagged blocks detect diff headers.
Use a `text` or `plaintext` fence to keep a block uncolored. Highlighting retains
source positions and code shading; an explicit `code_block.fg` overrides it.
Task clicks in View, double-clicks in Edit, and Space in View change only
the task's state byte as one undo entry. Code blocks are inert. Set
`md.task_interactive = false` for strict source viewers. `md.linkfn` receives
clicked links in read-only views or with Ctrl-click. Rulers, column width,
page separators and current-section layout are configurable through `md`.

Markdown appearance is configured per control through `md.styles`, separately
from parsing and layout. Inline code uses normal text colors and a slight
background tint rather than reverse video; fenced blocks use the same tint,
including blank lines. These defaults follow dark and light theme changes.

```v
viewer.md.styles = vtk.MarkdownStyles{
    code_shading: 5
    inline_code: vtk.MarkdownStyle{ attr: 0 }
    code_block: vtk.MarkdownStyle{ attr: 0 }
    link: vtk.MarkdownStyle{ attr: vtk.underline }
}
```

Each element style accepts optional `fg` and `bg` colors and an `attr` mask.
Styles are available for text, headings, inline code, code blocks, links, quotes,
table headers and table borders. Unset colors inherit or use the active theme;
attributes add to explicit Markdown emphasis. `code_shading` is a clamped
0–100 percentage of foreground mixed into the background (default 6); 0 disables
automatic shading. Explicit code backgrounds take priority. Selection colors
override code styling, and disabled controls retain the theme's dim foreground.

`control.vim_mode(true)` or `app.vim_set(true)` enables per-editor Normal,
Insert, Visual and Visual-line modes. Motions include h/j/k/l, w/b/W/B,
0/^/$ and gg/G; edits include i/a/I/A, o/O, J, x, dd/yy, dw/cw, p/P, undo
and redo. Insert mode also supports Emacs-style movement, cuts, paste and
transpose. Insert sessions and changes group into one undo step. Cursor
shape follows the focused editor's mode. With Vim mode enabled, j/k also
move the selection in tables, trees, radio lists and tabs.

Clipboard strings preserve explicit lengths, including NUL. `app.ctrl_c`
selects quit, ignore, copy, or callback behavior. Set `native_clipboard`
to additionally send copies through OSC 52. Ctrl-C and Tab are forwarded
to a focused terminal control; Ctrl-Tab still switches windows.

Drawing composes clipped cells and emits a single ANSI diff. Wide Unicode
characters occupy two cells and combining marks attach to the preceding
glyph. ASCII fallback changes display only. `Screen` exposes text, fill,
frame and line primitives; canvas callbacks draw in absolute cell coordinates.
`app.redraw()` and `app.snapshot()` work without opening a terminal. Canvas painters
use `screen.set_cursor(x, y, shape)` to place a caret within their clip rectangle.
Timers (`after`, `every`, `cancel_hook`) run on the event-loop thread.

The terminal control uses a Unix PTY or Windows ConPTY and an incremental
xterm subset: cursor movement, erasing, insert/delete, scroll regions, SGR,
16/256/RGB colors and UTF-8. Output is polled in bounded batches. Closing
the window releases the child process and PTY. It is not a full VT emulator.

Open a shell in a specific directory with a custom window title:

```v
mut window := app.terminal_window(
	directory: '/path/to/worktree'
	title: 'Shell: feature-worktree'
)!
window.set_text('Shell: renamed')
```

Both options are optional: `app.terminal_window()` inherits the application's
current directory and uses `Terminal` as the title. The directory is applied to
the child process without changing the application's working directory. Relative
paths resolve against the application's current directory; paths are passed
directly to the OS, so spaces and quotes need no shell escaping. Directory and
shell startup failures return an error before creating a window. Embedded
controls accept the same options: `vtk.terminal(72, 18, directory: worktree)!`;
`title` only applies to `terminal_window`.

Try `v run examples/terminal.v /path/to/worktree 'Shell: feature-worktree'`.

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
