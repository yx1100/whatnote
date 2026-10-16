cask "whatnote" do
  version "1.3.1"
  sha256 "420a5aed51dcbc416c372a00d475e1c0fa4734f78a17414d2226a531230fab9b"

  url "https://github.com/yx1100/whatnote/releases/download/v#{version}/Whatnote-v#{version}-macOS-arm64.zip"
  name "Whatnote"
  name "随便记"
  desc "Native desktop sticky notes with spatial organization"
  homepage "https://github.com/yx1100/whatnote"

  depends_on arch: :arm64
  depends_on macos: :big_sur

  app "Whatnote.app"
end
