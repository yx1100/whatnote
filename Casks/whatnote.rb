cask "whatnote" do
  version "1.3.1"
  sha256 "a3902248a0db38cb81ddc7e9277b737c2d83ffa9ab1e4f634e10a369b0c1d869"

  url "https://github.com/yx1100/whatnote/releases/download/v#{version}/Whatnote-v#{version}-macOS-arm64.zip"
  name "Whatnote"
  name "随便记"
  desc "Native desktop sticky notes with spatial organization"
  homepage "https://github.com/yx1100/whatnote"

  depends_on arch: :arm64
  depends_on macos: :big_sur

  app "Whatnote.app"
end
