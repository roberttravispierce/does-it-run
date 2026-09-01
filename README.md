# Coldstart

**Does your quickstart actually work?**

Setup instructions rot quietly. They are written once, on a machine that already
has the dependencies, and then they are never run cold again. The gap between
"the README says" and "a new user gets" is invisible to the person who wrote it
and obvious to everyone else — once, briefly, before they close the tab.

Coldstart executes documented setup steps **verbatim on a clean machine** and
reports exactly where a new user gets stuck, with evidence.

It is built on [Solari](https://getsolari.com), which is what makes the clean
machine affordable: a microVM boots from a snapshot in about a second, so every
attempt can start from nothing instead of from the residue of the last one.

## How it uses the three primitives

Each one does work the others cannot:

| Primitive | Job | Why it has to be this one |
| --- | --- | --- |
| **Browser** | Read the docs as published | Docs sites are JS-rendered and drift from the repo README. The discrepancy between the two is itself a finding. |
| **Sandbox** | Execute the steps verbatim | A fresh VM per attempt. "Works on my machine" stays invisible until the machine is clean. |
| **Desktop** | Steps a shell cannot do | GUI installers, native file dialogs, and visual confirmation that what the docs promise the user will *see* actually appears. |

## Status

Under construction, in the open.

- [x] Ruby client for the Solari REST API
- [ ] Recipe format — the documented steps, as data
- [ ] Runner — clean-room execution with per-step evidence
- [ ] Dashboard — live run progress and results

## The Ruby client

Solari ships SDKs for TypeScript, Python, Go, Rust, and C++. There is no Ruby
one, and Coldstart is written in Ruby, so `lib/solari/` is a small client over
the documented HTTP API.

It has **no dependencies** — `net/http` and `json` from the standard library are
the entire requirement, so adding it cannot disturb anyone's bundle.

```ruby
require "solari"

Solari.sandbox(cpu: 1, mem_mb: 1024) do |sandbox|
  sandbox.exec("echo", "argv form works")   #=> #<Result exit_code=0 ...>
  sandbox.sh("ls -la / | head -3")          #=> shell line, pipes intact
end
# VM released here, including if the block raised
```

Run the worked example against the real API:

```bash
export SOLARI_API_KEY=slr_live_...    # or put it in .env
ruby -Ilib examples/sandbox_lifecycle.rb
```

## Design notes

Three decisions that came from getting it wrong first.

**The block form is the primary interface.** The first sandbox this project ever
created was leaked — an exception between create and kill skipped the cleanup,
and the VM billed until its idle timeout. `Solari.sandbox { ... }` releases in an
`ensure`, which makes that failure unreachable rather than merely discouraged.
`#kill` is idempotent and treats a 404 as success, so the `ensure` can never
itself raise.

**`timeout_ms` defaults to 120s, not something generous.** It is a rolling idle
window that resets on every use, so it is not a deadline on useful work — it is
the backstop that bounds the cost of a leak. Short is the safe default.

**Commands are not shell-interpreted.** `exec("ls -la")` looks for a binary
literally named `ls -la` and fails. `examples/sandbox_lifecycle.rb` asserts this
on purpose rather than describing it, and `#sh` exists for anything wanting
pipes, globs, or redirection.

Key-shaped strings are scrubbed at the transport boundary, because error
responses habitually echo the request that caused them.

## License

MIT.
