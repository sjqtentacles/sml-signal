(* signal.sml

   Implementation of `signature SIGNAL`.

   Representation:
     - `'a signal` is a sampling function `real -> 'a` paired with the sorted,
       de-duplicated list of instants at which the value may change ("breaks").
       Keeping the breaks lets `runUntil` produce a deterministic step trace
       without ever consulting a clock.
     - `'a event` is a list of `(time, payload)` occurrences kept sorted by time
       with a stable tie-break (earlier list position wins). Every constructor
       and combinator preserves that invariant, so internal code may assume the
       list is sorted. *)

structure Signal :> SIGNAL =
struct

  type 'a signal = { at : real -> 'a, breaks : real list }
  type 'a event  = (real * 'a) list

  (* ---- sorted-unique union of two break lists ---- *)
  fun mergeBreaks (xs, ys) =
    let
      fun go ([], bs) = bs
        | go (as_, []) = as_
        | go (a :: as_, b :: bs) =
            if Real.< (a, b) then a :: go (as_, b :: bs)
            else if Real.> (a, b) then b :: go (a :: as_, bs)
            else a :: go (as_, bs)        (* equal: keep a single copy *)
    in go (xs, ys) end

  (* ---- signals ---- *)
  fun const x = { at = fn _ => x, breaks = [] }

  fun map f (s : 'a signal) : 'b signal =
    { at = fn t => f (#at s t), breaks = #breaks s }

  fun combine f (a : 'a signal) (b : 'b signal) : 'c signal =
    { at = fn t => f (#at a t, #at b t)
    , breaks = mergeBreaks (#breaks a, #breaks b) }

  fun sampleAt (s : 'a signal) t = #at s t
  fun breaks (s : 'a signal) = #breaks s

  (* ---- events ---- *)
  val never = []
  fun mapE f xs = List.map (fn (t, x) => (t, f x)) xs
  fun filterE p xs = List.filter (fn (_, x) => p x) xs
  fun countE xs = List.length xs
  fun occurrences xs = xs

  (* Stable merge by time: on a tie the left operand's occurrence comes first. *)
  fun merge (xs, ys) =
    let
      fun go ([], bs) = bs
        | go (as_, []) = as_
        | go ((x as (tx, _)) :: xs', (y as (ty, _)) :: ys') =
            if Real.<= (tx, ty) then x :: go (xs', y :: ys')
            else y :: go (x :: xs', ys')
    in go (xs, ys) end

  (* Stable top-down mergesort by time (contiguous halves preserve order). *)
  fun fromList xs =
    let
      fun sort lst =
        let val n = List.length lst
        in
          if n <= 1 then lst
          else
            let
              val half = n div 2
              val l = List.take (lst, half)
              val r = List.drop (lst, half)
            in merge (sort l, sort r) end
        end
    in sort xs end

  (* Drop consecutive duplicate times (input already sorted ascending). *)
  fun dedup [] = []
    | dedup [x] = [x]
    | dedup (x :: y :: rest) =
        if Real.== (x, y) then dedup (y :: rest) else x :: dedup (y :: rest)

  (* Incremental foldp: precompute the running accumulator at each unique
     occurrence time once, then a sample is a search for the last break <= t.
     This avoids re-folding the whole event list on every `sampleAt` while
     producing byte-identical results (breaks and values) to the naive fold. *)
  fun foldp f init ev =
    let
      (* steps : (time, accAfterThisTime) list, one entry per UNIQUE time, in
         ascending time order. For ties at the same time we fold every
         occurrence (in stream order) before recording the step. *)
      val steps =
        let
          fun build (acc, []) = []
            | build (acc, (t, x) :: rest) =
                let
                  (* fold all occurrences sharing this exact time t *)
                  fun same (acc, (t', y) :: more) =
                        if Real.== (t', t)
                        then same (f (y, acc), more)
                        else (acc, (t', y) :: more)
                    | same (acc, []) = (acc, [])
                  val (acc', rest') = same (f (x, acc), rest)
                in
                  (t, acc') :: build (acc', rest')
                end
        in
          build (init, ev)
        end

      (* value at t: last step whose time <= t, else init *)
      fun at t =
        let
          fun go (best, []) = best
            | go (best, (tt, v) :: more) =
                if Real.<= (tt, t) then go (v, more) else best
        in
          go (init, steps)
        end
    in
      { at = at, breaks = List.map #1 steps }
    end

  (* hold/stepper: keep the most recent occurrence's payload (no folding). *)
  fun hold init ev = foldp (fn (x, _) => x) init ev
  val stepper = hold

  (* ---- event <-> signal interaction ---- *)

  fun snapshot (s : 'b signal) (ev : 'a event) : ('a * 'b) event =
    List.map (fn (t, x) => (t, (x, #at s t))) ev

  fun tag (s : 'b signal) (ev : 'a event) : 'b event =
    List.map (fn (t, _) => (t, #at s t)) ev

  fun gate (s : bool signal) (ev : 'a event) : 'a event =
    List.filter (fn (t, _) => #at s t) ev

  (* accumE/scanlE: emit the post-occurrence state as a new event each time. *)
  fun accumE f init ev =
    let
      fun go (_, []) = []
        | go (acc, (t, x) :: rest) =
            let val acc' = f (x, acc)
            in (t, acc') :: go (acc', rest) end
    in
      go (init, ev)
    end
  val scanlE = accumE

  (* ---- dynamic switching ---- *)

  (* switcher: a `hold`-like signal over signals. At time t, find the latest
     switch occurrence whose time <= t and sample that signal; before any
     switch, use `init`. Breaks include the switch times plus the breaks of
     every candidate signal (a safe over-approximation that keeps `runUntil`
     deterministic). *)
  fun switcher (init : 'a signal) (ev : 'a signal event) : 'a signal =
    let
      fun activeAt t =
        let
          fun go (best, []) = best
            | go (best, (tt, sg) :: more) =
                if Real.<= (tt, t) then go (sg, more) else best
        in
          go (init, ev)
        end
      val switchTimes = List.map #1 ev
      val innerBreaks =
        List.foldl (fn ((_, sg), acc) => mergeBreaks (#breaks sg, acc))
          (#breaks init) ev
    in
      { at = fn t => #at (activeAt t) t
      , breaks = mergeBreaks (dedup switchTimes, innerBreaks) }
    end

  (* switch: flatten a signal-of-signals. *)
  fun switch (ss : 'a signal signal) : 'a signal =
    { at = fn t => #at (#at ss t) t, breaks = #breaks ss }

  (* ---- applicative lifting ---- *)

  fun lift2 f a b = combine f a b

  fun lift3 f (a : 'a signal) (b : 'b signal) (c : 'c signal) : 'd signal =
    { at = fn t => f (#at a t, #at b t, #at c t)
    , breaks = mergeBreaks (#breaks a, mergeBreaks (#breaks b, #breaks c)) }

  fun apply (sf : ('a -> 'b) signal) (sx : 'a signal) : 'b signal =
    { at = fn t => (#at sf t) (#at sx t)
    , breaks = mergeBreaks (#breaks sf, #breaks sx) }

  fun runUntil tMax (s : 's signal) =
    let
      val within = List.filter (fn t => Real.<= (t, tMax)) (#breaks s)
      val times = mergeBreaks ([0.0], within)
    in
      List.map (#at s) times
    end
end
