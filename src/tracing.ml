type tracing_fns = {
  on_job_enter : Execution_context.t -> unit;
  on_job_exit : Execution_context.t -> Time_ns.Span.t -> unit;
}

let tracers =
  ref { on_job_enter = (fun _ -> ()); on_job_exit = (fun _ _ -> ()) }

let set_tracers ~on_job_enter ~on_job_exit =
  tracers := { on_job_enter; on_job_exit }
