class Inkoscribe < Formula
  desc "Live, local, and private audio transcription"
  homepage "https://github.com/uohzxela/homebrew-inkoscribe"
  url "https://github.com/uohzxela/homebrew-inkoscribe/releases/download/v0.2.0/inkoscribe-mac.tar.gz"
  sha256 "ead02b1e1f0de3228e1472f629457f037ee6597c1d54a2a11817f8a07b980f7a"
  license "MIT"
  revision 1

  def install
    # Check for Apple Silicon architecture
    if OS.mac? && Hardware::CPU.arm?
      ohai "Detected Apple Silicon processor - proceeding with installation..."
    elsif OS.mac? && Hardware::CPU.intel?
      odie "Error: This application requires Apple Silicon (M1/M2/M3) processors. Intel Macs are not supported."
    else
      odie "Error: Unsupported CPU architecture. This application only supports Apple Silicon processors."
    end

    # Install actual binary in libexec
    libexec.install "inkoscribe"

    # Wrapper script: points the binary at the shared model directory and
    # downloads a named model on first use (e.g. `inkoscribe --model small.en`).
    # base.en ships by default so every machine gets a real-time baseline;
    # heavier models are strictly opt-in.
    (bin/"inkoscribe").write <<~EOS
      #!/bin/bash
      export WHISPER_MODEL_DIR="${WHISPER_MODEL_DIR:-#{var}/inkoscribe/models}"

      model=""
      prev=""
      for arg in "$@"; do
        if [ "$prev" = "--model" ] || [ "$prev" = "-m" ]; then
          model="$arg"
        fi
        case "$arg" in
          --model=*) model="${arg#*=}" ;;
        esac
        prev="$arg"
      done

      # Named model (not a path): fetch it into the model dir if missing.
      if [ -n "$model" ] && [[ "$model" != */* ]] && [[ "$model" != *.bin ]]; then
        model_file="$WHISPER_MODEL_DIR/ggml-$model.bin"
        if [ ! -f "$model_file" ]; then
          echo "Model '$model' not installed yet; downloading to $model_file ..."
          curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$model.bin" -o "$model_file" || exit 1
        fi
      fi

      exec "#{libexec}/inkoscribe" "$@"
    EOS
    (bin/"inkoscribe").chmod 0755
  end

  def post_install
    # Models live under var, NOT the versioned keg: keg contents are deleted
    # on upgrade, which would wipe downloaded models and force a re-download
    # of base.en every release.
    models_dir = var/"inkoscribe/models"
    models_dir.mkpath

    # Migrate models from the old keg-share location if any survived.
    old_dir = HOMEBREW_PREFIX/"share/whisper"
    if old_dir.directory?
      old_dir.glob("ggml-*.bin").each do |m|
        target = models_dir/m.basename
        FileUtils.mv(m, target) unless target.exist?
      end
    end

    # Ship the baseline model so first run works offline.
    base_model = models_dir/"ggml-base.en.bin"
    unless base_model.exist?
      ohai "Downloading Whisper base model to #{base_model}..."
      system "curl", "-L",
             "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
             "-o", base_model.to_s
    end
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

        # Higher-quality model (downloads ~470 MB on first use)
        inkoscribe --source sys --model small.en

        # Save finalized transcript lines to a file
        inkoscribe --source sys --transcript out.txt

      The default model is base.en, which runs in real time on all Apple
      Silicon Macs. Use --model small.en for noticeably better accuracy if
      your machine keeps up with it.

      Models are stored in #{HOMEBREW_PREFIX}/var/inkoscribe/models and
      survive upgrades.

      Environment variables:
        WHISPER_MODEL_DIR:  Directory holding ggml-<name>.bin model files
                            (default: #{HOMEBREW_PREFIX}/var/inkoscribe/models)
        WHISPER_MODEL_PATH: Full path to a model file (--model overrides this)
    EOS
  end

  test do
    # Test that the wrapper script exists and shows help
    assert_match "Live, local, and private transcription", shell_output("#{bin}/inkoscribe --help")
  end
end
