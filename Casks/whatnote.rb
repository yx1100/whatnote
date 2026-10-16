cask "whatnote" do
  version "1.3.0"
  sha256 "689ce0e7d43b2f89694e35bb214b09f19a36449eb0e8007172a310a559eaf4a4"

  url "https://github.com/yx1100/whatnote/releases/download/v#{version}/Whatnote-v#{version}-macOS-arm64.zip"
  name "Whatnote"
  name "随便记"
  desc "Native desktop sticky notes with spatial organization"
  homepage "https://github.com/yx1100/whatnote"

  depends_on arch: :arm64
  depends_on macos: :big_sur

  app "Whatnote.app"
end
