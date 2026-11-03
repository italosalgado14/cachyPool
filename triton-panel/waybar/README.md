# Waybar modules — optional, NOT applied

The same data as `triton-panel`, but always-on in the bar instead of in a window.
Nothing here is installed; the live Waybar config is untouched. Apply it only if
you want the numbers visible without opening the panel.

| file | what it is |
|---|---|
| `waybar-acer.sh` | one `custom/` module: fan RPM + EC temperature in the bar, with the platform profile and the charge-cap state in the tooltip |
| `waybar-acer.jsonc` | the two config blocks to merge into `~/.config/waybar/config.jsonc` |
| `waybar-acer.css` | three style rules for the module's `idle` / `high` / `unavailable` classes |

The second module is Waybar's **built-in** `power-profiles-daemon`
(`man waybar-power-profiles-daemon`), shipped since 0.9.22 and present in the
installed 0.15.0 — it needs no script, and a click cycles the profile.

## Apply

```bash
install -Dm755 waybar-acer.sh ~/.config/hypr/scripts/waybar-acer.sh
# then merge waybar-acer.jsonc into ~/.config/waybar/config.jsonc
# and waybar-acer.css into ~/.config/waybar/style.css
killall -SIGUSR2 waybar
```

Then mirror the two edited files back into `configs/waybar/`, per the repo's
usual rule that `configs/` is a hand-maintained mirror.

## Why it is separate from the panel

Same dependency as the panel: without `predator_v4=1`
(`../../runbooks/power-battery.md` §17) there is no `acer` hwmon, and the module
shows `--` with the reason in its tooltip rather than zeros. It also never
hardcodes `hwmonN` — see the header of `waybar-acer.sh`.
