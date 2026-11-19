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

`tests/test_update.sh` covers `macclean update` and the Mole setup without any network: releases
are local `file://` archives (good, mismatched version, broken syntax, not an archive, missing),
and Homebrew and Mole's installer are stubs that record how they were called. It checks that a
current Mole is left alone, an old one is updated through the channel that installed it, a
missing one is installed, and a bad release is refused with nothing changed. Test-only overrides
(`MACCLEAN_TEST_*`) work only with `MACCLEAN_TEST_SANDBOX=1` and never on macOS.

`tests/ci.sh` installs `lsof procps python3 jq shellcheck curl bsdutils`, runs shellcheck and
syntax checks, then all three suites. CI also runs `/bin/bash -n`, a dry-run `macclean scan`,
`bootstrap.sh --dry-run` and `macclean update --check` on a macOS runner, which covers macOS's
bash 3.2, BSD tools and the real GitHub release download.
