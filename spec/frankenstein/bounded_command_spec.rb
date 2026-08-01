# frozen_string_literal: true

RSpec.describe Frankenstein::BoundedCommand do
  it "captures output and succeeds on exit 0" do
    result = described_class.run("echo hello", chdir: Dir.pwd, timeout: 10)
    expect(result).to be_success
    expect(result.output).to include("hello")
  end

  it "treats a nonzero exit as failure" do
    result = described_class.run("exit 3", chdir: Dir.pwd, timeout: 10)
    expect(result).not_to be_success
    expect(result).not_to be_timed_out
  end

  it "caps captured output so a flood cannot exhaust memory" do
    result = described_class.run("yes | head -c 3000000", chdir: Dir.pwd, timeout: 20)
    expect(result).to be_success
    expect(result.output.bytesize).to be <= (1 << 20) + 64
    expect(result.output).to include("truncated")
  end

  it "bounds a hanging command and does not wait for it" do
    result = described_class.run("sleep 30", chdir: Dir.pwd, timeout: 1)
    expect(result).to be_timed_out
    expect(result).not_to be_success
    expect(result.duration).to be < 10
  end

  it "terminates the whole process group so a spawned child cannot outlive the bound" do
    require "tmpdir"
    Dir.mktmpdir do |dir|
      sentinel = File.join(dir, "child-survived")
      # `sh` waits on the sleep (foreground), so the 1s bound fires while the
      # child is alive. Killing only `sh` would orphan the sleep and let it
      # touch the sentinel at +3s; a process-group kill stops the child too.
      result = described_class.run("sleep 3 && touch #{sentinel}", chdir: dir, timeout: 1)
      expect(result).to be_timed_out
      Kernel.sleep(4)
      expect(File.exist?(sentinel)).to be(false)
    end
  end
end
