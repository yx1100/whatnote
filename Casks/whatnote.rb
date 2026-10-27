cask "whatnote" do
  version "1.5.6"
  sha256 "ab550016d2e7aa52e0179f8d0a575d4b2010db688544105b75b3909bb7ecda1a"

  url "https://github.com/yx1100/whatnote/releases/download/v#{version}/Whatnote-v#{version}-macOS-arm64.zip"
  name "Whatnote"
  name "随便记"
  desc "Native desktop sticky notes with spatial organization"
  homepage "https://github.com/yx1100/whatnote"

  depends_on arch: :arm64
  depends_on macos: :big_sur

  app "Whatnote.app"
end
