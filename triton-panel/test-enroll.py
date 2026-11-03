"""Drive EnrollWindow's result handler with synthetic EnrollStatus events.

The path a real finger reaches only by accident: a driver fault must restart
the enrollment WITHOUT tearing down the g-signal subscription, or the next
status would go nowhere and the window would look hung.
"""
import importlib.util, importlib.machinery, sys, time, types

spec = importlib.util.spec_from_loader(
    "tp", importlib.machinery.SourceFileLoader("tp", "triton-panel"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
EW = m.EnrollWindow

FAILS = []
def check(cond, label):
    print(("  ok   " if cond else "  FAIL ") + label)
    if not cond:
        FAILS.append(label)


class Label:
    def __init__(self): self.text = ""
    def set_text(self, t): self.text = t

class Button:
    def __init__(self):
        self.sensitive = None; self.label = None; self.css = set()
    def set_sensitive(self, v): self.sensitive = v
    def set_label(self, v): self.label = v
    def add_css_class(self, c): self.css.add(c)
    def remove_css_class(self, c): self.css.discard(c)

class Strip:
    def __init__(self): self.marks = []; self.supported = True
    def close_open_contact(self): return 0.31
    def mark(self, kind, duration=None): self.marks.append((kind, duration))
    def reset(self): self.marks.clear()
    def set_present(self, v): pass

class Dots:
    def __init__(self): self.passed = 0
    def set_passed(self, n): self.passed = n
    def configure(self, n): pass

class Banner:
    def __init__(self): self.revealed = False
    def set_revealed(self, v): self.revealed = v

class Device:
    """Records method calls; `fail_on` makes one of them raise."""
    def __init__(self, fail_on=None): self.calls = []; self.fail_on = fail_on
    def call_finish(self, result): return None
    def get_cached_property(self, name): return None
    def call_sync(self, method, args, flags, timeout, cancellable):
        self.calls.append(method)
        if method == self.fail_on:
            raise m.GLib.Error(f"{method} refused")
        return None


def make(stages=6, fail_on=None):
    o = types.SimpleNamespace()
    o.info = {"gesture": "press", "scan_type": "swipe", "stages": stages,
              "driver_scan_type_wrong": True}
    o.finger = "right-index-finger"
    o.label = "Right index"
    o.stages = stages
    o.passed = 0
    o.attempts = 0
    o.tally = {}
    o.restarts = 0
    o._dry_restarts = 0
    o._contact_since_restart = False
    o._restart_block = None
    o.running = True
    o.completed = False
    o._signal_handler = "SIGNAL-ALIVE"
    o._props_handler = "PROPS-ALIVE"
    o._tick_id = 42
    o.MAX_RESTARTS = EW.MAX_RESTARTS
    o.MAX_DRY_RESTARTS = EW.MAX_DRY_RESTARTS
    o.MAX_CAL_DRY = EW.MAX_CAL_DRY
    o.TICK_MS = EW.TICK_MS
    o.CAL_WINDOW = EW.CAL_WINDOW
    o.CAL_REQUIRED = EW.CAL_REQUIRED
    o.CAL_MIN = EW.CAL_MIN
    o.phase = "enroll"
    o.cal_log = []
    o.cal_tally = {}
    o.cal_attempts = 0
    o.cal_matched = 0
    o._cal_dry = 0
    o._cal_contact = False
    o._lifted = True
    o._presence_changes = 0
    o._last_counted_at = 0.0
    o._cal_noted_no_lift = False
    o._cal_suppressed = 0
    o._last_phase = None
    o._released = False
    o.SAME_PRESS_S = EW.SAME_PRESS_S
    o.calibrated = False
    o.device = Device(fail_on)
    o.strip = Strip()
    o.dots = Dots()
    o.banner = Banner()
    o.count_label = Label()
    o.status_label = Label()
    o.hint_label = Label()
    o.tally_label = Label()
    o.cal_button = Button()
    o.start_button = Button()
    o.stop_button = Button()
    o.cal_status = Label()
    o.cal_meter = Label()
    o.cal_detail = Label()
    o.cal_tally_label = Label()
    o.stages_note = Label()
    o.log = []
    o.stopped = []
    # stubs: _add_log builds Gtk widgets, _stop is what must NOT run
    o._add_log = lambda kind, title, detail: o.log.append((kind, title, detail))
    o._stop = lambda release=True: o.stopped.append(release)
    o._toast = lambda message, timeout=5: None
    o._render_live = lambda present, needed: None
    o._saw_contact = False
    # real behaviour under test
    o.ENROLL_REGIONS = EW.ENROLL_REGIONS
    for name in ("_handle_result", "_restart_enrollment", "_may_restart",
                 "_cycle_hint", "_update_tally", "_handle_verify_result",
                 "_stage_hint", "_region_for",
                 "_cal_gate", "_update_cal", "_verify_cycle",
                 "_idle_buttons", "_update_cal_tally", "_set_stages_note",
                 "_on_properties_changed"):
        setattr(o, name, getattr(EW, name).__get__(o, types.SimpleNamespace))
    return o


print("\n1. a retry continues and does not read as a stop")
o = make()
o._handle_result("enroll-retry-scan", False)
check(o.passed == 0, "no stage credited")
check(o.attempts == 1, "attempt counted")
check(o.restarts == 0, "no restart")
check(o.stopped == [], "_stop not called")
check("still going" in o.status_label.text, f"status names progress: {o.status_label.text!r}")
check("Lift the finger clear" in o.hint_label.text, "retry hint says to lift")

print("\n2. a terminal driver fault restarts without tearing down")
o = make()
o._handle_result("enroll-unknown-error", True)
check(o.restarts == 1, "restart counted")
check(o.device.calls == ["EnrollStop", "EnrollStart"], f"D-Bus: {o.device.calls}")
check(o.stopped == [], "_stop NOT called -- subscription kept")
check(o._signal_handler == "SIGNAL-ALIVE", "g-signal handler still connected")
check(o._props_handler == "PROPS-ALIVE", "properties handler still connected")
check(o._tick_id == 42, "tick still running")
check("Claim" not in o.device.calls, "no re-Claim, so no password prompt")
check(o.tally.get("Driver fault") == 1, "fault counted in the tally")
check("restarted (1)" in o.status_label.text, f"status: {o.status_label.text!r}")

print("\n3. the next status after a restart still lands")
o._handle_result("enroll-stage-passed", False)
check(o.passed == 1, f"stage credited after the restart: passed={o.passed}")
check(o.count_label.text == "1 / 6", f"count: {o.count_label.text!r}")

print("\n4. a restart that loses stages says so")
o = make()
o.passed = 3
o._handle_result("enroll-unknown-error", True)
check("discarded the 3 stages" in o.hint_label.text, f"hint: {o.hint_label.text!r}")
check(o.passed == 0 and o.count_label.text == "0 / 6", "counter honestly reset")

print("\n5. dry-restart cap trips on a wedged reader")
o = make()
for i in range(4):
    o._handle_result("enroll-unknown-error", True)
check(o.restarts == 3, f"restarted 3 times then stopped (restarts={o.restarts})")
check(o._dry_restarts == 3, f"dry restarts counted: {o._dry_restarts}")
check(o.stopped == [True], "_stop called once the cap tripped")
check("wedged" in (o._restart_block or ""), f"reason: {o._restart_block!r}")
check("fp-debug.sh rebind" in o.hint_label.text, "points at the recovery")
check(o.start_button.label == "Try again", "manual retry offered")

print("\n6. real contact between faults resets the dry counter")
o = make()
for i in range(6):
    o._contact_since_restart = True          # the user actually touched it
    o._handle_result("enroll-unknown-error", True)
check(o.restarts == 6, f"kept going: restarts={o.restarts}")
check(o._dry_restarts == 0, f"dry counter stays 0: {o._dry_restarts}")
check(o.stopped == [], "never stopped")

print("\n7. hard ceiling")
o = make()
o.restarts = EW.MAX_RESTARTS
o._handle_result("enroll-unknown-error", True)
check(o.stopped == [True], "_stop called at the ceiling")
check(f"{EW.MAX_RESTARTS} restarts" in (o._restart_block or ""), f"reason: {o._restart_block!r}")
check("not your gesture" in o.hint_label.text, "still does not blame the gesture")

print("\n8. a fatal result is NOT auto-restarted")
for res in ("enroll-duplicate", "enroll-data-full", "enroll-failed"):
    o = make()
    o._handle_result(res, True)
    check(o.restarts == 0 and o.stopped == [True], f"{res}: stopped, not restarted")

print("\n9. a failing EnrollStart on restart degrades cleanly")
o = make(fail_on="EnrollStart")
o._handle_result("enroll-unknown-error", True)
check(o.stopped == [True], "released after a failed restart")
check("Could not restart" in o.status_label.text, f"status: {o.status_label.text!r}")
check("rebind" in o.hint_label.text, "points at the recovery")

print("\n10. success still works")
o = make()
o._handle_result("enroll-completed", True)
check(o.completed is True, "completed")
check(o.stopped == [True], "released on success")

print("\n11. tally mentions restarts")
o = make()
o._handle_result("enroll-unknown-error", True)
o._handle_result("enroll-retry-scan", False)
check("1 restart ·" in o.tally_label.text, f"singular: {o.tally_label.text!r}")
o._handle_result("enroll-unknown-error", True)
check("2 restarts ·" in o.tally_label.text, f"plural: {o.tally_label.text!r}")

# --------------------------------------------------------------------------- #
# Calibration: the verify loop's state-machine invariant
#
# fprintd requires VerifyStop before the next VerifyStart once a VerifyStatus
# has arrived with done = True -- and both match and no-match are done = True.
# A retry (done = False) leaves the verify OPEN and fprintd already waiting,
# so cycling it would throw the operation away mid-flight. That asymmetry is
# invisible from the UI and is exactly what a later edit breaks silently.
# --------------------------------------------------------------------------- #

def cal(**kw):
    o = make(**kw)
    o.phase = "calibrate"
    o.running = True
    return o


def lift(o):
    """The finger coming off, as finger-present would report it."""
    o._on_properties_changed(
        None, m.GLib.Variant("a{sv}", {"finger-present": m.GLib.Variant("b", False)}), None)


def press(o, result, done=True):
    """One placement: the result arrives, then the finger comes off.

    Tests must model the lift, because since §20r a result with no lift since
    the last counted one is deliberately not a measurement.
    """
    o._handle_verify_result(result, done)
    lift(o)


print("\n12. a retry (done=False) does NOT cycle the verify")
o = cal()
o._handle_verify_result("verify-retry-scan", False)
check(o.device.calls == [], f"no D-Bus call: {o.device.calls}")
check(o.cal_attempts == 1, "attempt counted")
check(o.cal_log == [False], f"recorded as not scored: {o.cal_log}")
check("Lift the finger clear" in o.hint_label.text, "retry hint says to lift")

print("\n12b. the calibration tally is RENDERED, not just collected")
o = cal()
press(o, "verify-no-match")
press(o, "verify-no-match")
o._handle_verify_result("verify-retry-scan", False)
check("3 attempts" in o.cal_tally_label.text, f"tally: {o.cal_tally_label.text!r}")
check("2x Scored, did not match" in o.cal_tally_label.text, "counts by result")
check("1x No usable detail" in o.cal_tally_label.text, "both results shown")
check(o.tally_label.text == "", "the ENROLMENT tally stays empty -- different phase")

print("\n12c. the Stages card says why it is idle instead of looking broken")
o = cal()
o._set_stages_note()
check("Not in use" in o.stages_note.text, f"calibrating: {o.stages_note.text!r}")
o.phase = "enroll"; o._set_stages_note()
check(o.stages_note.text == "", "silent while enrolling")
o.phase = "idle"; o.passed = 0; o.completed = False; o._set_stages_note()
check("during enrolment" in o.stages_note.text, f"idle: {o.stages_note.text!r}")
o.passed = 3; o._set_stages_note()
check(o.stages_note.text == "", "silent once stages have real history")

print("\n13. a terminal result re-arms AT ONCE -- the device is never deaf")
o = cal()
o._handle_verify_result("verify-no-match", True)
check(o.device.calls == ["VerifyStop", "VerifyStart"], f"D-Bus: {o.device.calls}")
check(o.cal_log == [True], f"no-match counts as SCORED: {o.cal_log}")
check(o.cal_matched == 0, "no-match is not a match")
check(o.strip.marks == [("scored", 0.31)], f"marked distinctly: {o.strip.marks}")
check(o.stopped == [], "_stop not called -- the loop keeps the claim")

print("\n14. a match is recorded and still cycles")
o = cal()
press(o, "verify-match")
check(o.cal_matched == 1, "match counted")
check(o.cal_log == [True], "scored")
check(o.device.calls == ["VerifyStop", "VerifyStart"], f"D-Bus: {o.device.calls}")
check("Matching works" in o.cal_status.text, f"status: {o.cal_status.text!r}")

print("\n15. a driver fault is NOT placement evidence")
o = cal()
press(o, "verify-disconnected")
check(o.cal_log == [], f"kept out of the rolling window: {o.cal_log}")
check(o.cal_attempts == 1, "still counted as an attempt")
check(o.device.calls == ["VerifyStop", "VerifyStart"], "loop continues")

print("\n16. dry driver faults stop the loop instead of spinning")
o = cal()
for _ in range(EW.MAX_CAL_DRY):
    press(o, "verify-unknown-error")
check(o._cal_dry == EW.MAX_CAL_DRY, f"dry faults counted: {o._cal_dry}")
check(o.stopped == [True], "released once the cap tripped")
check("rebind" in o.hint_label.text, "points at the recovery")
check(o.cal_log == [], "nothing blamed on the hand")

print("\n17. real contact between faults keeps the loop alive")
o = cal()
for _ in range(EW.MAX_CAL_DRY + 2):
    o._cal_contact = True
    press(o, "verify-unknown-error")
check(o._cal_dry == 0, f"dry counter stays 0: {o._cal_dry}")
check(o.stopped == [], "never stopped")

print("\n18. the gate is a rolling window, and needs a floor of attempts")
o = cal()
o.cal_log = [True] * 8
check(o._cal_gate() == (False, 8, 8), f"8 scored but under CAL_MIN: {o._cal_gate()}")
o.cal_log = [True] * 8 + [False, False]
check(o._cal_gate() == (True, 8, 10), f"8 of the last 10: {o._cal_gate()}")
o.cal_log = [True] * 8 + [False] * 3
check(o._cal_gate()[0] is False, "early successes fall out of the window")
o.cal_log = [False] * 20 + [True] * 10
check(o._cal_gate()[0] is True, "a converged placement passes despite a bad start")

print("\n19. calibrated + nothing matched points at the TEMPLATE, not the hand")
o = cal()
o.cal_log = [True] * 10
o.phase = "idle"
o._update_cal()
check(o.calibrated is True, "gate passed")
check("TEMPLATE" in o.cal_detail.text, f"detail: {o.cal_detail.text!r}")
check(o.start_button.label == "Enroll now", f"button: {o.start_button.label!r}")
check("suggested-action" in o.start_button.css, "enroll becomes the suggested action")

print("\n20. thin captures refuse to recommend re-enrolling")
o = cal()
o.cal_log = [False] * 10
o.phase = "idle"
o._update_cal()
check(o.calibrated is False, "gate not passed")
check("too thin" in o.cal_status.text, f"status: {o.cal_status.text!r}")
check("another template that cannot be matched" in o.cal_detail.text,
      "says why enrolling now would be pointless")
check(o.start_button.label == "Enroll anyway", f"button: {o.start_button.label!r}")

print("\n21. a failing VerifyStart degrades cleanly")
o = cal(fail_on="VerifyStart")
ok = o._verify_cycle(first=True)
check(ok is False, "reports failure")
check(o.stopped == [True], "released")
check("rebind" in o.hint_label.text, "points at the recovery")

print("\n22. enrol after calibration tells you to reuse that placement")
o = make()
o.calibrated = True
o._begin_enroll = EW._begin_enroll.__get__(o, types.SimpleNamespace)
o._tick = lambda: False
o._begin_enroll()
check("DIFFERENT part of the finger" in o.hint_label.text, f"hint: {o.hint_label.text!r}")
check("the centre of your fingertip" in o.hint_label.text, "names the first region")
check(o.device.calls == ["EnrollStart"], f"D-Bus: {o.device.calls}")
check(o.phase == "enroll", f"phase: {o.phase}")

# --------------------------------------------------------------------------- #
# The Test button: one-shot verify from the main group.
#
# What is actually at risk here is not the verdict but the CLAIM. fprintd
# grants one at a time and a leaked claim leaves the next Super+L with no
# fingerprint until fprintd times it out -- and a verify nobody touches never
# ends on its own. So every exit path must release, and that is what these
# assert.
# --------------------------------------------------------------------------- #

TW = m.TritonWindow


class Row:
    def __init__(self): self.subtitle = ""; self.sensitive = None
    def set_subtitle(self, t): self.subtitle = t
    def set_sensitive(self, v): self.sensitive = v


class Params:
    def __init__(self, *values): self.values = values
    def unpack(self): return self.values


def tw(**kw):
    o = types.SimpleNamespace()
    o.fp_device = Device(kw.get("fail_on"))
    o.fp_info = {"gesture": "press", "scan_type": "swipe"}
    o._enrolling = False
    o._testing = True
    o._test_sig = None
    o._test_timeout_id = None
    o._test_selected = None
    o.TEST_TIMEOUT_MS = TW.TEST_TIMEOUT_MS
    o.fp_test_row = Row()
    o.fp_test_button = Button()
    o.fp_finger_row = Row()
    o.fp_enroll_button = Button()
    o.fp_delete_button = Button()
    o.fp_delete_row = Row()
    o.toasts = []
    o._toast = lambda msg, timeout=5: o.toasts.append(msg)
    for name in ("_on_test_signal", "_test_end", "_on_test_timeout",
                 "_on_fp_test", "_on_test_claimed"):
        setattr(o, name, getattr(TW, name).__get__(o, types.SimpleNamespace))
    return o


print("\n23. a retry does NOT release the claim")
o = tw()
o._on_test_signal(None, None, "VerifyStatus", Params("verify-retry-scan", False))
check(o.fp_device.calls == [], f"no D-Bus call: {o.fp_device.calls}")
check(o._testing is True, "still testing")
check("try again" in o.fp_test_row.subtitle, f"subtitle: {o.fp_test_row.subtitle!r}")

print("\n24. a match releases and names the finger")
o = tw()
o._on_test_signal(None, None, "VerifyFingerSelected", Params("right-index-finger"))
check(o._test_selected == "right-index-finger", "finger remembered")
o._on_test_signal(None, None, "VerifyStatus", Params("verify-match", True))
check(o.fp_device.calls == ["VerifyStop", "Release"], f"D-Bus: {o.fp_device.calls}")
check(o._testing is False, "no longer testing")
check("Right index" in o.fp_test_row.subtitle, f"subtitle: {o.fp_test_row.subtitle!r}")
check(o.fp_test_button.label == "Test", "button reset")
check(o.toasts and "matched" in o.toasts[0], f"toast: {o.toasts}")
check(o.fp_enroll_button.sensitive is True, "other controls re-enabled")

print("\n25. no-match releases and blames the stored print, not the finger")
o = tw()
o._on_test_signal(None, None, "VerifyStatus", Params("verify-no-match", True))
check(o.fp_device.calls == ["VerifyStop", "Release"], f"D-Bus: {o.fp_device.calls}")
check("stored print, not your finger" in o.fp_test_row.subtitle,
      f"subtitle: {o.fp_test_row.subtitle!r}")

print("\n26. a driver fault releases and does not blame the hand")
o = tw()
o._on_test_signal(None, None, "VerifyStatus", Params("verify-disconnected", True))
check(o.fp_device.calls == ["VerifyStop", "Release"], "released")
check("Not your hand" in o.fp_test_row.subtitle, f"subtitle: {o.fp_test_row.subtitle!r}")
check("rebind" in o.fp_test_row.subtitle, "points at the recovery")

print("\n27. the timeout releases the reader")
o = tw()
o._test_timeout_id = m.GLib.timeout_add(600000, lambda: False)
o._on_test_timeout()
check(o.fp_device.calls == ["VerifyStop", "Release"], "released on timeout")
check(o._test_timeout_id is None, "timer cleared")
check("released" in o.fp_test_row.subtitle, f"subtitle: {o.fp_test_row.subtitle!r}")

print("\n28. Cancel releases, and _test_end is safe twice")
o = tw()
o._on_fp_test(None)                      # _testing was True -> this cancels
check(o.fp_device.calls == ["VerifyStop", "Release"], f"D-Bus: {o.fp_device.calls}")
check(o._testing is False, "cancelled")
o._test_end("again")
check(o.fp_device.calls == ["VerifyStop", "Release", "VerifyStop", "Release"],
      "idempotent and still safe")

print("\n29. a claim granted after Cancel is released, not used")
o = tw()
o._testing = False                        # Cancel already ran
o._on_test_claimed(o.fp_device, None, None)
check(o.fp_device.calls == ["Release"], f"D-Bus: {o.fp_device.calls}")
check(o._test_sig is None, "never subscribed")

print("\n30. a failing VerifyStart releases")
o = tw(fail_on="VerifyStart")
o.fp_device.connect = lambda sig, cb: "SIG"
o._on_test_claimed(o.fp_device, None, None)
check("VerifyStart failed" in o.fp_test_row.subtitle, f"subtitle: {o.fp_test_row.subtitle!r}")
check("Release" in o.fp_device.calls, f"released: {o.fp_device.calls}")
check(o._testing is False, "not left testing")

# --------------------------------------------------------------------------- #
# Per-stage coverage (§20q).
#
# An enrolled NBIS print is a GPtrArray of per-stage minutiae sets and
# fpi_print_bz3_match returns success on the FIRST stored set to reach the bz3
# threshold -- one-of-N, not a composite. So each stage must capture a
# DIFFERENT region, and the window has to say which. The old copy said to
# repeat one placement, which wasted five of the six slots.
# --------------------------------------------------------------------------- #

print("\n31. each accepted stage names the NEXT region, not a repeat")
o = make()
seen = []
for n in range(1, 6):
    o._handle_result("enroll-stage-passed", False)
    seen.append(o.hint_label.text)
check(o.passed == 5, f"five stages credited: {o.passed}")
check(f"For stage 2, use {EW.ENROLL_REGIONS[1]}" in seen[0], f"after stage 1: {seen[0]!r}")
check(f"For stage 6, use {EW.ENROLL_REGIONS[5]}" in seen[4], f"after stage 5: {seen[4]!r}")
check(len({t for t in seen}) == 5, "a different instruction after every stage")
check(all("ANY one of them matches" in t for t in seen), "says why coverage wins")
check(all("Lift the finger clear" in t for t in seen), "still says to lift")

print("\n32. the last stage does not invent a seventh region")
o = make()
for _ in range(6):
    o._handle_result("enroll-stage-passed", False)
check(o.passed == 6, "all six credited")
check("For stage 7" not in o.hint_label.text, f"no stage 7: {o.hint_label.text!r}")
check("Lift the finger clear" in o.hint_label.text, "falls back to the plain cycle hint")

print("\n33. a device reporting a different stage count still gets regions")
o = make(stages=5)
for _ in range(4):
    o._handle_result("enroll-stage-passed", False)
check("For stage 5" in o.hint_label.text, f"stages=5: {o.hint_label.text!r}")
o._handle_result("enroll-stage-passed", False)
check("For stage 6" not in o.hint_label.text, "stops at the device's own count")
o = make(stages=8)
check(o._region_for(7) is not None, "stages=8 gets a region for stage 8 (modulo)")
check(o._region_for(8) is None, "and nothing past the end")
check(o._region_for(-1) is None, "negative index is not a region")

# --------------------------------------------------------------------------- #
# One press is one measurement (§20r).
#
# The real session that exposed this: 44 s of `No minutiae found` / protocol
# error alternating every 1-3 s while the finger never left the pad. Every
# done=True re-armed the verify immediately, every fresh VerifyStart captured
# the SAME resting finger, and each garbage image appended another False to
# the rolling window -- so the gate announced "Captures are too thin" about a
# finger that had been placed once. The invariant: a result with no lift since
# the last counted one must not touch cal_log and must not start a verify.
# --------------------------------------------------------------------------- #

print("\n34. a second result from the SAME press is not counted")
o = cal()
o._handle_verify_result("verify-retry-scan", True)       # first touch: counted
check(o.cal_log == [False], f"first counted: {o.cal_log}")
check(o._lifted is False, "lift flag cleared by the counted result")
o.device.calls.clear()
o._handle_verify_result("verify-retry-scan", True)       # same press
o._handle_verify_result("verify-retry-scan", True)
o._handle_verify_result("verify-retry-scan", True)
check(o.cal_log == [False], f"window untouched: {o.cal_log}")
check(o.cal_attempts == 1, f"one attempt, not four: {o.cal_attempts}")
check(o._cal_suppressed == 3, f"suppressions recorded: {o._cal_suppressed}")
check(o.device.calls == ["VerifyStop", "VerifyStart"] * 3,
      f"STILL re-armed every time -- never deaf: {o.device.calls}")
check("Lift the finger clear" in o.status_label.text, f"status: {o.status_label.text!r}")
check(o.hint_label.text.count("same press") == 1, "says why it was not counted")
check(sum(1 for k, t, d in o.log if t.startswith("Same contact")) == 1,
      "logged once per contact, not once per result")

print("\n35. a reported lift makes the next press count again")
o = cal()
o._handle_verify_result("verify-retry-scan", True)
lift(o)
check(o._lifted is True, "lift seen")
check(o._presence_changes == 1, "transition recorded")
o._handle_verify_result("verify-no-match", True)
check(o.cal_log == [False, True], f"next press counted: {o.cal_log}")
check(o._presence_changes == 0, "reset by the count")

print("\n36. an ON transition alone is enough -- no lift needed to count")
o = cal()
o._handle_verify_result("verify-retry-scan", True)
o._on_properties_changed(
    None, m.GLib.Variant("a{sv}", {"finger-present": m.GLib.Variant("b", True)}), None)
check(o._lifted is False, "no lift was reported")
check(o._presence_changes == 1, "but something moved")
o._handle_verify_result("verify-no-match", True)
check(o.cal_log == [False, True], f"counted on the ON edge: {o.cal_log}")

print("\n37. a reader that never reports finger-present is NOT gated")
o = cal()
o.strip.supported = None
o._handle_verify_result("verify-retry-scan", True)
o._handle_verify_result("verify-retry-scan", True)
check(o.cal_log == [False, False], f"both counted: {o.cal_log}")
check(o.device.calls.count("VerifyStart") == 2, f"re-armed immediately: {o.device.calls}")

print("\n38. unreliable finger-present cannot suppress the measurement forever")
o = cal()
o._handle_verify_result("verify-retry-scan", True)
# the driver reports nothing at all from here on
o._handle_verify_result("verify-retry-scan", True)
check(o.cal_log == [False], "the fast repeat is suppressed")
o._last_counted_at = time.monotonic() - (EW.SAME_PRESS_S + 1)
o._handle_verify_result("verify-no-match", True)
check(o.cal_log == [False, True], f"counted once a press cannot last that long: {o.cal_log}")
check(any(t == "Counted without a reported lift" for k, t, d in o.log),
      "and says the lift was assumed, not reported")

print("\n39. _stop twice does not ask fprintd to release twice")
o = cal()
o._stop = EW._stop.__get__(o, types.SimpleNamespace)
o.device.calls.clear()
o._stop(release=True)
check(o.device.calls == ["VerifyStop", "Release"], f"first: {o.device.calls}")
check(o._last_phase == "calibrate", "remembers what was running")
o._stop(release=True)
check(o.device.calls == ["VerifyStop", "Release"], f"second is a no-op: {o.device.calls}")

print("\n" + ("ALL PASS" if not FAILS else f"{len(FAILS)} FAILURES: {FAILS}"))
sys.exit(1 if FAILS else 0)
