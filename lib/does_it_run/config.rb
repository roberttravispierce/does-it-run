# frozen_string_literal: true

require "yaml"

module DoesItRun
  # Optional per-project configuration: `.does-it-run.yml` in the repo root.
  #
  #   name: my-project
  #   setup:
  #     - apt-get update -qq
  #     - apt-get install -y ruby
  #
  # `setup` is the toolchain a clean machine needs before the README's own
  # instructions can mean anything — a Ruby project needs Ruby, a Rust project
  # needs cargo. It runs BEFORE the graded steps and is deliberately excluded
  # from the verdict: "this machine had no compiler" is a fact about the machine,
  # not a defect in the documentation.
  #
  # The line between the two matters. Anything a reader would reasonably expect
  # to already have belongs in setup. Anything the README tells them to do
  # belongs in the graded steps, where it can fail.
  class Config
    FILENAME = ".does-it-run.yml"

    attr_reader :name, :setup, :readme, :steps

    def initialize(name: nil, setup: [], readme: "README.md", steps: nil)
      @name   = name
      @setup  = Array(setup)
      @readme = readme
      @steps  = steps && Array(steps)
    end

# Fetch the config belonging to a remote repository.
#
# This exists because reading .does-it-run.yml from the working directory is
# right in CI, where the repo under test IS the checkout, and badly wrong
# when checking someone else's repo from a laptop: the local config silently
# applies to a project that never asked for it. Config belongs to the
# project being checked.
def self.fetch(clone_url)
  require "net/http"
  m = clone_url.to_s.match(%r{github\.com/([^/]+)/([^/.]+)})
  return new unless m

  uri = URI("https://raw.githubusercontent.com/#{m[1]}/#{m[2]}/HEAD/#{FILENAME}")
  res = Net::HTTP.get_response(uri)
  return new unless res.is_a?(Net::HTTPSuccess)

  data = YAML.safe_load(res.body) || {}
  new(name: data["name"], setup: data["setup"], readme: data.fetch("readme", "README.md"),
      steps: data["steps"])
rescue StandardError
  new
end

def self.load(dir = Dir.pwd)
      path = File.join(dir, FILENAME)
      return new unless File.exist?(path)

      data = YAML.load_file(path) || {}
      new(name: data["name"], setup: data["setup"], readme: data.fetch("readme", "README.md"),
          steps: data["steps"])
    end
  end
end
