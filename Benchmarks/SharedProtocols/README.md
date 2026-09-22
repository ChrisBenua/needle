# Shared-protocols benchmark

10 000 `shared` properties on one component, each typed as its own protocol, read
three times. This is the benchmark behind the `SharedInstance` box in
`Component.shared` — it is the shape where upstream Needle's cached-instance cast
is at its worst.

```sh
cd Benchmarks/SharedProtocols
./run.sh                     # build both, 5 samples of each, table + threshold checks
./run.sh --samples 20
./run.sh --no-check          # print the table without failing on the thresholds
NEEDLE_SOURCE=fork swift run -c release --scratch-path .build-fork BenchNeedle
```

## Results

Apple M2 Max, macOS 26 (Darwin 25.5), Swift 6.3.2, release build, best of 5 fresh
processes per phase:

| phase | upstream 0.25.1 | this fork | |
|---|---|---|---|
| pass #1 (construct) | 3.95 µs | 3.67 µs | — |
| pass #2 (hit, cold cache) | 305.69 µs | 0.27 µs | **1138× faster** |
| pass #3 (hit, warm cache) | 0.51 µs | 0.24 µs | 2.1× faster |

Totals for the whole 10 000-property pass: upstream **3.06 s** on pass #2, the
fork **2.7 ms**.

**Pass #2 is the number this benchmark exists for.** It is 10 000 cache hits,
measured in a freshly launched process. Upstream reads the cache back with
`sharedInstances[__function] as? T?`; with `T` a protocol, the Swift runtime has
to produce a witness table for the stored value, and until its conformance cache
is warm that means scanning the conformance records of a binary containing 10 000
protocols. The fork casts to `SharedInstance<T>` instead — a check against one
concrete class — so it never consults the conformance tables at all, and the cost
does not depend on how many protocols the binary defines.

**Pass #3 is the same work with the runtime's conformance cache warm.** Upstream
recovers to 0.51 µs, which is why this is invisible in a microbenchmark that
resolves the same type twice. The realistic case is an app launch: every
dependency on the startup path is read for the first time, in a binary full of
protocols, exactly once.

**Pass #1 constructs the instances** and is a cache *miss* on both sides, so it
mostly measures the factory closures. The two are within noise of each other; the
fork's extra box allocation per property does not show above it.

## Why `T` is the protocol

Every generated property has a **two-statement** closure:

```swift
public var dep0: Protocol0 {
    shared {
        let instance = Class0()
        return instance
    }
}
```

That shape is load-bearing. With a single-expression closure, `shared { Class0() }`,
the type checker binds `T` to `Class0` and the cached cast is a cheap concrete-class
cast — no protocol involved. With two statements, `T` comes from the property's
type. Confirmed in SILGen: the two-statement form emits `apply %11<any P0>`, the
single-expression form `apply %11<C0>`.

Note also that the protocols here are **not** `AnyObject`-constrained, and that
matters. With `: AnyObject` the stored existential is a class existential and the
cast back hits a fast path — pass #2 measured 0.36 µs/call on *upstream*, i.e. no
effect to optimise at all. Plain (opaque) protocols are the case that pays.

## Why two builds of the same sources

`run.sh` builds the benchmark twice, against two different NeedleFoundations, picked
by the `NEEDLE_SOURCE` environment variable that `Package.swift` reads:

- `upstream` — `uber/needle` 0.25.1 from GitHub
- `fork` — this repository, via `.package(path: "../..")`

Each mode gets its own `--scratch-path` (`.build-upstream` / `.build-fork`) so both
stay cached and a re-run takes seconds. The two modes share one `Package.resolved`,
which SwiftPM rewrites on each switch; that is harmless, but **deleting it between
modes forces a full ~15-minute rebuild**, so `run.sh` does not.

`run.sh` also spawns a **fresh process per sample**. Pass #2 is measured against a
cold conformance cache; running it twice in one process gives a warm one the second
time and erases the effect. Do not turn the sampling into an in-process loop.

## Build times

The first build of each mode takes ~15 minutes: 10 000 `Codable` classes plus 10 000
`shared` properties is a lot of code. `BenchModels` is compiled `-Onone
-no-whole-module-optimization` even under `-c release` — optimising 10 000 classes
costs many minutes and buys nothing, since what this benchmark needs from that module
is its conformance records, which are identical at any optimisation level. The DI
library and `BenchNeedle` (the code whose speed is being measured) are built release
as usual.

## Layout

```
Package.swift                    NEEDLE_SOURCE picks upstream or fork
run.sh                           build both, sample, compare, check thresholds
Tools/generate-bench-sources.py  regenerates everything under Sources/*/Generated
Sources/
  BenchModels/Generated/         Protocol0…Protocol9999, Class0…Class9999
  BenchNeedle/main.swift         the three passes + identity assertions
  BenchNeedle/Generated/         BenchComponent, its shared properties, accessAll
```

Everything under a `Generated/` directory is script output — **never edit it by
hand**. To change the scale:

```sh
python3 Tools/generate-bench-sources.py --types 50000
```

Re-running the script with no arguments must leave the working tree clean; that is
the check that the committed sources match the generator.
