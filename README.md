# Building

Zig version: `0.11.0-dev.4187+1ae839cd2`

## For Linux:

```bash
apt install xorg-dev
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
```

## For Windows:

Release modes segfault the compiler `:(`. Looking for a workaround.

```bash
zig build -Dtarget=x86_64-windows-gnu
```


## For Mac:

Work in progress.
