(* demo.sml - a deterministic FRP scenario: a UI with a click counter and a
   derived "doubled" readout, traced over injected time. Writes the trace to
   assets/trace.txt (byte-identical on MLton and Poly/ML) and prints it. *)

(* Forced-decimal real formatting: always a decimal point, leading '-' (never
   SML's '~'), so the asset is byte-identical across compilers. *)
fun fmtReal r =
  let
    val s = Real.fmt (StringCvt.FIX (SOME 1)) (Real.abs r)
    val sign = if r < 0.0 then "-" else ""
  in sign ^ s end

fun padR (w, s) =
  if String.size s >= w then s
  else s ^ String.implode (List.tabulate (w - String.size s, fn _ => #" "))

open Signal

(* Mouse clicks arrive at t = 1, 2, 3, 5 (injected, never sampled from a clock). *)
val clicks = fromList [(1.0, ()), (2.0, ()), (3.0, ()), (5.0, ())]

(* Reactive UI state. *)
val count   = foldp (fn ((), n) => n + 1) 0 clicks
val doubled = map (fn n => n * 2) count

(* Sample instants: t = 0 plus every break point up to tMax. *)
val tMax = 6.0
val times =
  0.0 :: List.filter (fn t => t <= tMax) (breaks count)

val countTrace   = runUntil tMax count
val doubledTrace = runUntil tMax doubled

fun rows () =
  ListPair.map
    (fn (t, (c, d)) =>
        padR (8, "t=" ^ fmtReal t)
        ^ padR (12, "count=" ^ Int.toString c)
        ^ "doubled=" ^ Int.toString d)
    (times, ListPair.zip (countTrace, doubledTrace))

val report =
  String.concatWith "\n"
    ("sml-signal demo - click-counter trace" :: "" :: rows ())
  ^ "\n"

val () =
  let val os = TextIO.openOut "assets/trace.txt"
  in TextIO.output (os, report); TextIO.closeOut os end

val () = print report
