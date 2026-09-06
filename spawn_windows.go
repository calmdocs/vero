package vero

import (
	"os/exec"
	"syscall"
)

// createNoWindow is the Win32 CREATE_NO_WINDOW process creation flag.
const createNoWindow = 0x08000000

// hideConsole keeps the worker from opening a console window of its own.
//
// A worker is a console program, and Windows gives one a console the moment a
// GUI application spawns it - a black window that flashes up beside the app and
// stays there for as long as the worker runs.  Nothing reads it: the worker's
// output goes down the pipes the Supervisor created, not to a screen.
func hideConsole(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: createNoWindow}
}
