# frozen_string_literal: true

module DoesItRun
  # The evidence trail from one run.
  class Report
    StepResult = Data.define(:step, :index, :status, :exit_code, :stdout, :stderr, :seconds) do
      def ok?      = status == :ok
      def failed?  = status == :failed
      def blocked? = status == :blocked
      def skipped? = status == :skipped

      def excerpt(limit = 400)
        text = stderr.to_s.strip.empty? ? stdout.to_s : stderr.to_s
        text.strip[0, limit]
      end
    end

    attr_reader :recipe, :results, :seconds

    def initialize(recipe:, results:, seconds:)
      @recipe  = recipe
      @results = results
      @seconds = seconds
    end

    def passed?      = results.none? { |r| r.failed? || r.blocked? }
    def failure      = results.find(&:failed?)
    def blocker      = results.find(&:blocked?)
    def counts       = results.group_by(&:status).transform_values(&:size)

    # Three outcomes, not two. "Blocked" exists because a step that needs an API
    # key is a prerequisite the docs failed to mention, not a broken project —
    # and reporting it as a failure is the fastest way to make the whole report
    # untrustworthy.
    def verdict
      return :passed  if passed?
      return :failed  if failure
      :blocked
    end

    def to_markdown
      lines = ["## #{recipe.name}", ""]
      lines << case verdict
               when :passed  then "**Quickstart works.** #{results.size} steps, #{seconds}s on a clean machine."
               when :failed  then "**Fails at step #{failure.index + 1} of #{results.size}.**"
               else               "**Blocked at step #{blocker.index + 1} of #{results.size}** — needs something the docs do not supply."
               end
      lines << ""

      results.each do |r|
        mark = { ok: "PASS", failed: "FAIL", blocked: "BLOCKED", skipped: "skipped" }.fetch(r.status)
        lines << "- `#{r.step.command}` — **#{mark}**#{r.ok? ? " (#{r.seconds}s)" : ""}"
        lines << "  ```\n  #{r.excerpt.lines.first(6).join("  ").rstrip}\n  ```" if r.failed? || r.blocked?
      end

      lines.join("\n")
    end
  end
end
