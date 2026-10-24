# frozen_string_literal: true

RSpec.describe Frankenstein::SnapshotStore do
  def repository_at(name, files = {"README.md" => "# x"})
    Frankenstein::Repository.at(make_portfolio({name => files}).first)
  end

  def snapshot_of(repository)
    Frankenstein::ContractSnapshot.of(Frankenstein::EffectivePolicyResolver.new(repository).resolve)
  end

  describe "the committed, in-repository default" do
    it "keeps a repository's snapshot beside its contract, so drift arrives as a reviewable diff" do
      repository = repository_at("widget")
      expect(described_class.new.path_for(repository))
        .to eq(File.join(repository.path, ".frankenstein-snapshot.json"))
    end

    it "reports nothing recorded until something is, rather than inventing an empty baseline" do
      repository = repository_at("widget")
      store = described_class.new

      expect(store.recorded?(repository)).to be(false)
      expect(store.load(repository)).to be_nil

      store.save(snapshot_of(repository), repository)
      expect(store.load(repository).repository).to eq(repository.full_name)
    end
  end

  describe "a portfolio-side directory" do
    it "keys snapshots by repository and creates the directory on first write" do
      repository = repository_at("widget")
      directory = File.join(Dir.mktmpdir("frankenstein-store"), "nested")
      store = described_class.new(directory: directory)

      written = store.save(snapshot_of(repository), repository)

      expect(written).to eq(File.join(directory, "widget.json"))
      expect(store.load(repository)).not_to be_nil
    end

    it "flattens a repository identity into one safe filename" do
      repository = repository_at("widget")
      allow(repository).to receive(:full_name).and_return("codenamev/odd name!")
      store = described_class.new(directory: "/tmp/snaps")

      expect(File.basename(store.path_for(repository))).to eq("codenamev-odd-name-.json")
    end

    it "fails as a clean error when the directory cannot be written" do
      repository = repository_at("widget")
      store = described_class.new(directory: "/proc/nope/snaps")

      expect { store.save(snapshot_of(repository), repository) }
        .to raise_error(Frankenstein::ContractError, /Could not write the contract snapshot/)
    end
  end

  # The store is the one place that knows where snapshots live, so it is also
  # the one place that knows how to tell a maintainer to put one back.
  describe "the command it tells a maintainer to run" do
    it "names --record for the in-repository default" do
      expect(described_class.new.record_command).to eq("frankenstein drift --record")
    end

    it "carries the directory through when snapshots live portfolio-side" do
      expect(described_class.new(directory: "snaps").record_command)
        .to eq("frankenstein drift --record --snapshots snaps")
    end

    it "defers to an explicitly named file when the maintainer bypassed the store" do
      expect(described_class.new.record_command("some/where.json"))
        .to eq("frankenstein drift --save some/where.json")
    end
  end
end
