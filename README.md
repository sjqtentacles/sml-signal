# sml-signal

[![CI](https://github.com/sjqtentacles/sml-signal/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-signal/actions/workflows/ci.yml)

A tiny, pure **functional-reactive-programming (FRP)** core in Standard ML:
time-varying **signals** and discrete **event** streams with `map` / `combine` /
`filter` / `foldp`, plus a deterministic trace runner.

Reactive systems are usually riddled with clocks, callbacks, and shared mutable
state — none of which survive a byte-identical dual-compiler guarantee. This
library keeps the whole model **pure and deterministic**: there is no clock, no
threads, and no I/O anywhere. Time and external occurrences are *injected* by
the caller (you pass `sampleAt`'s instant and `fromList`'s timestamps), so the
same program produces the same trace on **MLton** and **Poly/ML**, every run.

It is the reactive-state foundation for the pure-SML GUI stack (`sml-ui`,
`sml-tea`): widget state is a `foldp` over an input-event stream.

- A **`'a signal`** is a value defined at every instant `t : real`. Sample it
  with `sampleAt`; signals also remember the instants ("breaks") where they may
  change, so a whole run can be traced with `runUntil`.
- An **`'a event`** is a finite, explicitly time-stamped list of occurrences,
  kept sorted by time with a documented stable tie-break.

No dependencies, no FFI, no clock — same inputs in, same trace out.

## API

```sml
structure Signal : sig
  type 'a signal                          (* a time-varying value *)
  type 'a event                           (* discrete occurrences  *)

  (* signals *)
  val const    : 'a -> 'a signal
  val map      : ('a -> 'b) -> 'a signal -> 'b signal
  val combine  : ('a * 'b -> 'c) -> 'a signal -> 'b signal -> 'c signal
  val sampleAt : 'a signal -> real -> 'a
  val breaks   : 'a signal -> real list

  (* events *)
  val never       : 'a event
  val mapE        : ('a -> 'b) -> 'a event -> 'b event
  val filterE     : ('a -> bool) -> 'a event -> 'a event
  val merge       : 'a event * 'a event -> 'a event   (* sorted; left wins ties *)
  val countE      : 'a event -> int
  val occurrences : 'a event -> (real * 'a) list
  val foldp       : ('a * 's -> 's) -> 's -> 'a event -> 's signal
  val fromList    : (real * 'a) list -> 'a event      (* stable sort by time *)
  val runUntil    : real -> 's signal -> 's list      (* deterministic trace *)
end
```

### Determinism rules

- **Time is injected, never sampled.** `sampleAt s t` and `fromList [(t, x), …]`
  take their instants from you; there is no `now ()`.
- **Stable, documented ordering.** `fromList` and `merge` sort by time; when two
  occurrences share a timestamp the earlier one (within a stream, and the left
  stream in `merge`) comes first.
- **`runUntil` traces a step function**: the value at instant `0.0` followed by
  the value at each break point `<= tMax`, in time order — identical bytes on
  both compilers.

### Example

```sml
open Signal

(* mouse clicks at t = 1, 2, 3 (injected timestamps) *)
val clicks  = fromList [(1.0, ()), (2.0, ()), (3.0, ())]

(* fold them into a running count: the classic FRP counter *)
val counter = foldp (fn ((), n) => n + 1) 0 clicks

val 0 = sampleAt counter 0.0        (* before any click *)
val 2 = sampleAt counter 2.5        (* after the 2nd click *)
val [0, 1, 2, 3] = runUntil 5.0 counter   (* the whole trace *)

(* signals compose pointwise *)
val doubled = map (fn n => n * 2) counter
val [0, 2, 4, 6] = runUntil 5.0 doubled
```

Running [`examples/demo.sml`](examples/demo.sml) with `make example` writes
[`assets/trace.txt`](assets/trace.txt) (byte-identical on both compilers):

```
sml-signal demo - click-counter trace

t=0.0   count=0     doubled=0
t=1.0   count=1     doubled=2
t=2.0   count=2     doubled=4
t=3.0   count=3     doubled=6
t=5.0   count=4     doubled=8
```

## Build & test

Requires [MLton](http://mlton.org/) and/or [Poly/ML](https://polyml.org/).

```sh
make test        # build + run the suite under MLton
make test-poly   # run the suite under Poly/ML
make all-tests   # both
make example     # build + run the demo (writes assets/trace.txt)
make clean
```

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-signal
smlpkg sync
```

Reference `lib/github.com/sjqtentacles/sml-signal/signal.mlb` from your own
`.mlb` (MLton / MLKit), or feed `sources.mlb` to `tools/polybuild` (Poly/ML).

## Layout

```
sml.pkg                                       smlpkg manifest
Makefile                                      MLton + Poly/ML targets
.github/workflows/ci.yml                      CI: MLton + Poly/ML (Variant A)
lib/github.com/sjqtentacles/sml-signal/
  signal.sig     SIGNAL signature
  signal.sml     pure FRP implementation
  sources.mlb    ordered source list
  signal.mlb     public basis
examples/
  demo.sml       click-counter trace -> assets/trace.txt
test/
  harness.sml    shared assertion harness
  test.sml       signal/event/foldp/runUntil vectors (23 checks)
  entry.sml / main.sml
tools/polybuild  Poly/ML build wrapper
```

## Tests

23 deterministic checks: `const`/`map`/`combine`/`sampleAt`; `fromList` stable
time-sorting (including equal-time ties); `mapE`/`filterE`; `merge` ordering
with the left-wins-ties rule; the `foldp` click counter (`[0,1,2,3]`), running
totals, mapped and combined `foldp` signals, and `runUntil` traces bounded by
`tMax`. Run `make all-tests` to verify identical output under both compilers.

## License

MIT. See [LICENSE](LICENSE).
