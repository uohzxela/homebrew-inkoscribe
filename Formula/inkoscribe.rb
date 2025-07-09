class Inkoscribe < Formula
  desc "Live, local, and private audio transcription"
  homepage "https://github.com/uohzxela/homebrew-inkoscribe"
  url "https://github.com/uohzxela/homebrew-inkoscribe/releases/download/v0.1.0/inkoscribe-mac.tar.gz"
  sha256 "53080f85bdbd7c2076b6bc10ac642a6b4db9422dec4261117fe64324763c6ff6"
  license "MIT"

  def install
    # Check for macOS 13 or later
    if OS.mac? && MacOS.version < :ventura
      odie "Error: This application requires macOS 13 (Ventura) or later. Current version: #{MacOS.version}"
    end

    # Check for Apple Silicon architecture
    if OS.mac? && Hardware::CPU.arm?
      ohai "Detected Apple Silicon processor - proceeding with installation..."
    elsif OS.mac? && Hardware::CPU.intel?
      odie "Error: This application requires Apple Silicon (M1/M2/M3+) processors. Intel Macs are not supported."
    else
      odie "Error: Unsupported CPU architecture. This application only supports Apple Silicon processors."
    end

    # Install actual binary in libexec
    libexec.install "inkoscribe"

    # Create wrapper script to set WHISPER_MODEL_PATH
    (bin/"inkoscribe").write <<~EOS
      #!/bin/bash
      export WHISPER_MODEL_PATH="${WHISPER_MODEL_PATH:-#{share}/whisper/ggml-base.en.bin}"
      exec "#{libexec}/inkoscribe" "$@"
    EOS
    (bin/"inkoscribe").chmod 0755

    # Create directory for Whisper models at the specified path
    whisper_dir = share/"whisper"
    whisper_dir.mkpath

    # Download base model if it doesn't exist at the specified path
    model_path = whisper_dir/"ggml-base.en.bin"
    unless model_path.exist?
      ohai "Downloading Whisper base model to #{model_path}..."
      system "curl", "-L",
             "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
             "-o", model_path.to_s
    end
  end

  def post_install
    # Set up model path environment variable
    ohai "Setting up Whisper model path..."
    puts "The Whisper model is installed at: #{share}/whisper/ggml-base.en.bin"
    puts "You can override this by setting WHISPER_MODEL_PATH environment variable"
  end

  def caveats
    <<~EOS
      inkoscribe requires microphone and system audio permissions.

      On first run, macOS will prompt for microphone access.
      For system audio capture, you may need to grant additional permissions
      in System Settings > Privacy & Security > Screen & System Audio Recording > ...

      Usage:
        # Transcribe from microphone
        inkoscribe --source mic

        # Transcribe system audio
        inkoscribe --source sys

        # Transcribe audio file
        inkoscribe --source /path/to/audio.wav
    EOS
  end

  test do
    # Test that the wrapper script exists and shows help
    assert_match "Live, local, and private transcription", shell_output("#{bin}/inkoscribe --help")
  end
end