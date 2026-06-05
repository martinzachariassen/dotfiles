#!/usr/bin/env python3
"""Drive install.sh through a real pseudo-terminal and assert it behaves.

This is the regression guard for the wizard's TTY handling — the area that has
bitten us before (a hand-rolled input "drain" that hung every menu; a stray
newline that aborted the whole run at the typed-phrase confirm). A unit test
can't catch those because they only manifest against a real terminal, so we
spawn the actual installer under a pty and play the part of the user.

Safety: the wizard is run with DRY_RUN=1 (every state-changing command is
printed, not executed) AND we always answer "No" at the final Proceed prompt, so
nothing is ever installed, removed, or written. It is safe to run anytime.

Assumptions: a macOS workstation with Homebrew present — that's what makes the
"custom" path show the Homebrew cleanup menu and the typed-phrase confirm, which
are the fragile bits we most want to exercise.

Usage:
    python3 tests/drive-wizard.py [clean|stray]

    clean  (default)  walk the full custom + mirror path, type the phrase, abort
    stray             send stray empty Enters at the phrase prompt first, then
                      the phrase — proves an accidental newline re-asks instead
                      of aborting the run

Exit codes: 0 ok · 1 unexpected output / never aborted cleanly · 2 wizard hung
"""
import os
import pty
import re
import select
import sys
import time

ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]|\x1b[=>]|\r")
DOWN = b"\x1b[B"
ENTER = b"\r"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Each step: (marker substring to wait for, bytes to send, human label).
# The wizard blocks on every prompt, so first-appearance matching is safe.
CLEAN = [
    (b"Press Enter to begin",      ENTER,                  "begin"),
    (b"Profile",                   ENTER,                  "profile=keep"),
    (b"Full name",                 ENTER,                  "name=keep"),
    (b"Git email",                 ENTER,                  "email=keep"),
    (b"Setup style",               DOWN + ENTER,           "setup=custom"),
    (b"1Password for SSH",         ENTER,                  "use_op=keep"),
    (b"SSH signing public key",    ENTER,                  "signingkey=keep"),
    (b"Install workstation Mac",   ENTER,                  "macapps=keep"),
    (b"Homebrew cleanup mode",     DOWN + ENTER,           "cleanup=mirror"),
    (b"MIRROR BREW to confirm",    b"MIRROR BREW" + ENTER, "phrase"),
    (b"Proceed with installation", DOWN + ENTER,           "proceed=No"),
]

# Same, but jam two reflex Enters in before the phrase. A correct wizard
# re-asks ("Nothing entered …") instead of aborting.
STRAY = [
    (b"Press Enter to begin",      ENTER,                  "begin"),
    (b"Profile",                   ENTER,                  "profile=keep"),
    (b"Full name",                 ENTER,                  "name=keep"),
    (b"Git email",                 ENTER,                  "email=keep"),
    (b"Setup style",               DOWN + ENTER,           "setup=custom"),
    (b"1Password for SSH",         ENTER,                  "use_op=keep"),
    (b"SSH signing public key",    ENTER,                  "signingkey=keep"),
    (b"Install workstation Mac",   ENTER,                  "macapps=keep"),
    (b"Homebrew cleanup mode",     DOWN + ENTER,           "cleanup=mirror"),
    (b"MIRROR BREW to confirm",    ENTER,                  "stray empty #1"),
    (b"Nothing entered",           ENTER,                  "stray empty #2"),
    (b"Nothing entered",           b"MIRROR BREW" + ENTER, "phrase"),
    (b"Proceed with installation", DOWN + ENTER,           "proceed=No"),
]

# Prompts that only appear on some machines (legacy dotfiles / oh-my-zsh present).
# Answered opportunistically so the driver doesn't stall if they show up.
OPTIONAL = [
    (b"Back up legacy files", ENTER, "legacy=keep"),
    (b"Uninstall oh-my-zsh",  ENTER, "omz=keep"),
]


def strip(b):
    return ANSI.sub(b"", b)


def main():
    scenario = sys.argv[1] if len(sys.argv) > 1 else "clean"
    steps = {"clean": CLEAN, "stray": STRAY}.get(scenario)
    if steps is None:
        print(f"unknown scenario: {scenario!r} (use clean|stray)", file=sys.stderr)
        return 1

    env = dict(os.environ)
    env.update(DRY_RUN="1", TERM="xterm-256color", COLORTERM="truecolor",
               LANG="en_US.UTF-8")

    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(REPO)
        os.execvpe("bash", ["bash", "install.sh"], env)
        os._exit(127)

    buf = b""
    transcript = b""
    i = 0
    fired_optional = set()
    last_rx = time.time()
    log = []

    while True:
        r, _, _ = select.select([fd], [], [], 0.5)
        now = time.time()
        if fd in r:
            try:
                data = os.read(fd, 4096)
            except OSError:
                break
            if not data:
                break
            buf += data
            transcript += data
            last_rx = now
            text = strip(buf)

            for marker, inp, label in OPTIONAL:
                if marker in text and label not in fired_optional:
                    time.sleep(0.15)
                    os.write(fd, inp)
                    fired_optional.add(label)
                    log.append(f"[opt] {label}")
                    buf = b""
                    text = b""
                    break

            if i < len(steps):
                marker, inp, label = steps[i]
                if marker in text:
                    time.sleep(0.2)
                    os.write(fd, inp)
                    log.append(f"[{i}] {marker.decode()!r} -> sent ({label})")
                    i += 1
                    buf = b""
        else:
            if i >= len(steps) and now - last_rx > 2.0:
                break
            if now - last_rx > 10.0:
                marker = steps[i][0] if i < len(steps) else b"(end)"
                log.append(f"[HANG] idle >10s waiting for step {i}: {marker.decode()!r}")
                _report(log, transcript)
                _reap(fd, pid)
                return 2

    _reap(fd, pid)
    out = strip(transcript).decode("utf-8", "replace")

    # Reaching the Proceed prompt at all proves the typed-phrase confirm was
    # accepted — a decline calls fail()+exit before Proceed is ever shown.
    ok = i >= len(steps) and "aborted - nothing changed" in out
    if scenario == "stray":
        # The empty Enters must have re-asked rather than aborted the run.
        ok = ok and "Nothing entered" in out

    _report(log, transcript)
    if ok:
        print(f"\nPASS ({scenario}): wizard drove to a clean abort, no hang.")
        return 0
    print(f"\nFAIL ({scenario}): did not reach a clean abort. "
          f"steps={i}/{len(steps)}", file=sys.stderr)
    return 1


def _reap(fd, pid):
    try:
        os.close(fd)
    except OSError:
        pass
    try:
        os.waitpid(pid, 0)
    except OSError:
        pass


def _report(log, transcript):
    print("===== DRIVER LOG =====")
    for line in log:
        print(line)


if __name__ == "__main__":
    sys.exit(main())
