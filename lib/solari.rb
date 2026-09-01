# frozen_string_literal: true

require_relative "solari/errors"
require_relative "solari/client"
require_relative "solari/sandbox"

# A small Ruby client for Solari — cloud browsers, sandboxes, and desktops
# behind one API key.
#
# Solari ships SDKs for TypeScript, Python, Go, Rust, and C++. This one exists
# because Coldstart is written in Ruby.
module Solari
  VERSION = "0.1.0"

  # Convenience wrapper: Solari.sandbox { |sbx| ... }
  def self.sandbox(**opts, &block) = Sandbox.open(**opts, &block)
end
