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
	"sync"
	"time"

	"github.com/calmdocs/vero"
)

type Job struct {
	ID       int    `json:"id"`
	Name     string `json:"name"`
	Phase    string `json:"phase"`
	Progress int    `json:"progress"`
}

type Status struct {
	Jobs    []Job  `json:"jobs"`
	Working bool   `json:"working"`
	Since   string `json:"since"`
}

// RestartJob is what the "restartJob" handler takes.  A named handler needs no
// "type" field: the name it is registered under is the routing.
type RestartJob struct {
	ID int `json:"id"`
}

type Request struct {
	Type string `json:"type"`
	ID   int    `json:"id"`
}

var (
	mu   sync.Mutex
	jobs = []Job{
		{ID: 1, Name: "Photos", Phase: "waiting"},
		{ID: 2, Name: "Documents", Phase: "waiting"},
		{ID: 3, Name: "Team share", Phase: "waiting"},
	}
	started = time.Now()
)

func snapshot() Status {
	mu.Lock()
	defer mu.Unlock()
	out := Status{Jobs: append([]Job{}, jobs...), Since: started.Format("15:04:05")}
	for _, j := range jobs {
		if j.Phase != "waiting" && j.Phase != "done" {
			out.Working = true
		}
	}
	return out
}

func main() {
	var opts vero.WorkerOptions
	opts.Version = version
	opts.RegisterFlags(flag.CommandLine)
	flag.Parse()

	// An interface that ships this worker in its bundle runs it with -version
	// to decide whether the copy on disk is older than the one it shipped.
	opts.PrintVersionAndExit()

	// Everything the interface draws.  Serve pushes it whenever it changes,
	// and an Update handler replies with it.
	opts.State = func() any { return snapshot() }

	w := vero.NewWorker(opts)
	if w.Supervised() {
		w.Log("started by an interface")
	} else {
		w.Log("running on its own; nothing is driving this")
	}

	go work(w)

	// One handler per request, each with its own types, so neither side has to
	// agree on a "type" field inside the message.
	vero.Handle(w, "status", func(context.Context, struct{}) (Status, error) {
		// Something opened a window and needs to draw it now.
		return snapshot(), nil
	})

	vero.Update(w, "restartJob", func(_ context.Context, req RestartJob) error {
		return restart(req.ID)
	})

	// An interface that has not moved to named handlers keeps working: this
	// takes anything the router has no name for.  w.FallbackCalls() reports
	// when it has stopped being used and can go.
	w.Fallback(handle)

	// Serve blocks. Under an interface it answers requests until that
	// interface quits; on its own it simply never returns.
	if err := w.Serve(); err != nil {
		w.Log("stopped: %v", err)
	}
	w.Log("the interface has gone; stopping")
}

func handle(ctx context.Context, request json.RawMessage) (any, error) {
	var r Request
	if err := json.Unmarshal(request, &r); err != nil {
		return nil, err
	}
	switch r.Type {
	case "status":
		// Something opened a window and needs to draw it now.
		return snapshot(), nil

	case "restart":
		if err := restart(r.ID); err != nil {
			return nil, err
		}
		return snapshot(), nil

	default:
		return nil, fmt.Errorf("unknown request type: %q", r.Type)
	}
}

// version is what -version reports. An interface compares it with the copy it
// has on disk, so it has to increase on every release.
var version = "0.4.0"

// work is the pretend business logic: it moves jobs along and says so.
func work(w *vero.Worker) {
	phases := []string{"looking for changes", "scanning", "uploading", "done"}
	for {
		time.Sleep(time.Duration(200+rand.Intn(400)) * time.Millisecond)

		mu.Lock()
		j := &jobs[rand.Intn(len(jobs))]
		before := j.Phase
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
		name, phase := j.Name, j.Phase
		mu.Unlock()

		// Nothing emits here: EmitOnChange notices. The log is a separate
		// question - format and volume are not the same thing, and a person
		// wants the phase changes, not every percent.
		if phase != before {
			w.Log("%s: %s", name, phase)
		}
	}
}

// restart puts one job back to the beginning.
func restart(id int) error {
	mu.Lock()
	found := false
	for i := range jobs {
		if jobs[i].ID == id {
			jobs[i].Phase, jobs[i].Progress = "waiting", 0
			found = true
		}
	}
	mu.Unlock()
	if !found {
		// The interface can show this. It is a bad request, not a broken
		// worker, and those want different responses.
		return fmt.Errorf("no job with id %d", id)
	}
	return nil
}
