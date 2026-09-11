// Package vero builds desktop applications whose logic is written once, in
// Go, and whose interface is the platform's own toolkit - SwiftUI on macOS,
// WinUI on Windows, GTK on Linux.
//
// The Go GUI field splits three ways: Fyne and Gio draw their own widgets, so
// the result looks the same everywhere and native nowhere; Wails and Lorca
// wrap a webview, which is Electron's tradeoff with a smaller binary; Walk is
// Windows only.  vero takes the fourth path.  The interface is genuinely the
// system's, and Go supplies everything behind it.
//
// # The shape of a vero application
//
// Your logic lives in a worker: an ordinary Go program that either runs on its
// own, as a daemon on a headless server, or is launched by a GUI.  The same
// binary does both, and it does not know which it is doing beyond one flag.
//
//	worker  ->  your logic; runs headless, or behind an interface
//	        ->  a Supervisor launches it, restarts it, and talks to it
//	        ->  a native interface drives the Supervisor through five C functions
//
// The channel between the interface and the worker is the pipes the operating
// system already gave you when the supervisor launched it.  That is not a
// smaller version of a socket, it is a different guarantee: there is no
// filesystem object, so nothing else on the machine can connect even in
// principle, and the channel is destroyed with the process.  It also means a
// worker cannot outlive the interface that started it - when the application
// quits, or crashes, or is force quit, the worker's standard input closes and
// it exits, with no PID file and no heartbeat to get wrong.
//
// # Crashes
//
// The worker is a separate process, so a panic in it - or one of Go's
// unrecoverable runtime failures, like a concurrent map write, which recover
// cannot catch - takes down the worker and not your interface.  The supervisor
// notices, reports it, and starts a new one.
//
// # The wire format
//
// Newline delimited JSON, in both directions.  Your own message travels in
// "p", untouched:
//
//	to the worker     {"id":7,"p":<your request>}
//	from the worker   {"t":"reply","id":7,"p":<your reply>}
//	                  {"t":"reply","id":7,"e":"what went wrong"}
//	                  {"t":"event","p":<your event>}
//
// Events are unsolicited: the worker sends one whenever its state moves, so an
// interface never polls and never waits on a timer.  Replies are matched to
// requests by id, so a slow request cannot hold up the events behind it.
//
// Standard output carries this stream and nothing else.  Logs go to standard
// error, always.  A worker that no one is watching writes neither.
package vero

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

// Envelope is one line of the protocol.  Everything is optional except what
// the message kind requires, so the same struct decodes in both directions.
type Envelope struct {
	// Kind is "event" or "reply" on the way out of a worker, and empty on the
	// way in, where every line is a request.
	Kind string `json:"t,omitempty"`

	// ID matches a reply to the request that caused it.  Events have none.
	ID uint64 `json:"id,omitempty"`

	// Name routes a request to a handler registered with Handle or Update.
	// Empty when
	// the worker has a single handler that dispatches for itself.
	//
	// It lives here rather than inside the payload so that vero can route
	// without knowing anything about the message, and so an application is
	// not obliged to carry a type field in every request it defines.
	Name string `json:"n,omitempty"`

	// Payload is your own message, carried through untouched.
	Payload json.RawMessage `json:"p,omitempty"`

	// Error is set instead of Payload when a handler returned an error.
	Error string `json:"e,omitempty"`
}

const (
	kindEvent = "event"
	kindReply = "reply"
)

// Handler answers one request.
//
// ctx is cancelled when the interface goes away, so a handler that waits -
// a long poll, most obviously - must select on ctx.Done() as well. Without
// that the worker cannot exit when its parent does: it has stopped reading
// requests, but it is still waiting for the answer to one nobody will read.  Returning an error sends the message to the
// caller rather than closing anything: the interface can then tell "the worker
// refused this" from "the worker is not there", which want opposite responses.
//
// Returning a nil reply and a nil error answers nothing at all, which suits a
// request that only causes an action.
type Handler func(ctx context.Context, request json.RawMessage) (reply any, err error)

// ErrWorkerNotRunning is returned by Request when the worker has died and has
// not been restarted yet.  It is worth distinguishing in an interface: it
// means wait, not that anything you did was wrong.
var ErrWorkerNotRunning = errors.New("vero: the worker is not running")

// RemoteError is what a Handler's error becomes on the other side of the pipe.
type RemoteError struct{ Message string }

// Error is the worker's own message, not vero's.
func (e *RemoteError) Error() string { return "vero: worker refused the request: " + e.Message }

// DefaultStateInterval is how often WorkerOptions.State is sampled for a
// change when StateInterval is not set.  Fast enough that a progress bar moves
// smoothly, slow enough that nothing is sent while nothing is happening.
const DefaultStateInterval = 100 * time.Millisecond

// MaxLineSize caps one protocol line, so a corrupt or hostile stream cannot
// ask for an unbounded allocation.  Payloads larger than this belong in a file
// with the path sent through the pipe.
const MaxLineSize = 16 << 20 // 16 MiB

func replyEnvelope(id uint64, reply any, err error) Envelope {
	if err != nil {
		return Envelope{Kind: kindReply, ID: id, Error: err.Error()}
	}
	if reply == nil {
		return Envelope{Kind: kindReply, ID: id}
	}
	payload, marshalErr := json.Marshal(reply)
	if marshalErr != nil {
		return Envelope{Kind: kindReply, ID: id, Error: fmt.Sprintf("cannot encode reply: %v", marshalErr)}
	}
	return Envelope{Kind: kindReply, ID: id, Payload: payload}
}
