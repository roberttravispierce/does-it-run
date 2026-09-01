# frozen_string_literal: true

require "yaml"

module DoesItRun
  # The documented setup steps for a project, as data.
  #
  # A recipe is either written by hand or extracted from a README. Extraction is
  # the interesting path: it means DoesItRun runs what the project actually
  # tells people to run, not a curated version of it.
  class Recipe
    Step = Data.define(:command, :source_line) do
      def to_s = command
    end

    attr_reader :name, :repo, :steps, :template

    def initialize(name:, steps:, repo: nil, template: "base")
      @name     = name
      @repo     = repo
      @steps    = steps
      @template = template
    end

    def self.from_yaml(path)
      data = YAML.load_file(path)
      new(
        name: data.fetch("name"),
        repo: data["repo"],
        template: data.fetch("template", "base"),
        steps: Array(data.fetch("steps")).map { |c| Step.new(command: c, source_line: nil) }
      )
    end

    # Pull runnable commands out of fenced shell blocks in a README.
    #
    # This is deliberately conservative. A README code block is prose as much as
    # it is a program: it contains output, placeholders, and comments, and
    # running those verbatim produces noise that looks like findings. Anything
    # ambiguous is dropped rather than guessed at, because a false failure costs
    # more credibility than a missed step.
    SHELL_FENCE = /^```(?:bash|sh|shell|console|zsh)\s*$/i
    FENCE_END   = /^```\s*$/

    # Lines that appear inside shell blocks but are not commands to run.
    NOT_A_COMMAND = [
      /\A\s*#/,                    # comment
      /\A\s*\z/,                   # blank
      /\A[^$\s]*\s*(=>|\.\.\.)/,   # illustrative output
      /\A(?:Done|OK|Success|Error|Traceback|warning:)/i
    ].freeze

    # Placeholders a human is expected to substitute. Running these verbatim
    # fails for reasons that say nothing about the project.
    PLACEHOLDER = /<[a-z0-9_ -]+>|YOUR_[A-Z_]+|xxxx|\.\.\.|\bslr_live_\.\.\./i

    def self.from_readme(markdown, name:, repo: nil)
      steps = []
      in_block = false

      markdown.each_line.with_index(1) do |line, number|
        stripped = line.chomp

        if !in_block && stripped.match?(SHELL_FENCE)
          in_block = true
          next
        elsif in_block && stripped.match?(FENCE_END)
          in_block = false
          next
        end
        next unless in_block

        command = stripped.sub(/\A\s*[$#>]\s+/, "").strip   # strip prompt markers
        next if NOT_A_COMMAND.any? { |re| command.match?(re) }
        next if command.match?(PLACEHOLDER)

        steps << Step.new(command: command, source_line: number)
      end

      new(name: name, repo: repo, steps: steps)
    end

    def empty? = steps.empty?
  end
end
