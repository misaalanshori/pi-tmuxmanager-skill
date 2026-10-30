<!-- worker-dispatch-prompt.md.tpl — substitute ${prompt_path}, ${done_channel}, and ${tmux_socket} per cycle (all required; the scripts have no defaults) -->
Okay, so we have all the things we need you to do documented. We have done major planning, lets just get started immediately by reading this prompt in its entirety and referencing it throughout the session to ensure alignment: ${prompt_path} it contains all the starting info you need to know and need to do to finish this final goal. It also refers to our ./docs and project specifications.

Like usual, ensure you work in phases, ensure each phase is clean and fully tested, then commit and push it, maybe check up on ci once in a while (we have gh cli setup). No need for my approval, ever, the plan is preapproved, go and execute it to completion, if you run into issues try to solve them yourself, any deviations must be documented at the end, but does not necessitate immediate confirmation with me. Ensure everything is documented well.

This project is in Rust and heavily relies on strict Test-Driven Development (TDD). Ensure you write failing tests first, implement the minimal passing solution, and verify against unit/integration test suites and project specifications before marking any phase done. **Crucial testing rule: Test the logic, not the runtime, external data, or things out of our control.** Focus test effort on verifying our own implemented business logic, algorithms, state transitions, routing rules, and transformations. Do not waste effort testing third-party crate internals, OS/kernel runtime behaviors, or upstream provider networks that are already tested upstream—mock or isolate those boundaries.

And also, please no context window anxiety, you musnt be worried about the token budget, we have plenty, all the previous cycles barely hit 80% out of 1M token context window, youre at basically 0% right now, so don't think about context budget, it really doesnt matter at this scale. Focus on doing everything as thoroughly as possible, no shortcuts, no cutting corners, run the tasks given to you properly, check your work, check back on the prompt file once in a while, refer back to the relevant docs and dont make baseless assumptions especially if youre uncertain, read the files and detailed documents in ./docs. Please utilize them.

You have various coding skills, mainly i want you to load (and ensure is loaded) rust-skills, ponytail, and caveman. Load others if it seems relevant or even slightly useful.

**Bound every command that can hang.** This is a standing rule, not a per-cycle
suggestion: a worker that issued an unbounded probe once sat wedged for 3.5 hours and
the cycle was lost. Use `timeout 300 cargo nextest run …`, `timeout 120 ./script`,
`timeout 60 gh run view …`. Choose the ceiling per command — a legitimately slow
suite gets 1200, a probe gets 60 — but never leave a call unbounded, because an
unbounded call is a cycle that can silently disappear. A spin/timeout probe is the
case that most needs the bound, not the least: the thing being measured may genuinely
never terminate, so hitting the ceiling **is** the measurement.

One last thing — the completion protocol: my supervisor process is blocked waiting for a signal from this tmux session. When you have FULLY completed the cycle (all phases done, all gates green, everything pushed, the report written to the path the prompt specifies), run exactly this command once:

    tmux -L ${tmux_socket} wait-for -S ${done_channel}

Then write your final summary in the pane as usual and stop. Do not run the signal early or speculatively — only when the cycle is genuinely complete. If you get blocked or need to hand back early, do NOT signal — just stop working and say so in the pane.
