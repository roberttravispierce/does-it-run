# frozen_string_literal: true

require "yaml"

module DoesItRun
  # The documented setup steps for a project, as data.
  #
  # A recipe is either written by hand or extracted from a README. Extraction is
  # the interesting path: it means Does It Run runs what the project actually
  # tells people to run, not a curated version of it.
  class Recipe
    Step = Struct.new(:command, :source_line, keyword_init: true) do
      def to_s = command
    end

    SHELL_FENCE = /^```(?:bash|sh|shell|console|zsh)\s*$/i
    FENCE_END   = /^```\s*$/
    HEADING     = /^\#{1,6}\s+(.*)$/

    # A README's shell blocks are not all setup steps. Most of a good README is
    # usage examples, and further down there is usually a contributing section
    # full of commands aimed at maintainers. Running those is not a check of the
    # quickstart — it is noise that produces findings nobody asked for.
    SETUP_HEADING = /\b(install|quick\s?start|getting started|setup|set up|running|run it|build)\b/i

    # Lines that appear inside shell blocks but are not commands to run.
    NOT_A_COMMAND = [
      /\A\s*#/,                    # comment
      /\A\s*\z/,                   # blank
      /\A[^$\s]*\s*(=>|\.\.\.)/,   # illustrative output
      /\A(?:Done|OK|Success|Error|Traceback|warning:)/i
    ].freeze

    # Placeholders a human is expected to substitute. Running these verbatim
    # fails for reasons that say nothing about the project.
    PLACEHOLDER = /<[a-z0-9_ -]+>|{[a-z0-9_ -]+}|YOUR_[A-Z_]+|xxxx|\.\.\./i

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

    # Pull runnable commands out of a README.
    #
    # Scoped to the sections a new user would follow. If scoping finds nothing —
    # a short README whose one code block sits under no recognisable heading —
    # it falls back to reading every block rather than reporting zero steps.
    def self.from_readme(markdown, name:, repo: nil, limit: 25)
      steps = scan(markdown, scoped: true)
      steps = scan(markdown, scoped: false) if steps.empty?

      # A quickstart is short by definition. Anything longer means extraction has
      # picked up a usage tour, and running 100 example invocations is both
      # expensive and meaningless — better to check the first steps and say so.
      truncated = steps.size > limit
      steps = steps.first(limit) if truncated

      recipe = new(name: name, repo: repo, steps: steps)
      recipe.instance_variable_set(:@truncated, truncated)
      recipe
    end

    def truncated? = !!@truncated
    def empty?     = steps.empty?

    # Deliberately conservative. A README code block is prose as much as it is a
    # program: it contains output, placeholders, and comments. Anything ambiguous
    # is dropped rather than guessed at, because a false failure costs more
    # credibility than a missed step.
    def self.scan(markdown, scoped:)
      steps    = []
      in_block = false
      in_scope = !scoped

      markdown.each_line.with_index(1) do |line, number|
        stripped = line.chomp

        if !in_block && (heading = stripped[HEADING, 1])
          in_scope = heading.match?(SETUP_HEADING) if scoped
          next
        end

        if !in_block && stripped.match?(SHELL_FENCE)
          in_block = true
          next
        elsif in_block && stripped.match?(FENCE_END)
          in_block = false
          next
        end

        next unless in_block && in_scope

        # Comment check BEFORE prompt stripping. `#` doubles as a root prompt and
        # as a comment marker, and stripping it first turns "# Install it
        # generally:" into a command. Comments vastly outnumber root prompts in
        # READMEs, so `#` is treated as a comment and only `$`/`>` are stripped.
        # The cost is missing a step written with a root prompt, which is the
        # safe direction to be wrong in.
        next if NOT_A_COMMAND.any? { |re| stripped.match?(re) }

        command = stripped.sub(/\A\s*[$>]\s+/, "").strip
        next if command.empty?
        next if command.match?(PLACEHOLDER)

        steps << Step.new(command: command, source_line: number)
      end

      steps
    end
    private_class_method :scan
  end
end
