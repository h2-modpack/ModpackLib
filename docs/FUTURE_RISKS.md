# Future Risks And Design Notes

This file records unresolved design questions that are not current user-facing
bugs, but are easy to reopen without the original context.

Use this for future investigations where the current behavior is intentional or
accepted, but a tempting cleanup has non-obvious tradeoffs.

## Activation Transactions And Integration Refresh

Current activation keeps separate transactions for hooks, integrations, and
overlays:

1. `internal.hooks.beginTransaction(owner)`
2. `internal.integrations.beginTransaction()`
3. `internal.overlays.beginTransaction(owner)`
4. refresh hooks, integrations, and overlays
5. sync coordinated runtime mutation state through `hostLifecycle.applyOnLoad(...)`
6. commit transactions only after the activation pass succeeds

This is more machinery than integrations appear to need at first glance, because
integration registration mostly updates Lib-owned registry tables. A proposed
simplification was to remove the activation-level integration transaction and
make `internal.integrations.refresh(providerId, register)` locally rollback only
registrations performed during that refresh.

That local rollback shape is coherent by itself:

- failed refresh can restore provider API entries changed during refresh
- failed refresh can remove provider entries newly added during refresh
- stale provider cleanup can still happen on successful refresh
- the global integration transaction table can be removed

The problem is activation ordering.

If integrations are moved after `hostLifecycle.applyOnLoad(...)` so they behave
like post-activation publication, then `registerIntegrations(...)` can fail
after runtime mutation state has already been applied. Activation would then
roll back hooks, overlays, integrations, and the live-host pointer, but mutation
side effects may already be live.

If integrations stay before runtime sync, a later activation failure still needs
some way to undo integration registry writes from that activation pass. That is
what the current activation-level integration transaction provides.

### Design Options

Keep the current transaction model if integration registration failure should
abort module activation.

Use local refresh rollback only if integrations are deliberately reclassified as
non-fatal publication. In that model, activation would commit the load-bearing
module behavior first, then integration registration failures would warn and
skip the integration without failing activation.

Add a broader activation transaction only if runtime mutation state is included
in the same rollback boundary. Without mutation rollback, moving fallible
publication after runtime sync weakens activation atomicity.

### Practical Rule

Do not remove `internal.integrations.beginTransaction()` just because integration
registration is table-local.

First decide whether integrations are:

- load-bearing activation capability, like hooks and overlays
- non-fatal publication after activation

Then align ordering, rollback, tests, and documentation around that decision.

### Tests To Add If This Is Reworked

- `registerIntegrations(...)` succeeds, then a later activation phase fails:
  prior provider state should be restored.
- `registerIntegrations(...)` fails after a provider update:
  old provider API should remain active.
- `registerIntegrations(...)` fails after adding a new provider:
  new provider API should not remain active.
- If integrations become non-fatal, activation should still succeed when
  integration registration fails, and the failure should be logged.
- If integrations run after runtime mutation sync, a failing integration should
  not leave the module in a half-activated runtime state.
