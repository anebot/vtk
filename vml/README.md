# VML

VML compiles declarative `.vml` UI files into ordinary `.v` functions. It follows
`../gtkaml`'s Gtkon syntax and separate constructor/composition hints, without
Vala's class resolver or an XML intermediate step. The generated application
does not load VML, JSON, or templates at runtime.

From the repository root:

```sh
make vml
./build/vmlc vml/examples/hello/ui.vml
./build/vml-hello
```

You can also use the compiler without building it first:

```sh
v run vml path/to/dialog.vml
v run vml -t vml/vtk.vmlt -o path/to/dialog.v path/to/dialog.vml
```

The bundled `vtk.vmlt` is embedded in the compiler, so the executable works from
other directories. Multiple inputs generate sibling `.v` files; `-o` accepts
one input. Existing outputs are replaced. All inputs are parsed and generated
before any output is written.

## Writing a UI

```text
Window $window title="Hello" width=40 height=12 {
    VBox expand {
        Label text="Name:";
        Entry $name text=World byte-limit=40;
        Button text="Greet" changed={greet} link={name};
    }
    -{
        app.layout()
        app.set_focus(name)
    }-
}
```

Save this as `dialog.vml`. Its generated `dialog.v` defines:

```v
pub fn build_dialog(mut app vtk.App) &vtk.Ctl
```

Compile the directory containing the generated file and your application:

```v
module main

import vtk

fn greet(mut button vtk.Ctl, mut app vtk.App) {
    name := button.link or { return }
    app.notify('Hello, ${name.text}!', 2000)
}

fn main() {
    mut app := vtk.new_app()
    build_dialog(mut app)
    app.run() or { eprintln(err) }
}
```

Use `v run path/to/app_directory`, so V compiles both files. The function name
comes from the input filename, with hyphens converted to underscores. Each file
has one root, which can be a window or a reusable control subtree. The builder
returns that root; callers can attach subtrees using the toolkit's normal APIs.

## Syntax

- `Type attributes { children }` creates a container; `Type attributes;` is a leaf.
  Empty braces work too. Whitespace and commas separate attributes; attributes
  can span lines. Leaves need `;` or `{}`.
- `key=value` and `key: value` are equivalent. Attribute hyphens become underscores.
- Single and double quoted strings support escapes such as `\n`, `\t`, `\u263a`,
  escaped quotes, and backslashes. Quoted `$` characters are literal.
- Bare words are strings: `text=Hello`. Bare numbers and `true`/`false` are V
  literals. Use `{expression}` for other V values: `changed={greet}`,
  `text-align={.center}`, `link={name}`, or an inline `fn (...) { ... }` callback.
- `expand` means `expand=true`; `!disabled` means `disabled=false`.
- `$name` gives a control a local V identifier. Names must start with a lowercase
  ASCII letter and contain letters, digits, or underscores. V keywords, `app`,
  duplicates, and the generator's `vml_` prefix are reserved. `id`, `parent`, and
  `child` are reserved attribute names.
- `#`, `//`, and `/* ... */` introduce comments. Block comments may nest.
- `-{ V statements }-` embeds builder setup code. Braces, quoted strings,
  interpolated strings, and comments inside V blocks are balanced by the parser.

Constructors are emitted first in tree order, so property expressions can refer
to any named control, including controls declared later. Constructor expressions
can only reference earlier declarations. Properties and child attachment then
run in tree order, completing each child subtree before attaching it. A node's
embedded setup blocks run after its children and its own attachment. Put setup
that needs the completed UI, such as setting focus, in the root's code block.
Named locals are available to these blocks; they are not exported as a generated
view class. Runtime updates use VTK callbacks and ordinary V state.

The parser reports filenames, lines, and columns for markup and rule errors.
V checks expression types, callback signatures, and public property names when
you compile the resulting program. This is a source generator, not a V parser
or a reactive binding system.

## Templates

`.vmlt` descriptors are JSON. `vtk.vmlt` contains the toolkit-specific rules;
the parser and generator contain no widget names or constructor APIs. To target
another V library, supply a descriptor with that library's imports and calls:

| Field | Meaning |
| --- | --- |
| `module_name` | Generated V module, default `main`. |
| `imports` | V imports emitted into the generated file. |
| `params` | Builder parameter declaration, e.g. `mut app vtk.App`. |
| `result` | Builder return type. |
| `widgets` | Map from markup tag names to widget rules. |
| `property` | Fallback assignment pattern for explicit non-constructor attributes. Omit to reject unmapped properties. |
| `properties` | Map from attribute names to setter patterns. |

Each widget rule has a `create` expression, optional `defaults` mapping attribute
names to **V source strings**, an optional `add` statement, and optional
`properties` overrides. Absence of `add` makes the widget a leaf.

```json
{
  "create": "vtk.entry({{text}}, {{byte_limit}})",
  "defaults": {"text": "''", "byte_limit": "0"}
}
```

Patterns replace `{{attribute}}` with the input's V expression or its descriptor
default. `{{id}}` is the current local variable. In a parent's `add` rule,
`{{parent}}` and `{{child}}` are the two local names, while other placeholders
come from the **child's** attributes and defaults. For example, VTK tabs use:

```json
{"create": "vtk.tabs()", "add": "{{parent}}.add_tab({{title}}, mut {{child}})"}
```

```text
Tabs {
    VBox title=General { Label text=Settings; }
    VBox title=About { Label text=VML; }
}
```

Attributes consumed by `create` or the incoming `add` rule do not also become
property assignments. Remaining explicit attributes use the widget's property
override, the template's override, or its fallback pattern, in that order.
Property patterns receive `{{id}}`, `{{name}}`, and `{{value}}`. Defaults supply
placeholder values only; they do not generate extra property assignments.
Substitution happens once, preserving literal `{{...}}` inside user strings.

The VTK descriptor uses public constructors and attachment methods, and maps
`text` and `value` property updates to `set_text` and `set_value`. Other properties
become ordinary public field assignments. `Table`, `Canvas`, and `DatePicker`
require `fetch`, `paint`/dimensions, and `initial` expressions respectively.
Combos and radios accept `Item text=...;` children. Menus, tree-node composition,
and terminal lifecycle setup remain ordinary V code in this first version.

Run `v test vml` for parser, descriptor, CLI, and headless generated-UI tests.
The checked-in example output is verified against its `.vml` input by the tests.
