# Vue quality follow-up

This work implements the behavior and delivery findings from the audit of
`fc2c891d5896f8c4fcd501adbd3632f03aa54e2f`. The earlier
[type and ownership cleanup](cleanup-plan.md) has its own baseline and numbering.

| Finding                              | Change                                                                                                                                                                                                      | Regression evidence                                                                                                                         |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Unsafe release output                | All six remotes share a canonical, symlink-aware preflight and verify the effective Vite output before cleanup. Repository descendants and ancestors are rejected.                                          | Actual Vite configurations, path aliases, missing tails, overrides, and preserved sentinels.                                                |
| Stale charts after server updates    | The chart controller reconciles changed snapshots, redraws samples, and rebuilds only for plot configuration changes. Equal snapshots preserve appended samples and local selection/visibility.             | Mounted workspace updates with stable widget identity and chart lifecycle tests.                                                            |
| Policy refresh race                  | A replaced read cannot turn into an uncertain mutation. Matching receipts from live projections settle the exact attempted command.                                                                         | Read/projection/reply races and recovery from an initially unconfirmed operation.                                                           |
| Policy navigation and receipt loss   | Required navigation guards cover submitted/queued effects. Phoenix persists the latest operation by organization, actor, and mission before executing it; refreshed pages recover its sequence and receipt. | Pagination, leaving/re-entering, a new LiveView, expired page tokens, duplicate sequences, actor/mission isolation, and unresolved effects. |
| Playlist navigation hangs            | Single-entry playback rearms locally. Multi-entry navigation awaits an explicit completed/cancelled/unchanged/failed result and clears its busy state.                                                      | Single-entry playback, router rejection, cancelled/unchanged/failed navigation, and lifecycle cleanup.                                      |
| Duplicated page boundaries           | Four scope-specific wrappers share envelope, UUID, captured capability, retry, and lifecycle handling; feature readers retain domain validation.                                                            | Cross-scope admission, stale responses, render failure, failed retry, and successful remount.                                               |
| Missing diagnostics                  | Local and remote boundaries emit the same bounded, allowlisted correlation record. Original causes remain in a bounded local diagnostic store.                                                              | Safe log contents, retained causes, bounded history, and visible matching references.                                                       |
| Eager frontend imports               | The shell/history remain synchronous. Page implementations and 60 public domain contributions load on demand, with timeouts, retry, and stale-load protection.                                              | Route/action suites plus cold-load, timeout, invalid module, and unmount tests. Production size and browser evidence are recorded below.    |
| Conflicting development ports        | A single fixed-port map drives all eight Vite development/preview configurations and demo URLs.                                                                                                             | Resolved Vite settings, unique ports, and package scripts without port overrides.                                                           |
| Manual acceptance                    | A checked-in GitHub workflow has independent frontend-quality and Phoenix producer/federation-browser jobs.                                                                                                 | Local execution of their gates; hosted status and branch protection require GitHub execution/configuration.                                 |
| Silent producer fixture passes       | All 29 fixture-dependent consumers explicitly skip in the ordinary suite. A separate required gate invokes real producer tests and checks a consumer execution ledger.                                      | Missing fixtures and unexecuted consumers fail the gate; inventory covers all helper callers.                                               |
| Tracked build cache and stale claims | Storybook writes build information under `node_modules/.tmp`; the tracked cache is removed. Current status is separated from the earlier historical cleanup evidence.                                       | Formatting, compiler coverage, and Git hygiene.                                                                                             |

Policy recovery retains one latest operation per actor/mission, not an unbounded receipt log.
It does not infer success from current domain state or retry an effect with an unknown outcome.
If execution was interrupted before its receipt could be recorded, the durable unconfirmed
operation keeps further effects blocked for that actor/mission. Existing Phoenix domain owners
still authorize and execute all effects. The additive database migration must be applied before
serving the updated policy page; it has been applied to this worktree's development and test databases.

## Validation

Local validation on 2026-09-12:

| Gate                           | Result                                                                                                                                                                                                                                                                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `corepack pnpm verify`         | 1,566 formatted files, 1,436 linted with zero warnings/errors, 20 strict compiler projects, and all three structural rules passed. 1,594 Vue/Storybook tests passed, including 66 Chrome stories; 29 producer-dependent tests explicitly skipped. Package build tests: 33 passed; root tooling: 72 passed; Phoenix transport tooling: 114 passed. |
| `corepack pnpm test:producers` | 148 Phoenix producer tests passed; the execution ledger confirmed all 29 fixture-dependent consumers ran their assertions.                                                                                                                                                                                                                        |
| Root `mix precommit`           | Compilation, formatting, Credo, architecture checks, 42 plane checks, and 3,961 application tests passed. The scheduler test now waits for its bootstrap continuation through the public snapshot call before asserting telemetry.                                                                                                                |
| Publication safety             | The host plus six remotes passed the existing output checker: 75 files. All 74 remote artifacts match two complete publication builds; two final host builds matched byte for byte.                                                                                                                                                               |
| Development services           | All seven remote Vite servers served their configured client URLs concurrently. The host correctly rejected occupied port 5173, preserving the existing Phoenix Vite process.                                                                                                                                                                     |
| Production browser             | Five federation/native-session checks passed. The Ops browser visited all 29 routes without asset or runtime errors and confirmed that the Phoenix-digested entry reuses the LiveView connection.                                                                                                                                                 |

The 75 primary publication artifacts match their reviewed repeated builds. Phoenix's 225
additional digested/compressed copies were checked against the corresponding primary bytes.
The reviewed host bundle is 287,151 bytes with SHA-256
`6b138c303964a2da533b9089df51045995af4d860e4e586fcb4781d5b3ca5a04`.
Its exact digest is admitted by the unchanged fail-closed publication policy.

Production initial JavaScript decreased from 1,964,076 to 486,452 bytes (75.23%). The final
manifest's static graph contains the 34-byte `app.js` entry and one shared runtime, with 21
dynamic imports from that runtime. The production root loads ES modules under `/assets/`;
the entry and lazy pages share a hashed runtime even when Phoenix digests the entry URL.
The configuration follows [Vite backend integration](https://vite.dev/guide/backend-integration)
and [Rollup entry signatures](https://rollupjs.org/configuration-options/#preserveentrysignatures).

The GitHub workflow is checked in and its local gates have been exercised. A hosted workflow
run and required branch-protection checks have not been established by this local validation.
