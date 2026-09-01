#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Sandbox lifecycle, end to end: create, run a command, round-trip a file,
# release. Self-contained — run it directly.
#
#   export SOLARI_API_KEY=slr_live_...   # or put it in .env
#   ruby -Ilib examples/sandbox_lifecycle.rb
#
# Every assertion below runs against the real API. Nothing is stubbed.

require "solari"

# Load .env if present. The library itself reads ENV and has no dependencies;
# only the examples care where the key came from.
if File.exist?(".env")
  File.readlines(".env").each do |line|
    key, value = line.strip.split("=", 2)
    ENV[key] ||= value if key && value && !key.start_with?("#")
  end
end

started = Time.now

Solari.sandbox(cpu: 1, mem_mb: 1024, timeout_ms: 120_000,
               metadata: { project: "does-it-run", example: "sandbox_lifecycle" }) do |sandbox|
  puts "created   #{sandbox.kind} in #{(Time.now - started).round(2)}s"

  result = sandbox.exec("echo", "argv form works")
  puts "exec      exit=#{result.exit_code} stdout=#{result.stdout.strip.inspect}"

  # Commands are NOT shell-interpreted. This looks for a binary literally named
  # "ls -la" and fails. It is here as an executable reminder, not an accident.
  trap = sandbox.exec("ls -la")
  puts "not a shell  exit=#{trap.exit_code} (expected non-zero)"

  # ...so anything needing pipes, globs, or redirection goes through #sh.
  listing = sandbox.sh("ls -la / | head -3")
  puts "sh        exit=#{listing.exit_code} lines=#{listing.stdout.lines.size}"

  sandbox.sh("mkdir -p /tmp/does-it-run && printf 'written-in-vm' > /tmp/does-it-run/proof.txt")
  echoed = sandbox.sh("cat /tmp/does-it-run/proof.txt")
  puts "file      round-trip=#{echoed.stdout.inspect}"

  puts "guest os  #{sandbox.sh('. /etc/os-release; echo $PRETTY_NAME').stdout.strip}"
end

# The block form released the VM on the way out, including if the block raised.
puts "released  total #{(Time.now - started).round(2)}s"

remaining = Solari::Client.new.get("/sandboxes").fetch("sandboxes", []).size
puts "live sandboxes now: #{remaining}"
