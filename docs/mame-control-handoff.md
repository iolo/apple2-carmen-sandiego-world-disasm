# Handoff: MAME control lessons for a2-mame

Date: 2026-10-19. Audience: the next maintainer improving the `a2-mame` skill.

Promote the local file-mailbox transport and debugger-aware Lua event loop into
reusable skill tooling. Keep program-specific addresses, route selection, and
completion criteria in a separate adapter. The existing console transport is
still useful for interactive work, but an owned persistent stdin terminal need
not be a requirement for every automation session.

These notes describe completed experiments and proposed improvements. They do
not modify the installed skill. The skill reviewed was
`/home/iolo/.codex/skills/a2skills/a2-mame/SKILL.md`, together with
`references/mame-lua.md` and `scripts/launch.py`.

## Evidence and scope

The fresh autoplay run used MAME 0.285 on Linux, unenhanced `apple2e`, 64K main
RAM plus an `ext80` 64K auxiliary card, and the CFFA202 controller with locally
supplied 6502 firmware. It booted a copy of the user's requested
`build/korean/approved/carmen-world-ko.po`.

The player made 30 arrests, including Carmen, through native game menus. It
reached rank 5, displayed the Hall of Fame, and saved the retired detective's
name to disk. It delivered 2,016 keyboard responses and completed in 59 host
seconds with throttling disabled. This is a measurement from this machine and
workload, not a speed guarantee. A one-case visible run, a one-case headless
run, and a new process continuing the saved detective also passed. The user
subsequently confirmed that watching it worked.

The player is memory-assisted: it reads the culprit and planned route. It
supplies keyboard-register responses without writing game RAM, CPU registers,
code, ranks, clocks, or routes. It does not demonstrate visual clue recognition
or correctness of MAME's host keyboard implementation.

| Evidence or implementation | What to take from it |
| --- | --- |
| [Autoplay receipt](korean/runtime/autoplay.json) | Exact input/script hashes, 30 case starts, final state, disk checks, smaller runs |
| [Autoplay Lua](../tools/korean/autoplay.lua) | Breakpoint phases, input consumption, native-state assertions, cleanup |
| [Player documentation](korean/autoplay.md) | Launch examples and limitations |
| [Mailbox plugin](../tools/korean/mame_plugins/carmen_mailbox/init.lua) | Host-periodic command processing and startup while stopped |
| [Mailbox client](../tools/korean/mame_rpc.py) | Atomic requests, client lock, unique receipts, ambiguous-timeout handling |
| [Mailbox smoke receipt](korean/runtime/mame-mailbox.json) | Earlier recorded tests of pause, debugger stop, Lua errors, screenshots, clean exit |
| [Launcher](../tools/korean/mame.py), [bootstrap](../tools/korean/start.lua) | Profile, disposable media, plugin loading, optional autonomous player |
| [Earlier gameplay tests](../tools/korean/gameplay_test.py) | Natural-keyboard draining and exact menu-row checks |
| [Runtime workflow](korean/runtime-workflow.md) | Banking, input, save, and overlay findings from earlier project work |

The mailbox and natural-keyboard drain existed before this autoplay task.
The autonomous player and its Hall of Fame completion fix were developed in
this task. The installed skill already documents explicit `bpset` arguments,
Qt debugger selection, banking caveats, and scheduled-versus-completed receipts;
retain these as established guidance rather than presenting them as new findings.

The source image hash recorded for the autoplay run is
`d5328b1570fe709811d55d5043c357d351b2f67262b1a23f446395df248e66e1`.
It already differed from the build manifest hash at the first launch. Every
source-image hash recorded during these runs matched that first launch. We
verified the supplied file remained unchanged, not that it matched the older
build manifest. Preserve that distinction when reusing the evidence.

The recorded verified session command used `-noreadconfig`, no video/audio,
and no AVI recording. At handoff, the working launcher has subsequent viewing
customizations: BGFX CRT chains, a fixed `/home/iolo/carmen.avi` output, and
configuration loading enabled. Preserve the user's changes. For reproducing
the measured baseline, use the recorded session command, not an assumption
that today's launcher is identical. General skill tooling should make shaders,
recording paths, and configuration loading explicit options.

## 1. Add a mailbox transport alongside the console

The project's plugin registers `emu.register_periodic(...)`. In the tested
version, this callback runs while the CPU is stopped in the debugger and while
the machine is ordinarily paused. That allows the host to inspect state and
resume execution without waiting for another emulated frame or stdin read.
The earlier mailbox smoke receipt directly checks those states.

The useful protocol is small:

1. Create a new, private session directory and launch an owned process.
2. The plugin waits until the machine, CPU, address space, and debugger exist.
3. Initialize helpers, then write `ready.json` with version, driver, and success
   or failure. A ready file records startup; a fresh request tests liveness.
4. The client takes a single-client lock and writes a unique request to a
   temporary file, then atomically renames it to `request.json`.
5. The plugin archives the accepted request under its ID before executing it.
6. Run one operation under `pcall`; write a matching response by atomic rename.
7. Archive failures as receipts too, so malformed Lua need not disable control.

A response saying `scheduled='go'` means the command was accepted. It does not
mean the target breakpoint has been reached. Save, restore, and exit have the
same distinction. Observe the subsequent state or artifact.

After a timeout, inspect the exact accepted request and its receipt before
retrying a mutation. The operation may already have executed. The current
client refuses to overwrite a pending request or proceed past an accepted
request with no receipt. Preserve this behavior in any generic client.

Suggested extraction: a generic plugin/client using `A2_MAME_*` environment
variables and a configurable startup module. Remove Korean maps, game bootstrap,
and absolute skill-installation paths from the transport layer. Preserve the
skill launcher's existing portable plugin discovery instead of copying this
project's Linux-only plugin directory. Treat initialization failure as a
terminal transport state until an explicit recovery or fresh session.

Arbitrary `--lua` is an intentional local code-execution interface. Keep its
files private to the owner and retain the owned-process model; this experiment
does not establish a remotely exposed service design.

## 2. Run repeated control decisions inside Lua

Autoplay uses the mailbox plugin for startup, but does not make one Python RPC
per key. Its Lua controller registers another periodic callback and reacts to
owned breakpoints:

```lua
-- Sketch: handlers and owned breakpoints are installed by the program adapter.
emu.register_periodic(function()
    if not active then return end
    if machine.debugger.execution_state ~= 'stop' then return end
    local handler = handlers[cpu.state.PC.value]
    -- Unknown stops must become a diagnostic result, not an automatic resume.
    assert(handler, 'unexpected debugger stop')
    handler()
    if active then
        emu.unpause()
        cpu.debug:go()
    end
end)
```

The actual player wraps handlers in `pcall`, writes a result on failure, and
cleans up its owned resources. Include those protections in a reusable helper;
the sketch above only shows dispatch. A handler returns promptly. It never
loops waiting for the emulated CPU to advance inside the Lua callback.

Use `machine.debugger.execution_state` for debugger stops. Ordinary pause is
a separate state. `emu.unpause()` followed by `cpu.debug:go()` resumes both
layers in the tested workflow. Observe a breakpoint before making changes
that require a 6502 instruction boundary; an ordinary pause alone is weaker.

Retain explicit `cpu.debug:bpset(address, '1', '')` arguments for 0.285, as the
existing skill requires. Store each returned ID and remove only owned IDs.
There is no reason to erase a user's unrelated breakpoints.

Give a session one execution controller. A mailbox lock serializes host
requests; it does not serialize those requests against an active autonomous
Lua player. Stop or suspend the player before issuing independent execution
commands. An unrelated debugger stop should halt automation for inspection.

The current player has a 180-second host-wall-time progress watchdog and an
`active` flag that makes its callback inert after completion. It caches CPU
and address-space handles for one cold boot. A generic version must handle
reset/load lifecycle explicitly and reacquire handles; this run does not
validate resetting or restoring a state while the player is active.

## 3. Offer distinct keyboard-control modes

| Mode | Appropriate use | Required observation |
| --- | --- | --- |
| Natural keyboard | Human-like strings and ordinary software use | Verify queue delivery and program consumption |
| Physical field press/release | Arrows, modifiers, joystick buttons; testing driver input | Enumerate the selected driver's fields and verify release |
| One-shot keyboard-register response | Instrumented automation at known polling instructions | Verify the intended CPU read consumes exactly one byte |

The previous gameplay tests found that a posted Return can survive a debugger
stop and affect a following menu. Repeated physical arrows can also look like
one continuous hold without an emulated release interval. Open Apple speeds
text in this game but also acts as confirmation, so it can change menu behavior.

Those earlier tests allow the natural-keyboard queue to drain, disable fast
text, and wait for both `natkeyboard.empty` and `not natkeyboard.is_posting`
plus an emulated idle interval. Their temporary read taps suppress stale
keyboard/button input during that interval. This is an instrumented workaround,
not proof of an entirely unmodified physical-input path. Queue emptiness alone
also does not prove the game consumed the intended action.

For autoplay, we used a more direct input mode. Stop immediately before a known
`LDA $C000`, arm one byte, and resume. A retained read-tap handle substitutes the
next real CPU keyboard read and clears the pending byte:

```lua
local pending_key
local tap = space:install_read_tap(0xC000, 0xC000, 'a2-one-key',
    function(_, data)
        if pending_key ~= nil and not machine:side_effects_disabled() then
            local value = pending_key
            pending_key = nil
            return value | 0x80
        end
        return data
    end)

-- Only at an adapter-verified keyboard polling breakpoint:
assert(pending_key == nil)
pending_key = 0x0D -- Return
emu.unpause()
cpu.debug:go()
```

The next relevant breakpoint asserts that the pending byte was consumed.
No helper reads `$C000` to check it. Debugger reads with side effects disabled
must not drain the pending key. Keep the tap object alive, and call
`tap:remove()` during shutdown/error cleanup.

This tap is armed for the next CPU read, not for an intrinsically identified
caller. Its correctness depends on stopping at the verified keyboard polling
instruction and resuming into that read. A generic helper should refuse to arm
at arbitrary PCs and verify the expected instruction bytes. The player checks
`AD 00 C0` at its three N polling symbols after that module loads. Those short
checks detect some mismatches; they are not a complete binary identity check.

Do not describe this mode as a full Apple II keyboard-latch emulation. It
substitutes one response; it does not reproduce latch persistence, typematic
repeat, or modifier hardware. Programs that reread the latch or process keys
differently need their own adapter. In this game, Return is `$0D`, previous row
is `$08`, and next row is `$15`; these are consumer-specific decisions.

## 4. Scope breakpoints and symbols to the loaded module

Carmen's intro R and gameplay N both occupy `$6000` and overlap other addresses.
Installing all N breakpoints during boot could interpret intro execution as a
gameplay event. The successful sequence was:

1. Install the intro keyboard-poll and `R_ENTER_GAME` breakpoints.
2. At the intro handoff, remove those owned breakpoints.
3. Wait for the subsequently loaded `N_MAIN_ENTRY` at `$6000`.
4. Check known instructions against N's symbols, then install N handlers.

Use build-produced symbol maps instead of copied numeric address lists. Track
module identity and relevant bank mapping along with PC. Keep this technique in
the generic reference, but leave actual handoff addresses in game adapters.

Likewise, CPU-mapped memory is not always main RAM. The earlier runtime work
identified auxiliary zero page at the game's normal screens. Read case state
through the current CPU mapping at known stops; record ALTZP/RAMRD/RAMWRT and
other relevant switches for dumps that must be interpreted later. Do not
replace mapped reads with direct-pointer reads without understanding the bank.

## 5. Completion is a program-specific state machine

The first full attempt did arrest Carmen and save retirement, but my controller
expected the final screen to wait in `N_POLL_KEY_OR_BUTTON`. The Hall of Fame
actually calls `N_READ_GAME_KEY`, reaching `N_POLL_GAME_KEYBOARD`. Autoplay
therefore pressed through the finished screen, returned to registration, and
reported a name-input error. MAME itself exited normally.

The fix was to detect retirement and entry into the Hall of Fame, then stop at
its actual input wait before supplying another key. Both polling handlers now
honor the terminal condition. The corrected run left the native state at
suspect 0, warrant 0, rank 5, solved count 30, with the Hall of Fame displayed.

This is why a generic runner needs adapter-defined terminal predicates and an
explicit result receipt. A return to some familiar prompt, one favorable
counter, or MAME exit code 0 is insufficient. A clean emulator exit can still
accompany an automation error.

The successful run checked three levels:

- Input outcome: native menu choices, unique warrant, expected route destination.
- Game outcome: correct-arrest path, incremented solved count, retirement rank.
- Persistence: after exit, extract F/G and verify the retired name in G and its
  removal from F; compare unrelated files and the original input hash.

An initial verification assertion expected both F and G to differ at the end.
That was too strict: this fresh detective's F slot returned to its original
empty bytes after retirement, so only G differed. Verify intended file contents
and permitted changes rather than requiring every file written to have a final
byte difference. The one-case run separately showed F containing rank 1 and
one solved case. Continuing that disk in a fresh process reached two solved
cases. This continuation test was progress persistence, not an H saved-case
restore test and not MAME save-state interchange.

## 6. Capture pixels and time without disturbing the state

A PNG taken at a debugger stop may show the previous rendered frame. The
player saves both a MAME screenshot and the exact current HGR page bytes. In
this game's known display mapping it reads PAGE2 status at `$C01C`, selects
`$2000` or `$4000`, and dumps 8,192 bytes. An offline monochrome HGR renderer
confirmed the Korean Hall of Fame screen with `LUASLEUTH`.

That extraction is specific to this game's standard HGR mode and mapped bank.
A reusable capture helper must account for video mode, page selection, and
main/aux mapping. Do not generalize it to double-hires, 80-column text, or every
IIe banking state. Keep the raw dump and mapping metadata beside the PNG. If
using an extra rendered frame instead, ensure advancing emulation cannot lose
the state being documented.

Record both host elapsed time and `machine.time:as_double()`. Use host timeouts
to detect stalled control; use emulated time for keyboard release intervals.
A host sleep has very different emulated effects under throttle and fast-forward.
The current Lua watchdog uses coarse `os.time()`; a generic host supervisor can
use a monotonic clock and should separately bound overall run time.

## 7. Generalize the machine and media profile carefully

The working hardware portion was:

```text
apple2e -aux ext80 -ramsize 64K -sl7 cffa202 -hard1 <copied-media.hdv>
```

The copy is still a raw 800K ProDOS image. Changing the extension from `.po` to
`.hdv` here selects an accepted hard-disk media path; it is not a format
conversion or a universal rule for `.po` files. The 6502 CFFA firmware permits
this unenhanced IIe profile. Verify both machine and card ROMs and inspect media
slots after configuring the controller. The current skill launcher's `--disk`
always uses `-flop1`, so this workflow needs an explicit controller/media profile.

For the recorded headless run, use `-debug -debugger qt -video none -sound none`
with SDL dummy video/audio and `QT_QPA_PLATFORM=offscreen`. The existing skill
warns that the `none` debugger backend does not reliably hold stops in 0.285;
retain that version-specific guidance. Display suppression and debugger
selection are separate choices.

Expose visibility and throttle independently: `--visible` to watch, throttle
for original speed, fast-forward for automation. Leave rendering shaders and
AVI recording opt-in. Copy writable media before launching, isolate output
paths, record the exact command and hashes, and wait for the owned process to
exit before checking saved files. Keep originals unchanged.

## Proposed skill changes, in implementation order

| Priority | Change | Acceptance evidence to require |
| --- | --- | --- |
| 1 | Make console and mailbox first-class transport choices in SKILL.md; extract a generic plugin/client | Fresh request succeeds while running, ordinarily paused, and debugger-stopped; Lua error produces receipt; exit needs no stdin wakeup |
| 2 | Add a bounded Lua breakpoint dispatcher with resource ownership | Known handlers run; unknown stop becomes diagnostic; only owned breakpoints/taps removed; player can be stopped without killing MAME |
| 3 | Add an explicit opt-in one-shot input adapter | Two identical keys create exactly two intended actions; debugger reads do not consume them; wrong PC/opcode is rejected; pending key is cleared on stop |
| 4 | Add named machine/controller/media profiles and independent visibility/throttle options | Existing floppy fixture still works; IIe/ext80/CFFA copy boots with verified ROMs; source hash unchanged |
| 5 | Add structured session/result/capture artifacts | Operation acceptance distinguished from completion; failed automation visible despite exit code 0; paused image lag handled with evidence |
| 6 | Add overlay/bank lifecycle guidance and reset cleanup | Fixture with reused addresses cannot fire stale module handlers; reset invalidates or rebuilds cached handles |

Keep SKILL.md short: select profile and transport, launch an owned session,
check receipts, verify outcomes, clean up. Put mailbox details, precise input,
and event-driven automation in focused reference files. Retain the current
console path, platform notes, helper API, and smoke fixtures as regression
coverage. The Carmen player should remain an integration example, with its
route/trait/game-state logic outside the general MAME skill.

Cross-platform mailbox behavior, other MAME releases, other Apple II drivers,
concurrent controllers, and reset/save-state recovery during active autoplay
remain unverified by this task. Any proposed generic implementation should test
those separately before claiming support.
