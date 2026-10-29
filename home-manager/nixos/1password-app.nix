{
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  hmLib = import ./lib.nix { inherit lib pkgs; };

  # The desktop app must run in the initial (unsandboxed) user namespace for its
  # CLI integration to work: 1Password authenticates CLI peers by comparing the
  # connecting process's effective GID against the onepassword-cli group, and a
  # session-launched instance that sat in a restricted user namespace (mapping
  # only uid 1000 / gid 100) could never map gid 31002, so every handshake was
  # rejected ("connecting to desktop app: read: connection reset"). This service
  # execs the app from the user manager's initial namespace instead, where the
  # kernel-applied setgid GID of the CLI wrapper is visible. See
  # docs/1password-cli-initial-namespace.md for the full diagnosis.
  #
  # null when the host does not enable the 1Password GUI module.
  app = (osConfig.programs._1password-gui or { package = null; }).package;
in
lib.optionalAttrs (app != null) {
  systemd.user.services."1password-app" = hmLib.mkGraphicalUserService {
    description = "1Password desktop app (initial user namespace)";
    execStart = "${app}/bin/1password --ozone-platform-hint=auto";
    service = {
      # Quitting from the tray is a clean exit; restart only on crash so the
      # tray does not resurrect itself.
      Restart = "on-failure";
    };
  };
}
