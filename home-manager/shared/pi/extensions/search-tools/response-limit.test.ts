import assert from "node:assert/strict";
import test from "node:test";
import { readResponseBodyLimited } from "./web-fetch.ts";

const FIVE_MIB = 5 * 1024 * 1024;

test("readResponseBodyLimited accepts exactly five MiB", async () => {
  const response = new Response(new Uint8Array(FIVE_MIB));
  const body = await readResponseBodyLimited(response);
  assert.equal(body.byteLength, FIVE_MIB);
});

test("readResponseBodyLimited rejects streamed responses over five MiB", async () => {
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array(FIVE_MIB));
      controller.enqueue(new Uint8Array(1));
    },
    cancel() {
      cancelled = true;
    },
  });

  await assert.rejects(() => readResponseBodyLimited(new Response(stream)), /exceeds 5MB/);
  assert.equal(cancelled, true);
});
