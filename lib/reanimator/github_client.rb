# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Reanimator
  # A minimal GitHub REST client for the {Submitter}: JSON in, JSON out, and an
  # error for anything that is not a 2xx. It holds the only copy of the
  # submission token, and nothing else in Reanimator constructs one.
  class GitHubClient
    API = "https://api.github.com"

    # A request GitHub refused, carrying the HTTP status so callers can tell
    # "already exists" (422) apart from real failures.
    class Error < Reanimator::Error
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end
    end

    def initialize(token:, api: API)
      @token = token
      @api = api
    end

    # Percent-encodes text for a URL path or query, keeping the slashes that
    # branch names and refs legitimately contain.
    def self.escape(text)
      URI.encode_www_form_component(text.to_s).gsub("%2F", "/").gsub("+", "%20")
    end

    def get(path) = request(Net::HTTP::Get, path)

    def post(path, body) = request(Net::HTTP::Post, path, body)

    def patch(path, body) = request(Net::HTTP::Patch, path, body)

    private

    def request(verb, path, body = nil)
      uri = URI("#{@api}#{path}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: 10, read_timeout: 30) do |http|
        http.request(build(verb, uri, body))
      end
      parse(response, verb, path)
    rescue Error
      raise
    rescue => e
      # Transport and parsing failures (TLS, timeouts, an HTML error page
      # where JSON was promised) are refusals, never crashes that lose the run.
      raise Error, "GitHub #{verb::METHOD} #{path} failed: #{e.class}: #{e.message}"
    end

    def build(verb, uri, body)
      request = verb.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      request["User-Agent"] = "reanimator/#{VERSION}"
      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end
      request
    end

    def parse(response, verb, path)
      data = response.body.to_s.empty? ? nil : JSON.parse(response.body)
      return data if response.is_a?(Net::HTTPSuccess)

      message = data.is_a?(Hash) ? data["message"] : response.message
      raise Error.new("GitHub #{verb::METHOD} #{path} returned #{response.code}: #{message}",
        status: response.code.to_i)
    end
  end
end
