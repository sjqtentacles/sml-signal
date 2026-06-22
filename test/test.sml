(* Tests for sml-signal: pure FRP signals + event streams.

   Vectors are hand-computed and deterministic. The headline is the "click
   counter": clicks at t = 1,2,3 folded with (+1) trace to [0,1,2,3]. *)

structure Tests =
struct
  open Harness
  open Signal

  fun runAll () =
    let
      (* ---- signals: const / map / combine / sampleAt ---- *)
      val () = section "signals"
      val s0 = const 7
      val () = checkInt "const samples constant" (7, sampleAt s0 0.0)
      val () = checkInt "const at other time"    (7, sampleAt s0 99.0)

      val s1 = map (fn x => x * 2) s0
      val () = checkInt "map doubles"            (14, sampleAt s1 0.0)

      val sa = const 3
      val sb = const 4
      val sc = combine (fn (a, b) => a + b) sa sb
      val () = checkInt "combine adds"           (7, sampleAt sc 0.0)

      val () = checkIntList "const has no breaks" ([], List.map Real.round (breaks s0))

      (* ---- events: fromList sorts stably ---- *)
      val () = section "events"
      val e = fromList [(3.0, "c"), (1.0, "a"), (2.0, "b")]
      val () = checkStringList "fromList sorts by time"
                 (["a", "b", "c"], List.map #2 (occurrences e))
      val () = checkInt "countE" (3, countE e)
      val () = checkInt "never is empty" (0, countE (never : int event))

      (* stable tie-break: equal timestamps keep list order *)
      val eTie = fromList [(1.0, "x"), (1.0, "y"), (1.0, "z")]
      val () = checkStringList "fromList stable on ties"
                 (["x", "y", "z"], List.map #2 (occurrences eTie))

      (* ---- mapE / filterE ---- *)
      val () = section "mapE / filterE"
      val nums = fromList [(1.0, 1), (2.0, 2), (3.0, 3), (4.0, 4)]
      val () = checkIntList "mapE squares"
                 ([1, 4, 9, 16], List.map #2 (occurrences (mapE (fn x => x * x) nums)))
      val () = checkIntList "filterE keeps evens"
                 ([2, 4], List.map #2 (occurrences (filterE (fn x => x mod 2 = 0) nums)))

      (* ---- merge: left-before-right on ties, otherwise by time ---- *)
      val () = section "merge"
      val left  = fromList [(1.0, "L1"), (3.0, "L3")]
      val right = fromList [(1.0, "R1"), (2.0, "R2")]
      val m = merge (left, right)
      val () = checkStringList "merge sorts, left wins ties"
                 (["L1", "R1", "R2", "L3"], List.map #2 (occurrences m))
      val () = checkIntList "merge times"
                 ([1, 1, 2, 3], List.map (Real.round o #1) (occurrences m))

      (* ---- foldp + runUntil: the click counter ---- *)
      val () = section "foldp / runUntil"
      val clicks = fromList [(1.0, ()), (2.0, ()), (3.0, ())]
      val counter = foldp (fn ((), n) => n + 1) 0 clicks
      val () = checkInt "counter before any click" (0, sampleAt counter 0.0)
      val () = checkInt "counter after first click" (1, sampleAt counter 1.0)
      val () = checkInt "counter between clicks"     (1, sampleAt counter 1.5)
      val () = checkInt "counter after all clicks"   (3, sampleAt counter 9.0)
      val () = checkIntList "runUntil trace" ([0, 1, 2, 3], runUntil 5.0 counter)
      val () = checkIntList "runUntil stops at tMax" ([0, 1, 2], runUntil 2.0 counter)
      val () = checkIntList "foldp breaks are event times"
                 ([1, 2, 3], List.map Real.round (breaks counter))

      (* foldp (+) running totals *)
      val deposits = fromList [(1.0, 10), (2.0, 5), (3.0, 20)]
      val balance = foldp (fn (x, acc) => acc + x) 0 deposits
      val () = checkIntList "running totals" ([0, 10, 15, 35], runUntil 9.0 balance)

      (* mapped foldp signal still traces deterministically *)
      val tenx = map (fn n => n * 10) counter
      val () = checkIntList "map over foldp signal" ([0, 10, 20, 30], runUntil 5.0 tenx)

      (* combine two foldp signals: breaks are the union of event times *)
      val combined = combine (fn (a, b) => a + b) counter balance
      val () = checkIntList "combine union trace"
                 ([0, 11, 17, 38], runUntil 9.0 combined)
    in
      ()
    end

  fun run () = (reset (); runAll (); Harness.run ())
end
