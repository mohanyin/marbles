cask "marbles" do
  version "0.1.0"
  sha256 :no_check

  # Until a notarized release URL exists, brew install --cask from this file
  # after `scripts/package.sh` (arm64 macOS 14+).
  url "file://#{File.expand_path(File.join(__dir__, "..", "dist", "Marbles.zip"))}"
  name "Marbles"
  desc "Desktop overlay for local coding agents"
  homepage "https://github.com/mohan/marbles-v2"

  depends_on macos: ">= :sonoma"

  app "Marbles.app"

  caveats <<~EOS
    This build is not notarized. If Gatekeeper blocks it, right-click
    /Applications/Marbles.app and choose Open.

    First launch installs Claude Code and Cursor hooks. Undo from the
    menu bar extra. Intel Macs are not supported.
  EOS

  uninstall quit: "dev.marbles.app",
            delete: "/Applications/Marbles.app"

  zap trash: [
    "~/Library/Application Support/Marbles",
  ]
end
