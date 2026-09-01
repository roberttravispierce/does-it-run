# frozen_string_literal: true

module Solari
  Error = Class.new(StandardError)

  # Raised when the API answers with a non-2xx status. Carries the status and
  # the (redacted) body so callers can branch on it without re-parsing.
  class APIError < Error
    attr_reader :status, :body

    def initialize(status, body)
      @status = status
      @body   = body
      super("Solari API returned #{status}: #{body}")
    end
  end

  ConfigurationError = Class.new(Error)
end
