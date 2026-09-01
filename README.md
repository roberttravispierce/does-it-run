# Does It Run

[![Does It Run](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Froberttravispierce%2Fdoes-it-run%2Fdoes-it-run%2Fbadge.json)](https://github.com/roberttravispierce/does-it-run/actions/workflows/does-it-run.yml)

**Your quickstart worked the day you wrote it. Does it still work today?**

Setup instructions rot silently. They are written once, on a machine that already
has the dependencies, and then they are never run cold again. The dependency that
was globally installed, the step that assumed a directory, the version that moved
on — none of it shows up for the author, and all of it shows up for the next
person, once, briefly, before they close the tab.

Does It Run executes **your own README's quickstart on a clean machine** on every
push, and gives you a badge that says whether it still works.

```markdown
![Does It Run](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/OWNER/REPO/does-it-run/badge.json)
```

## Use it on your repo

Add the workflow:

```yaml
# .github/workflows/does-it-run.yml
name: Does It Run
on:
  push:
    branches: [main]
  schedule:
    - cron: "0 12 * * 1"

permissions:
  contents: write

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: roberttravispierce/does-it-run@main
        with:
          solari-api-key: ${{ secrets.SOLARI_API_KEY }}
```

Then put the badge in your README, replacing `OWNER/REPO`:

```markdown
![Does It Run](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/OWNER/REPO/does-it-run/badge.json)
```

The badge is published to a branch of your own repo, so nothing is hosted
anywhere and no account is needed beyond a Solari key.

### If your project needs a toolchain

A bare machine has `git`, `curl`, `python3`, `node`, `npm`, `make` and `gcc` —
and nothing else. Declare what yours needs in `.does-it-run.yml`:

```yaml
setup:
  - apt-get update -qq
  - apt-get install -y ruby
```

Setup runs before the graded steps and is excluded from the verdict. "This
machine had no compiler" is a fact about the machine; "your README never said
you need one" is a finding.

### If your quickstart needs a key

Pass it through, or every run reports `blocked`:

```yaml
with:
  solari-api-key: ${{ secrets.SOLARI_API_KEY }}
  env: |
    MY_API_KEY=${{ secrets.MY_API_KEY }}
```

## Why it also runs on a schedule

Quickstarts rot from the outside in. A dependency ships a breaking release, a
package is renamed, an install script changes upstream — and nothing in your
repository changed. A push-triggered check would never notice. The weekly run
is what catches the world moving underneath you.

## Why a clean machine

Because that is the only place the answer is honest. CI images accumulate
toolchains, your laptop has everything already, and both will happily run a
quickstart that a new user cannot. Every check here starts from a bare Debian
microVM that has nothing on it and ceases to exist afterward.

That is affordable because of [Solari](https://getsolari.com): a VM restores from
a memory snapshot in about a second, so a fresh machine per run costs a fraction
of a cent instead of a build queue.

## How it works

1. **Read the README** — pull the shell commands out of the fenced blocks, the
   ones a new user would actually paste.
2. **Boot a clean machine** — bare Debian 12, nothing installed.
3. **Run the steps in order** — with the working directory carried across them,
   because each command is its own process and a documented `cd` would otherwise
   be silently discarded.
4. **Classify each step** — passed, failed, or blocked on something the docs
   never mentioned.
5. **Write the badge.**

## Three outcomes, not two

The difference between "broken" and "needs an API key" is the whole credibility
of the tool. A step that fails because it wants a credential is a **prerequisite
your docs did not state** — a real finding, and a different one from a command
that does not work. Reporting the first as the second makes the tool wrong about
projects that are fine, and nobody reads it twice.

| Result | Meaning |
| --- | --- |
| **passed** | The command ran and exited zero on a machine with nothing on it. |
| **failed** | It ran and did not work. This is the finding. |
| **blocked** | It needs a key, a prompt, or something unstated. Also a finding. |

A failing step halts the run, because everything after it was written assuming
it succeeded.

## Status

Built in the open, and honest about where it is:

- [x] Ruby client for the Solari API — no dependencies, stdlib only
- [x] README step extraction
- [x] Clean-room runner with working-directory continuity and three-way classification
- [x] GitHub Action and badge output
- [ ] Verified against real repositories

## The Ruby client

Solari ships SDKs for TypeScript, Python, Go, Rust and C++. There is no Ruby one,
so `lib/solari/` is a small client over the documented HTTP API, with **no gem
dependencies** — `net/http` and `json` are the entire requirement.

```ruby
require "solari"

Solari.sandbox(cpu: 1, mem_mb: 1024) do |sandbox|
  sandbox.exec("echo", "argv form works")   # argv, not a shell line
  sandbox.sh("ls -la / | head -3")          # shell when you want one
end
# VM released here, including if the block raised
```

Run it against the real API:

```bash
export SOLARI_API_KEY=slr_live_...    # or put it in .env
ruby -Ilib examples/sandbox_lifecycle.rb
```

## Design notes

Three decisions that came from getting it wrong first.

**The block form is the primary interface.** The first sandbox this project ever
created was leaked — an exception between create and kill skipped the cleanup and
the VM billed until its idle timeout. `Solari.sandbox { ... }` releases in an
`ensure`, which makes that failure unreachable rather than discouraged. `#kill` is
idempotent and treats a 404 as success, so the `ensure` can never itself raise.

**`timeout_ms` defaults to 120s, not something generous.** It is a rolling idle
window that resets on use, so it is not a deadline on real work — it is the
backstop that bounds the cost of a leak.

**Commands are not shell-interpreted.** `exec("ls -la")` looks for a binary named
`ls -la` and fails. `examples/sandbox_lifecycle.rb` asserts that on purpose rather
than describing it, and `#sh` exists for anything wanting pipes or redirection.

Key-shaped strings are scrubbed at the transport boundary, because error responses
habitually echo the request that caused them.

## License

MIT.
