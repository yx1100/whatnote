cask "whatnote" do
  version "1.3.1"
  sha256 "9bd281fef0345fc99ee434b38fad75ae5b7a72f18225f9aae395e4faacd2593e"

  url "https://github.com/yx1100/whatnote/releases/download/v#{version}/Whatnote-v#{version}-macOS-arm64.zip"
  name "Whatnote"
  name "随便记"
  desc "Native desktop sticky notes with spatial organization"
  homepage "https://github.com/yx1100/whatnote"

  depends_on arch: :arm64
  depends_on macos: :big_sur

  app "Whatnote.app"
end
