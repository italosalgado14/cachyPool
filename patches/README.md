# patches/

Patches against **software this machine does not own**. Everything here is
third-party source, so two rules apply that do not apply anywhere else in this
repo:

1. **Nothing here is applied.** A patch in this directory is a reviewed
   artefact, not live state. The live state of each one is a row in
   `../ACTUAL-CONFIGURATION.md` §15 and a line in `../CHANGELOG.md`.
2. **A patch reverts on `paru -Syu`.** That is not a bug to work around — it is
   the rollback. The replaced package stays in the pacman cache
   (`paccache -k3`, see `../runbooks/updates.md`), so going back is one
   `pacman -U`.

Run `../tests/check-libfprint-patch.sh` after any upgrade that moves the
patched package. It checks the hunks still apply **and** that the new
`driver_data` bit has not started colliding with something upstream added —
the second would change the reader's behaviour with nothing failing to build.

## libfprint-elan-0c4f-busy-retry.patch

Three lines against `libfprint v1.94.100`. Reasoning, measurements and the
ranked alternatives are in `../runbooks/fingerprint.md` §20x; the short version
is that `elan.c` turns the sensor's own documented *"not ready"* / *"finger
removed or sensor busy"* status bytes into a **fatal** `FP_DEVICE_ERROR_PROTO`
on every device except `0c58`, and on `04f3:0c4f` that lands between two
enrolment stages, which makes enrolment impossible.

### ⚠ Step 0, not optional

Building needs `meson`, `gobject-introspection`, `gtk-doc` and `umockdev`,
none of which are installed. ~~Installing packages against a refreshed database
is the **partial upgrade** `../CLAUDE.md` forbids, and there is an upgrade
backlog.~~ ✅ The backlog is gone: the full upgrade ran **2026-11-03 18:47**
(662 packages, kernel 7.3.1 — `../CHANGELOG.md`). What is left:

```bash
# ✅ done 2026-11-03:  ./tests/check-live-system.sh --strict  &&  paru -Syu
reboot                                     # 7.3.1 is installed, 7.2.8 is running
./tests/check-live-system.sh               # must be clean after it — two FAILs
                                           # before it are expected, see
                                           # ../runbooks/updates.md Issue history
paru -Syu --needed meson gobject-introspection gtk-doc umockdev
```

⚠ ~~After that, libfprint may no longer be 1.94.100~~ ✅ the upgrade left
`libfprint 1.94.100-1.1` and `fprintd 1.94.5-2.1` untouched, so the hunks hold
as verified, and 1.94.100 is upstream's newest tag. Run
`../tests/check-libfprint-patch.sh` with `LIBFPRINT_SRC` after the *next*
upgrade that moves the package, and re-read `../runbooks/fingerprint.md` §20x.

### Test it without installing anything (preferred first)

A build plus a drop-in under `/run`, which is tmpfs: **a reboot undoes all of
it** and no package is touched.

```bash
paru -S --needed meson gobject-introspection gtk-doc umockdev   # after step 0
git clone --depth 1 --branch v1.94.100 \
    https://gitlab.freedesktop.org/libfprint/libfprint.git /tmp/fp-src
cd /tmp/fp-src
git apply ~/code/cachyPool/patches/libfprint-elan-0c4f-busy-retry.patch
meson setup build -Ddrivers=all -Dinstalled-tests=false
meson compile -C build
meson test -C build --print-errorlogs        # upstream's own suite

sudo mkdir -p /run/systemd/system/fprintd.service.d
printf '[Service]\nEnvironment=LD_LIBRARY_PATH=/tmp/fp-src/build/libfprint\n' \
  | sudo tee /run/systemd/system/fprintd.service.d/99-patched-libfprint.conf
sudo systemctl daemon-reload && sudo systemctl restart fprintd
```

Then enrol. To undo: delete that file, `daemon-reload`, `restart fprintd` — or
reboot.

### Make it permanent (only once the test above worked)

Build a real package, so pacman owns it and an upgrade replaces it cleanly:

```bash
pkgctl repo clone --protocol=https libfprint     # or git clone the packaging repo
cd libfprint
cp ~/code/cachyPool/patches/libfprint-elan-0c4f-busy-retry.patch .
# add it to source=() and apply it in prepare(); then
makepkg -si
```

**Rollback:** `sudo pacman -U /var/cache/pacman/pkg/libfprint-1.94.100-*.pkg.tar.zst`

⚠ `pam_fprintd` is `sufficient` in `/etc/pam.d/sudo`, so a broken libfprint
cannot lock anyone out — Enter falls through to the password. The hyprlock
fingerprint block is currently absent. Keep both true while testing.
