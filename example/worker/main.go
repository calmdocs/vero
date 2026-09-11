// Command worker is the logic half of the example: the part you would write.
//
// It runs three ways, from one binary and one code path:
//
//	worker                 a daemon. Logs what changes; writes no stream.
//	worker -json           the same, with the event stream on stdout for a
//	                       script, a pipe, or anything else that is watching.
//	worker -quiet          silent.
//
// and, without any flag at all, as the worker behind the menu bar app, which
// sets VERO_SERVE when it launches this. Nothing here has to know which.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
	"time"

	"github.com/calmdocs/vero"
)

type Job struct {
	vero.WithID[int]
	Name     string `json:"name"`
	Phase    string `json:"phase"`
	Progress int    `json:"progress"`
}

// Restart puts one job back to the beginning.  A method on the job, because
// that is what the button on its row means.
func (j *Job) Restart() {
	j.Phase, j.Progress = "waiting", 0
}

type Status struct {
	Jobs    []Job  `json:"jobs"`
	Working bool   `json:"working"`
	Since   string `json:"since"`
}

type Request struct {
	Type string `json:"type"`
	ID   int    `json:"id"`
}

var started = time.Now()

// working is true while any job is mid-flight.  Derived rather than stored, so
// it is recomputed wherever the jobs change.
func working(s *Status) {
	s.Working = false
	for _, j := range s.Jobs {
		if j.Phase != "waiting" && j.Phase != "done" {
			s.Working = true
		}
	}
}

func main() {
	var opts vero.WorkerOptions
	opts.Version = version
	opts.RegisterFlags(flag.CommandLine)
	flag.Parse()

	// An interface that ships this worker in its bundle runs it with -version
	// to decide whether the copy on disk is older than the one it shipped.
	opts.PrintVersionAndExit()

	w := vero.NewWorker(opts)

	// Everything the interface draws.  The worker pushes it whenever it
	// changes, and every reply below is it.
	state := w.NewState(Status{
		Jobs: []Job{
			{ID: 1, Name: "Photos", Phase: "waiting"},
			{ID: 2, Name: "Documents", Phase: "waiting"},
			{ID: 3, Name: "Team share", Phase: "waiting"},
		},
		Since: started.Format("15:04:05"),
	})

	if w.Supervised() {
		w.Log("started by an interface")
	} else {
		w.Log("running on its own; nothing is driving this")
	}

	go work(w, state)

	// One handler per request.  The name each is registered under is the
	// routing, so neither side needs a "type" field inside the message.

	// Something opened a window and needs to draw it now: no change, and the
	// reply is the state.
	state.Update("status", func(*Status) error { return nil })

	// The button on a row names one job.  Update rather than EditItem, because
	// Working is derived from every job and has to be recomputed after the
	// change.  A request naming a job that is gone is refused, and the worker
	// carries on: a bad request and a broken worker want different responses.
	state.UpdateWith("restartJob", func(s *Status, req vero.ID[int]) error {
		if err := vero.Edit(s.Jobs, req.ID, (*Job).Restart); err != nil {
			// vero says "no item"; an interface should hear what this
			// application calls the thing.
			return fmt.Errorf("no job with id %d", req.ID)
		}
		working(s)
		return nil
	})

	// An interface that has not moved to named handlers keeps working: this
	// takes anything the router has no name for.  w.FallbackCalls() reports
	// when it has stopped being used and can go.
	w.Fallback(handle(state))

	// Serve blocks. Under an interface it answers requests until that
	// interface quits; on its own it simply never returns.
	if err := w.Serve(); err != nil {
		w.Log("stopped: %v", err)
	}
	w.Log("the interface has gone; stopping")
}

func handle(state *vero.State[Status]) vero.Handler {
	return func(ctx context.Context, request json.RawMessage) (any, error) {
		var r Request
		if err := json.Unmarshal(request, &r); err != nil {
			return nil, err
		}
		switch r.Type {
		case "status":
			// Something opened a window and needs to draw it now.
			return state.JSON()

		case "restart":
			if err := restart(state, r.ID); err != nil {
				return nil, err
			}
			return state.JSON()

		default:
			return nil, fmt.Errorf("unknown request type: %q", r.Type)
		}
	}
}

// version is what -version reports. An interface compares it with the copy it
// has on disk, so it has to increase on every release.
var version = "0.7.1"

// work is the pretend business logic: it moves jobs along and says so.
func work(w *vero.Worker, state *vero.State[Status]) {
	phases := []string{"looking for changes", "scanning", "uploading", "done"}
	for {
		time.Sleep(time.Duration(200+rand.Intn(400)) * time.Millisecond)

		var name, phase, before string
		state.Do(func(s *Status) {
			j := &s.Jobs[rand.Intn(len(s.Jobs))]
			before = j.Phase
			switch {
			case j.Phase == "waiting" || j.Phase == "done":
				j.Phase, j.Progress = phases[0], 0
			case j.Progress >= 100:
				for i, p := range phases {
					if p == j.Phase && i+1 < len(phases) {
						j.Phase, j.Progress = phases[i+1], 0
					}
				}
			default:
				j.Progress += 20 + rand.Intn(30)
				if j.Progress > 100 {
					j.Progress = 100
				}
			}
			name, phase = j.Name, j.Phase
			working(s)
		})

		// Nothing emits here: the worker notices. The log is a separate
		// question - format and volume are not the same thing, and a person
		// wants the phase changes, not every percent.
		if phase != before {
			w.Log("%s: %s", name, phase)
		}
	}
}

// restart puts one job back to the beginning, for the old unnamed requests
// the fallback still answers.
func restart(state *vero.State[Status], id int) error {
	var err error
	state.Do(func(s *Status) {
		if err = vero.Edit(s.Jobs, id, (*Job).Restart); err != nil {
			err = fmt.Errorf("no job with id %d", id)
			return
		}
		working(s)
	})
	return err
}
