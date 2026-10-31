> **Optional mode — OFF by default.**
> The default is one worker and no pricing-window gate: nothing is held back
> because of the hour. Enable this only when the operator explicitly asks for it,
> and only for the worker it names — see "Operating modes" in `SKILL.md`. While it
> is off, none of this file applies: no clock check, and no worker parked through
> peak hours.

## Off-Peak Dispatch Gate (worker 2 only, opt-in)

Once enabled, the priced worker is subject to a strict **Peak / Off-Peak Dispatch Gate** in the timezone you set as `$PRICE_TZ`. Any other worker is unaffected and runs continuously.

### 1. Peak vs. off-peak schedule

The windows below are the example this gate was written for (`$PRICE_TZ=Asia/Jakarta`,
WIB, UTC+7). Take the real ones from the provider's current price table — they change.

* **PEAK HOURS (No new dispatches to Worker 2)**:
  * **Monday – Friday**: `08:00 – 10:59 WIB` and `13:00 – 16:59 WIB`
* **OFF-PEAK HOURS (Full dispatch enabled for Worker 2)**:
  * **Monday – Friday**: `00:00 – 07:59 WIB`, `11:00 – 12:59 WIB` (midday window), and `17:00 – 23:59 WIB`
  * **Saturday & Sunday**: All day (`00:00 – 23:59 WIB`)

### 2. Mandatory Clock Check at Every Wait Return & Pre-Dispatch
Never eyeball the clock. After every `worker-wait.sh` return and immediately before dispatching any new brief or fix-up to Worker 2, run this exact shell check:

```bash
TZ=$PRICE_TZ date '+%u %H%M %a %Y-%m-%d %H:%M:%S %Z' | awk '{
  dow=$1; hm=$2+0;
  if (dow <= 5 && ((hm >= 800 && hm < 1100) || (hm >= 1300 && hm < 1700)))
    print "STATUS: PEAK — DO NOT DISPATCH worker-2 (" $0 ")";
  else
    print "STATUS: OFF_PEAK — CLEAR TO DISPATCH worker-2 (" $0 ")";
}'
```

### 3. Execution Rules by Worker State

* **If `STATUS: OFF_PEAK`**:
* Dispatch new cycles and fix-up briefs to Worker 2 normally.


* **If `STATUS: PEAK` and Worker 2 is ALREADY running a cycle**:
* **Leave it alone.** Do NOT interrupt, kill, or pause an in-flight turn. Continue supervising it until it signals completion (`rc 0`) or hits a genuine wall.
* Once Worker 2 finishes its in-flight cycle during Peak hours, run your review and merge/hygiene steps as usual, then **PARK Worker 2 in an idle state** until the next Off-Peak window opens (`11:00 WIB` or `17:00 WIB`).


* **If `STATUS: PEAK` and Worker 2 is IDLE at a cycle boundary**:
* **Do NOT dispatch** a new brief or fix-up to Worker 2.
* **Do NOT attach `worker-wait.sh` to Worker 2** while it is parked (otherwise its 120s idle detector will fire `rc 1` every 2 minutes). Supervise Worker 1 exclusively until the shell check returns `STATUS: OFF_PEAK`, then immediately resume dispatching to Worker 2.
