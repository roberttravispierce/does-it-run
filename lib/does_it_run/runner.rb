# frozen_string_literal: true

require "solari"
require_relative "recipe"
require_relative "report"

module DoesItRun
  # Executes a recipe on a clean machine, one step at a time.
  SetupError = Class.new(StandardError)

  class Runner
    CWD_MARKER = "__DOES_IT_RUN_CWD__"
    START_DIR  = "/root/work"

    # Signals that a step failed for want of a credential or a human, rather
    # than because the project is broken. Reporting these as failures would be
    # both wrong and the fastest way to lose a reader's trust.
# A command the machine does not have is a prerequisite the docs did not
# state — not a broken instruction. Reporting "python: not found" as a
# FAILURE against a widely-used project makes the tool look wrong even when
# it is literally correct, and one wrong-looking verdict costs more trust
# than a dozen right ones earn.
MISSING_TOOL = /(?:^|\W)([\w.\/-]+): (?:not found|command not found)|command not found: (\S+)/

BLOCKED_PATTERNS = [
      /\bAPI[_ ]?KEY\b.*(?:not set|missing|required|unset)/i,
      /(?:authentication|authorization|credentials?|unauthorized|permission denied \(publickey\))/i,
      /\b(?:401|403)\b.*(?:unauthorized|forbidden)/i,
      /please (?:log ?in|authenticate|provide)/i,
      /environment variable .* (?:is )?(?:not set|required)/i
    ].freeze

    def initialize(recipe, client: Solari::Client.new, cpu: 1, mem_mb: 2048, step_timeout_ms: 300_000, envs: {}, setup: [])
      @recipe   = recipe
      @client   = client
      @cpu      = cpu
      @mem_mb   = mem_mb
      @timeout  = step_timeout_ms
      @envs     = envs
      @setup    = setup
    end

    def run
      results = []
      started = Time.now
      cwd     = START_DIR

      Solari::Sandbox.open(client: @client, cpu: @cpu, mem_mb: @mem_mb, timeout_ms: @timeout, envs: @envs,
                           metadata: { project: "does-it-run", recipe: @recipe.name }) do |sandbox|
        sandbox.sh("mkdir -p #{START_DIR}")

        @setup.each do |command|
          result = sandbox.sh("cd #{shell_quote(START_DIR)} && #{command}")
          raise SetupError, "setup failed: #{command}\n#{result.stderr.strip[0, 300]}" unless result.exit_code.zero?
        end

        @recipe.steps.each_with_index do |step, index|
          if halted?(results)
            results << Report::StepResult.new(step: step, index: index, status: :skipped,
                                              exit_code: nil, stdout: "", stderr: "", seconds: 0.0)
            next
          end

          t0 = Time.now
          raw = sandbox.sh(wrap(step.command, cwd))
          seconds = (Time.now - t0).round(2)

          stdout, cwd = extract_cwd(raw.stdout, cwd)
          results << Report::StepResult.new(
            step: step, index: index, status: classify(raw.exit_code, stdout, raw.stderr),
            exit_code: raw.exit_code, stdout: stdout, stderr: raw.stderr, seconds: seconds
          )
        end
      end

      Report.new(recipe: @recipe, results: results, seconds: (Time.now - started).round(2))
    end

    private

    # Each exec is a separate process, so `cd` does not persist between steps.
    # A README that says `cd project` and then `make` on the next line would
    # otherwise fail for a reason the project is not responsible for. The marker
    # reports where the command left the shell, preserving the real exit code.
    def wrap(command, cwd)
      <<~SH
        cd #{shell_quote(cwd)} 2>/dev/null || cd #{shell_quote(START_DIR)}
        #{command}
        __cs_rc=$?
        printf '\\n#{CWD_MARKER}%s' "$(pwd)"
        exit $__cs_rc
      SH
    end

    def shell_quote(str) = "'#{str.gsub("'", %q{'\\''})}'"

    def extract_cwd(stdout, fallback)
      if (m = stdout.match(/\n?#{Regexp.escape(CWD_MARKER)}(.*)\z/m))
        [stdout[0...m.begin(0)], m[1].strip.empty? ? fallback : m[1].strip]
      else
        [stdout, fallback]
      end
    end

    def classify(exit_code, stdout, stderr)
      return :ok if exit_code.zero?

      text = "#{stdout}\n#{stderr}"
      return :blocked if text.match?(MISSING_TOOL)

      BLOCKED_PATTERNS.any? { |re| text.match?(re) } ? :blocked : :failed
    end

    # A failed step invalidates everything after it: the rest of the quickstart
    # was written assuming it succeeded. Blocked steps stop the run for the same
    # reason, but are reported as a prerequisite rather than a defect.
    def halted?(results) = results.any? { |r| %i[failed blocked].include?(r.status) }
  end
end
