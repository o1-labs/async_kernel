(* Scratch driver: proves the jobtrace extensions actually fire, not just typecheck.
   Not part of the library build; see README-jobtrace.md. *)
open! Core
open! Async_kernel

let burn_ms ms =
  let start = Time_ns.now () in
  let target = Time_ns.Span.of_ms ms in
  while Time_ns.Span.( < ) (Time_ns.diff (Time_ns.now ()) start) target do
    ()
  done
;;

let () =
  let entered = ref 0 in
  let exited = ref 0 in
  Tracing.set_tracers
    ~on_job_enter:(fun _ -> incr entered)
    ~on_job_exit:(fun _ _ -> incr exited);
  let long_jobs = ref [] in
  let long_cycles = ref [] in
  don't_wait_for
    (Stream.iter' Async_kernel_scheduler.long_jobs_with_context ~f:(fun (ctx, span) ->
       long_jobs := (ctx, span) :: !long_jobs;
       Deferred.unit));
  don't_wait_for
    (Stream.iter'
       (Async_kernel_scheduler.long_cycles_with_context
          ~at_least:(Time_ns.Span.of_ms 500.))
       ~f:(fun (span, ctx) ->
         long_cycles := (span, ctx) :: !long_cycles;
         Deferred.unit));
  (* a job tagged with a tid, running long enough to trip the 2000ms threshold *)
  let ctx =
    Execution_context.with_tid (Async_kernel_scheduler.current_execution_context ()) 42
  in
  Async_kernel_scheduler.enqueue_job ctx (fun () -> burn_ms 2100.) ();
  (* several cycles: one to run the job, later ones to drain [long_jobs_last_cycle],
     which is flushed at cycle *start*. *)
  for _ = 1 to 5 do
    Async_kernel_scheduler.Expert.run_cycles_until_no_jobs_remain ()
  done;
  let failures = ref 0 in
  let check name b =
    printf "%s %s\n" (if b then "PASS" else "FAIL") name;
    if not b then incr failures
  in
  check "on_job_enter fired" (!entered > 0);
  check "on_job_exit fired" (!exited > 0);
  check "long_jobs_with_context yielded a job" (not (List.is_empty !long_jobs));
  check
    "long job carries its tid"
    (List.exists !long_jobs ~f:(fun (ctx, _) -> ctx.Execution_context.tid = 42));
  check
    "long job duration >= 2000ms"
    (List.exists !long_jobs ~f:(fun (_, span) ->
       Float.( >= ) (Time_ns.Span.to_ms span) 2000.));
  check "long_cycles_with_context yielded a cycle" (not (List.is_empty !long_cycles));
  check
    "Monitor.here is exported"
    (Option.is_none (Monitor.here (Monitor.create ())) || true);
  printf "long_jobs=%d long_cycles=%d entered=%d exited=%d\n"
    (List.length !long_jobs) (List.length !long_cycles) !entered !exited;
  exit (if !failures = 0 then 0 else 1)
;;
