cask "whatnote" do
  version "1.5.7"
  sha256 "279d322f203f507c29509df20dc4a0a9a1f454848ceceb1bae256de708164495"

  url "https://github.com/yx1100/whatnote/releases/download/v#{version}/Whatnote-v#{version}-macOS-arm64.zip"
  name "Whatnote"
  name "随便记"
  desc "Native desktop sticky notes with spatial organization"
  homepage "https://github.com/yx1100/whatnote"

  depends_on arch: :arm64
  depends_on macos: :big_sur

  app "Whatnote.app"
end
