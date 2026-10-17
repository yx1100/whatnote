cask "whatnote" do
  version "1.5.5"
  sha256 "f1e3accb51b3cc93a49e2e87cd3640af2954ac338c7dc765650e60157c9bc510"

  url "https://github.com/yx1100/whatnote/releases/download/v#{version}/Whatnote-v#{version}-macOS-arm64.zip"
  name "Whatnote"
  name "随便记"
  desc "Native desktop sticky notes with spatial organization"
  homepage "https://github.com/yx1100/whatnote"

  depends_on arch: :arm64
  depends_on macos: :big_sur

  app "Whatnote.app"
end
