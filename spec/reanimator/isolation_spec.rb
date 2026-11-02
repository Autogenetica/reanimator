# frozen_string_literal: true

RSpec.describe Reanimator::Isolation do
  it "copies links that stay inside the repository, and leaves out every link that leads out" do
    outside = make_repo(files: {"outside_spec.rb" => "raise 'outside'\n"})
    root = make_repo(files: {"docs/README.md" => "inside", "spec/real_spec.rb" => "true\n"})
    {
      "README.md" => "docs/README.md",
      "fixtures" => File.join(outside),
      "shared" => "../#{File.basename(outside)}",
      "docs/up" => "../../#{File.basename(outside)}",
      "escape" => "docs/.."
    }.each { |link, target| File.symlink(target, File.join(root, link)) }
    File.symlink("/", File.join(root, "docs", "root"))
    File.symlink("docs/root/..", File.join(root, "through"))
    File.symlink("nowhere", File.join(root, "dangling"))

    described_class.copy(root) do |copy|
      links = Dir.glob("**/*", File::FNM_DOTMATCH, base: copy).select { |path| File.symlink?(File.join(copy, path)) }
      expect(links).to contain_exactly("README.md", "escape", "dangling")
      expect(File.read(File.join(copy, "README.md"))).to eq("inside")
      expect(File.directory?(File.join(copy, "spec"))).to be(true)
    end
  end
end
