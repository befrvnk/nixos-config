import assert from "node:assert/strict";
import test from "node:test";
import { isLocalHostname, isPublicIpAddress, normalizeHostname } from "./network-safety.ts";

test("isPublicIpAddress rejects IPv4 special-use ranges", () => {
  for (const address of [
    "0.0.0.1", "10.0.0.1", "100.64.0.1", "127.0.0.1", "169.254.1.1",
    "172.16.0.1", "192.0.0.1", "192.0.2.1", "192.88.99.1", "192.168.1.1",
    "198.18.0.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255",
  ]) {
    assert.equal(isPublicIpAddress(address), false, address);
  }
  assert.equal(isPublicIpAddress("8.8.8.8"), true);
  assert.equal(isPublicIpAddress("93.184.216.34"), true);
});

test("isPublicIpAddress rejects IPv6 special-use and mapped private ranges", () => {
  for (const address of [
    "::", "::1", "fc00::1", "fe80::1", "ff00::1", "2001:db8::1", "2002::1",
    "3fff::1", "::ffff:127.0.0.1", "::ffff:7f00:1",
  ]) {
    assert.equal(isPublicIpAddress(address), false, address);
  }
  assert.equal(isPublicIpAddress("2001:4860:4860::8888"), true);
});

test("hostname normalization covers dotted localhost names", () => {
  assert.equal(normalizeHostname("LOCALHOST."), "localhost");
  assert.equal(isLocalHostname(normalizeHostname("api.localhost.")), true);
});
