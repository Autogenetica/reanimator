# frozen_string_literal: true

# Stands in for {Reanimator::GitHubClient} so no spec ever talks to GitHub. It
# answers the endpoints the submitter uses, records every call, and can be
# told the reanimator/ branch already exists (with a tip written by Reanimator
# or by someone else), that a pull request is open (draft or ready), or that
# opening the pull request fails.
class FakeGitHub
  attr_reader :calls

  # @param branch_tip [String, nil] commit message at the existing branch tip;
  #   nil means the branch does not exist
  def initialize(head:, default_branch: "main", branch_tip: nil, open_pull: nil, refuse_pulls: false)
    @head = head
    @default_branch = default_branch
    @branch_tip = branch_tip
    @open_pull = open_pull
    @refuse_pulls = refuse_pulls
    @calls = []
  end

  def get(path)
    @calls << [:get, path, nil]
    case path
    when %r{/git/ref/heads/#{@default_branch}\z} then {"object" => {"sha" => @head}}
    when %r{/git/ref/heads/} then branch_ref
    when %r{/git/commits/tip\z} then {"message" => @branch_tip}
    when %r{/git/commits/} then {"tree" => {"sha" => "base-tree"}}
    when /pulls\?/ then @open_pull ? [@open_pull] : []
    else {"default_branch" => @default_branch}
    end
  end

  def post(path, body)
    @calls << [:post, path, body]
    case path
    when %r{/git/trees\z} then {"sha" => "new-tree"}
    when %r{/git/commits\z} then {"sha" => "new-commit"}
    when %r{/git/refs\z} then {}
    when %r{/pulls\z}
      raise Reanimator::GitHubClient::Error.new("Draft pull requests are not supported", status: 422) if @refuse_pulls

      {"html_url" => "https://github.com/acme/widget/pull/7", "number" => 7}
    end
  end

  def patch(path, body)
    @calls << [:patch, path, body]
    path.include?("/pulls/") ? {"html_url" => @open_pull.fetch("html_url")} : {}
  end

  def posted(suffix) = @calls.find { |verb, path, _| verb == :post && path.end_with?(suffix) }&.last

  def patched(fragment) = @calls.find { |verb, path, _| verb == :patch && path.include?(fragment) }&.last

  def wrote? = @calls.any? { |verb, _, _| verb != :get }

  private

  def branch_ref
    raise Reanimator::GitHubClient::Error.new("Not Found", status: 404) unless @branch_tip

    {"object" => {"sha" => "tip"}}
  end
end
