package vero_test

import (
	"context"
	"fmt"
	"time"

	"github.com/calmdocs/vero"
)

// The contract with the interface: the same fields Swift, C# and Python
// declare on their side.
type Job struct {
	vero.WithID[int]
	Name     string `json:"name"`
	Progress int    `json:"progress"`
	Paused   bool   `json:"paused"`
}

type Status struct {
	Jobs []Job `json:"jobs"`
}

// A whole worker: your types, your logic, and four calls into vero.
//
// Serve blocks until the interface goes away, then returns so this process can
// leave with it.
func Example() {
	w := vero.NewWorker(vero.WorkerOptions{})

	// Everything the interface draws.  vero pushes it whenever it changes, and
	// every reply below is it.
	jobs := w.NewState(Status{Jobs: []Job{
		{WithID: vero.WithID[int]{ID: 1}, Name: "Photos"},
		{WithID: vero.WithID[int]{ID: 2}, Name: "Documents"},
	}})

	// The work, under the lock, until the interface goes away.
	jobs.Every(200*time.Millisecond, func(s *Status) {
		for i := range s.Jobs {
			if !s.Jobs[i].Paused && s.Jobs[i].Progress < 100 {
				s.Jobs[i].Progress++
			}
		}
	})

	// A button with no payload.
	jobs.Update("addJob", func(s *Status) error {
		n := len(s.Jobs) + 1
		s.Jobs = append(s.Jobs, Job{
			WithID: vero.WithID[int]{ID: n},
			Name:   fmt.Sprintf("Job %d", n),
		})
		return nil
	})

	// A button on one row: vero decodes the id, finds the job, and replies
	// with the new state.
	jobs.UpdateItem("pauseJob", func(j *Job) error {
		j.Paused = !j.Paused
		return nil
	})

	w.Serve()
}

// Edit finds an item by the id an interface sent, and changes it.  The pointer
// is into the slice, so the change sticks.
func ExampleEdit() {
	jobs := []Job{
		{WithID: vero.WithID[int]{ID: 1}, Name: "Photos", Progress: 50},
		{WithID: vero.WithID[int]{ID: 2}, Name: "Documents", Progress: 80},
	}

	err := vero.Edit(jobs, 1, func(j *Job) { j.Progress = 0 })
	fmt.Println(jobs[0].Progress, err)

	// A request naming something that is gone is refused, and the worker
	// carries on.
	fmt.Println(vero.Edit(jobs, 99, func(j *Job) { j.Progress = 0 }))

	// Output:
	// 0 <nil>
	// no item with id 99
}

// A request that carries something of its own needs a type for it, and
// UpdateWith rather than Update.
func ExampleState_UpdateWith() {
	type Rename struct {
		ID   int    `json:"id"`
		Name string `json:"name"`
	}

	w := vero.NewWorker(vero.WorkerOptions{})
	jobs := w.NewState(Status{})

	jobs.UpdateWith("renameJob", func(s *Status, req Rename) error {
		return vero.Edit(s.Jobs, req.ID, func(j *Job) { j.Name = req.Name })
	})

	w.Serve()
}

// Handle is for a reply that is not the state: its own request and reply
// types, and a context that is cancelled when the interface goes away.
func ExampleWorker_Handle() {
	type Query struct {
		Path string `json:"path"`
	}
	type Size struct {
		Bytes int64 `json:"bytes"`
	}

	w := vero.NewWorker(vero.WorkerOptions{})

	w.Handle("sizeOf", func(ctx context.Context, req Query) (Size, error) {
		// ctx ends when the interface does, so a slow answer can give up.
		return Size{Bytes: 1024}, nil
	})

	w.Serve()
}

// Do is a write from the worker's own code, rather than an answer to a
// request: the lock is taken for the moment of the change, and the new state
// is pushed to the interface like any other.
func ExampleState_Do() {
	w := vero.NewWorker(vero.WorkerOptions{})
	jobs := w.NewState(Status{})

	go func() {
		// …work happens…
		jobs.Do(func(s *Status) {
			s.Jobs = append(s.Jobs, Job{WithID: vero.WithID[int]{ID: 7}, Name: "Found"})
		})
	}()

	w.Serve()
}
