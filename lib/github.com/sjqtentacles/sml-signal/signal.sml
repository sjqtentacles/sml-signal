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

  fun foldp f init ev =
    let
      fun at t =
        List.foldl
          (fn ((tt, x), acc) => if Real.<= (tt, t) then f (x, acc) else acc)
          init ev
    in
      { at = at, breaks = dedup (List.map #1 ev) }
    end

  fun runUntil tMax (s : 's signal) =
    let
      val within = List.filter (fn t => Real.<= (t, tMax)) (#breaks s)
      val times = mergeBreaks ([0.0], within)
    in
      List.map (#at s) times
    end
end
