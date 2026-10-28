# frozen_string_literal: true

# Stands in for {Reanimator::GitHubClient} so no spec ever talks to GitHub. It
# answers the handful of endpoints the submitter uses, records every call, and
# can be told that the branch or an open pull request already exists.
class FakeGitHub
  attr_reader :calls

  def initialize(head:, default_branch: "main", branch_exists: false, open_pull: nil)
    @head = head
    @default_branch = default_branch
    @branch_exists = branch_exists
    @open_pull = open_pull
    @calls = []
  end

  def get(path)
    @calls << [:get, path, nil]
    case path
    when %r{/git/ref/heads/} then {"object" => {"sha" => @head}}
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
    when %r{/git/refs\z}
      raise Reanimator::GitHubClient::Error.new("Reference already exists", status: 422) if @branch_exists

      {}
    when %r{/pulls\z} then {"html_url" => "https://github.com/acme/widget/pull/7", "number" => 7}
    end
  end

  def patch(path, body)
    @calls << [:patch, path, body]
    path.include?("/pulls/") ? {"html_url" => @open_pull["html_url"]} : {}
  end

  def posted(suffix) = @calls.find { |verb, path, _| verb == :post && path.end_with?(suffix) }&.last

  def patched(fragment) = @calls.find { |verb, path, _| verb == :patch && path.include?(fragment) }&.last
end
