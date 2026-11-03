"""Drive BatteryRun and BatteryGraph with synthetic samples.

Three things here are only reachable by waiting hours on real hardware, which
is exactly why they are the things most likely to be wrong:

  * a SUSPEND in the middle of a discharge. time.monotonic() does not advance
    across s2idle and time.time() jumps, so the run must restart at the hole
    instead of averaging a sleeping laptop into an awake projection. hypridle
    suspends this machine on battery, so this is the ordinary path.
  * an IDLE blip ("Not charging", which is what AC + the 80% cap reports all
    day) must NOT wipe the trace, while a real reversal must.
  * the DRAW function must survive every state -- no projection, a projection
    past the clamp, charging, no battery at all. A Cairo exception inside a
    draw handler is swallowed into a warning and an empty widget, so it will
    not show up as a crash; it shows up as a panel that silently stops
    drawing.

Headless on purpose (same reason as test-enroll.py): it renders onto an
ImageSurface with a stand-in for the widget, so it needs no display.

    python3 test-battery.py
"""
import importlib.util, importlib.machinery, math, time, types

import cairo

spec = importlib.util.spec_from_loader(
    "tp", importlib.machinery.SourceFileLoader("tp", "triton-panel"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

FAILS = []
def check(cond, label):
    print(("  ok   " if cond else "  FAIL ") + label)
    if not cond:
        FAILS.append(label)

def near(a, b, tol=0.01):
    return a is not None and abs(a - b) <= tol


# --------------------------------------------------------------------------- #
# A battery sample, as Sampler._battery() would return it
# --------------------------------------------------------------------------- #

WH_FULL = 100.0

def bat(percent, status="Discharging", watts=20.0, cap=1):
    return {
        "percent": percent, "status": status, "cycles": 0,
        "power_w": watts, "health_percent": 101.7,
        "wh_now": percent / 100.0 * WH_FULL, "wh_full": WH_FULL,
        "cap": cap, "temp_c": 31.9,
    }


def feed(run, samples, start=1_000_000.0, step=2.0, seed=None):
    """Replay samples at a fixed cadence, with time.time() under our control.

    `samples` is a list of (battery dict | ("skip", seconds)). The skip is how
    a suspend is injected: the clock moves and no sample arrives.
    """
    clock = [start]
    real_time, real_seed = m.time.time, m.upower_charge_history
    m.time.time = lambda: clock[0]
    m.upower_charge_history = (lambda direction, span=0: list(seed or []))
    try:
        state = None
        for item in samples:
            if isinstance(item, tuple) and item and item[0] == "skip":
                clock[0] += item[1]
                continue
            state = run.update(item)
            clock[0] += step
        return state
    finally:
        m.time.time = real_time
        m.upower_charge_history = real_seed


# --------------------------------------------------------------------------- #
print("\nupower_points: where a run begins")
# The real answer from this machine on 2026-11-02, newest first. The pair of
# 64% entries 7.4 h apart with an UNKNOWN marker between them is a suspend:
# the run that is still going starts at the marker, not at the earlier 64%.
HISTORY = [
    (1793670040, 48.0, 2), (1793669859, 49.0, 2), (1793669709, 50.0, 2),
    (1793669589, 51.0, 2), (1793669499, 52.0, 2), (1793669348, 53.0, 2),
    (1793667303, 63.0, 2), (1793667268, 64.0, 2), (1793667268, 0.0, 0),
    (1793640616, 64.0, 2), (1793640375, 65.0, 2), (1793625640, 0.0, 0),
]
points = m.upower_points(HISTORY, 2, now=1793670100.0)
check(len(points) == 8, f"stops at the UNKNOWN marker (got {len(points)})")
check(points[0] == (1793667268.0, 64.0), "oldest point is the marker's 64%")
check(points[-1] == (1793670040.0, 48.0), "newest point last (reversed)")
check(all(b >= a for (a, _), (b, _) in zip(points, points[1:])),
      "timestamps ascending")
check(m.upower_points(HISTORY, 2, now=1793670100.0, span=600) == [
          (1793669589.0, 51.0), (1793669709.0, 50.0),
          (1793669859.0, 49.0), (1793670040.0, 48.0)],
      "span trims the walk at the first point older than it")
check(m.upower_points([(1793670040, 48.0, 2)], 1, now=1793670100.0) == [],
      "a charging walk takes nothing from a discharging history")
check(m.upower_points([(1793670040, 0.0, 0)], 2, now=1793670100.0) == [],
      "a history that opens on a marker seeds nothing")
check(m.upower_charge_history("full") == [], "no history is asked for an idle state")

# --------------------------------------------------------------------------- #
print("\nprojection: discharging")
run = m.BatteryRun()
state = feed(run, [bat(50, watts=20.0)] * 40)
check(state["direction"] == "discharging", "direction read from status")
check(near(state["rate_w"], 20.0, 0.2), f"EMA converges on 20 W ({state['rate_w']})")
# 50 Wh at 20 W = 2.5 h
check(near(state["seconds_left"], 9000, 60),
      f"50 Wh / 20 W = 2 h 30 min (got {state['seconds_left']:.0f} s)")
check(near(state["eta"] - state["now"], state["seconds_left"], 1), "eta is now + left")
check(state["target_percent"] == 0.0, "a discharge is projected to empty")
check(m.human_duration(state["seconds_left"]) == "2 h 30 min",
      f"formatted as 2 h 30 min (got {m.human_duration(state['seconds_left'])})")

print("\nprojection: the EMA is a rate NOW, not the run average")
run = m.BatteryRun()
state = feed(run, [bat(50, watts=20.0)] * 60 + [bat(50, watts=40.0)] * 3)
check(20.0 < state["rate_w"] < 24.0,
      f"three ticks at 40 W move the EMA a little, not all the way "
      f"({state['rate_w']:.1f} W)")
# The clock has to CONTINUE, or the restart would reset the EMA and this
# would pass without ever testing convergence.
state = feed(run, [bat(50, watts=40.0)] * 120, start=1_000_000.0 + 63 * 2)
check(state["after_gap"] is False, "the run continues, so the EMA is not reset")
# 240 s is 5.3 time constants, so convergence is the assertion, not the
# tolerance: at 2 time constants it would still be 1.2 W short.
check(near(state["rate_w"], 40.0, 0.5),
      f"a sustained change does arrive ({state['rate_w']:.2f} W)")

print("\nprojection: charging stops at the cap")
run = m.BatteryRun()
state = feed(run, [bat(50, status="Charging", watts=50.0, cap=1)] * 40)
check(state["target_percent"] == 80.0, "with the cap on, the target is 80%")
check(near(state["seconds_left"], 30 / 100.0 * WH_FULL / 50.0 * 3600, 60),
      f"30 Wh to go at 50 W = 36 min (got {state['seconds_left']:.0f} s)")
run = m.BatteryRun()
state = feed(run, [bat(50, status="Charging", watts=50.0, cap=0)] * 40)
check(state["target_percent"] == 100.0, "with the cap off, the target is 100%")
run = m.BatteryRun()
state = feed(run, [bat(85, status="Charging", watts=50.0, cap=1)] * 5)
check(state["seconds_left"] is None and "target" in state["note"],
      "above the cap there is nothing to project, with a reason")

print("\nprojection: the guards")
run = m.BatteryRun()
state = feed(run, [bat(80, status="Not charging", watts=0.0)] * 5)
check(state["seconds_left"] is None, "idle projects nothing")
check(state["rate_w"] is None, "idle has no draw")
check("cap" in state["note"], f"at 80% with the cap on it says why: {state['note']!r}")
state = feed(m.BatteryRun(), [bat(42, status="Unknown", watts=0.0)] * 5)
check("nothing to project" in state["note"],
      f"and does not blame the cap at 42%: {state['note']!r}")
run = m.BatteryRun()
state = feed(run, [bat(50, watts=0.2)] * 40)
check(state["seconds_left"] is None and "0.5 W" in state["note"],
      "a draw under the floor is not divided by")
run = m.BatteryRun()
state = feed(run, [bat(100, watts=1.0)] * 40)
check(state["over"] is True, "a projection past a day is flagged")
check(state["seconds_left"] > m.BATTERY_PROJECTION_MAX_SECONDS,
      "and the raw figure is kept, not clamped in the state")
check(m.BatteryRun().update(None) is None, "no battery, no state")

# --------------------------------------------------------------------------- #
print("\nthe run: a suspend ends it")
run = m.BatteryRun()
seed = [(999_000.0, 70.0), (999_500.0, 60.0)]
state = feed(run, [bat(50)] * 10, seed=seed)
check(m.BATTERY_GAP_SECONDS > 8, "the gap threshold clears a blocking sudo call")
check(state["seeded"] is True and len(state["points"]) == 3,
      f"upower seeds the part before the panel ({len(state['points'])} points)")
check(state["run_start_percent"] == 70.0, "the run starts where upower says")
before = state["rate_w"]
state = feed(run, [("skip", m.BATTERY_GAP_SECONDS + 1), bat(48, watts=60.0)],
             start=1_000_100.0, seed=seed)
check(state["after_gap"] is True, "a wall-clock hole is detected")
check(state["seeded"] is True and len(state["points"]) == 3,
      "and upower is asked again, which is what heals a FALSE gap -- one of "
      "this panel's own 8 s sudo calls must not cost the history")
check(near(state["rate_w"], 60.0, 0.01),
      "the EMA restarts too, so a pre-suspend rate cannot leak into it")

print("\nthe run: an idle blip does not wipe it, a reversal does")
run = m.BatteryRun()
state = feed(run, [bat(50)] * 5 + [bat(50, status="Not charging", watts=0.0)]
             + [bat(49)] * 5, seed=seed)
check(state["seeded"] is True and state["run_start_percent"] == 70.0,
      "'Not charging' for one tick keeps the discharge on screen")
check(state["direction"] == "discharging", "and the direction comes back")
run = m.BatteryRun()
state = feed(run, [bat(50)] * 5 + [bat(51, status="Charging", watts=45.0)] * 5,
             seed=seed)
check(state["direction"] == "charging" and state["run_start_percent"] == 70.0,
      "a reversal re-seeds from upower (same stub here) and flips direction")

print("\nthe run: the trace is decimated without losing the live point")
run = m.BatteryRun()
state = feed(run, [bat(50)] * 100)
check(len(state["points"]) == 2,
      f"100 samples at an unchanged percent are two points -- the run's fixed "
      f"start and one moving end ({len(state['points'])})")
check(near(state["points"][-1][0], state["now"], 0.01),
      "whose timestamp is the live one, so the flat segment reaches 'now'")
state = feed(m.BatteryRun(), [bat(50)] * 100 + [bat(49)] * 10 + [bat(48)] * 10)
check(len(state["points"]) == 4, "a new percent appends a point")
check(near(state["run_seconds"], 2 * 119, 1),
      f"and the run's start never moves ({state['run_seconds']:.0f} s of a "
      f"238 s feed)")

print("\nthe run: consumed, and the average")
run = m.BatteryRun()
# 20 minutes from 60% to 50%: 10 Wh in 1200 s = 30 W.
state = feed(run, [bat(60)] * 300 + [bat(50)] * 300, step=2.0)
check(near(state["run_delta_percent"], 10.0), "consumed 10 percentage points")
check(near(state["run_seconds"], 1198, 4), "over the run's own span")
check(near(state["average_w"], 10 / 100.0 * WH_FULL / (1198 / 3600.0), 0.2),
      f"average = charge moved / time ({state['average_w']:.1f} W)")
check(near(state["used_wh_from_full"], 50.0), "and 50 Wh gone since full")
run = m.BatteryRun()
state = feed(run, [bat(50)] * 100)
check(state["average_w"] is None,
      "no average while the run is too short or too flat to mean anything")

# --------------------------------------------------------------------------- #
print("\nthe graph draws every state")

class Colour:
    red = green = blue = 0.9

def render(state, width=760, height=190):
    """BatteryGraph._draw against a real Cairo context, no display needed.

    Returns the legend only for a state that has a trace -- the empty-trace
    case leaves _draw before it builds one.
    """
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    cr = cairo.Context(surface)
    obj = types.SimpleNamespace(state=state, get_color=Colour)
    for name in ("AXIS_WIDTH", "LEGEND_HEIGHT", "FOOT_HEIGHT",
                 "LEVEL", "USED", "FUTURE"):
        setattr(obj, name, getattr(m.BatteryGraph, name))
    obj._time_step = m.BatteryGraph._time_step
    obj._clock = m.BatteryGraph._clock
    obj._legend = lambda st: m.BatteryGraph._legend(obj, st)
    m.BatteryGraph._draw(obj, None, cr, width, height)
    return obj._legend(state) if state and state.get("points") else ("", "")

def draws(state, label, width=760, height=190):
    try:
        render(state, width, height)
        check(True, label)
    except Exception as error:                      # noqa: BLE001
        check(False, f"{label} -- {type(error).__name__}: {error}")

draws(None, "no battery at all")
draws({"points": []}, "a state with an empty trace")
run = m.BatteryRun()
draws(feed(run, [bat(50)] * 40), "a discharge with a projection")
head, detail = render(feed(run, [bat(50)] * 40))
check("50%" in head and "left" in head, f"headline reads {head!r}")
run = m.BatteryRun()
draws(feed(run, [bat(50, status="Charging", watts=45.0)] * 40), "a charge")
run = m.BatteryRun()
draws(feed(run, [bat(50, status="Not charging", watts=0.0)] * 5), "idle at the cap")
run = m.BatteryRun()
draws(feed(run, [bat(100, watts=1.0)] * 40), "a projection past the clamp")
run = m.BatteryRun()
state = feed(run, [bat(60)] * 300 + [bat(50)] * 300)
draws(state, "a long run with a consumed band")
draws(state, "a window squeezed to nothing", width=80, height=60)
head, detail = render(state)
check("used 10%" in detail, f"detail reads {detail!r}")
check(m.BatteryGraph._time_step(3 * 3600) == 1800,
      "a three-hour span is labelled every half hour")
check(m.BatteryGraph._time_step(5 * 60) == 60, "a five-minute span, every minute")
check(m.BatteryGraph._time_step(40 * 3600) == 43200, "and a span past the ladder")

print()
if FAILS:
    print(f"{len(FAILS)} FAILED:")
    for label in FAILS:
        print("  - " + label)
    raise SystemExit(1)
print("all passed")
