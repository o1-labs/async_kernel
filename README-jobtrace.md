# `async_kernel` — o1-labs "jobtrace" fork

This is o1-labs' fork of Jane Street's [`async_kernel`]. It adds a small set of
hooks and accessors that let Mina instrument the Async scheduler for tracing and
for long-job / long-cycle diagnostics. None of these changes affect the behavior
of unmodified programs: every addition is opt-in and defaults to a no-op, so
there is no measurable overhead unless a consumer opts in.

## Differences from upstream `async_kernel`

### `Async_kernel.Tracing` — per-job callbacks

A new `Tracing` module lets you install a pair of callbacks that run around every
Async job:

```ocaml
val set_tracers
  :  on_job_enter:(Execution_context.t -> unit)
  -> on_job_exit:(Execution_context.t -> Time_ns.Span.t -> unit)
  -> unit
```

- `on_job_enter` is called with the job's execution context immediately before
  the job runs.
- `on_job_exit` is called after the job returns, with the same execution context
  and the wall-clock duration of the job.

Both callbacks default to no-ops. Calling `set_tracers` replaces any previously
installed pair (the tracers are global scheduler state, not per-job).

Caveat: if a job raises, the exception propagates to the scheduler's cycle-level
handler, and `on_job_exit` is **not** called for that job. Do any required
cleanup in `on_job_enter` defensively rather than relying on a matching
`on_job_exit`.

### `Execution_context.tid` — logical thread ids

`Execution_context.t` carries an extra field `tid : int` (default `0`), together
with an accessor:

```ocaml
val Execution_context.with_tid : t -> int -> t
```

Mina's `o1trace` uses this to tag execution contexts with a logical thread id, so
that traced jobs can be attributed to the "thread" that scheduled them.

### Scheduler diagnostics streams

Two extra streams are exposed on `Async_kernel_scheduler`:

```ocaml
val long_cycles_with_context
  :  at_least:Time_ns.Span.t
  -> (Time_ns.Span.t * Execution_context.t) Async_stream.t
```

Like upstream's `long_cycles`, but each element also carries the execution
context that was current at the start of the long cycle, which is useful for
attributing slow cycles to a subsystem.

```ocaml
val long_jobs_with_context : (Execution_context.t * Time_ns.Span.t) Async_stream.t
```

A stream of the *individual* jobs that ran for at least 2000 ms, each paired with
its execution context and its duration. Long jobs are accumulated as they run
during a cycle and flushed to the stream at the start of the following cycle.

### Miscellaneous accessors

- `Monitor.here : t -> Source_code_position.t option` — the source position a
  monitor was created at (the `?here` passed to `Monitor.create`), if any.
- `Async_kernel_scheduler.t : unit -> Scheduler.t` — the raw global scheduler,
  exposed for Mina.

## Example: installing tracers

```ocaml
let () =
  Async_kernel.Tracing.set_tracers
    ~on_job_enter:(fun ctx -> (* record job start for [ctx] *) ignore ctx)
    ~on_job_exit:(fun ctx elapsed ->
      (* [elapsed] is the wall-clock time the job took *)
      ignore (ctx, elapsed))
```

[`async_kernel`]: https://github.com/janestreet/async_kernel
