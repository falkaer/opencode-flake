{
  description = "Prebuilt opencode binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      version = "1.18.29";

      sources = {
        x86_64-linux = {
          asset = "opencode-linux-x64.tar.gz";
          hash = "sha256-6oALf/ViJrcJUhJsn8HiUXykxLVoL9nT+eh0SWl6EZQ=";
        };
        aarch64-linux = {
          asset = "opencode-linux-arm64.tar.gz";
          hash = "sha256-cLr3aTlcpOemiSQCZTDDkOrOGU87fkkZ1O/LKqLu08A=";
        };
        aarch64-darwin = {
          asset = "opencode-darwin-arm64.zip";
          hash = "sha256-/nZPfzYMWEqD4Y3V8j+xprJyX17ohUsCUv5Vj3eY6UY=";
        };
      };

      systems = builtins.attrNames sources;
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkOpencode =
        pkgs:
        let
          inherit (pkgs) lib stdenv;
          source = sources.${stdenv.hostPlatform.system};
        in
        stdenv.mkDerivation {
          pname = "opencode";
          inherit version;

          src = pkgs.fetchurl {
            url = "https://github.com/anomalyco/opencode/releases/download/v${version}/${source.asset}";
            inherit (source) hash;
          };

          unpackPhase = ''
            runHook preUnpack
            mkdir source
            cd source
            case "$src" in
              *.zip) unzip -q "$src" ;;
              *) tar xzf "$src" ;;
            esac
            runHook postUnpack
          '';

          nativeBuildInputs = [
            pkgs.installShellFiles
            pkgs.makeBinaryWrapper
            pkgs.writableTmpDirAsHomeHook
          ]
          ++ lib.optional stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook
          ++ lib.optional (lib.hasSuffix ".zip" source.asset) pkgs.unzip;

          dontConfigure = true;
          dontBuild = true;
          dontStrip = true;

          env.OPENCODE_DISABLE_MODELS_FETCH = true;

          installPhase = ''
            runHook preInstall

            install -Dm755 opencode $out/bin/opencode

            wrapProgram $out/bin/opencode \
              --prefix PATH : ${
                lib.makeBinPath ([ pkgs.ripgrep ] ++ lib.optional stdenv.hostPlatform.isDarwin pkgs.sysctl)
              }

            runHook postInstall
          '';

          postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
            installShellCompletion --cmd opencode \
              --bash <($out/bin/opencode completion) \
              --zsh <(SHELL=/bin/zsh $out/bin/opencode completion)
          '';

          nativeInstallCheckInputs = [
            pkgs.versionCheckHook
            pkgs.writableTmpDirAsHomeHook
          ];
          doInstallCheck = true;
          versionCheckKeepEnvironment = [
            "HOME"
            "OPENCODE_DISABLE_MODELS_FETCH"
          ];
          versionCheckProgramArg = "--version";

          meta = {
            description = "The open source coding agent";
            homepage = "https://opencode.ai";
            changelog = "https://github.com/anomalyco/opencode/releases/tag/v${version}";
            license = lib.licenses.mit;
            mainProgram = "opencode";
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
            platforms = systems;
          };
        };
    in
    {
      packages = forEachSystem (pkgs: rec {
        default = opencode;
        opencode = mkOpencode pkgs;
      });

      overlays.default = final: _prev: {
        opencode = mkOpencode final;
      };
    };
}
