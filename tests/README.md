# Tests

The tests build a fake home folder full of traps (protected data, in-use browser profiles,
sockets, symlink attacks, foreign-owned files, live processes) and check that MacClean removes
only what it should. macOS-only tools (`mo`, `sudo`, the root helper) are stubbed, and the
cleaner runs as an unprivileged test user so ownership checks are real.

They create a user and fake system folders (`/Library`, `/private`, `/cores`), so they refuse to
run anywhere except a disposable Linux container:

```bash
docker run --rm -v "$PWD":/src -w /src ubuntu:24.04 bash tests/ci.sh
```

`tests/ci.sh` installs `lsof procps python3 jq shellcheck`, runs shellcheck and syntax checks, then
both suites. CI also runs `/bin/bash -n` and a dry-run `macclean scan` on a macOS runner, which
covers macOS's bash 3.2 and BSD tools.
