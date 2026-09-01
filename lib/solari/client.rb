# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

require_relative "errors"

module Solari
  # Thin HTTP client over the Solari REST API.
  #
  # Deliberately dependency-free: the whole surface this needs is Net::HTTP and
  # JSON from the standard library, so installing the gem cannot break anyone's
  # bundle.
  class Client
    DEFAULT_BASE_URL = "https://api.getsolari.com"

    # Anything shaped like a key is scrubbed before it can reach a log, an
    # exception message, or a terminal. Error responses habitually echo the
    # offending request, so the redaction lives at the transport boundary
    # rather than at each call site.
    KEY_PATTERN = /slr_[a-z]+_[A-Za-z0-9._\-]+/

    attr_reader :base_url

    def initialize(api_key: ENV["SOLARI_API_KEY"], base_url: DEFAULT_BASE_URL)
      raise ConfigurationError, "no API key: set SOLARI_API_KEY" if api_key.nil? || api_key.empty?

      @api_key  = api_key
      @base_url = base_url
    end

    def get(path)    = request(Net::HTTP::Get, path)
    def delete(path) = request(Net::HTTP::Delete, path)
    def post(path, body = nil) = request(Net::HTTP::Post, path, body)

    # Scrub a string of anything key-shaped. Public because callers that build
    # their own log lines need the same guarantee.
    def self.redact(text) = text.to_s.gsub(KEY_PATTERN, "slr_***")

    private

    def request(klass, path, body = nil)
      uri = URI("#{@base_url}#{path}")
      req = klass.new(uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Accept"]        = "application/json"

      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                            open_timeout: 20, read_timeout: 120) { |http| http.request(req) }

      parse(res)
    end

    def parse(res)
      status = res.code.to_i
      raw    = self.class.redact(res.body)
      data   = raw.empty? ? {} : (JSON.parse(raw) rescue { "raw" => raw })

      raise APIError.new(status, raw[0, 500]) unless status.between?(200, 299)

      data
    end
  end
end
