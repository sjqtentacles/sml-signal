(* signal.sig

   A tiny, pure functional-reactive-programming (FRP) core: time-varying
   `signal`s and discrete `event` streams with the usual `map`/`combine`/`fold`
   combinators.

   Everything is DETERMINISTIC and byte-identical across MLton and Poly/ML
   because there is NO clock, NO threads, and NO external I/O anywhere: time and
   external occurrences are *injected* by the caller.

     - A `'a signal` is a value defined for every instant `t : real`. Sample it
       with `sampleAt`. Signals also remember the discrete instants ("breaks")
       at which they may change, so a whole run can be traced with `runUntil`.
     - An `'a event` is a finite, explicitly time-stamped list of occurrences,
       kept sorted by time with a documented, stable tie-break (see `merge`).

   The classic worked example is a click counter: feed clicks as an event
   stream, `foldp` them into a running total, and `runUntil` yields the trace
   `[0, 1, 2, 3]`. *)

signature SIGNAL =
sig
  type 'a signal                          (* a time-varying value *)
  type 'a event                           (* discrete occurrences  *)

  (* ---- signals ---- *)

  (* A constant signal: the same value at every instant; no break points. *)
  val const   : 'a -> 'a signal

  (* Map a pure function over a signal (break points preserved). *)
  val map     : ('a -> 'b) -> 'a signal -> 'b signal

  (* Combine two signals pointwise; the result changes at the union of both
     operands' break points. *)
  val combine : ('a * 'b -> 'c) -> 'a signal -> 'b signal -> 'c signal

  (* Sample a signal at an injected instant (time is an argument, never a
     clock). *)
  val sampleAt : 'a signal -> real -> 'a

  (* The sorted, de-duplicated instants at which a signal may change value.
     `const` has none; `foldp` exposes its event times. *)
  val breaks  : 'a signal -> real list

  (* ---- events ---- *)

  (* The empty event stream (no occurrences ever). *)
  val never   : 'a event

  (* Map a pure function over each occurrence's payload (times unchanged). *)
  val mapE    : ('a -> 'b) -> 'a event -> 'b event

  (* Keep only the occurrences whose payload satisfies the predicate. *)
  val filterE : ('a -> bool) -> 'a event -> 'a event

  (* Merge two streams into one, sorted by time. Tie-break rule (stable and
     documented): occurrences with equal timestamps keep the LEFT stream's
     occurrences before the RIGHT stream's, and within a stream their original
     order is preserved. *)
  val merge   : 'a event * 'a event -> 'a event

  (* The number of occurrences in a stream (handy for tests). *)
  val countE  : 'a event -> int

  (* Read a stream back out as a sorted (time, value) list. *)
  val occurrences : 'a event -> (real * 'a) list

  (* Accumulate a stream into a stepwise signal (the FRP `foldp`). The value at
     instant `t` is `init` folded over every occurrence whose time is <= `t`, in
     time order. Its break points are the (unique) occurrence times. *)
  val foldp   : ('a * 's -> 's) -> 's -> 'a event -> 's signal

  (* Build a stream from an explicitly time-stamped list (sorted stably by
     time; equal-time entries keep their list order). *)
  val fromList : (real * 'a) list -> 'a event

  (* A deterministic trace of a signal up to (and including) `tMax`: the value
     at instant 0.0 followed by the value at each break point <= tMax, in time
     order. The same list comes out on MLton and Poly/ML. *)
  val runUntil : real -> 's signal -> 's list
end
