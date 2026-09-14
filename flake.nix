{
  description = "Prebuilt opencode binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      version = "1.18.31";

      sources = {
        x86_64-linux = {
          asset = "opencode-linux-x64.tar.gz";
          hash = "sha256-6TEr517YA7dBX8Kuq9ofT+k4kSo5Zzdi3Aw4wOEeveQ=";
        };
        aarch64-linux = {
          asset = "opencode-linux-arm64.tar.gz";
          hash = "sha256-1OMy9GsidEhYLA2fx19vgm3+lcn3UbwgEfxNk3oEK+Y=";
        };
        aarch64-darwin = {
          asset = "opencode-darwin-arm64.zip";
          hash = "sha256-yvfzH6GuwjU+qFnU75q4JMYnPZQbAW6I1RGT+jAo004=";
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
            ${lib.optionalString stdenv.hostPlatform.isLinux ''
              # autoPatchelfHook only runs in fixupPhase, but we need to execute the
              # binary here; the sandbox has no /lib/ld-linux-*.so.
              autoPatchelf $out/bin
            ''}
            $out/bin/opencode completion > completions.bash
            SHELL=/bin/zsh $out/bin/opencode completion > completions.zsh
            installShellCompletion --cmd opencode \
              --bash completions.bash \
              --zsh completions.zsh
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
