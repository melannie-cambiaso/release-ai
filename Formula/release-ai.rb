class ReleaseAi < Formula
  desc "Automated release management with Claude AI"
  homepage "https://github.com/melannie-cambiaso/release-ai"
  url "https://github.com/melannie-cambiaso/release-ai/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "4c83ea68ad12cce5e49246797167ea4f8b95866c1f9a3e35340a5707b2f341f9"
  license "MIT"
  version "1.0.0"

  depends_on "jq"
  depends_on "gh"

  def install
    # Install the main script
    bin.install "bin/release-ai"

    # Install library files
    libexec.install "lib"

    # Install templates
    libexec.install "templates"

    # Create wrapper script that sets the correct library paths
    (bin/"release-ai").unlink
    (bin/"release-ai").write <<~EOS
      #!/usr/bin/env bash
      export RELEASE_AI_LIB_DIR="#{libexec}/lib"
      export RELEASE_AI_TEMPLATES_DIR="#{libexec}/templates"
      exec "#{libexec}/bin/release-ai" "$@"
    EOS

    # Make wrapper executable
    chmod 0755, bin/"release-ai"

    # Move the actual script to libexec
    libexec.install Dir["bin/*"]
  end

  test do
    system "#{bin}/release-ai", "version"
  end
end
