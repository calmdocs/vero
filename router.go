package vero

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"sync/atomic"
)

// Router sends each request to a handler chosen by name, with the request and
// the reply as the types that handler actually wants.
//
// Without it a worker takes one Handler and dispatches for itself, which means
// a switch on a type field, a json.Unmarshal per branch, and a caller that has
// to work out what came back. That last part is where it goes wrong: an
// application ends up trying to decode a reply as one type, then another,
// until one succeeds - and an empty JSON array decodes as any of them, so a
// list that happens to be empty is read as whatever was tried first.
//
//	vero.Handle(w, "getGroups", func(ctx context.Context, _ struct{}) ([]Group, error) {
//	    return groups(), nil
//	})
//	vero.Update(w, "addGroup", func(ctx context.Context, req AddGroup) error {
//	    return add(req.Name)
//	})
//	w.Serve()
//
// The name travels in the envelope, so an application's own messages stay
// exactly as it defined them.
type router struct {
	mu       sync.RWMutex
	routes   map[string]route
	fallback Handler
	fellBack atomic.Uint64
}

type route struct {
	name string
	fn   func(context.Context, json.RawMessage) (any, error)
}

func newRouter() *router {
	return &router{routes: map[string]route{}}
}

// Handle answers one request name.
//
// Req is what the request decodes into and Rep is what the reply is encoded
// from, so neither the handler nor the caller has to guess. Use struct{} for a
// request that carries nothing.
func Handle[Req any, Rep any](w *Worker, name string, fn func(ctx context.Context, request Req) (Rep, error)) {
	r := w.router
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, taken := r.routes[name]; taken {
		panic("vero: two handlers registered for " + name)
	}
	r.routes[name] = route{
		name: name,
		fn: func(ctx context.Context, raw json.RawMessage) (any, error) {
			var request Req
			if len(raw) > 0 {
				if err := json.Unmarshal(raw, &request); err != nil {
					return nil, fmt.Errorf("cannot read a %s request: %w", name, err)
				}
			}
			return fn(ctx, request)
		},
	}
}

// Fallback answers requests whose name matches nothing registered, including
// requests that carry no name at all.
//
// Without one an unknown name is refused, which is the default and usually
// right: it is what makes named routing the only way in. Set one only while
// something older is still expected to connect, and watch FallbackCalls to
// know when that has stopped being true. It is worth
// setting when an interface can be newer than the worker it is driving: it
// then asks for things this build has never heard of, and refusing is a
// failure the person did not cause and cannot act on.
func (r *router) Fallback(h Handler) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.fallback = h
}

// FallbackCalls counts the requests that have reached the fallback.
//
// It answers the question a fallback creates: when can it go? A fallback is
// there for interfaces that predate named routing, and while any of them are
// still running this climbs. When it stays at zero across a release, nothing
// is using the untyped path and both it and the fallback can be deleted -
// which is what makes typed routing the only way in.
func (r *router) FallbackCalls() uint64 { return r.fellBack.Load() }

// Names lists what has been registered, in no particular order.
func (r *router) Names() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]string, 0, len(r.routes))
	for name := range r.routes {
		out = append(out, name)
	}
	return out
}

func (r *router) route(ctx context.Context, name string, payload json.RawMessage) (any, error) {
	r.mu.RLock()
	rt, ok := r.routes[name]
	fallback := r.fallback
	r.mu.RUnlock()

	if ok {
		return rt.fn(ctx, payload)
	}
	if fallback != nil {
		r.fellBack.Add(1)
		return fallback(ctx, payload)
	}
	return nil, fmt.Errorf("unsupported request type: %q", name)
}
