{ ... }:

{
  services.keyd = {
    enable = true;
    keyboards = {
      nuphy = {
        ids = [ "19f5:1028" ];
        settings = {
          main = {
            # Swap Alt and Meta (Win) keys
            # leftalt = "leftmeta";
            # leftmeta = "leftalt";
            # rightalt = "rightmeta";
            # rightmeta = "rightalt";

            # Map media keys back to function keys
            brightnessdown = "f1";
            brightnessup = "f2";
            scale = "f3"; # expose
            search = "f4";
            f20 = "f5"; # mic (often mapped to f20)
            sleep = "f6";
            previoussong = "f7";
            playpause = "f8";
            nextsong = "f9";
            mute = "f10";
            volumedown = "f11";
            volumeup = "f12";
          };
        };
      };
    };
  };
}
