# Coding and refactoring rules

VTK should stay small, readable, and easy to use. Reduce production LOC by
removing duplication and unnecessary work while preserving correct behavior.
Shorter syntax alone does not make a better API.

## Good decisions to follow

- **Choose receivers by responsibility.** `Ctl` represents every widget kind.
  Keep window-only actions such as maximize, minimize, and raise on the window
  manager (`App`) while this shared model exists. Put them on a window receiver
  only when its type actually represents a window.
- **Measure the whole refactor.** Count production implementation and caller
  changes together; report tests and documentation separately. Distinguish LOC
  saved by removing duplication from changes that merely move or rename code.
- **Remove actual duplication.** Share identical behavior, callbacks, and
  validation when doing so makes the code easier to understand. Prefer deleting
  a duplicate implementation over introducing another forwarding layer.
- **Keep abstractions small and justified.** Prefer direct V code, existing
  toolkit mechanisms, the standard library, and native OS bindings. Add a helper
  or type when it removes repeated reasoning or expresses a useful constraint.
- **Keep ownership consistent.** Use the existing ownership model or validate
  an explicit app/control pairing. Callbacks must receive the app that owns the
  control, including after reparenting.
- **Preserve mutation contracts.** Account for validation, read-only state,
  byte limits, selection, undo history, notifications, and redraw scheduling.
  Make differences between loading state and editing state explicit.
- **Preserve lifecycle behavior.** Respect close vetoes, modal ownership, focus,
  hover, capture, and terminal cleanup. Account for callbacks that close,
  destroy, or reparent controls while an operation is running.
- **Make meaning visible.** Use names that identify purpose, units, and valid
  ranges. For new APIs, distinguish absence, rejection, and unchanged state
  when callers need that distinction.
- **Keep one clear public path.** When an API intentionally changes, migrate
  library callers, examples, tests, and documentation together. Keep an old
  entry point only when compatibility is an actual requirement.
- **Validate observable behavior.** Add focused regression tests for bugs and
  changed contracts. Use `make test`, `make all`, and `make check-windows` as
  appropriate to the affected code; Windows checks do not prove runtime behavior.
- **Keep changes attributable.** Establish relevant baseline failures, preserve
  unrelated local edits, and report remaining failures accurately. Keep patches
  focused enough to review their behavior and LOC impact.

## Bad decisions to avoid

- **Moving methods just to shorten calls.** `button.maximize()` is a design
  problem even if its implementation rejects buttons. A runtime kind check
  does not make an unrelated operation belong on every `Ctl`.
- **Treating existing mistakes as precedents.** An operation already exposed on
  the wrong type is a reason to reconsider it, not to spread the same pattern.
- **Adding architecture as an automatic cure.** Do not introduce widget type
  hierarchies, wrappers, interfaces, or generic dispatch merely to make a small
  refactor look cleaner. Evaluate their total code and usability cost.
- **Confusing code golf with simplification.** Do not hide control flow, pack
  unrelated statements together, or remove useful names and comments to lower
  a line count. Correctness fixes may legitimately add code.
- **Duplicating rules across callers.** Avoid repeating ownership resolution,
  validation, notification, or cleanup logic at each call site. Put a rule where
  the operation can enforce it consistently.
- **Adding more hidden meanings.** Avoid new unrelated uses of `value`, `low`,
  `high`, `link`, magic integers, or incompatible integer encodings. Avoid
  spreading unchecked `voidptr` casts through ordinary application code.
- **Bypassing invariants for convenience.** Do not mutate structural or derived
  state directly when an existing operation maintains ownership, focus, history,
  or invalidation. Do not remove required checks or cleanup to save LOC.
- **Changing policy inside a mechanical refactor.** Do not silently alter
  callback delivery, initialization side effects, modal event loops, resource
  lifetime, or error handling while renaming or moving methods. Make intended
  behavior changes explicit and test them.
- **Keeping redundant APIs without a reason.** Avoid permanent compatibility
  wrappers, aliases, and parallel implementations when all callers can migrate.
- **Inflating verification or hiding failures.** Avoid tests that only mirror
  implementation details, unrelated formatting churn, and changes to unrelated
  failing tests. Do not claim the suite passes when failures remain.
