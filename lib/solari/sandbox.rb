# frozen_string_literal: true

require_relative "client"

module Solari
  # A running microVM.
  #
  # Prefer the block form. A sandbox that is created and not released keeps
  # billing until its idle timeout expires, and the easiest way to leak one is
  # an exception between create and kill:
  #
  #   Solari::Sandbox.open(cpu: 1) do |sbx|
  #     sbx.sh("apt-get install -y ripgrep")
  #   end   # killed even if the block raises
  #
  class Sandbox
    # Result of one command. `success?` reads better than `exit_code.zero?` at
    # the call sites that matter.
    Result = Struct.new(:exit_code, :stdout, :stderr, keyword_init: true) do
      def success? = exit_code.zero?
      def output   = (stdout.to_s + stderr.to_s)
    end

    attr_reader :id, :kind, :control_url, :expires_at

    # Create a sandbox and guarantee it is released.
    def self.open(client: Client.new, **opts)
      sandbox = create(client: client, **opts)
      begin
        yield sandbox
      ensure
        sandbox.kill
      end
    end

    # `timeout_ms` is a ROLLING IDLE WINDOW, not a hard deadline: every use
    # resets it. It is the backstop that bounds the cost of a leak, so it
    # defaults to something short rather than something generous.
    def self.create(client: Client.new, kind: "sandbox", cpu: 1, mem_mb: 1024,
                    timeout_ms: 120_000, template: nil, envs: nil, metadata: nil)
      body = { kind: kind, cpu: cpu, memMb: mem_mb, timeoutMs: timeout_ms }
      body[:template] = template if template
      body[:envs]     = envs     if envs
      body[:metadata] = metadata if metadata

      new(client, client.post("/sandboxes", body))
    end

    def initialize(client, attrs)
      @client      = client
      @attrs       = attrs
      @id          = attrs.fetch("sandboxId")
      @kind        = attrs["kind"]
      @control_url = attrs["controlUrl"]
      @expires_at  = attrs["expiresAt"]
      @killed      = false
    end

    # Run one binary with an argv array.
    #
    # NOT shell-interpreted: `exec("ls -la")` looks for a binary literally named
    # "ls -la" and fails. Pass argv separately, or use #sh for a shell line.
    def exec(cmd, *args)
      data = @client.post("/sandboxes/#{encoded_id}/exec", { cmd: cmd, args: args.flatten.map(&:to_s) })
      Result.new(exit_code: data["exitCode"].to_i, stdout: data["stdout"].to_s, stderr: data["stderr"].to_s)
    end

    # Run a shell line, with pipes, globs, and redirection intact.
    def sh(script) = exec("/bin/sh", "-c", script)

    # Ends the VM. `kill` is the real teardown: dropping a local control channel
    # leaves the machine running until its idle timeout. Idempotent, so the
    # ensure block in .open is always safe.
    def kill
      return true if @killed

      @client.delete("/sandboxes/#{encoded_id}")
      @killed = true
    rescue APIError => e
      # A VM that already expired is not a failure to clean up.
      raise unless e.status == 404

      @killed = true
    end

    def killed? = @killed

    private

    def encoded_id = URI.encode_www_form_component(@id)
  end
end
