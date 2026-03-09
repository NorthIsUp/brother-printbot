# Docker test harness

This container builds and installs the HL-4570CDW drivers using
`alexivkin/brother-in-arms`. It is mainly for verifying the packaging steps
and that the PPD shows up in CUPS.

## Build

```
docker build -t printbot-brother-test -f docker/Dockerfile .
```

## Quick verification

```
docker run --rm -it printbot-brother-test lpinfo -m | grep -i hl4570
```

## Run CUPS in the container

```
docker run --rm -it -p 631:631 --privileged printbot-brother-test
```

Then visit `http://localhost:631` and confirm the driver is available. You
still need USB device access if you want to attach a real printer.
