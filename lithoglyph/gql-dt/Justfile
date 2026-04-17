# Nerdctl-first deployment
default: check
check:
    @command -v nerdctl >/dev/null && nerdctl build . || (command -v podman >/dev/null && podman build . || docker build .)
