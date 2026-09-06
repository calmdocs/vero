//go:build !windows

package vero

import "os/exec"

// hideConsole does nothing here.  Only Windows attaches a console to a child
// process that nobody asked for one.
func hideConsole(*exec.Cmd) {}
