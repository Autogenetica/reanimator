# frozen_string_literal: true

# The client is the submitter's only window onto GitHub, so anything that goes
# wrong on the way - a refusal, an HTML error page, a dropped connection - has
# to arrive as a GitHubClient::Error the submitter turns into a refusal, never
# as an exception that loses the run.
RSpec.describe Reanimator::GitHubClient do
  let(:client) { described_class.new(token: "t") }

  def respond_with(response)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  def response(klass, code, body)
    klass.new("1.1", code, "msg").tap { |r| allow(r).to receive(:body).and_return(body) }
  end

  it "returns parsed JSON for a success" do
    respond_with(response(Net::HTTPOK, "200", '{"default_branch":"main"}'))
    expect(client.get("/repos/acme/widget")).to eq("default_branch" => "main")
  end

  it "raises an error carrying the status for a refusal" do
    respond_with(response(Net::HTTPUnprocessableEntity, "422", '{"message":"Reference already exists"}'))

    expect { client.post("/repos/acme/widget/git/refs", {}) }.to raise_error(described_class::Error) { |e|
      expect(e.status).to eq(422)
      expect(e.message).to include("Reference already exists")
    }
  end

  it "turns an HTML error page into an error, not a parser crash" do
    respond_with(response(Net::HTTPBadGateway, "502", "<html>Bad gateway</html>"))
    expect { client.get("/repos/acme/widget") }.to raise_error(described_class::Error, /JSON::ParserError/)
  end

  it "turns transport failures into errors" do
    allow(Net::HTTP).to receive(:start).and_raise(OpenSSL::SSL::SSLError, "certificate verify failed")
    expect { client.get("/repos/acme/widget") }.to raise_error(described_class::Error, /certificate verify failed/)
  end

  it "escapes branch names for URLs while keeping their slashes" do
    expect(described_class.escape("reanimator/fix #1 50%")).to eq("reanimator/fix%20%231%2050%25")
  end
end
