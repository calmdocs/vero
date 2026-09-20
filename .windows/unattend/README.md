# Building and recording the Windows example

The WPF example cannot be built on a Mac — WPF is Windows-only — so this is
what is needed to build it, run it, and record it the way the macOS and Linux
examples were recorded.

## What is here

- `autounattend.xml` — installs Windows without the forty minutes of clicking.
  It bypasses the TPM, Secure Boot and RAM checks a VM cannot satisfy, creates
  a local account (Windows 11 otherwise insists on a Microsoft account, and
  there is no way past that screen without one), enables auto-login, and runs
  `setup.ps1` at first login.
- `setup.ps1` — installs Go, the .NET 8 SDK, git and a C compiler. cgo needs a
  compiler and the Go toolchain does not include one.

## Making the answer disk

The two files go on a small ISO that is attached as a second drive, so the
installer finds the answer file and the setup script:

```bash
cd .windows/unattend
hdiutil makehybrid -iso -joliet -default-volume-name UNATTEND -o unattend.iso .
```

## In UTM

1. New virtual machine, Virtualise, Windows.
2. Point it at the Windows 11 ARM64 ISO.
3. Give it 4 GB of memory and a 24 GB disk. Windows needs about 20 GB, so
   watch the free space on the host - this is the part most likely to bite.
4. Add `unattend.iso` as a second drive.
5. Start it, and leave it alone. It installs, reboots, logs in and installs the
   toolchain by itself.

## Then

From the Mac, with the VM running:

```bash
utmctl exec "Windows 11" --cmd "go version"
```

`utmctl` can copy files in and run commands, which is enough to build the
example and take the screenshots without touching the VM's own desktop.
