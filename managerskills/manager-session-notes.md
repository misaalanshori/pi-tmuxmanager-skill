# Manager session notes — project log (out of tree)

Running log of standing instructions, owner directives, and findings for this
management session. Append-only. Read this at the start of every cycle.

---

## 2026-10-27 — Session open

**Topology:** single worker (`tmux -L agent-mgr`, session `worker-1`), main/default
branch only — no branches, no worktrees, no merges/rebase. Manager owns `main`;
worker commits and pushes directly to it. If the worker creates a branch, it is a
deviation to flag at review.

**Worker:** `opendesign/deepseek-v4.1-flash`, `/thinking high`, fallbacks
`antigravity/gemini-3.8-flash`, `opendesign/mimo-v2.6-flash`.
Session uuid `01a17d40-93f9-75d6-a33f-eabbc3b7ac78` (primed 2026-10-27).

**Local toolchain:** `rust-toolchain.toml` says `channel = "stable"`, which
resolves to rustc **1.98.1** on this box. Installed additionally:
`1.99.0` (+ `x86_64-unknown-linux-musl` target) so cross-target checks are
possible locally.

---

## Owner directive (2026-10-27): NO context-window anxiety, NO time anxiety

Standing instruction, restated by the owner mid-session:

> "Zero context window anxiety please, do not overthink context usage or work
> duration, take your time on your work."

Concretely, for this session:

- Do **not** compact, re-prime, or recycle the worker to "save context". The
  worker has a 1M-token window and has been running at under 10%. A cycle that
  uses 40% of it is a normal cycle, not a problem.
- Do **not** shorten a brief, skip a phase, batch unrelated issues, or accept a
  shallow review to "save time". Take the long way when the long way is correct.
- Do **not** poll. One blocking `worker-wait.sh` call per wait, 1–1.5 hours is
  the normal ceiling. The manager sleeps; the worker works.
- Do **not** second-guess an idle worker that is simply thinking. A frozen
  context % over ~15–20 min with `● Working` still means "check the log
  timestamp", not "interrupt to be safe".
- Brainstorm here, in the notes, rather than in the worker's pane. The pane is
  for dispatch and steering, not for the manager thinking out loud.
- The one thing that *is* urgent: an idle worker with nothing dispatched. An
  idle worker is a defect. Re-dispatch is part of the cycle, not after it.

---

## Observed state at session open (ground truth, verified)

- **224 open issues**, all authored by `misaalanshori`, **0 closed**.
  Numbered 1–224. Body text mirrors `ISSUE-0001`..`ISSUE-0224` from the two
  audit indexes in `../<project>_audit_and_remediation_plan/`.
- **CI is RED on `master`** — three consecutive failed runs:
  - `40430914540` (HEAD `ac385e5`) — `test (x86_64-unknown-linux-musl)` fails
  - `40410653618` (`9f14798`) — same leg fails
  - `40238192346` (`7cc2e4d`) — `governance` job fails at `Check formatting`
  - `40154440168` — `governance` fails at doc consistency/traceability
- Every other leg (linux-gnu, aarch64 gnu/musl, macOS) passes.

### RCA of the musl leg (verified, not guessed)

Commit `e28f84a` ("bigbang(everything)") changed `rust-toolchain.toml` from
`channel = "1.99.0"` to `channel = "stable"`. CI's job installs toolchain
`1.99.0` **plus** the `x86_64-unknown-linux-musl` target via
`dtolnay/rust-toolchain`; the repo-local `rust-toolchain.toml` then **overrides**
the active toolchain to `stable` (the run log says so verbatim:
`note that the toolchain 'stable-x86_64-unknown-linux-gnu' is currently in use
(overridden by '.../rust-toolchain.toml')`). `stable` has no musl target
installed → `can't find crate for core` / `std`.

So: **the file pin change broke the cross-target legs.** The fix direction is
either (a) put the version pin back in `rust-toolchain.toml` (and keep it in sync
with CI + Docker + README), or (b) make CI stop relying on a file-overridden
channel. This is exactly what **ISSUE-0038** describes, and that issue's stated
resolution is "one consistent toolchain specification across all five files".
Issue 38 is the natural Tier-1 target: it is cheap (config/docs), it is the
*current* red-CI cause, and a green `master` is a precondition for trusting any
later cycle's CI evidence.

### Note on `Cargo.toml` MSRV

`Cargo.toml` says `rust-version = "1.95"` while everything else says 1.99.0.
Issue 38 says to document the MSRV **and** the pinned channel so the two are not
read as contradictory. Do not silently bump MSRV; document and align.

---

## Worker priming output (2026-10-27, session `01a17d40`)

Two priming prompts completed. What the worker reported, condensed:

**Doc-level understanding:** transparent reverse proxy + load balancer + usage
governance engine for coding agents; safe Rust, SQLite WAL, multi-tenant,
session affinity, SSRF defense. It flagged, unprompted, that the docs read
ahead of the code ("README and docs describe v1.0 as delivered, but nothing I
read confirmed that").

**Code-level bearings:** read ~15 files in depth (not all 312), ran the full
test suite once plus 5 repeats of a failing test. Notable claims to verify
before trusting:

- the suite has at least one **repeating** failure (5 repeats) — needs the test
  name and mechanism extracted before it becomes a brief
- it observed a possible **transcoding vs ADR-6** conflict
- perf claims (overhead ms, req/s, idle RSS) unverified — expected, it did not
  run benches

Disk after priming: `target/` 16 GB, free 105 GB. Healthy.

---

## Queue shape (for prioritization, not recency)

The two audit indexes are the reference for *order*, GitHub is the reference for
*state*. Phase order from the primary index:

1. **Phase 1** (13) — critical security/auth/data-plane correctness:
   `ISSUE-0001` argon2 self-deadlock, `ISSUE-0002` non-RFC CSRF HMAC +
   static key, `ISSUE-0003` pool-tier encoding, `ISSUE-0004` reserved-in-flight
   headroom, `ISSUE-0005` `stable_counter_id` collision, `ISSUE-0007` trace-tap
   CAS race, `ISSUE-0009` `inherit` scope, `ISSUE-0031`, `ISSUE-0045`,
   `ISSUE-0046`, `ISSUE-0050` SSRF IPv6, `ISSUE-0058`, `ISSUE-0059`.
2. **Phase 2** (15) — docs alignment, fake-preset removal, governance gates.
   Contains `ISSUE-0038` (the red-CI toolchain issue).
3. **Phase 3** (34), **Phase 4** (62).
4. Supplemental `ISSUE-0125`–`0224`: S1 stubs (20), S2 data-plane gaps (25),
   S3 control-plane gaps (25), S4 half-baked UI (15), S5 missing tests (15).

**Value × cost lens** (the owner's prioritization law, above recency):
- highest value now = green `master`. Cheap, unblocks trustworthy CI evidence
  for every subsequent cycle.
- next = Phase 1 criticals, because they are real defects in shipped paths and
  each is small and well-scoped (`ISSUE-0001`, `ISSUE-0002`, `ISSUE-0004`,
  `ISSUE-0005`, `ISSUE-0007` are all single-file).
- `ISSUE-0003` (pool-tier encoding) is Critical but spans four crates — batch it
  alone, never with anything else.
- the Phase 4 epics (`ISSUE-0010`, `ISSUE-0019`, `ISSUE-0022`–`0024`) are big;
  phase them, land value early.

---

## Manager discipline reminders specific to this repo

- The whole `crates/proto/src/providers/*.rs` tree (~16k LOC across 80 modules)
  is scheduled for deletion by `ISSUE-0010`. Do **not** spend cycles polishing
  files that issue will delete; check whether a target file survives Phase 4
  before briefing work in it.
- `xtask` gates (`doc-consistency`, `docs-bundle --check`, `migration-check`,
  `traceability --milestone M6`) run in CI's governance job. A docs edit can
  redden CI without any Rust change — run those four locally on docs cycles.
- CI pins `1.99.0` in `.github/workflows/{ci,release}.yml`; `Dockerfile` pins a
  digest of `rust:1.99.0-bookworm`. Any toolchain alignment must touch all of
  them or none.

---

## Cycle ledger (this session)

| Cycle | Issues | Commits | CI run | Tests | Notes |
|---|---|---|---|---|---|
| 1 | #38 (toolchain/MSRV) + shutdown-cut test hole | `471efe3`, `4b1cd79` | `40514391678` ✅ | 636 | First green `master` since 2026-10-25 |
| 2 | #1 (login deadlock), #2 (CSRF HMAC), #45, #46 (declined w/ rationale) | `6be8685`, `81e2e7f`, `bdfba72` | `40530668461` ✅ | 647 | |
| 3 | #4 (in-flight in admission), #5 (counter ids) | `ed9df54`, `a015226`, `758b129` | `40540453295` ✅ | 657 | |
| 4 | #7 (trace budget atomicity + wrap) | `f35b345`, `92cf2bd` | `40547147332` ✅ | 664 | Provider 503 mid-cycle → resumed, no work lost |
| 5 | #59 (bounded failure maps) | `3e5ff89`, `75958aa`, `f53e336` | `40554053041` ✅ | 673 | Also extracted `login_limiter.rs`, fixing a 1,204-line file breach |

| 6 | #9 (inherit scope on both bypassing paths) | `ff24cb5`, `59b1480` | `40561510802` ✅ | 680 | Also closed stale #3, #50, #58 |
| 7 | #147 (decompress before budget semaphore) | `01aeecd`, `a381865` | `40566836151` ✅ | 685 | |
| 8 | #148 (non-streaming latency always 0 → P2C EWMA poisoned) | `d0f80d0`, `75d6c3d` | `40570683567` ✅ | 687 | One-line production change |
| 9 | #145 (count_tokens gate gaps) | `6495e9d`, `f033094` | `40575102262` ✅ | 692 | Shared-gate extraction; also cut state_bound 1,241→1,192 |
| 10 | #149 (charged timeout dropped its ledger row) | `cc2b203` | `40579738700` ✅ | 696 | Billing integrity: money charged, no row |
| 11 | #150 + #151 (embedded rejection + G7 refusal dropped rows) | `e24c0e3` | `40583456998` ✅ | 703 | Worker found 2 sites I missed, refuted 1 I claimed |
| 12 | #225 (filed here: decompose `pipeline.rs`) | `0b7273e`, `cec8f8c`, `d2c5f22` | `40587834311` ✅ | 703 | Pure refactor: 1,476 → 1,245; headroom 124 → 355 |
| 13 | #152 (failed 429 retry reused stale 429) + #153 (terminal event dropped session_hash/pin_outcome) | `46d1676` | `40591215295` ✅ | 710 | |
| 14 | #154 (metrics: missing token classes + list cost) | `4093451` | — | 718 | Correct fix, one weak test |
| 14fix | my audit finding: that test had no teeth | `89d7e80` | `40598634833` ✅ | 718 | Test-only, verifiably discriminating |
| 15 | #146 (count_tokens failover + fake 200) | `1bdeeef` (red), `f50f488` | `40602308211` ✅ | 728 | TDD visible in git log |
| 16 | #155 (state-bound gates) + #156 (fake 200 on decode) | `f9c9bc2` (red), `5e8815f` | `40605055105` ✅ | 732 | #155 needed **no code change** |
| 17 | #171 (unapproved custom shares + key-label leak) | `b4c5704` (red), `4ca04ba`, `3177983` | `40609043868` ✅ | 740 | Also found+fixed a TPM window race → filed #226 |
| 18 | #182 (preferences rebuild) + #192 (price delete 404) + #193 (SA pin eviction) | `89ccf48` (red), `50c81a8`, `79fe7ea`, `92a58e6` | `40612218736` ✅ | 748 | Worker corrected me twice, both times right |
| 19 | #189 + #190 (both false) + #221 (the real gap: tests) | `d2f0908`, `650a4d2` | `40615385737` ✅ | 754 | Verification cycle: zero production edits |
| 20 | #188 (cookie `Secure` — issue was **inverted**) | `f907705` (red), `d315b6b` | `40618599232` ✅ | 761 | Also filed #227 (A4 Rustls listener does not exist) |
| 21 | #191 (share approval) + #194 (retention purge did nothing) | `008af40`, `544d41c` (red), `bc9d664`, `d5448c3` | `40621485001` ✅ | 771 | #194 was far worse than filed |
| 22 | #173 (Logs Explorer total) + #176 (ledger reasoning) | `ca85a2d` (red), `d2e3622`, `53ff1b9`, `7b82fb2` | `40625690229` ✅ | 778 | Worker caught an arithmetic error in my brief |
| 23 | #175 (usage endpoints ignored their filters) | `3b23335` (red), `8d82ff2`, `63d5bc3`, `6d60ac0` | `40629180912` ✅ | 785 | 2 mutants SURVIVED → tests added |
| 24 | #143 (CSV) + #144 (audit log) + #142 (ledger initiator) | `393dfde` (red), `75f9060`, `4adc051` | `40632906825` ✅ | 796 | Traceability gate caught MY bad `SEC-20` citation |
| 25 | #174 (log detail drawer) | `8187bd1` (red), `46abc25` | `40635564211` ✅ | 805 | Found #228 (drawer invents an attempt) |
| 26 | #137 (zero-key session hash) + #138 (master-key audit derivation) | `6e64829` | `40637944820` ✅ | 815 | **#138 was a real ADR-11 violation** |
| 27 | family sweep: zero `instance_id` = wrong HKDF salt (filed #229) | `d9226b5`, `3231a0c` | `40642127140` ✅ | 827 | Third instance of the secret-fallback family |
| 28 | #129 (invented model id — **mine**) + #128 (13 discarded label validations) | `563f77d` (red), `757a458` | `40647619266` ✅ | 834 | `cargo clean` freed 73 GB mid-session |
| 29 | #130, #131, #132, #133 (four hardcoded config values) | 4 red+fix pairs | `40653326882` ✅ | 846 | Found #230: `control_plane_logs` never swept |
| 30 | #230 (`control_plane_logs` unbounded) | `2a426d6` (red), `4fa3374` | `40657168659` ✅ | 852 | Also deleted the dead `run_retention_pass` |
| 31 | #13 (split `app.js`) + #56 (static-asset gate) | `e1c64c4` (red), `d38a059`, `225152c`, `e1e62e4` | `40662183628` ✅ | 858 | 1,649 → 12 modules, max 450; filed #231 |
| 32 | #170 (`patch_admin_model`) | `a8f9933` (red), `25eff38` | `40668691650` ✅ | 868 | 2 of 4 requested fields declined w/ reason |
| 33 | #178 (key probe) + alias-delete bypass | `d24ff80` (red), `6c6460a` | `40673641180` ✅ | 877 | 9-site sweep → filed #232, #233 |
| 34 | #180 (Argon2 under write lock) + #181 (role coercion) | `1d81b12` (red), `26fe8c1`, `113ce61` | `40686534256` ✅ | 884 | Found the same defect 1 layer deeper |
| 35 | #183 (doctor schema version) + #179 (price sync byte cap) | `5e4a79b` (red), `bcc88e6` | `40706634738` ✅ | 896 | Corrected my exit-code advice with a spec citation |
| 35f | #183 fix-up (loader delegation + drift by direction) | `fa15046` (red), `375a37c` | `40717134828` ✅ | 903 | Found MAX()-NULL bug via the unreadable arm |
| 36 | #232 (pin move discarded result) + #233 (route pref bypass) | `1661eb5` (red), `375c17a` | `40774771799` ✅ | 915 | #233's premise refuted by measurement |
| 37 | #231 (setting key into element id) | `32aefed` (red), `615238c` | `40778533261` ✅ | 919 | Wrote a census test that has teeth, then proved it |
| 38 | #227 (silent TLS ignore) + #228 (invented attempt) | `c6f9792` (red), `4c16260`, `07d4e03` | `40790153483` ✅ | 927 | Steered out of an unbounded-red-test hang; CI flake fixed by deleting coverage |
| 39 | #186 (hourly anchor) + #187 (plaintext repeater) | `86d7f18` (red), `be94f36` | `40796142821` ✅ | 940 | `PeriodicTask` helper; `fetch_max` for NTP-backdated rows |
| 40 | #184 (nested credential leak) + #210 (doctor/export tests) | `2b25337` (red), `cf88609` | `40799721604` ✅ | 952 | Pre-fix receipt: 5 marker leaks; found the `{name,value}` shape |
| 41 | #172 (tenant audit visibility) | `16fd8e1` (red), `ed495b2` | `40803426364` ✅ | 962 | Found a doc citing a test that did not exist |
| 41f | #172 fix-up (the phantom test) | `567a32f` | `40805629313` ✅ | 963 | Killed mutant: 13th `?` with no bind |
| 42 | #169 (pin capacity reclaim) | `6e39102` (red), `9d87ad4` | `40809206764` ✅ | 969 | **My RCA wrong twice**; my design violated two specs |
| 43 | #168 (live pins in the view) | `cdb0aa3` (red), `f30a14c` | `40816147248` ✅ | 978 | All 3 named handlers nonexistent; spec settled my open question |
| 44 | #167 (pin move eligibility) | `905696c` (red), `53c98b1` | ✅ | 999 | `14.t.4` prescribed the fix + the error code verbatim |
| 45 | #165 (trace `$blk` rehydration) | `2ada51a` (red), `3073721` | ✅ | 1019 | Reused cycle 43's placeholder builder; filed #235 |
| 46 | #164 (prices by upstream id) + #235 (user move filter) | `a02187a` (red), `496f646` | ✅ | 1032 | Invented $ rates were being *displayed*; e2e tests caught over-fix |
| 47 | #34, #36, #37, #55 (doc drift, 4 issues) | `d052c5f` (red), `e461cbb` | ✅ | 1037 | 3 new doc↔code guards; 1 issue already-satisfied |
| 48 | #162 (budget offset period) + #163 (price API round-trip) | `fd45bbe`, `cd25f65` | ✅ | 1059 | Round-trip test found a data-loss bug in PUT |
| 49 | #160 + #161 (**both already fixed**) | `8007b9b`, `993c3bf` | ✅ | 1063 | Verification cycle: tests only, zero prod edits |

Closed so far (14): #1, #2, #3, #4, #5, #7, #9, #38, #45, #46, #50, #58, #59, #147, #148.
**Phase 1 fully drained. Phase S2 (P0 data-plane) started.**
Open: 210.

Disk note: `target/` reached 62 GB at cycle 8's end. Free is still 113 GB, so no
`cargo clean` is required yet, but it is worth watching — it grew from 53 to 62 GB
across cycles 7-8 as the suite grew.

### Bonus value from cycle 5 (worth remembering)

The worker found a **latent logic bug I had only posed as a question**:
`record_success` cleared only the `(username, IP)` tier, so a user who mistyped
their password 50 times within an hour stayed escalated to `EnforceTotpOrDelay`
**forever**, even after a successful login. It now also clears the username tier
(and deliberately still leaves the per-IP tier, since one success from an address
does not clear that address for attacking other accounts). That is a real
user-facing defect that was not in any issue.

Lesson: "check whether this is intended, don't change it silently" in a brief
produces better findings than "don't touch it". Keep posing questions.

### CORRECTION (cycle 10): MNT-3 *is* enforced — at 1,600 lines, by a test

My earlier note was wrong. `crates/server/tests/workspace_boundaries.rs:451-476`
(`all_rust_files_are_under_1600_lines`) walks `crates/`, `tests/`, `benches/`,
`xtask/`, `fuzz/` and fails on any `.rs` file above **1,600** lines. It is a real,
running gate in the default suite. I had only grepped `xtask/src/source_scan.rs`,
which is a *different* governance surface (Spec/Trace annotation coverage), and
concluded no gate existed. Lesson: "I grepped one place and found nothing" is not
"nothing exists" — grep the whole workspace before writing a finding into the notes.

What is still true: the **1,200-line** figure in the playbooks/review checklist has
no enforcement anywhere, so files between 1,200 and 1,600 are legal-but-over-budget.
`crates/proxy/src/orchestrator/pipeline.rs` is now **1,413** — under the real gate,
over the convention, and growing. Worth a decomposition cycle before it approaches
1,600. #24 (decompose `admit_inbound_request`/`routes.rs`) and #19/#23 are the
relevant issues; `pipeline.rs` itself is not explicitly covered by one, so consider
filing a decomposition issue for it.

Also worth noting: the worker hit this gate for real in cycle 10 — adding the new
tests inline pushed `integration_streaming_accounting.rs` past 1,600, so it created
`integration_streaming_accounting/charged_timeout_ledger.rs` instead. The gate shaped
the change correctly, which is what a gate is for.

### Recurring finding: audit-issue premises are often stale

Four issues in a row had factually wrong bodies, verified against the tree:

- #1: claimed `spawn_blocking` was missing (it was present); claimed
  `Semaphore::new(4)` hardcoded (it is `available_parallelism`); claimed a
  permanent freeze (the 2s timeout makes it a 503 stall).
- #2/#45: named `crates/admin/src/csrf.rs`, which **does not exist**.
- #4: the contrast was inverted — no `effective_used` impl included in-flight,
  not "one did, two didn't".
- #5: claimed `dedup_by_key` on `counter_id`; **no dedup exists anywhere**. The
  stated consequence (a window silently dropped, spend bypassing a cap) never
  existed. The underlying defect was still real for other reasons.
- #7: named `MAX_GLOBAL_IN_FLIGHT_BYTES = 64 MiB` (doesn't exist; real ones are
  `GLOBAL_TRACE_BUDGET_BYTES`, 256 MiB, runtime-settable) and `push_block` (it is
  `try_feed_chunk`).

**Standing rule for every future brief:** verify each issue's file paths, line
numbers, constants and function names against the tree *before* writing the
brief, and list the corrections explicitly in the brief AND in the GitHub design
comment. This costs ~5 minutes and has caught a wrong premise every single cycle.

### Cycle-2 finding I am carrying, not fixed

`crates/admin/src/auth.rs:1179` now has
`.unwrap_or_else(|_| unreachable!("HMAC-SHA256 accepts keys of any length"))` in
the production CSRF path. It is genuinely unreachable (HMAC accepts any key
length), but this project forbids panics in production code, and they rejected
`expect()`. Should become a non-panicking fallback — e.g. return
`sha256_hex(b"invalid-csrf-key" || token)` on the impossible branch, or change the
signature to `Result` and have the one caller treat it as 500. Small, worth doing
in a cleanup cycle rather than spending a whole cycle on it. **Do not let it
survive to release.**


---

## Phase 1 complete (cycles 1-6). Starting the P0 data-plane set (Phase S2).

### Stale-premise issues closed with evidence, not work

Three Phase-1 issues turned out to be already satisfied or non-reproducible. Each
got a full evidence comment before closing — that is the right shape: the comment is
the artifact, so a future reader can check the claim rather than trusting a close.

- **#3** (tier encoding): both enums are `Own=0/Shared=1/Global=2/Blended=3` with
  matching `from_u8`/`from_code`, a single exhaustive conversion `match`, and an
  existing test (`rbac::tests::ownership_routing_and_pool_tiers_match_the_closed_contract`)
  pinning every value. The label leak it feared is produced by `provider_scope_label`
  from `OwnershipScope`+`share_id`, not from the numeric tier — so the encoding was
  never on that path.
- **#50** (SSRF IPv6): already blocks `2001::/23` (incl. Teredo), `2001:db8::/32`, and
  **both** NAT64 prefixes, and it *unwraps* NAT64/IPv4-mapped to recurse into the IPv4
  block list — strictly better than the blanket block the issue asked for.
- **#58** (413 masked by `u32::try_from`): no `try_acquire_bytes`, no `u32::try_from`.
  The method returns `BodyTooLarge` **before** any conversion, and uses an `as u32`
  cast on an already-bounded value. Mechanism has no code path.

### Cycle 7 note: closing a P0 with a real mechanism

#147 was the first *non-stale* P0 and worth the detail: decompression ran before the
budget semaphore, so N concurrent compressed requests could allocate N × 16 MiB while
the budget read "free". Worth remembering that the issue's own prescription
("reserve the compressed wire bytes first") was **wrong** — compressed size is not the
conserved resource; a 1 KB gzip body legitimately expands to 16 MiB. Reservations must
be denominated in what is actually being conserved.

Also: the per-request bomb defence already worked and was already tested. The unbounded
thing was concurrency. Keeping "one body is fine" and "N bodies are not" distinct is
what made the fix small.

### Reviewer lesson from cycle 6 (important, do not repeat)

I mutated `listeners.rs` back to the buggy `parse_scope` and the tests **passed** —
because my grep filter (`-E 'test(inherit)'`) happened to select only the
*non-discriminating* tests. The test named
`visible_models_resolves_inherit_against_the_user_default` passes with **and** without
the fix, because `PersonalFirst` (the buggy fallback) also includes the global tier.
Only `visible_models_does_not_widen_a_strict_user_scope` fails without the fix.

Two rules out of this:
1. **Mutate, then run the whole module, not a name-filtered subset.** A filter can
   select exactly the tests that cannot fail.
2. **A test whose name says "resolves X" may be vacuous if the buggy fallback also
   satisfies it.** The discriminating direction is the *narrowing* one. In cycle 7 I
   applied this: the reservation test only fails with the bug because I checked the
   worst-case reservation specifically.


---

## Cycle 11: the worker corrected me twice, and both corrections were right

Worth recording in detail, because it is the pattern that has made these cycles work.

**I claimed** the non-retryable-4xx passthrough at
`attempt_non_streaming.rs:233-248` was a dropped-ledger site. **It is not.** Every non-2xx
is intercepted at `pipeline.rs:777` (`if !status.is_success()`) *before*
`handle_non_streaming_attempt` is ever called, and that path already enqueues. I verified
the refutation myself at `:777` and `:1341` — the worker is right, and the two tests it
wrote for that path pass before and after, correctly kept as status-quo pins.

**I missed two real sites:**
1. **Streaming first-frame `RequestRejected`** (`attempt_streaming.rs`) — worse than the
   non-streaming case: it computes a `failure_charge`, pushes the attempt, returns
   400/403, and records nothing. So money was committed with no ledger row. That is
   exactly the defect class of #149, on the streaming side, and I had explicitly told the
   worker to only *investigate* it.
2. **Gate G7 refusal is at `admission.rs:772`, not `pipeline.rs:1332`.** The client-key
   monthly cap is enforced in admission, before the attempt loop. `pipeline.rs`'s
   `last_cap_error` tail is a *different* case (a candidate's share/global cap). Both now
   enqueue; only the G7 site correctly has `None`/`None`/`None` attribution since no
   upstream call happened.

Also: cycle 10's report said the streaming rejection branch was "unreachable with the mock
harness". That was true for the *timeout* abort it was discussing, but not for the
rejection branch — a `StreamRequestRejected` mock reaches it fine. The worker drew that
distinction itself.

**Lesson for me, restated:** my line-number-based RCA is a *hypothesis generator*, not a
finding. Every cycle where the worker verified independently, it improved the diagnosis.
The briefs already say "verify, and if the evidence refutes me say so plainly" — that
clause is load-bearing and should stay in every brief.

### Line-count situation after cycle 11

`pipeline.rs` **1,476** (was 1,413; MNT-3 hard gate is 1,600 via
`workspace_boundaries::all_rust_files_are_under_1600_lines`). That is 124 lines of
headroom. **The next cycle that touches `pipeline.rs` should extract something, not add.**
The natural candidate is the terminal-usage call block, or splitting the file along the
`handle_*_attempt` seam. `pipeline.rs` has no decomposition issue of its own — worth
filing one.


---

## Cycle 12 verified as a genuine pure refactor

Three checks, all clean:
1. **Test count unchanged** at 703 before and after — no tests added, removed, or renamed.
2. **Zero test files touched** (`git diff --name-only` shows only `CHANGELOG.md`, the two
   new modules, `mod.rs`, `pipeline.rs`).
3. **Moved code is byte-identical** — I diffed `TerminalUsageFacts` and
   `enqueue_terminal_usage` between `e24c0e3:pipeline.rs` and the new
   `terminal_accounting.rs`: identical, doc comments included.

Final layout: `pipeline.rs` 1,245 (−231), `terminal_accounting.rs` 119,
`attempt_body.rs` 221. MNT-3 headroom went from **124 lines to 355**.

The worker substituted my planned step 2 (non-2xx interception) with a better seam:
`attempt_body.rs`, the 151-line outbound body/header preparation block (session field
editing, cross-key failover sanitisation, cross-protocol transcoding, preset
normalization, cache rewrites, header synthesis). Its justification was that the body-prep
block is what #152/#154 will add to, so extracting it caps future growth at the true churn
point. That is a better read of the file than mine.

### Current session totals

| | |
|---|---|
| Cycles completed | 12 |
| Issues closed | **20** — #1,2,3,4,5,7,9,38,45,46,50,58,59,145,147,148,149,150,151,225 |
| New issue filed | #225 (pipeline decomposition — landed same night) |
| Tests | 636 → **703** (+67) |
| `master` | green continuously since cycle 1; 12 consecutive green CI runs |
| Convention violations | none outstanding; `pipeline.rs` back under budget with 355 lines of headroom |

### Next queue (value × cost)

**Cheap, same seam, helper already exists:** #152 (stale 429 reuse on second-attempt
timeout), #153 (terminal event drops `session_hash`/`pin_outcome`), #154 (metrics omit
cache-write/reasoning/plan-multiplier). All three now touch `terminal_accounting.rs`
rather than a 1,476-line file, so each should be a small cycle.

**Then:** #146 (count_tokens failover — pairs with #145), #155/#156 (state-bound responses
gates + decompression error as 502), then the S3 control-plane batch (#170-#194), then S4
UI (#195-#209), S5 tests (#210-#224).

**Still parked:** the `unreachable!` at `crates/admin/src/auth.rs:1179` (cycle 2
carry-over). It is genuinely unreachable but violates the no-panic-in-prod rule. Needs a
small cleanup cycle, not a full cycle of its own — fold it into whichever cycle next
touches `auth.rs`.


---

## /compact executed at the first real boundary (owner reminder)

I had let the worker reach **78.1%** before compacting, which is well past the 45% rule.
The owner had to remind me. Correcting the habit below.

**Why I delayed, and why that was wrong:** each cycle ended green and I re-dispatched
immediately, treating "the tree is clean" as the only boundary condition. But compaction is
*also* a boundary — a clean tree is exactly when it is safe, so every cycle end since ~45%
was a valid compact point and I skipped all of them.

**Result:** `/compact` at 78.1% → **3.5%** verified (818,703 tokens compacted, confirmed by
a probe turn because the footer shows `?` until the next turn recomputes it). It worked
fine at 78%, but had it failed — and this project has seen `/compact` fail silently with
"generation hit the token cap" — recovery would have meant recycling the session and
repriming, which is the expensive path.

**The rule, restated as a checklist item rather than a judgement call:** after the reviewer
confirms a cycle is done and the tree is clean, **check the footer**; if ≥45%, `/compact`
*before* writing the next brief. Not after. Not "next time". The brief-writing time is
exactly when the worker sits idle and the context keeps growing.

Verification method worth keeping: after `/compact`, the footer shows `?` until the next
turn. Send a trivial probe (`reply with just the word: ready`) and read the footer on the
resulting turn — that is the durable proof, not the `[compaction]` marker alone.


---

## Cycle 16: #155 was almost entirely wrong, and the worker proved it

I halved the issue (said 3 of 5 named controls were not applicable). The worker went
further and refuted **four of the five**, with evidence I then verified myself:

| # | Control #155 named | Reality |
|---|---|---|
| 1 | `state.budget_semaphore` | **No inbound body exists.** Signature takes `inbound: &HeaderMap`; all four callers pass headers only. GET/DELETE/cancel are bodyless. |
| 2 | `check_transfer_encoding_smuggling` | No request body ⇒ no framing to adjudicate. |
| 3 | `client_rpm` | **Already enforced.** `auth.rs:421` sets `is_inference` with `path.starts_with("/v1/responses")`, which prefix-matches `/v1/responses/{id}` — so G5 runs. Worker verified empirically with a throwaway probe (`rate_limit_rpm = 1`, two requests, second gets 429), not just by reading. |
| 4 | `upstream_rpm` | **Does not exist.** No schema column, no symbol, no SRDD passage — I confirmed with `rg` over `crates/` and `docs/`. |
| 5 | `upstream_concurrency` | **Does not exist.** Same. Only semaphores in the proxy are the preflight body budget and the `/usage` poller's 8-permit global. |

So #155 required **no code change at all**, and closed with that finding. Two of the five
controls it demanded are features that were never built; asking for them in a remediation
issue is a category error, not a gap.

**The pattern, now unmistakable across 16 cycles:** these audit issues were generated from a
static read of the code and a spec, so they systematically (a) cite stale line numbers,
(b) name non-existent symbols, (c) describe controls as "missing" that exist elsewhere in
the stack (middleware, router prefixes), and (d) demand features that were never specified.
The brief's correction table has caught something in **every single cycle**. That table is
now the highest-value part of the brief-writing process, not boilerplate.

### Cycle 16 also added a genuinely useful status-quo pin

`state_bound_response_op_is_not_budget_semaphore_gated` asserts the op succeeds with the
preflight budget saturated *because there is no body to admit*. Without it, a future reader
taking #155's text at face value would add a body gate and make bodyless operations fail
under load. That is the right shape: a test that encodes "we deliberately do not do this,
and here is why" is worth as much as one that encodes "we do this".


---

## Cycle 17: an out-of-scope fix I decided to accept, and why

The worker pushed **three** commits for a two-issue cycle. The third (`3177983`) fixes
`try_consume_client_key_tpm` in `crates/core` — which my brief had marked **out of scope**.

**I accepted it.** Reasoning, recorded because "worker exceeded scope" is normally a finding:

1. **It was found through our own CI**, not through wandering. Its cycle's push went red on
   `aarch64-apple-darwin`; the worker investigated its own failure rather than re-running
   until green, which is exactly the behaviour I want.
2. **It diagnosed rather than dismissed.** 0/12 isolated, 0/15 whole-binary locally, job green
   on three previous runs — the pattern *looks* like a flake, and the correct move was to
   make the race deterministic before calling it one. It did that.
3. **It is a real production bug**, not a test artifact: a client can exceed its `rate_limit_tpm`
   by timing requests across a minute boundary, worst case ~2× within 1 ms.
4. **It kept `master` green in one push** rather than leaving a red commit behind.
5. The pre-existing window test still passes **unmodified**, and I mutation-checked the new
   test myself (restoring the minute-keyed comparison fails it).

What I did **not** accept silently:
- I filed **#226** for it and closed it with the commit, so the bug has a tracked record
  rather than existing only in a commit message. A production rate-limit bypass that lives
  only in `git log` will be re-introduced.
- I **corrected its claim**. The commit says "which is what 'sliding-minute limit' means". It
  is not: it is a **fixed window anchored at the first request of a burst**. A true sliding
  window would additionally deny `limit/2` at `t=0` + `limit/2` at `t=59s` + `limit/2` at
  `t=61s`; the anchored window permits that because its window restarts at `t=60s`. The
  anchored form closes the *exploitable* hole (the ~2× in 1 ms boundary race) in O(1) per key,
  which is the right cost/benefit — but the doc comment should not claim the stronger
  property. Recorded in #226's body so the next reader starts from the truth. SRDD CLK-5 does
  not specify the window shape, so this is a product decision, not a spec violation.


---

## Cycle 18: I was wrong about #182, and the worker proved it with the middleware

My design note on #182 said: *"The handler publishes no `ConfigDomain` at all… There is no
rebuild to skip."* **That was wrong**, and I had verified the handler's text before writing it.

The rebuild was real, just not caused by the handler:

1. `domains_for_path` (`common.rs:309`) has **no branch** for `/api/user/preferences`, so it
   falls through to `Vec::new()` — whose semantic is *"unknown mutation domain: force a full
   snapshot rebuild to stay correct"*.
2. `control_mutation_barrier` (`common.rs:~593`) publishes for **any** mutation whose handler
   did not set `MUTATION_HANDLED`. The preferences handler didn't, so every theme change
   rebuilt all nine slices.

I checked the handler and stopped there. The worker checked the *middleware that wraps it*.
That is the second time this session that "read the function" was insufficient and "read what
calls/wraps the function" was the answer.

**The lesson, now with two independent instances:** when a brief makes a claim of the form
"X does not happen", the verification must include the **callers and the wrapping middleware**,
not just the function body. `domains_for_path` + `control_mutation_barrier` + `MUTATION_HANDLED`
is a three-part mechanism and I read one part.

The fix also split correctly at the *writer* boundary rather than the domain list, because
`execute_single_control_task` bumps `config_version` unconditionally inside the transaction —
so routing a UI-only update through `execute_atomic_mutation` with an empty domain vec would
still bump. I had suggested exactly that wrong shape in the brief.

### Second correction, on #193

My brief assumed delete was also broken. It was not: both delete handlers already collected
child key IDs before the mutation and evicted after commit. **Only the disable path was
missing**, and the worker found that by reading rather than by trusting my framing.

### And a self-caught unfalsifiable test

The worker found that its own over-eviction guard was **unfalsifiable**: the "unrelated" client
key in the fixture had no `client_keys` row at all, so a query that dropped its
`WHERE service_account_id = ?` filter would also never have returned it — meaning the test
would have passed for a fix that evicts every key. It fixed the fixture (a real unrelated key
with `NULL service_account_id`) and confirmed dropping the WHERE clause now fails.

That is the third distinct class of weak test this session has produced or caught:
1. **Non-discriminating** (cycle 6): passes with and without the fix.
2. **Unscoped** (cycle 14): a global delta satisfiable by a parallel test.
3. **Unfalsifiable fixture** (cycle 18): the negative case cannot be reached at all.

Worth stating explicitly in every future brief: a guard test is only a guard if you have
watched it fail for the reason it exists. Cycle 18's mutation discipline is what surfaced this
one, which is why mutation-checking is now a standing requirement rather than a suggestion.


---

## Cycle 19: the verification-cycle pattern worked

Three issues, two of which described broken behaviour (#189 "unenrolled re-enroll silently
disables 2FA", #190 "recovery codes generated but never accepted") and a third (#221) which
said "and none of this is tested".

I read the code and concluded both behaviour claims were **false**. Rather than closing them on
a code reading — which is exactly the error I made in cycle 18 with #182 — I dispatched a
**verification cycle**: the brief's job was to *write the tests that would refute me*, with no
production edits permitted.

Outcome: six tests written, **all passing against unmodified production code**, three issues
closed with evidence. Zero production files changed (`git diff --name-only` confirms only the
test file plus CHANGELOG).

Mutations I ran myself to confirm the tests aren't vacuous:
- Commenting out the recovery-code branch → 3 tests fail (`login_with_a_recovery_code_succeeds`,
  `a_recovery_code_is_single_use`, `recovery_code_cannot_be_used_twice_in_a_row`).
- Removing the `TotpAlreadyEnabled` guard → `re_enrolling_an_enabled_account_is_refused` fails.

### This is the pattern to use for the rest of the stale issues

Both extremes are wrong:
- **Closing on a code reading** is what blew up in cycle 18 (#182 — I read the handler, missed
  the middleware, and was wrong).
- **Dispatching a fix cycle for a non-bug** wastes a cycle and risks "fixing" working code.

The middle path: a verification cycle that writes the test which would fail if the issue were
true, with production edits forbidden. Then the outcome is evidence either way, and the issue
closes (or reopens) on data rather than opinion.

Given ~195 issues left and the hit rate of false premises this session (13 of 31 closed so far
were already-satisfied or non-reproducible), **expect several more verification cycles**. They
are cheap — one test file, no production risk — and they convert an untrustworthy audit backlog
into a tested one.

### One residual recorded, not fixed

Enrolling a *pending* (never-verified) account a second time overwrites the first pending
secret. Benign — nothing was enabled, so the user loses only a screenshot — but "pending
enrollment state" does not exist. That is a schema change with migration/eviction concerns, so
it stays out of scope with a status-quo pin test
(`re_enrolling_a_pending_account_replaces_the_pending_secret`) and a recommendation in the
report.


---

## Cycle 20: the issue was inverted, and a test was defending the bug

**#188 said** the `Secure` cookie attribute was *missing* on forwarded-https. **The truth was
the opposite**: `Secure` was set **unconditionally** (unless a dev override), so on plain-HTTP
loopback the browser dropped the session cookie entirely and **login was impossible**.

Severity breakdown, which the report established properly:

| Path | Sets the dev override? |
|---|---|
| `docker-compose.yml:201`, `docker-compose.local.yml:31` | **yes** (`--dev-insecure-cookies`) |
| `Dockerfile:105`/`:131` (`CMD ["serve"]`) | **no** |

→ latent in Compose, **live for anyone running the image or binary directly.**

### The finding that matters most: a test was asserting the bug

The pre-existing `login_csrf_and_security_headers` contained
`assert!(cookie_str.contains("Secure"))` **on a plain-http request**. So the defect was not
merely untested — it was *defended*. That is a fourth class of weak test to add to the list:

1. **Non-discriminating** (cycle 6): passes with and without the fix.
2. **Unscoped** (cycle 14): a global delta satisfiable by a parallel test.
3. **Unfalsifiable fixture** (cycle 18): the negative case cannot be reached.
4. **Bug-defending** (cycle 20): the assertion encodes the current behaviour as if it were the
   requirement.

Class 4 is the most dangerous because it *looks* like coverage — the area has tests, they pass,
CI is green — while actively preventing the fix. Detectable only by mutation: change the
behaviour the test asserts and see whether the test objects. Which is why mutation-checking is
now non-negotiable in every brief.

### A second bug fixed alongside, correctly

`__Host-` (the cookie-name prefix) is **also** only valid over HTTPS and was likewise applied
unconditionally. The fix ties prefix and `Secure` into one `CookiePolicy`, because a `__Host-`
name without TLS is equally dropped by the browser. Fixing only `Secure` would have left half
the lockout live. That was the worker's own catch, not in the brief.

### Filed: #227 — SRDD A4 promises a feature that does not exist

SRDD **A4** and the Section 5 env table promise a built-in `rustls` listener via
`<APP>_TLS_CERT`/`<APP>_TLS_KEY`. `rg -l 'TlsAcceptor|axum-server' crates/` is **empty**;
the only `rustls` in the workspace is reqwest's outbound client. The env vars are **silently
ignored** — the worst failure mode for a security setting, because an ignored TLS option looks
exactly like a working one.

This mattered *for this cycle*: my brief's stop condition was "no direct-TLS signal ⇒ a resolver
would strip `Secure` from a real TLS deployment". The condition did not trigger only because
**there is no direct-TLS path to regress**. So #227 is also a latent trap: whoever implements A4
must plumb a per-request scheme marker, or the `Secure` decision silently becomes wrong for every
native-TLS deployment.

Recommendation in #227: either implement A4 **plus** the scheme marker, or delete it from the
docs **and reject the env vars at startup**. Silent-ignore is not an acceptable third option.


---

## Cycle 21: #194 was much worse than filed — retention reduction deleted nothing

The issue said: *"retention reduction leaves orphaned `trace_blocks`"*. The truth: **the purge
itself never ran.**

`put_admin_traceability_handler` **counted** the rows a purge *would* affect — to fill
`affected_rows` in the 409 confirmation body — and then only rewrote the `traceability_config`
settings row. **Zero DELETEs executed.** A record older than the newly-lowered window survived
indefinitely.

And the periodic sweeper genuinely could not cover it: `sweep_expired_trace_records` deletes on
`expires_at`, which was stamped from the retention in force **when the record was written**. So
lowering retention never made an existing row expire. The bug was permanent, silent, and had no
second line of defence.

That is the fifth distinct severity shape this session:
| # | Shape | Example |
|---|---|---|
| 1 | Stale premise / already fixed | #3, #50, #58, #189, #190 |
| 2 | Inverted premise | #188 (set always, issue said never) |
| 3 | Non-existent symbol/feature | #5 (`dedup`), #145 (`try_acquire`), #227 (A4 rustls) |
| 4 | Real but mis-scoped | #171 (display path, not data plane), #155 (bodyless op) |
| 5 | **Worse than filed** | #194 (nothing purged at all), #149 (money charged, no row), #17-era TPM race |

### The design fork answered correctly

My brief flagged the decisive question: is a block reference **indexable** or only inside sealed
JSON? Answer: `trace_record_blocks(usage_event_id, owner_user_id, block_hash)` is a join table
with `idx_trace_record_blocks_ref(owner_user_id, block_hash)`, populated at insert time. So the
sweep is an indexed `NOT EXISTS` — the cheap branch — and a correct batched sweeper
(`retention::sweep_orphaned_trace_blocks`, `LIMIT`-chunked) **already existed**. The fix reuses it
and loops until a short chunk, rather than writing a second one. Good.

It also reasoned explicitly about atomicity: purge commits first, then sweep, because a crash
between them leaves *orphaned blocks* (collected later, safe) whereas the reverse — blocks deleted
while records still reference them — would corrupt live traces, since `trace_blocks` is
content-addressed (`ADR-9`). That is the right direction of failure.

And it caught its own bug: the first version purged on **every** call including retention
*increases*, which would have deleted records the operator never agreed to lose. A test
(`raising_retention_purges_nothing`) now pins it.

### My own mutation-testing mistake, worth recording

I botched two mutation attempts on this cycle and briefly concluded the tests were toothless:
1. First attempt left the `DELETE` still executing via a `let _skip = ...` binding — so the
   behaviour was unchanged and the tests rightly passed.
2. Second attempt ran the restore in the *same shell command* as the test, so the test ran against
   restored source.

Only the third attempt (remove the whole statement, don't restore until after) produced the
expected 3 failures. **Rule: a mutation must be verified as actually applied before the result is
interpreted** — `grep` the marker, and never restore in the same command as the run. Otherwise
"the test didn't fail" and "the mutation didn't take" are indistinguishable, and the natural
conclusion ("the test is weak") is the wrong one.


---

## Cycle 22: the worker caught me double-counting reasoning tokens

My brief told it (echoing #173's acceptance criteria) to make `total_tokens` the sum of **all five**
token classes: `input_uncached + cache_read + cache_write + output + reasoning`. I even wrote an
expected value of `675` into the test spec.

**That is wrong, and the worker refused it**, with citations I then verified independently:

- `crates/core/src/pricing.rs:24` documents `reasoning` as a **"Diagnostic subset of `output` that
  the provider attributed to reasoning/thinking."**
- `docs/srdd/12. SRDD:133-134` states for both `chat` and `responses` that `output_tokens`
  "**includes reasoning**".
- `calculate_cost_micro_usd` (`pricing.rs:251-254`) sums exactly **four** classes and never touches
  `reasoning`.

So summing all five reports **675** for a row whose true volume is **650** — silently double-counting
25 tokens on every reasoning response. The correct total is the four-class sum.

The worker encoded `650` in the tests and documented the divergence in the report so it would not be
mistaken for a test bug. That is exactly right: **the issue's own acceptance criteria were wrong, my
brief inherited the error, and the test is what caught it.**

### Why this one matters beyond the cycle

It is the first time the error was **mine, in the brief**, rather than in an audit issue — and it was
caught because the worker checked the arithmetic against the *domain* (what is a subset of what)
instead of against the *instruction*. The mutation discipline plus the cross-screen consistency test
(`usage_ledger_totals_match_the_logs_projection`) is what made the disagreement visible: one event,
one row, two screens, `logs=150` vs `ledger=650`.

Recording the general rule: **a "sum all N fields" instruction is a claim about set relationships,
and must be verified against the schema/domain before it becomes code.** Field lists are not
sums — subsets exist.

### Also worth noting: clippy caught over-reach

The first fix carried a `reasoning` field in a `TokenClasses` struct that nothing read, because
reasoning is never part of a total. Clippy flagged it as dead, and the follow-up commit
(`7b82fb2`) removed it with the reasoning spelled out. A struct that says "four classes that sum"
is more honest than one that carries a fifth for symmetry.


---

## Cycle 23: two mutants survived, and that is the best outcome available

The worker mutation-tested its own fix and **two mutants survived** — meaning the tests were
weaker than they looked. Rather than "fixing" the mutants or quietly dropping them, it added the
missing tests and re-killed them:

| Mutant | Result |
|---|---|
| M1 — drop `canonical_id` from the rollup predicate | killed (3 tests) |
| M2/M2b — collapse the union, shifted placeholders | **inert** — the mutant did not change behaviour, so it proved nothing |
| **M2c** — collapse the union, placeholder count preserved | **survived** → test added → killed (`left: 0, right: 7150`) |
| **M5** — `hour_ms >= ?` → `hour_ms > ?` at all six sites | **survived** → boundary test added → killed (`left: 20, right: 30`) |

Two lessons worth keeping:

1. **An inert mutant is not a killed mutant.** M2/M2b "passed" because altering the placeholder
   count shifted binds rather than changing the predicate — the mutant never expressed the bug. The
   worker recognised this and re-cut it (M2c) so the behaviour actually differed. Distinguishing
   "the test caught it" from "the mutation was meaningless" is the whole game.
2. **M5 is the general lesson**: `>=` → `>` at every site survived because nothing tested a value
   *exactly at* `since`/`until`. Boundary-exact tests are usually missing and usually matter,
   especially when splicing predicates into queries that already bind the same parameter twice.
   That is now in the standing brief language (`since_until_boundaries_are_inclusive`).

### And the worker corrected my `initiator` guidance

I told it: implement **one** meaning (recommending `client_key_id`), and specifically *not* a
disjunction of all three, warning that a disjunction "would make the filter broader than its
label".

**I was wrong, and the SRDD says so verbatim.** `14.n.2`:

> Dropdown lists all users, service accounts (`agents`, `ci`, `bots`), and individual client keys
> (`llr_...`) in the workspace.

One dropdown, three kinds of principal. So the union **is** the label, not broader than it. The
worker read the spec instead of taking my fallback, implemented the three-way `OR` the spec
describes, and reported the correction with the citation.

The general lesson, and it is now the third time this session: **when a brief offers a "fallback if
ambiguous", the worker must check whether it is actually ambiguous before accepting the fallback.**
My instruction to avoid the disjunction was a strong prior based on a plausible-sounding principle
("narrower is safer"), and the spec overrode it.


---

## Cycle 24: the traceability gate caught a bad citation that was **mine**

I wrote into the brief: *"cycle-era work added `sanitize_csv_cell` for `SEC-20`"*. **`SEC-20` does not
exist.** The highest `SEC-` id in `docs/srdd/requirements.toml` is `SEC-19`, and `14.l` attributes
formula-sanitised export to **`SEC-6`**.

The worker carried it into two test annotations and a doc comment, then
`cargo xtask traceability --milestone M6` rejected it — because the gate fails on Rust annotations
naming an id absent from the registry. That gate exists precisely for this and it worked on the first
thing that tried it.

**This is the fourth time this session the worker had to correct me** (cycle 18 middleware ×2,
cycle 22 reasoning-token arithmetic, cycle 23 `initiator` semantics, and now this). The pattern is
consistent: my errors are always **plausible-sounding specifics** — a requirement id that follows
the existing numbering convention, a "narrower is safer" design instinct, a field list that looks
like a sum. Each was believable enough to survive my own re-reading, and each was caught only by
checking against an authority (the spec, the pricing table, the middleware, the gate).

**Practical rule: any concrete identifier in a brief (requirement id, constant name, symbol, line
number) must be verified against the source of truth before it is written, not reasoned about.** I
have been doing this for file paths and line numbers since cycle 1; requirement ids slipped through
because they *look* like documentation rather than code. They are just as checkable.

Also noted: one open issue (#102) cites the same nonexistent `SEC-20`. I left a comment there so the
next reader does not re-derive it.

### #142 was real

`LedgerQuery::initiator` **was** still a dead field, and is now implemented using cycle 23's
three-way union (user, service account, client key) — so the same word means the same thing on all
five endpoints that expose it.


---

## Cycle 25: the XSS question answered "no", and two better findings came out of it

I asked the brief's most pointed question: *does the drawer build DOM with `innerHTML`, which would
make adding a headers grid an XSS vector?* The answer was **no, and the reasoning was evidence
rather than assertion**:

- The drawer is **server-rendered** — `render_log_detail_drawer_html` in `api/log_detail_drawer.rs`
  returns `Html<String>` that HTMX swaps into `#drawer-content`. `app.js` never touches it.
- `app.js` has 24 `innerHTML` uses, **none on the log-detail path** (aliases table, settings grid,
  charts, chat preview, sessions/SA/prices tables, TOTP box — separate features).
- Every interpolated value already passed through `escape_html`.
- The new headers grid escapes both name and value, and mutant M2 (removing `escape_html` from the
  value) makes `log_detail_escapes_header_values_in_the_render` fail — so the escaping test has teeth.

That is the right shape for a "no" answer: not "I checked and it's fine", but the four observations
that make "fine" inspectable.

### Two findings that were worth more than the seven fields

1. **#228 — the drawer invents `1 attempt (served)`.** When no `usage_attempts` rows exist, the
   renderer emits a confident claim of one successful attempt. Found because the cycle's own fixture
   (one event, zero attempt rows) rendered "1 attempt". That is the *same* invented-value failure the
   brief forbade for `client_location` ("render a dash, do not invent a value"), sitting a few lines
   away in the same file. Filed with a three-state recommendation (rows / not-recorded /
   rejected-before-dispatch) rather than a two-state dash, because the third state is genuinely
   informative.

2. **`app.js` is 1,649 lines — 49 over the MNT-3 ceiling — and the gate cannot see it.**
   `workspace_boundaries.rs:451` only collects `.rs` files
   (`path.extension().is_some_and(|extension| extension == "rs")`), so `.js`/`.css` are invisible.
   The file has been over budget and passing CI the whole time. That is #13 + #56's exact coupling:
   the split without the gate drifts back, the gate without the split fails immediately — they need
   to land together, or the gate lands with a temporary allow-list naming this file. I recorded the
   concrete measurement and the 24 `innerHTML` sites on #13.

### Reviewer note

The `app.js` finding came from a `wc -l` the brief asked for as a *risk check* ("don't grow it"), and
it turned into a governance finding ("it is already over and nothing says so"). Asking for a
measurement in a brief keeps paying off beyond its stated purpose.


---

## Cycle 26: #138 looked stale and was the most serious thing closed all session

My reading was that `audit_key_hex` did not exist, so #138 was probably already satisfied — the
conclusion for 13 of 44 closed issues. **Wrong in the best way.** The named function was gone, but two
sites still fell back to `sha256_hex(master_key)`:

- `api/common.rs` — `execute_atomic_mutation`
- `api/sessions_and_traces.rs` — the trace-view audit write

That is not merely "non-HKDF". **`ADR-11` guarantees that rotating `<APP>_MASTER_KEY` does not
invalidate the audit chain** — that is the whole point of separating instance secrets from the
rotatable key. A master-key-derived audit key destroys exactly that guarantee, and it does so
**silently**: after a rotation, old rows simply stop verifying while new rows chain from a different
key. Discovered during an incident, not before one.

The fix fails closed (`resolve_audit_hmac_key` → `Err(InstanceKeyNotConfigured)`, and the two call
sites skip the audit write). That is the right trade: **a missing row is visible and recoverable; a
chain that looks valid for new rows and invalid for old ones is not.**

It also had to fix a **bug-defending fixture**: `test_audit_log_captures_authenticated_actor_user_id_on_mutations`
asserted an audit row while configuring no `audit_hmac_key` — the row only appeared *because* of the
derivation being removed. Same class as cycle 20's cookie test.

### And it found a third instance of the same pattern

The brief named two fallbacks; it found three. The empty-key affinity token
(`session_hmac_secret.unwrap_or(b"")`) was the same "pretend to be keyed while providing nothing"
shape, fixed through one extracted `derive_salted_affinity_token`.

**Reviewer lesson, now unavoidable:** the defect family "secret absent ⇒ silently substitute a
constant/derived value" appeared in **four** forms across this one session (zero-key HMAC, empty-key
HMAC, domain-separated SHA, master-key derivation). When one instance is found, grep for the
*syntactic shape* — `unwrap_or(` near a secret, `[0u8; N]` fallbacks, `sha256` of another key — rather
than for the specific issue's citation. The brief did this once; it should do it every time.

### Keyed hashes are byte-identical

Confirmed by `keyed_session_hash_is_unchanged_by_this_cycle`, because a deployment upgrades and must
still resolve its stored pins. And the `client_key_id` vs `owner_user_id` scoping asymmetry was
*kept* rather than "fixed", since re-keying would orphan every pin in the field — reported instead.
Both are the right calls.


---

## Cycle 27: the family sweep paid for itself — third instance was the worst

Cycle 26's report recommended grepping for the **syntactic shape** rather than an issue citation.
I ran that sweep and found three more sites substituting `[0u8; 16]` for `instance_id`.

**And `instance_id` is not AAD — it is the HKDF salt** (`crypto.rs:303`:
`Hkdf::<Sha256>::new(Some(instance_id), master_key.as_bytes())`). So a zero fallback derives a
**different encryption key**, not merely a differently-bound envelope. Consequences:

- data sealed under the fallback is **permanently unreadable** once the real id loads;
- it fails **silently** — seal "succeeds", open fails later;
- `reloader.rs` made it reachable **at startup**, and it swallowed both the query error and the length
  mismatch (`fetch_optional(...).ok().flatten().unwrap_or([0;16])`).

Verified detail worth keeping: `load_or_initialize` **already fails closed** on a bad id
(`decode_instance_id(...)?`), so the three readers were bypassing a guarantee the codebase already
enforced. No schema change needed — only the readers were wrong. The schema even has
`CHECK (length(instance_id) = 16)`.

### My own mutation mistake, second time this session

I mutated the malformed-length branch and the tests passed. My first conclusion was "gap in the
tests". **Wrong — the mutation was inert:** the schema `CHECK` makes that branch unreachable, so
creating a short id is impossible and the branch genuinely cannot be exercised. Cycle 23 taught
exactly this and I still nearly mis-read it.

The correct mutation (restore the `fetch_optional(...).ok().flatten().unwrap_or([0;16])` shape, i.e.
the *absent row* path, which is the reachable trigger) failed **2 tests** immediately.

**Refined rule for the notes file:** when a mutation survives, the first question is always *"is this
code reachable?"* — not *"is the test weak?"*. Unreachable branches survive every mutation by
construction. Cycle 23's inert-mutant lesson needs this companion: inert ≠ untested, and the
distinguisher is a schema/constraint check, not another test.

### Where the project stands after 27 cycles

| | |
|---|---|
| Issues closed | **47** (from 0) |
| New issues filed (mine) | #225, #226, #227, #228, #229 — all fixed and closed except #227 (needs an owner call) |
| Tests | 636 → **827** (+191) |
| `master` | green; CI green on every push since cycle 1 |
| Secret-fallback family | **4 shapes, 8 sites, all closed fail-closed** |

### Remaining queue shape (182 open)

- **S1 stubs** (#128–#141): mostly small; #128 (enforce `validate_metric_labels`) is the sibling of
  cycle 14's constant work and now cheap.
- **S3 control plane** (#170, #172, #178, #180–#187, #189–#194): a long tail of single-handler fixes.
- **S4 UI** (#195–#209): the largest untouched block; needs its own multi-cycle plan, and #13/#56
  (`app.js` at 1,649 lines with no gate) should land first or the UI work will make it worse.
- **S5 tests** (#210–#224): several will be satisfied cheaply (as #221 was) by the cycles that fix
  their subject.


---

## Cycle 28: the only defect I can trace to my own instruction

`state_bound.rs` had `.map_or_else(|| "gpt-4o".to_string(), ...)` for the model id used to attribute a
decode-failure usage row. **I introduced it in cycle 16** while fixing #156 — the model id was needed
for the ledger row, the lookup *looked* safe, and `gpt-4o` was the first plausible string.

### And I overstated it, then corrected myself in the same cycle

My first draft of the brief called it "a live billing data error on `master` since cycle 16". Tracing
further:

- `response_links.model_pk` is FK-constrained (`REFERENCES models(model_pk) ON DELETE RESTRICT`,
  `0001_initial.sql:387`), so a dangling id cannot exist.
- The snapshot loads models **unfiltered** (`SELECT ... FROM models`, no `exposed` predicate), so every
  FK-valid model is present.

⇒ **The fallback is unreachable in production.** It is a latent hazard, not a live error. I corrected
the brief before dispatch and recorded the correction on the issue rather than shipping the scarier
claim because it made the cycle feel more important.

Fixed anyway, and the justification is honest: it is a trap for whoever later adds a filter to the
snapshot loader (an `exposed = 1` predicate is an obvious future optimisation, and then this silently
emits `gpt-4o` rows), and an error with an actionable message beats a plausible string.

### A test-fixture trap the worker hit and reported

Its first version of the negative assertion ("no row names `gpt-4o`") failed — because the
**link-creation** call legitimately wrote a row and the fixture's real model happened to be named
`gpt-4o`. Distinguishing by `request_id` did not work either. That is the fifth distinct fixture trap
this session, and the general lesson is now clear: **when asserting absence, make sure the honest path
cannot accidentally produce the same value.** A fixture whose "real" data collides with the "invented"
sentinel tests nothing.

### Disk

`disk-guard.sh --check` flagged pressure at 70 GB combined (threshold 60). No builders running, so
`cargo clean` removed **73.4 GB** at the cycle boundary — free space 104 → 174 GB. Back to 31 GB now.
The guard earned its keep: without it, another 20-30 GB of growth from the UI cycles would have hit the
394 GB disk mid-build.

### Session totals after 28 cycles

| | |
|---|---|
| Issues closed | **49** |
| Filed by me | #225–#229 (all fixed/closed except #227, owner call pending) |
| Tests | 636 → **834** (+198) |
| `master` | green throughout |
| Compactions | 3 (78%→3.5%, 41.9%→3.7%, 44.2%→4.2%) |


---

## Cycle 29: asking "what is the honest value?" found an unbounded table

#133 looked like a two-line fix: `"retention_days": 30` hardcoded in two places, wire it to
`RetentionPolicy`. Instead, asking *"what value is actually in force here?"* turned up **#230**:

**`control_plane_logs` is never swept in production.** The two retention paths have diverged:

| Path | Sweeps `control_plane_logs`? | Has a production caller? |
|---|---|---|
| Live loop, `serve.rs:590-618` (30 s `JobSupervisor` tick) | **no** — it sweeps 10 other tables | yes |
| `run_retention_pass`, `retention.rs:291` | yes (`sweep_expired_control_plane_logs`) | **no — only tests** |

So the table that records every control-plane HTTP request grows without bound, and the function
written to trim it has never run in production. The `"retention_days": 30` was doubly false: not the
configured value, and not even the effective one (which is *unbounded*).

### The general lesson, which is the best one this session

**A hardcoded literal is a claim about the system, and checking the claim is more valuable than
replacing the literal.** Three of this cycle's four issues were two-line fixes. The fourth turned into a
storage-growth defect because the worker asked "what should this number be?" instead of "what number do
I write here?".

That is now the standing instruction for every "hardcoded value" brief: **the report must state where
the value comes from *and* what value is actually in force at runtime**, and if those disagree with the
literal in a third way, that is a finding.

### Also worth noting: it did not repurpose #134

#134 (WAL banner in the overview partial) is a different defect entirely, and it stayed open. The new
finding got its own issue with a full evidence trail rather than being folded into #133's scope. That is
the right instinct — scope creep into an existing issue is how cross-cutting findings get lost.

### Where the queue stands

180 → 180 open (four closed, one filed). 49 closed total. Tests 636 → 846 (+210). `master` green.

The remaining 180 split roughly: ~110 S3/S4 (control-plane tail + the whole UI block), ~25 S5 (tests,
several of which the cycles above have partly satisfied), and the rest older architecture/refactor
items (#19–#25 decompositions, #10's provider-module deletion). **The UI block (#195–#209) is now the
biggest untouched mass** and needs #13/#56 (`app.js` at 1,649 lines with no gate) landed first, or the
UI work will deepen that file's overshoot.


---

## Cycle 30: closing the loop on a finding from the cycle before

#230 came out of cycle 29's "what value is actually in force?" question. This cycle fixed it:

- **The live tick now sweeps `control_plane_logs`** — the twelfth table, using the same `cutoff` as
  `usage_events` (configured `usage_events_retention_days`, default 30).
- **The sweep gained a `LIMIT`** (`5_000`), matching every other sweeper. Both halves were required:
  adding the call without the bound converts a slow leak into a one-off write-lock stall over a table
  holding months of rows.
- **`run_retention_pass` was deleted**, after a table-by-table comparison proving the live loop covers
  everything it did. Leaving a comprehensive retention pass with no caller is a trap — the next person
  fixes retention by editing dead code.

### The citation work was better than the fix

The worker went and found **three** SRDD citations for the window (`AUD-2`, `14.l` §1, `A6`) rather than
picking one, and established that `14.l` *names the setting* — which is what makes "configured, default
30" the right answer rather than "a constant 30".

It also found that the sweep's existing doc comment cited **`USG-8`, which is multi-tenant privacy on
`GET /v1/usage` and says nothing about retention**. That is a fourth kind of stale-metadata defect: not a
wrong line number or a missing symbol, but a *requirement citation that points at an unrelated
requirement*. Worth watching for — `cargo xtask traceability` validates that a cited id **exists**, not
that it is *about* the thing, so this class passes every gate.

### Session totals after 30 cycles

| | |
|---|---|
| Issues closed | **51** |
| Filed by me/worker | #225–#230 (all closed except #227, owner call pending) |
| Tests | 636 → **852** (+216) |
| `master` | green throughout; 30 consecutive green CI runs |
| Compactions | 3 |
| `cargo clean` | 1 (73 GB at cycle 28) |

### What is left (179 open) and how I would sequence it

1. **#13 + #56 together** — `app.js` is 1,649 lines (49 over) and `.js` is invisible to the MNT-3 gate.
   Must land before the UI block or that file gets worse and the gate still will not see it.
2. **S3 control-plane tail** (#170, #172, #178, #180–#187, #189–#194) — single-handler fixes, high
   value-per-cycle, several already partly done by adjacent cycles.
3. **S4 UI** (#195–#209) — the largest untouched mass; needs phasing, and several will be cheap because
   their backing APIs were just fixed (#196 needs the timeseries endpoint, #200 needs route prefs,
   #205 needs the admin-scoped partial).
4. **S5 tests** (#210–#224) — several are already satisfied by the cycles that fixed their subject;
   expect a run of cheap verification closes like #221.
5. **Decompositions** (#19–#25, #10's provider-module deletion) — expensive, do after the value work.


---

## Cycle 31: the UI prerequisite is done, and the gate now sees what it named

`app.js` 1,649 lines → **12 domain modules**, largest **450** (`app-core.js`). The gate now collects
`.js`/`.css`/`.html` and I verified it myself: creating a 1,700-line JS file makes
`all_static_assets_are_under_1600_lines` fail; removing it passes. That is the mutation proof a governance
test needs, and its absence is exactly how the `.rs`-only version came to be trusted for months.

Split shape (measured, not my guess — my brief guessed `charts/modals/tables/...` and was wrong):
`core 450, providers 194, keys 173, settings 172, auth 148, charts 133, catalog 108, sessions 105,
accounts 90, prices 83, shares 59, users 44`.

### Two things I want to keep from this cycle

1. **It refused to mix escaping fixes into the move.** The 24 `innerHTML` sites stayed untouched, with a
   full inventory reported in the cycle report instead. A 1,649-line move that also rewrites escaping is
   unreviewable — and I have now filed **#231** from that inventory, with the two genuinely interesting
   sites identified:
   - `app-catalog.js:59` — `targetSelect.innerHTML` from API models, escaping unconfirmed.
   - `app-settings.js:35` — an unescaped settings key in `id`/`for` attributes, **safe only by type**
     (`RuntimeSettings` is a closed 14-field struct). If that endpoint ever returns a map — a natural
     refactor, since `settings.rs` already has a string-keyed registry — it becomes an injection point
     with nothing recording the dependency. That is "safe by accident" and #231 converts it.
2. **It diagnosed an unrelated CI failure instead of absorbing it.** `cargo deny` started failing on
   **RUSTSEC-2026-0414** (`pulldown-cmark` 0.13.4) between the previous cycle's green run and this one. It
   verified the diff touched no dependency and no consumer of the crate, bumped `0.13.5`, and said so
   plainly. That is the right handling of a fresh advisory: not "my cycle broke CI", not "ignore it".

### Session totals after 31 cycles

| | |
|---|---|
| Issues closed | **56** |
| Filed | #225–#231 (all closed except #227 and #231) |
| Tests | 636 → **858** (+222) |
| `master` | green; 31 consecutive green CI runs |

### What this unblocks

The UI block (#195–#209) is now workable without deepening a 1,649-line file — and several of those issues
got cheaper because their backing APIs were fixed by cycles 22–29 (#196 needs the timeseries endpoint
cycle 23 wired; #200 needs route prefs which cycle 18 published correctly; #205 needs the admin-scoped
partial that #171/#173 touched). That is the next coherent block.


---

## Cycle 32: two of four requested fields declined, and the third bypassing handler

#170 asked to make `patch_admin_model` accept `distribution`, `routing_strategy`, `headroom_scaling`,
and `max_context_tokens`. Only two of those are real:

| Field | Verdict |
|---|---|
| `distribution` | real column (`CHECK IN ('weighted','strict')`) |
| `routing_strategy` | real column, nullable, NULL = inherit |
| `headroom_scaling` | **not a column** — the instance-wide runtime setting `headroom_scaling_enabled`. Declined. |
| `max_context_tokens` | **must not become one** — the real column is `context_window`, **discovered from upstream**, and migration 0002's own comment says *"the proxy must omit the field rather than fabricate a capability value (audit F-031)"*. An admin-writable context window is a mechanism for fabricating exactly what F-031 forbids. Declined. |

That second declination is the interesting one: it is not "the issue is stale", it is "**the issue asks
for something the spec deliberately prevents**". Making a discovered capability admin-editable would let
an operator advertise a context length the upstream never claimed. Declining with the F-031 citation, and
recording it on the issue, is the right outcome — and it is a category I had not hit before this session
(issues that ask for a *harmful* change rather than a stale one).

### The recurring pattern, now three instances

This handler was the **third** found bypassing `execute_atomic_mutation`, so it wrote to the DB with no
`audit_log` row, no `ConfigDomain` publish, and no version bump:

1. #182 — `PATCH /api/user/preferences` (cycle 18): routing-scope changes never reached the data plane.
2. #191 — share approval (cycle 21): an admin approval left no audit trail.
3. #170 — model patch (this cycle): model exposure changes kept the stale snapshot.

**That is a searchable shape**: any handler doing `state.auth.pool.begin()` or a bare
`sqlx::query(...).execute(&state.auth.pool)` instead of `execute_atomic_mutation` is a candidate. Worth
one deliberate sweep rather than three more cycles of finding them one at a time.

### A good sentinel decision

`routing_strategy` is nullable and NULL means "inherit", but JSON `null` deserialises to `None` — 
indistinguishable from "field absent" in a partial update. The worker chose **`""` means "clear to
inherit", `null`/absent means "unchanged"**, implemented as
`CASE WHEN ? THEN ? ELSE routing_strategy END` so the clear is explicit rather than inferred. It also
added `patch_model_refusal_leaves_no_partial_write`, which is the assertion I most wanted: a validation
that errors *after* writing is not validation.


---

## Cycle 33: the sweep found a *different* defect class, which is why it was worth doing

Cycle 32's notes said the atomic-mutation bypass was "a searchable shape" and should be swept once rather
than found three more times. Cycle 33 did the sweep — all 9 `execute(&state.auth.pool)` sites — and the
result was more interesting than expected:

| Verdict | Sites |
|---|---|
| Genuine atomic-path bypass needing a fix | 4 in `models.rs`/`providers.rs` (now all fixed, cycles 32–33) |
| **Different defect class** | 4 pin handlers in `sessions_and_traces.rs` |
| Already correct by design | 1 (`users_and_auth` preferences, after cycle 18) |

The pin handlers are **not** the same bug. They discard their SQL result (`let _ = sqlx::query(...)`) and
then hand-update the in-memory `PinStore` anyway — so a move/delete matching zero rows **returns success
and mutates the store**, producing an in-memory pin with no database row behind it. That is arguably worse
than a stale snapshot: a silent no-op is indistinguishable from success at the API boundary, and the
divergence points traffic at a pin that does not exist.

Crucially, **all four do it identically** — so it is one design mistake applied four times, not four
slips. Filed as #232 (with that observation, because "one mistake ×4" is easier to fix correctly than
"four bugs").

And `put_user_route_preference` turned out to be a **Low**, not a bypass to worry about: `user_route_prefs`
*is* a snapshot slice and `/user/routes/...` prefix-matches `/routes`, so the barrier's fallback publish
already covers it. Only the unchecked result is missing. Filed as #233 — and explicitly marked Low with
the reasoning, because inflating it to Medium would have been easy and wrong.

### The general lesson, third time

**Sweeping a pattern finds the pattern *and* its near-neighbours.** Each of the last three cycles found
something the issue did not name, and this one found a *variant* defect class that shares the syntax
(`let _ = sqlx`) but has a completely different consequence (lost error vs lost publish). A sweep that
only greps for the exact mechanism would have missed it.

### Session totals

| | |
|---|---|
| Issues closed | **59** |
| Filed | #225–#234 (6 closed, 3 open: #227, #231, #232, #233) |
| Tests | 636 → **877** (+241) |
| `master` | green; CI green on every cycle's final push |


---

## Cycle 34: the worker found the same defect one layer down

#180 was "setup hashes Argon2id inside `BEGIN IMMEDIATE`". Correct, verified, fixed. But the third
commit fixed something the brief did not name:

**`change_password` ran Argon2id *twice* while holding SQLite's write lock** — once to verify the current
password, once to hash the replacement. That is the same defect as #180, one layer below it, and worse in
magnitude: two full hashes of lock holding rather than one.

It also found `set_password` with the same shape. So the family was:
`post_setup` (fixed), `create_user` (permit held across the whole store call), `set_password`,
`change_password` (×2 hashes). Four sites, one design mistake.

The refactor shape is the right one: transaction contains **only writes**; verify and hash each take their
own permit **sequentially, never two at once** — because a one-permit pool acquiring twice would deadlock
on itself. That is the kind of detail that looks obvious in the commit message and is easy to get wrong in
the code, and it was explicitly reasoned about rather than discovered by a hanging test.

It also kept `create_user`'s five-argument signature intact (so ~40 fixture call sites need no edit) and
added `create_user_with_hash` for the permit-bounded path — the pragmatic split, and it said which caller
uses which.

### The pattern this confirms, for the notes

Three cycles running, the *family* was bigger than the issue:
- Cycle 26: two fallbacks named → found a third (empty-key affinity token).
- Cycle 33: four bypasses fixed → found a different class entirely (discarded SQL results) + one Low.
- Cycle 34: one lock-holding hash → found three more, one of which hashed twice.

**Every brief now says "sweep the syntactic shape, not just the citation."** That instruction has paid for
itself in each of the last three cycles.

### Session totals

| | |
|---|---|
| Issues closed | **61** |
| Filed | #225–#234 (6 closed; #227, #231, #232, #233 open) |
| Tests | 636 → **884** (+248) |
| `master` | green; CI green on every cycle's final push |
| Worker session | recycled once (`01a17d40` → `01a18224`) after a `Summarization failed` compaction |


---

## Cycle 35 + fix-up: two things worth remembering

### The worker corrected my brief with a spec citation, and was right

I told it to use exit `12` for schema mismatch, having enumerated `1,3,6,8,10,11,13` from a grep. It
checked §5.5.1 properly and found `12` was already the writer-panic code, so it used `15` and added the
table row. **My enumeration was from code, not from the spec's table** — and the table is the authority for
exit codes. Root cause of my error: I grepped `ExitCode::from(` which only sees codes that are *constructed
inline*, not codes that arrive via `exit_code()` methods. That is a real blind spot in the method; from now
on, read §5.5.1 directly.

### Then my review found the thing it had missed — same class as the issue itself

`doctor` said 15 for a newer database while `MigrationError::SchemaTooNew` said 14 for the same file. One
binary, two answers, one database. That is *exactly* the defect #183 was filed about (a command reporting
something inconsistent), reappearing one layer up — in the fix. Three-way split by direction fixed it, and
the receipt is `doctor` and `serve` both saying 14.

### The 74-identical-lines finding, and why the note is about shape not size

`load_instance_state` duplicated `load_or_initialize`'s verification body byte-for-byte. I diffed the
shared region to be sure — identical, not similar. That region holds the AAD-bound unseal and the length
check. The fix is `load_or_initialize` = (bootstrap branch) | `verify_instance_state`, with the meta row
**passed down** so the startup hot path keeps its two-query count.

**The durable artefact is not the deletion, it is the table-driven agreement test**: run *both* entry
points over the same fixture, assert the same error variant *and* the same exit code. After that, the two
paths cannot drift without a red test. Prefer that shape whenever collapsing duplicated validation.

### A bug that only existed because the awkward arm got a test

`MAX(version)` over an empty table is SQL NULL; decoded into a non-nullable `i64` it becomes `Some(0)`,
which reads as "this file is at version 0" — an ancient database — rather than "no version row". I
reproduced the NULL independently. The worker found it *because* the `schema_unknown` arm was asserted
rather than left as unreachable-looking code.

**Generalisation: an arm that looks unreachable is worth one test, because the encoding of "absent" is
where the bugs live.** This is the third time this session that testing a "can't happen" path found a real
conversion bug (cf. cycle 27's inert mutant, cycle 33's discarded SQL results).

### Process notes

- `worker-wait.sh` was rebuilt this cycle: `window_activity` from tmux replaces the pipe-pane→log→mtime
  chain, `wait -n` (bare) replaces `wait -n "$j1" "$j2"`, and two new selftest cases (orphan-no-starvation,
  idle-latency). 7/7 pass. Idle now detected in ~5 s.
- Two aborted waits had left **5 orphaned `tmux wait-for`** processes. Verified empirically that
  `wait-for -S` wakes *every* waiter, so orphans cannot starve the live wait — the selftest now pins that
  property so a future tmux change cannot silently break it.
- `pgrep -f "tmux -L agent-mgr wait-for"` killed my own shell (exit 143) — the documented `pkill -f` scar,
  repeating with `pgrep`. Use a pattern that cannot match the invoking command line.

### Session totals

| | |
|---|---|
| Issues closed | **63** |
| Tests | 636 → **903** (+267) |
| `master` | green; CI green on every cycle's final push |
| Queue | **171 open** (was 0 at session start → this audit queue is deep) |

The queue is genuinely large — 171 issues, mostly the audit's test-coverage block (#210–#224) and UI block
(#195–#209), plus docs/refactor (#1–#62). At ~2 issues/cycle this is a long haul; value-per-cost ordering
still applies, and the audit's P0/P1 defects are already drained.


## Cycle 36: a premise refuted by measurement, and why that only worked because the brief asked

#233 claimed `put_user_route_preference_handler`'s bare UPSERT caused "no publish, no audit entry, stale
snapshot". The worker found **all behavioural tests pass against the unmodified handler**, because
`control_mutation_barrier` (`common.rs:600`) is middleware: it classifies POST/PUT/PATCH/DELETE by path and
publishes + audits on every successful mutation. Handlers do not have to remember.

The two measurements that settle it, and the reason they exist:
1. **Detach the barrier** → the behavioural test fails exactly as the issue describes.
2. **Restore the bare UPSERT, keep the barrier** → every behavioural test still passes.

Step 2 is the one that matters. Without it, a green suite "confirms" the fix and nobody learns the defect
was never there. The brief asked for "prove this test can fail" on that exact test — that instruction is
what turned a false green into a refutation.

**Lesson for briefs:** when a fix's test could pass for a reason unrelated to the fix, demand the
*complementary* measurement (revert the fix, keep the claimed cause absent, and show the test still
passes). One sentence in the brief; it is the difference between evidence and decoration.

### #232 was worse than filed — three defects, and the worst was invisible to a response test

`let _ = ...execute()` (silent failure), zero-rows-reported-as-success (false claim), **and the store
updated either way** (wrong system state). The third is the one no response-only test would catch: the
read-back selected by `session_hash` alone — with no ownership or model filter in the admin variant — so it
pushed *unmoved* rows into `PinStore`, and the data plane routes from the store.

Fixed by driving the store from the statement's own `RETURNING` set, which is the structural answer:
the store can no longer disagree with the write because it is fed by the write. Worth remembering as a
pattern — **derive the secondary state from the primary write, never from a re-read.**

Also bumped into SQLite's constraint that `RETURNING` takes column references only (no subqueries), solved
with one follow-up query inside the same transaction, safe because `pins.model_pk` is `ON DELETE RESTRICT`.

### Session totals

| | |
|---|---|
| Issues closed | **65** |
| Tests | 636 → **915** (+279) |
| Queue | 169 open |


## Cycle 37: layering two guards is only right when they compose

The obvious fix for "settings key interpolated into `id=`" is `escapeHtml(id)`. It closes the injection and
**breaks the save path**: `saveSetting` does `getElementById(\`setting-${key}\`)`, and `&quot;` is a valid
attribute value but not a valid element id. A fix that passes review and breaks at runtime for exactly the
payloads it protects.

The worker took the guard (`/^[a-z0-9_]+$/`) *and* the escaping. That is normally redundant-gesture smell —
except the two **compose**: a key passing the guard has no character `escapeHtml` touches, so it is the
identity and `getElementById` matches. Worth remembering: **redundancy is fine when you can state why the
layers agree; it is noise when you cannot.**

### The census test, and the two properties I now check for

`no_module_interpolates_into_an_attribute_without_escaping` walks all 12 JS modules, brace-matches `${…}`,
checks 15 attribute names. I asked two questions of it:

1. **Can it pass vacuously?** It asserts `inspected >= 15` — a floor, so if the walker stops reaching the
   modules it fails rather than going quietly green. *This is the guard I now want on every static-census
   test*, and it is the one most authors omit.
2. **Does it have teeth?** I mutated one `id="${escapeHtml(id)}"` back to `id="${id}"`, confirmed the text
   changed, ran it, saw it fail, restored. Killed.

Static analysis tests are the class most likely to decay into decoration, because they pass when they look
at nothing. Both guards cost ~4 lines.

### The recurring pattern this session, stated plainly

Five cycles running, the *family* exceeded the issue: cycle 26 (2 fallbacks named → found a 3rd), 33 (found
discarded-SQL class), 34 (found `change_password` hashing twice), 36 (found the `PinStore` divergence,
invisible to response tests), 37 (found the routing-theme `<option>` raw on both sides). The sweep
instruction earns its place in every brief.

### Session totals

| | |
|---|---|
| Issues closed | **66** |
| Tests | 636 → **919** (+283) |
| Queue | 168 open |


## Cycle 38: a red test that hangs is not a red test

The worker wrote four tests for the TLS rejection and then hit **three consecutive 15-minute silent
timeouts**. Root cause, found by reading its test helper:

`serve_with_env` used `command.output().await` — which waits for the child to exit. Pre-fix, `serve`
*correctly* starts and runs forever, so `output()` never returns and the test hangs until the outer bound.
**A test for "must be rejected" cannot be written against "must exit", because the failure mode of the
untested code is "keeps running".**

The fix is `tokio::time::timeout(Duration::from_secs(20), command.output())`, with `Elapsed` treated as a
distinct, loud result. `kill_on_drop(true)` was already there, so the child is cleaned up.

**Generalisable rule for briefs: when the defect is "silently proceeds", the red test must bound the
proceeding, or it hangs instead of failing.** This is the same family as the spin-probe bound (2026-10-23)
— the bound is the instrument, and hitting it is the measurement.

### The flake response was right, and it is the one people get wrong

Its first push went red: `serve_starts_normally_without_tls_vars` waited 60 s for `/readyz` in CI, passed
locally in 0.36 s. The fix **deleted the readiness polling** rather than raising the timeout, because
end-to-end readiness is already covered by `test_serve_cli_boots_serves_readyz_and_handles_lock_contention`
— the duplicate coverage's only contribution was a new way to fail for an unrelated reason. That is the
`ponytail` response to a flake and the opposite of the reflex.

### The census pattern, now proven twice

Cycle 37's JS attribute census and cycle 38's env-var census are the same artefact: **enumerate the claim,
check it against the code, classify every exception.** The env census found exactly 2 unread of 19
documented, and correctly separated 5 deployment-artefact names (`<APP>_DOMAIN`, compose port
mappings) from binary variables — a distinction a naive grep would have missed and reported as 7 defects.

Two things make such a census worth its cost: the **method** (distinguish "mentioned in a doc comment"
from "read at runtime") and the **classification column** (read / unread / intentionally-ignored-with-reason).
Without the second, the output is a list of grep hits, not a decision.

### Session totals

| | |
|---|---|
| Issues closed | **68** |
| Tests | 636 → **927** (+291) |
| Queue | 166 open |


## Cycle 39: my mutation was invalid, and re-cutting it was the whole point

I tried to verify the duplicate-anchor guard by replacing `match LAST_ANCHOR_AT_MS.load(..)` with
`match Some(0_i64)`. It failed to **compile** (type error). A mutant that does not compile proves nothing —
it is neither killed nor survived, it never ran. I re-cut it as `last_anchor_at_ms() -> None` (valid,
reachable, behaviour-changing), which failed exactly the intended test, then restored.

This is the fourth time this session that a mutation needed re-cutting before it meant anything. The
checklist item stands: **confirm the mutant applied *and compiles* before interpreting a result.** The
grep-for-marker check catches "did not apply"; only a successful build catches "applied but inert".

### The NTP interaction, which is why the worker's design beat my brief

I asked for an in-memory last-anchored timestamp. The worker made it `fetch_max`, because **audit rows can
carry a backdated `ts` after a backward NTP step** — the chain verifier already has a test for that — so a
plain store would let one backdated row rewind the guard and re-open the duplicate-anchor window.

That is a genuine interaction between two distant subsystems that my brief did not anticipate. Worth
noting the shape: **the guard's own ordering discipline has to survive the data it is derived from**, and
here the data can move backwards. Two related details it also got right: `ts` (what the anchor attests) and
`emitted_at_ms` (when it was emitted) are separate, since deriving the guard from the payload's `ts` would
make an idle instance unable to anchor — the exact case the timer exists for.

### `interval_at` over "discard the first tick"

I suggested either. Its reasoning for `interval_at` is better and worth reusing: **a discarded tick is easy
to delete by accident in a future edit, whereas the offset documents itself in the constructor.** The
general principle: prefer the shape where the correct behaviour is *structural* over the one where it is a
statement someone must not remove.

### Session totals

| | |
|---|---|
| Issues closed | **70** |
| Tests | 636 → **940** (+304) |
| Queue | 164 open |


## Cycle 40: the redaction function had no test anywhere in the workspace

That is the whole finding. `redact_provider_config_json` is called by a diagnostics export whose *purpose* is
to be safe to hand to a stranger, and a `grep` across all crates found it only at its definition and its one
call site. **A redaction function nobody exercises is indistinguishable from a working one**, which is
exactly how a nested-OAuth-refresh-token leak survived in a codebase this disciplined.

Measured, not argued: seed a real DB with a marker at five placements, run the **shipped binary** pre-fix →
**5 occurrences**. Post-fix → 0, with `key_visible_123` and `secret_last4` still present so the export stays
useful. The receipt has two halves and the second is what makes it a receipt.

### The shape nobody would have specified

Beyond recursion, the fix handles `{name|path|header: <sensitive>, value: …}` — the object **names** its
secret in one field and **carries** it in another, so no key-name test on `value` can ever find it. I did not
specify that; it is in the config format. Worth generalising: **when redacting by key name, ask whether any
structure separates the label from the payload.** If yes, name-based traversal alone cannot be complete.

### Ordering as the correctness mechanism

`is_sensitive_key` checks the non-secret allow-list **first**, because `max_tokens` contains `token`. An
allow-list that ran after the substring scan would redact the model's output budget — a bug that would look
like strictness. Also normalizes `-`/`.` to `_` so one vocabulary serves `x-api-key`, config keys and JSON
paths.

The threat model in the brief was over-inclusion: a "fix" that redacts everything containing `key` passes
review and makes the export useless. Pinned by a test now.

### Session totals

| | |
|---|---|
| Issues closed | **72** |
| Tests | 636 → **952** (+316) |
| Queue | 162 open |


## Cycle 41: the doc comment cited a test that was never written

The implementation was good — an allow-list predicate, one shared macro, both handlers using it, 962 green.
But `usage_filters.rs:370` said:

> `tenant_audit_visibility_placeholder_count_matches_binder` in this module's tests now pins the two
> together so the next edit cannot repeat it.

**`grep -rn placeholder_count` across the workspace returned only those two doc lines.** The test did not
exist, and the commit message repeated the claim.

This is now the **third** instance this session of a safety property existing only in prose (cycle 38's
silently-ignored TLS variables, cycle 40's untested redactor, now this). Worth naming as a pattern to check
for deliberately: **when a comment or commit message says "a test pins this", verify the test exists.** It
costs one grep and it is the cheapest possible audit — and a false claim of coverage is worse than an admitted
gap, because it stops the next person from writing the test.

### The hazard the phantom test described was real

A mis-spliced predicate is **not a compile error** and not necessarily a SQL error: it shifts every later bind
by one, and the query then returns a plausible but wrong set or fails with a bare "datatype mismatch" naming
no column. The worker hit exactly that while writing it (11 binds for 12 placeholders).

The real test now asserts three things, and the third is the one I would have missed: `declared == 12`
alongside `declared == bound`. Equality alone passes if a **clause and its bind are deleted together** — and
for a security predicate, silent removal is the failure mode, not miscount. I verified by adding a 13th `?`
with no bind and watching it fail.

**Generalisation: for security-decision lists, assert the exact membership, not just internal consistency.**
A consistency check protects against typos; a count protects against quiet deletion.

### Session totals

| | |
|---|---|
| Issues closed | **73** |
| Tests | 636 → **963** (+327) |
| Queue | 161 open |


## Cycle 42: my RCA was wrong twice, and my design would have shipped a spec violation

I briefed #169 as: "nothing ever reclaims expired pins, so degradation is permanent; fix it by sweeping
**and** evicting (provisional before confirmed, then LRU)."

Both halves were wrong.

**Wrong #1 — `sweep()` exists.** `pins.rs:602`, `retain`-based, wired at `serve.rs:679` on the 30s tick. I
grepped `expires_ms|retain|remove` filtered to lines mentioning `retain|sweep|expire` — and missed a
`retain` closure whose expiry test is `now_ms < entry.expires_ms` on the *next* line. **The grep was wrong,
not the code.** So the degradation is bounded by the sweep interval, not permanent.

**Wrong #2 — eviction is rejected by the spec, by name.**
`15. SRDD:16` rejects `moka` for `PinStore` precisely because *"TinyLFU eviction would silently drop
confirmed pins"*, and `21. SRDD:60`/`RTE-10` mandate the refusal: *"Confirmed pins are never evicted by
TinyLFU capacity pressure… route via WRR with `pin_outcome = 'unpinned_capacity'`"*.

So the capacity refusal is **intended behaviour**. My "fix" would have broken in-flight stream affinity —
worse than the bug — and shipped as a bug fix. The worker rejected the brief's design **with citations**
rather than implementing it.

### The real defect, which is narrower and real

`acquire`'s capacity branch counts `entries.len()`, which includes entries whose `expires_ms` has passed but
the 30s sweep has not collected. So a store with **zero live pins** reports as full. Measured: 6 threads ×
30 acquisitions → **180/180 refused**. The fix runs the existing `sweep(now)` on that branch and re-checks.

### Three briefs this session whose design section would have caused a spec violation

- cycle 34: exit `12` (already the writer-panic code) → worker used `15` per §5.5.1.
- cycle 39: in-memory guard → worker used `fetch_max` for NTP-backdated rows.
- cycle 42: eviction → worker refused it for two cited spec sections.

**The template instruction that saves this: state the mechanism as a claim to verify and name the spec
sections to check, not as settled fact.** That is worth more than any other line in the brief. It also means
"where my RCA was wrong" in the report is not a formality — it has caught something in every one of the last
three cycles.

### Session totals

| | |
|---|---|
| Issues closed | **74** |
| Tests | 636 → **969** (+333) |
| Queue | 160 open |


## Cycle 43: the issue named three handlers that do not exist, and credited a fourth with work it never did

Every symbol was wrong: `get_user_pins_handler`, `get_admin_sessions_handler`, `get_user_partial_pins` do not
exist; `list_all` is `list_active`; `session_pins` is `pins`. And the premise was **inverted** — the issue said
the two broken handlers were unlike `get_user_client_key_sessions_handler` which "merges live entries", but
that handler has zero `pin_store` references and **`list_active` had zero production callers**.

So the audit's claim was built on a handler that never did the thing it was credited with. Worth noting because
the *underlying* staleness was real (async `durable_state` queue, 250 ms writer tick) — the issue was right
about the symptom and wrong about everything else, which is the most expensive shape to brief from.

### The open question I left, and what closed it

I offered a not-a-defect close if the pins view were a view of durable state. `Section 14` settled it: the
endpoint "returns live `PinStore` pins" and `14.t.1` says Active Sessions renders "confirmed session pins in
`PinStore`". **A spec sentence beats a debate**, and leaving the question open was correct — closing it as
by-design would have contradicted two spec sections.

### The security shape worth keeping

A live `PinEntry` has `upstream_key_id` + `pool_tier` but **no owner**, while the SQL predicate scopes with
`ck.owner_user_id = ?`. The merge resolves it with **one scoped query** that both resolves ownership and
applies the predicate; an id absent from the result has **no provable owner** and is dropped, exactly like a
foreign one. "Absent means drop" is the only safe direction at a tenant boundary.

I verified by deleting the predicate (`if true { String::new() }`): `a_live_pin_from_another_tenant_is_never_shown`
failed, then restored. That test passes trivially pre-fix — nothing merged, nothing to leak — so it exists
purely to guard the new code, which makes the mutation the only proof it works.

### Session totals

| | |
|---|---|
| Issues closed | **75** |
| Tests | 636 → **978** (+342) |
| Queue | 159 open |


## Cycle 44: the spec had already named the behaviour *and* the status code

`14.t.4` says the move handler must verify `C1`–`C8` and return **`422 target_route_ineligible`**. That is the
whole requirement, written down, with the code. The issue read as an open design question only because nobody
had opened the section.

Counting this session: cycle 34 (§5.5.1 exit codes), 42 (`15. SRDD:16` + `21. SRDD:60`), 43 (`Section 14` "live
`PinStore` pins"), 44 (`14.t.4`). **Four cycles where opening the cited spec section replaced a judgement call
with a citation.** The brief-writing habit that earns this: name the section numbers in the brief and tell the
worker to reconcile them, rather than presenting a design as advice.

### The honest-partial-check pattern, now established

The full predicate needs `&ConfigSnapshot` + `&RuntimeState`; `ApiAppState` has neither (verified). So the fix
verifies the **row-derived subset** and says plainly in the report which conditions are unreachable and why.

That is the right answer and it is worth naming, because the wrong answer is tempting and looks better: a SQL
query that approximates health status returns a confident answer from possibly-stale data. **A check that
claims "healthy" from stale rows is worse than an admitted gap**, because it converts "we don't know" into
"it's fine". Partial + documented > complete + approximated.

The mirror it wrote is faithful to `KeyHealthEntry::is_routable` — `invalid` never routable (no reset window),
`exhausted`/`cooling_down` only while the window is open, so a **past window is genuinely healthy rather than
a stale claim.** That last distinction is what makes it a check instead of a guess.

### Mutation discipline: "0 tests run" is not a survivor

My first mutation used `-E 'test(pin_move_eligibility)'` and got `0 tests run: 0 passed, 446 skipped`. That is
**neither killed nor survived — it never executed.** Re-cut with the real test name and it failed correctly.

Add to the mutation rules: **check the test actually ran.** A filter typo silently reports the most reassuring
possible result.

### Session totals

| | |
|---|---|
| Issues closed | **76** |
| Tests | 636 → **999** (+363) |
| Queue | 158 open |


## Cycle 45: reuse over duplication, and the absent-vs-failed distinction

Two things worth keeping.

### The worker widened cycle 43's helper instead of writing a third copy

The `IN (?,?,…)` placeholder builder added in cycle 43 for `active_pins` was `pub(crate)`-ed rather than
duplicated. Three copies of a SQL placeholder builder is how bind-order bugs get introduced — cycle 41 found a
11-vs-12 mismatch in exactly that kind of macro. **When a fix needs a helper a previous cycle wrote, widening
it is cheaper than the copy, and the copy is what creates the next discrepancy.**

### Absence, failure, and foreignness are three different things

The rehydration renders:

| state | rendering |
|---|---|
| block missing | `{"$blk":"<hash>","$unresolved":"missing_block"}` |
| decrypt failed | `{"$blk":"<hash>","$unresolved":"decrypt_failed"}` |
| foreign owner | indistinguishable from missing |

Collapsing decrypt-failure into absence **hides a key-rotation fault behind a retention story** — an operator
reading "block missing" concludes garbage collection, when the real answer is "your master key changed". And
neither may be `null`, because `null` renders as empty content, turning "we lost it" into "it was empty".

That is the fourth variant this session of the same underlying rule: **an absent value must render as absent,
not as a plausible default** (cycle 174 `client_location`, cycle 35 `MAX()`→`Some(0)`, cycle 40 `json!({})`
on parse failure, cycle 45 these three).

### `cargo clean` ran here

target/ hit 80 GB (guidance: clean at >25 GB); free was 95 GB. Cleaned at a clean-tree boundary while no
build was running: **freed 85 GB, free 95 → 174 GB.** Target regrew to 38 GB by the next cycle, which is
normal for this crate count.

### Session totals

| | |
|---|---|
| Issues closed | **77** |
| Filed this session | #225–#235 (11) |
| Tests | 636 → **1019** (+383) |
| Queue | 157 open |


## Cycle 46: invented money, and the existing test that caught an over-fix

`get_usage_event_breakdown_internal` bound `canonical_id` into `upstream_model_id`, missed for most providers,
and fell back to `Rates::default()` — `$3 / $15 / $0.30 / $3.75 per MTok` — then **computed a cost popover from
them**. Not "no cost shown": a confident number from rates never in the price book. Fourth variant this
session of the invented-value class, and the first where the value is money.

### The over-fix, and why the existing tests mattered

Its first attempt nulled `line_items` for unpriced events. **Two existing `e2e_dashboard_htmx` tests failed.**

That is the right signal, and it names a distinction worth keeping: **token counts are metered facts, money is
a derived fact.** The Logs Explorer, Usage Ledger and this popover must agree on the canonical total even when
pricing is unavailable. So `pricing: "unavailable"` + `rates: null`, but `line_items` still carry `tokens`.

A fix that was "more correct" in isolation was wrong at the system level, and a pre-existing test said so. This
is the strongest argument for never loosening an assertion to go green — the test that fails against a
plausible fix is the one earning its keep.

### Absent vs unreadable, finally separated

A found row whose rate column will not read → `500` (schema surprise). An absent row → `Unavailable`
(reportable state). The old `unwrap_or(3_000_000)` was the conflation that turned the second into a displayed
number. **Same pair as cycle 45's missing-block vs decrypt-failure:** absence and failure are different facts
and must not share a rendering.

### The money guard asserts over the whole payload

`a_breakdown_with_no_price_row_does_not_report_invented_rates` serialises the entire body and asserts none of
`3_000_000`, `15_000_000`, `300_000`, `3_750_000` appears *anywhere*. Correct choice: the failure mode is a
fabricated number surfacing in a field nobody thought to check, so a field-targeted assertion would miss
exactly the cases that matter.

### Session totals

| | |
|---|---|
| Issues closed | **79** |
| Tests | 636 → **1032** (+396) |
| Queue | 155 open |


## Cycle 47: the fix that outlives four doc corrections is the guard

Four Doc-Conflict issues, one cycle. The corrections themselves are small; the durable part is
`crates/server/tests/doc_code_consistency.rs`, which compiles three documents against the code:

- README settings keys vs `ALL_SETTINGS_KEYS`
- every `ExitCode::from(N)` in production code vs §5.5.1
- every documented exit code vs whether anything returns it

That third one is the pair to the second and the more interesting: **a documented code nobody returns is a
promise the binary does not keep, and nothing fails when it happens.** Guarding only the used-but-undocumented
direction would leave half the drift invisible.

### The word-order trap, which is the best single finding

Real key: `usage_events_retention_days`. README: `retention_usage_events_days`. Same words, opposite order.
A user copies the README, sets the variable, and **nothing fails** — the setting is silently ignored. That is
the same shape as cycle 38's silently-ignored `<APP>_TLS_CERT`, and it is why "the docs are just prose"
underestimates the cost: a wrong key in a settings table is a silent no-op with a UI that looks configured.

### My own process error, recorded

I posted the cycle-47 summary to **#47** instead of the four issues — same class as the failure I keep briefing
against, caused by working from a bare integer instead of a title. Corrected with an explicit retraction on #47
and the summary posted to the right four. Worth noting because the fix is mechanical: **print the title before
commenting**, not just the number.

### Session totals

| | |
|---|---|
| Issues closed | **83** |
| Tests | 636 → **1037** (+401) |
| Queue | 151 open |


## Cycle 48: the acceptance test I wrote found a bug worse than the issue

#163 was filed as "the admin price API hides tiered pricing". The brief's acceptance criterion was **"a GET
followed by a PUT of the same body must not drop or alter tiers/schedules"** — and implementing it revealed:

`UpsertPriceParams::tiers` was `Vec` with `#[serde(default)]`, so an **omitted** field became `vec![]`, and
`upsert_price_tx` wrote `None` for an empty vec. **A UI editing only the flat rates cleared the operator's
tiers and returned `200 OK`.**

So the real defect was data loss on save, not a display gap. The fix is `Option<Vec<_>>` (`None` = unchanged,
`Some(vec![])` = clear) with `COALESCE(excluded.x, prices.x)` — the rule `patch_admin_model_handler` already
documents at `models.rs:100-104`.

**Generalisable: when a surface reads and writes the same struct, the fidelity test is not a nicety — it is the
test that finds the omission bug.** A read-only or write-only test passes in both worlds. "Round-trip it and
compare" is the assertion that makes partial plumbing visible.

### The branch I would have got wrong, and the worker didn't

I briefed the anchored/rolling split. The worker also added `window_instance_start IS NULL` to the **rolling**
branch — which my brief did not ask for. Without it, a rolling window sums anchored adjustments that fall
inside the lookback: the same cross-period leak in the opposite direction. **Filtering on both sides of a
boundary is what makes two branches actually disjoint**, and a one-sided filter looks complete.

### A `SUM` needs its own test

`summing_offsets_ignores_other_instances` — a `WHERE` that filters rows correctly but still aggregates across
instances passes a per-row assertion and returns the wrong money. I mutation-checked it alongside the
period-boundary test; both failed when I neutralised the filter.

### Lesson for briefs

The most productive line in a brief this session has not been the RCA — it has been **the acceptance criterion
that names an invariant rather than an outcome**. "Round-trip preserves it" and "no invented financial values"
have each found a defect the issue did not describe.

### Session totals

| | |
|---|---|
| Issues closed | **85** |
| Tests | 636 → **1059** (+423) |
| Queue | 149 open |


## Cycle 49: two "defects" that were not defects, and the test that had no teeth

Both `crates/proxy` issues were already satisfied. #160's `/key` append cannot happen (`Custom => None` plus a
trailing `?`, and the caller `else { continue }`). #161's TTFB is recorded at first frame from
`attempt_started`, with `in_flight` released separately — the exact split the issue asked for.

Verification cycle discipline held: tests only, zero production edits, all three test files inside existing
`#[cfg(test)] mod tests` blocks.

### The finding that matters is about the test I would have accepted

The streaming-TTFB test's first cut asserted only `ewma < ceiling`. **Reverting `Some(ttfb_ms)` to `None` still
passed it** — a test that cannot distinguish "recorded the right value" from "recorded nothing".

Fixed with a **lower bound** derived from the numbers: first frame 300 ms, hold 2000 ms, EWMA weight 0.2 → correct
value ≈60, wrong value ≈400. Assertion `40 <= ewma <= 200` is 3x below the wrong value and 7x above zero, so it
survives a loaded runner *and* kills the inert mutant.

**This is cycle 6's "non-discriminating test" class, found by mutation rather than by reading.** The general
lesson: a `<` assertion against a derived quantity needs the *other* side's value named, or it tests
nothing. Assert the gap, not just one end of it.

### Verification cycles are worth running

Neither issue had a bug, but both now have a guard where there was none — and #160's census test puts a five-arm
`match` into one reviewable table. **Two of three defects in this subsystem were in the audit's imagination; the
third was a real missing test that would have let them come back.**

That is the honest yield of a verification cycle, and it is why the brief forbids production edits: an
"already-fixed" close with no test is an opinion, and an "already-fixed" close with a test is a receipt.

### Session totals

| | |
|---|---|
| Issues closed | **87** |
| Tests | 636 → **1063** (+427) |
| Queue | 147 open |
