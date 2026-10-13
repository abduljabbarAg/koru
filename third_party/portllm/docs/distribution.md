# Distribution and platform

Decisions and the reasoning behind them. Written down so the question does not
get re-litigated every few weeks, and so the reasons survive the person who had
them.

## Artifact shape

**One static binary per platform. No runtime, no dependencies.**

PortLLM builds to 350 KB with zero crates. A stripped release binary is the
entire install: no Python, no Node, no toolchain. That is the product. Every
distribution decision below has to preserve it, and any wrapper that adds a
runtime to ship it has made the product worse.

## CLI: yes, and first

The CLI is the primitive. Everything else is a way of invoking it.

```
portllm detect            what this machine is
portllm recommend         what to run here
portllm plan              where the bytes would live
portllm inspect f.gguf    what a model file contains
portllm run f.gguf        generate (not yet written)
```

GitHub Releases per platform tag. No package manager needed to try it, which
matters when the audience is people who do not know the project yet.

## A C ABI before any of the wrappers

The stable C header is the thing that makes both pip and npm possible without
touching the Rust. Build it early even though the CLI does not need it, because
it is expensive to add later and trivial to keep stable now.

It is also the thing the planned mobile app consumes, so it is not speculative:
two consumers, one interface.

## pip: yes, but late, and thin

A wrapper that resolves the platform, fetches the matching binary, and execs
it. No engine logic in Python. `llama-cpp-python` is the precedent and the
shape to copy.

It is a real surface though: wheels, platform tags, PyPI releases, a matrix
that breaks on new Python versions. Build it when someone asks, not before.
The audience that wants it is researchers who would otherwise compile, and
there are not many of them before there are.

## npm: no, for now

Node is the wrong runtime for this. The win is a 350 KB native binary; wrapping
it in a dependency tree inverts the value entirely.

The stronger argument is structural. npm versions *packages*. PortLLM's inputs
are a *model file* and a *hardware profile*, and npm has no opinion about
either. The nearest analogue in the market is Ollama, which ships a CLI and a
daemon and installs with a shell script rather than an npm package. That is
the market saying something.

If an npm surface is ever wanted, the honest shape is a thin FFI binding over
the C ABI for Electron apps. That is a v1 conversation with a real user in it,
not something to build speculatively.

## Desktop

**Yes, and mostly free — but not before the engine runs.**

What already generalises: core count, RAM, storage throughput, accelerator
reachability, the fit scorer, the placement policy, GGUF, the kernel.

What does not, and it is worth being specific:

| Probe                    | Desktop reality                                          |
| ------------------------ | -------------------------------------------------------- |
| `cpu_capacity` big.LITTLE| absent, reports homogeneous, usually correct               |
| storage throughput        | NVMe at 5-7 GB/s, so the **streaming tier becomes viable**, which never happens on a phone |
| unreachable-GPU branch   | real GPUs are reachable, so `ReachableGpu` activates with a placeholder bandwidth |
| total RAM                 | 32 GB; every model fits, so the recommender gets trivial   |
| thermal                   | phones throttle, desktops do not; a scheduler input disappears |

The genuinely valuable part is that a desktop GPU is how `Accel::ReachableGpu`
bandwidth finally gets *measured* instead of guessed. That placeholder is the
main honesty gap left in the placement policy.

### Keep one probe, add a platform tag

Make `Platform { Mobile, Desktop }` additive and keep the shape. Do not fork.
The autodetect code is the same code; only the sort key differs:

- **Mobile**: rank by *fit*. Memory is the binding constraint.
- **Desktop**: rank by *speed*. Fit is trivially satisfied, so ranking by it
  says nothing.

Same scorer, different key. That is the difference between an engine that runs
everywhere and one that thinks about what it is running on.

## Sequencing

1. Engine runs, on the phone. One token.
2. C ABI frozen.
3. Desktop probe, and measure the GPU bandwidth placeholder away.
4. pip wrapper when someone asks for it.
5. npm only if an Electron client appears with a user attached.