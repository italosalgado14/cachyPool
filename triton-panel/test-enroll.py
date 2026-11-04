"""Drive EnrollWindow's result handler with synthetic EnrollStatus events.

The path a real finger reaches only by accident: a driver fault must restart
the enrollment WITHOUT tearing down the g-signal subscription, or the next
status would go nowhere and the window would look hung.
"""
import importlib.util, importlib.machinery, os, pathlib, shutil, sys, tempfile, time, types

# Point the panel's log directory at a throwaway before importing it: LOG_DIR
# is resolved at import time, and a test run must not write into the real
# ~/.local/state/triton-panel (nor prune what is there).
LOGS = tempfile.mkdtemp(prefix="tp-test-logs-")
os.environ["TRITON_PANEL_LOG_DIR"] = LOGS

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
    def queue_draw(self): pass

class Dots:
    def __init__(self): self.passed = 0
    def set_passed(self, n): self.passed = n
    def configure(self, n): pass

class Banner:
    def __init__(self): self.revealed = False
    def set_revealed(self, v): self.revealed = v

class Device:
    """Records method calls; `fail_on` makes one of them raise.

    `fail_message` carries the exact D-Bus error text when a test needs the
    handler to read it -- NoEnrolledPrints is dispatched on the string.
    """
    def __init__(self, fail_on=None):
        self.calls = []; self.fail_on = fail_on; self.fail_message = None
    def call_finish(self, result): return None
    def get_cached_property(self, name): return None
    def call_sync(self, method, args, flags, timeout, cancellable):
        self.calls.append(method)
        if method == self.fail_on:
            raise m.GLib.Error(self.fail_message or f"{method} refused")
        return None


def make(stages=6, fail_on=None):
    o = types.SimpleNamespace()
    # reports_presence is the measured device fact (PRESENCE_SENSORS): this
    # reader DOES publish finger-present, so a silent pad means no finger.
    o.info = {"gesture": "press", "scan_type": "swipe", "stages": stages,
              "driver_scan_type_wrong": True, "reports_presence": True}
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
    o.MAX_STALLED_RESTARTS = EW.MAX_STALLED_RESTARTS
    o._best_passed = 0
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
    o.has_print = True          # §20v: calibration needs something to score against
    o._claimed = True           # a claim is held while a phase is running
    o._released = False
    o._presence_changes = 0
    o._press_seen = False
    o._phantom_noted = False
    o._phantoms = 0
    o.PHANTOM_RESULTS = EW.PHANTOM_RESULTS
    o._last_counted_at = 0.0
    o._cal_noted_no_lift = False
    o._cal_suppressed = 0
    o._last_phase = None
    o._released = False
    o.SAME_PRESS_S = EW.SAME_PRESS_S
    # thermal budget (§20t)
    o.THERMAL_HOT_S = EW.THERMAL_HOT_S
    o.THERMAL_WARN_S = EW.THERMAL_WARN_S
    o.THERMAL_COOL_S = EW.THERMAL_COOL_S
    o.THERMAL_INSTANT_S = EW.THERMAL_INSTANT_S
    o.THERMAL_WARM_AGAIN_S = EW.THERMAL_WARM_AGAIN_S
    o.MAX_THERMAL_CYCLES = EW.MAX_THERMAL_CYCLES
    o.THERMAL_RESUME_GRACE_S = EW.THERMAL_RESUME_GRACE_S
    o._armed_total = 0.0
    o._armed_since = None
    o._armed_wall = None
    o._thermal_hits = 0
    o._thermal_until = None
    o._thermal_id = None
    o._thermal_warned = False
    o._thermal_shown = None
    o._thermal_resumed_at = None
    o._thermal_futile = 0
    o._thermal_evidence = None
    # The journal is stubbed: the real one would be read for every test, and
    # this machine's own journal currently HAS the overheating line in it, so
    # every fault would come back thermal. `journal_verdict` is what fprintd
    # is pretending to have logged -- None means "could not tell", which is
    # the case the budget inference exists for.
    o.journal_verdict = None
    o._journal_too_hot = lambda: o.journal_verdict
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
                 "_on_properties_changed",
                 "_arm_started", "_arm_stopped", "_armed_seconds",
                 "_looks_thermal", "_thermal_remaining", "_enter_thermal",
                 "_thermal_resume", "_tick",
                 "_presence_known", "_looks_phantom", "_note_phantom"):
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

print("\n40. the thermal lockout is not a wedged endpoint (§20t)")
# A `verify-disconnected` after the budget is spent is libfprint's clock, not
# a dead USB endpoint -- the old code counted it as a dry driver fault and,
# four of them in, told the user to go and rebind the device.
o = cal()
o.strip.supported = None
o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
o.device.calls.clear()
o._handle_verify_result("verify-disconnected", True)
check(o._cal_dry == 0, f"NOT counted as a dry driver fault: {o._cal_dry}")
check(o.stopped == [], "calibration is not torn down")
check("VerifyStart" not in o.device.calls,
      f"and NOT re-armed into a refusal: {o.device.calls}")
check(o._thermal_until is not None, "a cooldown is running")
check(any(t == "Thermal lockout" for k, t, d in o.log), "logged as thermal")
check("thermal lockout" in o.status_label.text.lower(),
      f"status names it: {o.status_label.text!r}")
check("rebind" not in o.hint_label.text,
      "and does NOT tell anyone to rebind a cooling device")
check("journalctl" in o.hint_label.text, "points at the one source of truth")

print("\n41. four thermal faults in a row never reach MAX_CAL_DRY")
o = cal()
o.strip.supported = None
for _ in range(4):
    o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
    o._handle_verify_result("verify-disconnected", True)
check(o._cal_dry == 0, f"_cal_dry untouched: {o._cal_dry}")
check(o.stopped == [], "calibration still running, no rebind advice")

print("\n42. a genuine driver fault still counts and still stops")
# The budget is the discriminator, so an early fault must behave exactly as
# it did before this section existed.
o = cal()
o.strip.supported = None
o.device.calls.clear()
for _ in range(EW.MAX_CAL_DRY):
    o._handle_verify_result("verify-disconnected", True)
check(o._cal_dry == EW.MAX_CAL_DRY, f"counted as dry faults: {o._cal_dry}")
check(o.stopped == [True], "calibration stopped")
check("rebind" in o.hint_label.text, "and rebind IS the advice here")

print("\n43. once hot, an instant refusal is recognised without the budget")
o = cal()
o.strip.supported = None
o._thermal_hits = 1
o._armed_since = time.monotonic()          # armed just now
o._handle_verify_result("verify-disconnected", True)
check(o._cal_dry == 0, "a fault in under a second read nothing: not a measurement")
check(o._thermal_until is not None, "treated as the lockout")

print("\n44. the cooldown re-arms by itself, and Stop cancels it")
o = cal()
o.strip.supported = None
o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
o._handle_verify_result("verify-disconnected", True)
o.device.calls.clear()
o._thermal_resume()
check(o.device.calls == ["VerifyStop", "VerifyStart"],
      f"re-armed after the wait: {o.device.calls}")
check(o._thermal_until is None, "cooldown cleared")
o = cal()
o.strip.supported = None
o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
o._handle_verify_result("verify-disconnected", True)
o._stop = EW._stop.__get__(o, types.SimpleNamespace)
o._stop(release=True)
check(o._thermal_id is None, "Stop cancels the pending resume timer")

print("\n45. an enrolment cut off by the clock is not blamed on the hand")
o = make()
o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
o.device.calls.clear()
o._handle_result("enroll-disconnected", True)
check(o.restarts == 0, "no restart into a hot device")
check(o._dry_restarts == 0, f"no dry restart charged: {o._dry_restarts}")
check(o.stopped == [True], "the run is ended cleanly")
check("thermal" in o.status_label.text.lower(), f"status: {o.status_label.text!r}")
check("rebind" not in o.hint_label.text, "no rebind advice")
check("three minutes" in o.hint_label.text,
      "and says an enrolment has to fit inside the budget")

print("\n46. the armed budget is on screen before it runs out")
o = cal()
o._armed_since = time.monotonic() - 10
o.cal_tally["Contact too short"] = 1
o._update_cal_tally()
check("armed 10s of 180s" in o.cal_tally_label.text,
      f"tally carries the budget: {o.cal_tally_label.text!r}")
o = cal()
o._armed_since = time.monotonic() - (EW.THERMAL_WARN_S + 1)
o._tick()
check(o._thermal_warned is True, "warned once")
check("libfprint cuts the sensor off" in o.hint_label.text,
      f"before it happens: {o.hint_label.text!r}")
before = len(o.log)
o._tick()
check(len(o.log) == before, "and only once")

print("\n47. the tick counts the cooldown down instead of going quiet")
o = cal()
o.strip.supported = None
o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
o._handle_verify_result("verify-disconnected", True)
o._tick()
check("answers again in" in o.status_label.text,
      f"countdown shown: {o.status_label.text!r}")

print("\n48. the armed budget survives the calibrate → enroll boundary")
# The flow the window itself steers people into: calibrate, press "Enroll
# anyway", trip partway through the enrolment. libfprint's model does not
# reset at a phase boundary, so neither may the estimate -- zeroing it here is
# how a cooldown got charged to the hand and answered with "go and rebind".
o = make()
o._armed_since = time.monotonic() - 100          # 100 s of calibration
o._arm_stopped()
EW._begin_enroll  # (the real one builds widgets; the invariant is the reset)
check(o._armed_seconds() >= 100, f"carried over: {o._armed_seconds():.0f}s")
o._armed_since = time.monotonic() - 65           # 65 s more of enrolment
o._handle_result("enroll-disconnected", True)
check(o._dry_restarts == 0, f"no dry restart charged: {o._dry_restarts}")
check(o.restarts == 0, "not restarted into a hot device")
check("thermal" in o.status_label.text.lower(), f"status: {o.status_label.text!r}")
check("rebind" not in o.hint_label.text, "and no rebind advice")
check("_armed_total = 0.0" not in open("triton-panel").read().split(
          "def _begin_enroll")[1].split("def ")[0],
      "_begin_enroll does not zero the budget")

print("\n49. the journal outranks the inference, both ways")
o = cal()
o.strip.supported = None
o.journal_verdict = True                          # fprintd logged overheating
o._armed_since = time.monotonic()                 # budget says nothing yet
o._handle_result = None
o._handle_verify_result("verify-disconnected", True)
check(o._thermal_until is not None, "a cold budget + the journal = thermal")
check(o._thermal_evidence == "journal", f"evidence named: {o._thermal_evidence!r}")
o = cal()
o.strip.supported = None
o.journal_verdict = False                         # a real protocol error
o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
o._handle_verify_result("verify-disconnected", True)
check(o._thermal_until is None, "a spent budget + the journal = NOT thermal")
check(o._cal_dry == 1, f"counted as the driver fault it is: {o._cal_dry}")

print("\n50. after a cooldown the model is WARM, so the next trip is recognised")
o = cal()
o.strip.supported = None
o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
o._handle_verify_result("verify-disconnected", True)
check(o._armed_total >= EW.THERMAL_HOT_S - EW.THERMAL_WARM_AGAIN_S - 1,
      f"estimate resumes warm, not at zero: {o._armed_total:.0f}s")
o._thermal_resume()
# From WARM the next trip is THERMAL_WARM_AGAIN_S away, not a fresh 180 -- so
# that is when the second one actually arrives, and it must still read as the
# clock. The estimate is 69 + 111 = 180 by then, which is what makes it.
o._armed_since = time.monotonic() - (EW.THERMAL_WARM_AGAIN_S + 1)
o._handle_verify_result("verify-disconnected", True)
check(o._cal_dry == 0, "the second trip is still thermal, not a dry fault")
check(o._thermal_evidence == "armed budget",
      f"and the budget is what recognised it: {o._thermal_evidence!r}")

print("\n51. two cooldowns that resume into a refusal stop calling it thermal")
o = cal()
o.strip.supported = None
for _ in range(EW.MAX_THERMAL_CYCLES):
    o._armed_since = time.monotonic() - (EW.THERMAL_HOT_S + 1)
    o._handle_verify_result("verify-disconnected", True)
    o._thermal_resume()
    o._armed_since = time.monotonic()             # armed just now
    o._thermal_hits = max(o._thermal_hits, 1)
    o._handle_verify_result("verify-disconnected", True)
check(o.stopped == [True], f"stopped: {o.stopped}")
check("still refuses" in o.status_label.text, f"status: {o.status_label.text!r}")
check("rebind" in o.hint_label.text, "and rebind is named as the next step")
check("not 'Device" in o.hint_label.text or "NOT" in o.hint_label.text,
      "while still pointing at the journal to decide")

# --------------------------------------------------------------------------- #
# The 10-second phantom (§20u). Measured with ./fp-debug.sh presence: a real
# touch always reports finger-present before its result, and the driver's own
# ELAN_CMD_TIMEOUT capture produces `*-swipe-too-short` with no presence at
# all, every 10 s, on an untouched pad. These blocks are the counting rule
# that §20s deliberately left unchanged until that measurement existed.
# --------------------------------------------------------------------------- #

def presence(o, value):
    """Feed one finger-present transition, the way fprintd delivers it."""
    o._on_properties_changed(
        None,
        m.GLib.Variant("a{sv}", {"finger-present": m.GLib.Variant("b", value)}),
        None)


print("\n52. an untouched pad's 10s timeout is not a measurement")
o = make()
o.phase = "calibrate"
o._arm_started()
o._handle_verify_result("verify-swipe-too-short", False)
check(o.cal_log == [], "nothing in the rolling window")
check(o.cal_tally == {}, "nothing in the tally")
check(o.cal_attempts == 0, "not counted as an attempt")
check(o.strip.marks == [], f"nothing drawn on the strip: {o.strip.marks}")
check(o._phantoms == 1, "but it is counted as a phantom")
check("too short" not in o.hint_label.text.lower(),
      f"the hint does not tell an untouched pad to press longer: "
      f"{o.hint_label.text!r}")
check(len(o.log) == 1 and o.log[0][0] == "info",
      f"said once, as info: {o.log}")
check("not a placement" in o.log[0][2] or "idling" in o.log[0][2],
      f"and says what it is: {o.log[0][2]}")

print("\n53. ten of them do not fill the window, and are said once")
o = make()
o.phase = "calibrate"
o._arm_started()
for _ in range(EW.CAL_WINDOW):
    o._handle_verify_result("verify-swipe-too-short", False)
check(o.cal_log == [], "the window is still empty")
check(o._phantoms == EW.CAL_WINDOW, f"all {EW.CAL_WINDOW} seen")
check(len(o.log) == 1, f"one log line, not ten: {len(o.log)}")
ready, scored, window = o._cal_gate()
check(not ready and window == 0,
      "so the gate never opens or closes on phantoms")
check("reader timeout" in o.cal_tally_label.text,
      f"the tally line says why nothing appeared: {o.cal_tally_label.text!r}")

print("\n54. the SAME result after a real touch is counted")
o = make()
o.phase = "calibrate"
o._arm_started()
presence(o, True)
check(o._press_seen, "the ON edge was recorded")
o._handle_verify_result("verify-swipe-too-short", False)
check(o.cal_log == [False], f"counted as a rejected placement: {o.cal_log}")
check(o.cal_attempts == 1, "and as an attempt")
check(o._phantoms == 0, "not a phantom")
check("too short" in o.hint_label.text.lower() or "sensor" in o.hint_label.text.lower(),
      f"and the gesture hint is shown: {o.hint_label.text!r}")

print("\n55. the press is spent: no new touch, so the next one is a phantom")
o = make()
o.phase = "calibrate"
o._arm_started()
presence(o, True)
presence(o, False)
o._handle_verify_result("verify-swipe-too-short", False)
check(o.cal_log == [False], "the real press counted")
o._last_counted_at = 0.0          # 10 s later, past SAME_PRESS_S
o._handle_verify_result("verify-swipe-too-short", False)
check(o.cal_log == [False], f"the driver's timeout did not: {o.cal_log}")
check(o._phantoms == 1, "it is a phantom, because nothing touched it again")

print("\n56. a reader that never reports presence keeps the escape hatch")
o = make()
o.info["reports_presence"] = False      # not in PRESENCE_SENSORS
o.strip.supported = None                # and nothing seen this session
o.phase = "calibrate"
o._arm_started()
check(not o._presence_known(), "presence is genuinely unknown")
o._handle_verify_result("verify-swipe-too-short", False)
check(o.cal_log == [False],
      "so the result is counted rather than silently discarded -- §20j: an "
      "unreliable finger-present must never suppress the measurement forever")
check(o._phantoms == 0, "and it is not called a phantom")

print("\n57. the gate works before the first touch, from the USB id alone")
o = make()
o.strip.supported = None                # the strip has learned nothing yet
o.phase = "calibrate"
o._arm_started()
check(o._presence_known(), "but the device fact says this reader reports it")
o._handle_verify_result("verify-swipe-too-short", False)
check(o.cal_log == [] and o._phantoms == 1,
      "so phantoms arriving while the user reads the screen are discarded")

print("\n58. enrolment: phantoms do not build a verdict about the hardware")
o = make()
o.phase = "enroll"
o._arm_started()
for _ in range(4):
    o._handle_result("enroll-swipe-too-short", False)
check(o.attempts == 0, f"no attempts charged: {o.attempts}")
check(o.tally == {}, f"nothing in the tally: {o.tally}")
check(o.strip.marks == [], "nothing drawn")
check("may simply not handle this sensor" not in o.hint_label.text,
      f"and NOT the hardware verdict the repeats counter used to reach: "
      f"{o.hint_label.text!r}")
check(o._phantoms == 4 and len(o.log) == 1, "four seen, said once")
check("reader timeout" in o.tally_label.text,
      f"shown on the enrol tally line too: {o.tally_label.text!r}")

print("\n59. enrolment: a real short contact still counts and still advises")
o = make()
o.phase = "enroll"
o._arm_started()
for _ in range(3):
    presence(o, True)
    o._handle_result("enroll-swipe-too-short", False)
check(o.attempts == 3, f"three attempts: {o.attempts}")
check(o.tally.get("Contact too short") == 3, f"tallied: {o.tally}")
check(o._phantoms == 0, "none of them a phantom")
check("may simply not handle this sensor" in o.hint_label.text,
      "and the repeats wording is reached by real touches, as designed")

print("\n60. the phantom check runs before the strip is asked for a contact")
src = open("triton-panel", encoding="utf-8").read()
body = src[src.index("def _handle_result(self, result, done):"):]
body = body[:body.index("\n    def ", 10)]
check(body.index("_looks_phantom") < body.index("close_open_contact"),
      "or the strip would invent a contact duration for an untouched pad")
cal = src[src.index("def _handle_verify_result(self, result, done):"):]
cal = cal[:cal.index("\n    def ", 10)]
check(cal.index("_looks_phantom") < cal.index("quiet ="),
      "and before the same-press gate, which is about a press that happened")

print("\n61. verify-disconnected at +25s armed is NOT thermal (measured)")
# 2026-11-03 16:11:42, ./fp-debug.sh presence: the first verify-disconnected
# seen after the thermal work was `protocol error` at 25 s armed, and the very
# next arm worked. Rule 5 live -- one string, three errors.
o = make()
o._arm_started()
o._armed_total = 25.0
o.journal_verdict = False                        # journal says protocol error
check(o._looks_thermal(25.0) is False,
      "the journal decides, and it said PROTO")
check(o._thermal_evidence == "journal", "and says so")
o.journal_verdict = None                         # journal unreadable
check(o._looks_thermal(25.0) is False,
      "and the budget inference agrees: 25s is nowhere near the 180s clock")

print("\n62. a suppression branch must never leave the window deaf")
# Both phantom branches are suppressions, and a suppression that skips the
# re-arm is how §20r made the device deaf. Measured phantoms are all
# done = False, so these assert the guard, not the observed shape.
o = make()
o.phase = "calibrate"
o._arm_started()
o.device.calls.clear()
o._handle_verify_result("verify-swipe-too-short", False)
check(o.device.calls == [], "a retry leaves the verify open -- nothing to do")
o._handle_verify_result("verify-swipe-too-short", True)
check(o.device.calls == ["VerifyStop", "VerifyStart"],
      f"but a TERMINAL one is re-armed even though it is not counted: "
      f"{o.device.calls}")
check(o.cal_log == [] and o._phantoms == 2, "and still not counted")

o = make()
o.phase = "enroll"
o._arm_started()
o._handle_result("enroll-swipe-too-short", True)
check(o._phantoms == 0,
      "on the enrol side a terminal result is NOT swallowed -- it has to "
      "reach the restart machinery (../CLAUDE.md rule 3)")
check(o.attempts == 1 or o.restarts == 1 or o.stopped,
      f"it went somewhere: attempts={o.attempts} restarts={o.restarts} "
      f"stopped={o.stopped}")

# --------------------------------------------------------------------------- #
# §20v. The same-press gate is about a PRESS, so it must not hold a driver
# result. Found in a real session's log, where every single suppression read
# "Same contact -- not counted -- Reader cut off": the gate caught no actual
# repeat and ate driver faults instead -- including, fatally, the thermal
# lockout, whose check lives in the terminal `driver` branch below that return.
# --------------------------------------------------------------------------- #

def after_a_counted_result(o):
    """The state a counted result leaves behind: finger still down, no
    transition since, the clock just reset. This is where the gate bites."""
    o._lifted = False
    o._presence_changes = 0
    o._last_counted_at = time.monotonic()

print("\n63. a thermal lockout is NOT 'the same press' -- it must be entered")
o = make()
o.phase = "calibrate"
o._arm_started()
o._armed_since = time.monotonic()        # refused instantly, dt < 1s
o.journal_verdict = True                 # fprintd logged overheating
after_a_counted_result(o)
check(o.strip.supported is True and not o._lifted and o._presence_changes == 0,
      "precondition: exactly the state the gate used to fire in")
o._handle_verify_result("verify-disconnected", True)
check(o._thermal_until is not None,
      "the cooldown was entered -- this is the hole §20v closed")
check(o._thermal_hits == 1, "and counted as a thermal hit")
check("Lift the finger clear" not in o.status_label.text,
      f"NOT told to lift a finger off a reader that stopped reading: "
      f"{o.status_label.text!r}")
check(o._cal_suppressed == 0, "and not recorded as a suppression")

print("\n64. a real placement result in the same state IS still suppressed")
o = make()
o.phase = "calibrate"
o._arm_started()
after_a_counted_result(o)
o.device.calls.clear()
o._handle_verify_result("verify-retry-scan", True)
check(o._cal_suppressed == 1, "the same-press gate still does its §20r job")
check(o.cal_log == [], "nothing counted")
check("Lift the finger clear" in o.status_label.text, "and says so")
check(o.device.calls == ["VerifyStop", "VerifyStart"], "re-armed anyway (§20s)")

print("\n65. a PROTO fault is tallied, and does not spend the press evidence")
o = make()
o.phase = "calibrate"
o._arm_started()
o._armed_total = 20.0                    # nowhere near the 180s clock
o.journal_verdict = False                # journal says protocol error
after_a_counted_result(o)
before = o._last_counted_at
o._handle_verify_result("verify-disconnected", True)
check(o._thermal_until is None, "not called thermal -- the journal said PROTO")
check(o.cal_tally.get("Reader cut off") == 1,
      f"tallied, so a storm of them is visible instead of hidden: "
      f"{o.cal_tally}")
check(o.cal_log == [], "but never in the rolling window -- it is not the hand")
check(o._last_counted_at == before and o._presence_changes == 0,
      "and the press evidence is untouched: it measured no press")
check(o._cal_dry == 1 or o._cal_contact is False,
      f"it reached the dry-fault accounting: _cal_dry={o._cal_dry}")

print("\n66. and the escape hatch stays out of it too")
o = make()
o.phase = "calibrate"
o._arm_started()
o._armed_total = 20.0
o.journal_verdict = False
o._lifted = False
o._presence_changes = 0
o._last_counted_at = 0.0                 # long ago: the hatch window
o._handle_verify_result("verify-disconnected", True)
check(not any(t == "Counted without a reported lift" for _, t, _ in o.log),
      f"no 'counted without a lift' line about a fault: {o.log}")

# --------------------------------------------------------------------------- #
# §20v, second half: the window offered Calibrate with zero prints enrolled,
# marked it the SUGGESTED action, and answered fprintd's refusal with "the
# reader may be wedged -- run ./fp-debug.sh rebind". Five times.
# --------------------------------------------------------------------------- #

print("\n67. with no print enrolled, Calibrate cannot be the offer")
o = make()
o.has_print = False
o.phase = "idle"
o._update_cal()
check(o.cal_button.sensitive is False,
      "Calibrate is disabled -- it is a verify loop with nothing to verify")
check("suggested-action" not in o.cal_button.css,
      f"and certainly not the suggested action: {o.cal_button.css}")
check(o.start_button.label == "Enroll",
      f"Enroll leads, and is not called 'anyway': {o.start_button.label!r}")
check("suggested-action" in o.start_button.css, "and is the suggested action")

print("\n68. and the refusal is never answered with rebind advice")
o = make()
o.has_print = False
o.phase = "calibrate"
o.device.fail_on = "VerifyStart"
o.device.fail_message = ("GDBus.Error:net.reactivated.Fprint.Error."
                         "NoEnrolledPrints: No fingerprints enrolled")
check(o._verify_cycle(first=True) is False, "the cycle reports failure")
check("./fp-debug.sh rebind" not in o.hint_label.text,
      f"NOT sent to reset a USB endpoint over empty storage (the §20g "
      f"mistake): {o.hint_label.text!r}")
check("a rebind would do nothing" in o.hint_label.text,
      "and rebind is named only to rule it out, since that is the habit "
      "this subsystem has to break")
check("Enroll" in o.hint_label.text,
      f"told what will actually work: {o.hint_label.text!r}")
check("not a reader fault" in o.hint_label.text, "and that it is not the reader")
check(o.status_label.text == "Nothing to calibrate against",
      f"status: {o.status_label.text!r}")

print("\n69. a different VerifyStart failure still points at rebind")
o = make()
o.phase = "calibrate"
o.device.fail_on = "VerifyStart"
o.device.fail_message = "GDBus.Error:org.freedesktop.DBus.Error.NoReply: boom"
check(o._verify_cycle(first=True) is False, "still a failure")
check("rebind" in o.hint_label.text,
      f"the wedged-reader advice is intact for a real fault: "
      f"{o.hint_label.text!r}")

print("\n70. with a print, Calibrate is offered again -- no regression")
o = make()
o.has_print = True
o.phase = "idle"
o._update_cal()
check(o.cal_button.sensitive is True, "Calibrate is back")
check(o.start_button.label == "Enroll anyway",
      f"and Enroll goes back to 'anyway': {o.start_button.label!r}")

print("\n71. a window that never claimed must not call EnrollStop/Release")
o = make()
o.phase = "idle"
o._claimed = False                      # nothing was ever claimed
o._released = False                     # and nothing released, as at startup
o._stop = EW._stop.__get__(o, types.SimpleNamespace)    # the REAL _stop
o.device.calls.clear()
o._stop(release=True)
check(o.device.calls == [],
      f"no D-Bus calls at all -- fprintd used to answer 'Device was not "
      f"claimed before use' twice here: {o.device.calls}")

print("\n72. and a window that DID claim still releases")
o = make()
o.phase = "calibrate"
o._claimed = True
o._released = False
o._stop = EW._stop.__get__(o, types.SimpleNamespace)
o.device.calls.clear()
o._stop(release=True)
check(o.device.calls == ["VerifyStop", "Release"],
      f"the claim/release invariant is intact: {o.device.calls}")
check(o._claimed is False, "and the claim is marked gone")

print("\n73. every log line is written to a file, not only to stderr")
m._log("a line that must survive Walker")
path = m.log_file_path()
check(path is not None, f"a log file was opened: {path}")
check(pathlib.Path(path).exists(), "and it exists on disk")
body = pathlib.Path(path).read_text()
check("a line that must survive Walker" in body,
      f"with the line in it: {body[-120:]!r}")
check(str(LOGS) in str(path), "in the directory the environment asked for")

shutil.rmtree(LOGS, ignore_errors=True)

# --------------------------------------------------------------------------- #
# §20w. The blocker, measured: a stage is ACCEPTED, a protocol error ends the
# operation before the next capture can arm, fprintd discards the partial
# enrolment, §20k's loop restarts at stage 1. Ten times in 44 s, never
# reaching stage 2. MAX_DRY_RESTARTS cannot see it -- contact is fine.
# --------------------------------------------------------------------------- #

def stage_then_fault(o):
    """One cycle of the measured pattern: accepted, then a driver fault."""
    o._on_properties_changed(
        None, m.GLib.Variant("a{sv}", {"finger-present": m.GLib.Variant("b", True)}), None)
    o._handle_result("enroll-stage-passed", False)
    o._handle_result("enroll-disconnected", True)

print("\n74. a stage accepted and lost every time is recognised and stopped")
o = make()
o.phase = "enroll"
o._arm_started()
for _ in range(EW.MAX_STALLED_RESTARTS):
    stage_then_fault(o)
check(o.restarts == EW.MAX_STALLED_RESTARTS,
      f"{o.restarts} restarts happened: the loop is not disabled")
check(o._best_passed == 1, f"and never got past stage 1: {o._best_passed}")
check(o.stopped == [], "still running at the ceiling")
stage_then_fault(o)
check(o.stopped == [True], f"the next one stops it: {o.stopped}")
check("never past stage 1" in o.hint_label.text,
      f"naming the actual pattern: {o.hint_label.text!r}")
check("ACCEPTED" in o.hint_label.text,
      "and that the reader IS reading the finger")
check("./fp-debug.sh rebind" not in o.hint_label.text,
      f"NOT sent to rebind -- nothing is wedged, captures succeed: "
      f"{o.hint_label.text!r}")
check("./fp-debug.sh press" in o.hint_label.text,
      "pointed at the one measurement still unrun")
check(o.restarts == EW.MAX_STALLED_RESTARTS,
      "and no further restart was spent")

print("\n75. but progress earns the full MAX_RESTARTS budget")
o = make()
o.phase = "enroll"
o._arm_started()
for _ in range(3):
    o._on_properties_changed(
        None, m.GLib.Variant("a{sv}", {"finger-present": m.GLib.Variant("b", True)}), None)
    o._handle_result("enroll-stage-passed", False)
check(o._best_passed == 3, f"three stages accumulated: {o._best_passed}")
for _ in range(EW.MAX_STALLED_RESTARTS + 2):
    stage_then_fault(o)
check(o.stopped == [],
      f"the stalled ceiling does NOT fire -- this run is making progress "
      f"(restarts={o.restarts}, best={o._best_passed})")
check(o.restarts > EW.MAX_STALLED_RESTARTS, "and the restarts kept going")

print("\n75b. and a run where NO stage ever passed keeps the old governors")
# §20l's 6/6 needed this loop to survive protocol errors that arrived BEFORE
# any stage passed, and the stalled message would be a lie about such a run
# ("every accepted stage" when none was). Tests 5 and 6 caught this when the
# condition read `<= 1`.
o = make()
o.phase = "enroll"
o._arm_started()
for _ in range(EW.MAX_STALLED_RESTARTS + 1):
    o._on_properties_changed(
        None, m.GLib.Variant("a{sv}", {"finger-present": m.GLib.Variant("b", True)}), None)
    o._handle_result("enroll-disconnected", True)
check(o._best_passed == 0, "no stage was ever accepted")
check(o.stopped == [], f"the stalled ceiling stays out of it: {o.stopped}")
check(o.restarts == EW.MAX_STALLED_RESTARTS + 1,
      f"the restart loop is intact: {o.restarts}")

print("\n76. MAX_RESTARTS is still the backstop once progress was made")
o = make()
o.phase = "enroll"
o._arm_started()
o._best_passed = 4                      # this run did get somewhere
o.restarts = EW.MAX_RESTARTS
o._contact_since_restart = True
check(o._may_restart() is False, "blocked at the hard ceiling")
check(f"{EW.MAX_RESTARTS} restarts" in o._restart_block,
      f"with the counting message, not the stalled one: {o._restart_block!r}")

print("\n77. the high-water mark survives a restart, and only _begin_enroll clears it")
o = make()
o.phase = "enroll"
o._arm_started()
o._on_properties_changed(
    None, m.GLib.Variant("a{sv}", {"finger-present": m.GLib.Variant("b", True)}), None)
o._handle_result("enroll-stage-passed", False)
o._handle_result("enroll-stage-passed", False)
check(o._best_passed == 2, f"two stages: {o._best_passed}")
o._handle_result("enroll-disconnected", True)
check(o.passed == 0, "the live count is reset by the restart, as fprintd did")
check(o._best_passed == 2,
      f"but the high-water mark is not -- that is the whole point: "
      f"{o._best_passed}")
src = open("triton-panel", encoding="utf-8").read()
body = src[src.index("def _begin_enroll(self):"):]
body = body[:body.index("\n    def ", 10)]
check("_best_passed = 0" in body,
      "and a fresh enrolment is where it is cleared")

print("\n" + ("ALL PASS" if not FAILS else f"{len(FAILS)} FAILURES: {FAILS}"))
sys.exit(1 if FAILS else 0)
