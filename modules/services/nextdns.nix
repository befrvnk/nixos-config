_:

{
  networking.nameservers = [
    "45.90.28.0#9da5b3.dns.nextdns.io"
    "2a07:a8c0::#9da5b3.dns.nextdns.io"
    "45.90.30.0#9da5b3.dns.nextdns.io"
    "2a07:a8c1::#9da5b3.dns.nextdns.io"
  ];

  networking.networkmanager.dns = "systemd-resolved";

  services.resolved = {
    enable = true;
    dnssec = "true";
    domains = [ "~." ];
    dnsovertls = "true";
  };
}
