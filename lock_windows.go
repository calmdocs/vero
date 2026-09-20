package vero

import (
	"os"
	"syscall"
	"unsafe"
)

// LockFileEx and UnlockFileEx, called through kernel32 rather than through
// golang.org/x/sys, so that this package keeps having no dependencies.
var (
	kernel32     = syscall.NewLazyDLL("kernel32.dll")
	procLockFile = kernel32.NewProc("LockFileEx")
	procUnlock   = kernel32.NewProc("UnlockFileEx")
)

const (
	lockfileExclusiveLock   = 0x00000002
	lockfileFailImmediately = 0x00000001
)

// The lock is on the handle, so Windows drops it when the process exits -
// the same guarantee flock gives everywhere else.
func lockFile(f *os.File) error {
	var overlapped [4]uintptr // an OVERLAPPED, zeroed: lock from offset 0
	r, _, err := procLockFile.Call(
		f.Fd(),
		uintptr(lockfileExclusiveLock|lockfileFailImmediately),
		0,
		1, 0, // one byte is enough to be exclusive
		uintptr(unsafe.Pointer(&overlapped[0])),
	)
	if r == 0 {
		return err
	}
	return nil
}

func unlockFile(f *os.File) {
	var overlapped [4]uintptr
	procUnlock.Call(f.Fd(), 0, 1, 0, uintptr(unsafe.Pointer(&overlapped[0])))
}
