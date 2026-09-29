import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import worker from "../src/index.js";

if (!globalThis.crypto) globalThis.crypto = webcrypto;

function resetCache() {
  const entries = new Map();
  globalThis.caches = {
    default: {
      match: async (request) => entries.get(request.url)?.clone(),
      put: async (request, response) => { entries.set(request.url, response.clone()); },
    },
  };
}

function environment(limiter = { limit: async () => ({ success: true }) }) {
  return {
    LOGO_DEV_SECRET_KEY: "search-secret",
    CONTEXT_DEV_API_KEY: "context-secret",
    SEARCH_LIMITER: limiter,
    IDENTIFY_LIMITER: limiter,
  };
}

test("search forwards only the company query and returns safe suggestions", async () => {
  resetCache();
  let upstreamRequest;
  globalThis.fetch = async (request, options) => {
    upstreamRequest = { request: new URL(request), options };
    return Response.json([
      { name: "Starbucks", domain: "starbucks.com", logo_url: "https://img.logo.dev/starbucks.com?token=pk_test" },
      { name: "Bad", domain: "not a domain", logo_url: "https://elsewhere.example/logo" },
    ]);
  };
  const result = await worker.fetch(new Request("https://bow.example/search?q=Starbucks"), environment());
  assert.equal(result.status, 200);
  assert.equal(upstreamRequest.request.hostname, "api.logo.dev");
  assert.equal(upstreamRequest.request.searchParams.get("q"), "Starbucks");
  assert.equal(upstreamRequest.options.headers.Authorization, "Bearer search-secret");
  assert.deepEqual(await result.json(), [
    { name: "Starbucks", domain: "starbucks.com", logo_url: "https://img.logo.dev/starbucks.com?token=pk_test" },
  ]);
});

test("identification sends only the descriptor and requests a high-confidence match", async () => {
  resetCache();
  let upstreamBody;
  let authorization;
  globalThis.fetch = async (_url, options) => {
    upstreamBody = JSON.parse(options.body);
    authorization = options.headers.Authorization;
    return Response.json({ brand: { title: "Blue Bottle Coffee", domain: "bluebottlecoffee.com", description: "Coffee shops" } });
  };
  const result = await worker.fetch(new Request("https://bow.example/identify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ descriptor: "SQ *BLUE BOTTLE OAK", amount: 123.45, account: "private" }),
  }), environment());
  assert.equal(result.status, 200);
  assert.equal(authorization, "Bearer context-secret");
  assert.deepEqual(upstreamBody, {
    type: "by_transaction",
    transaction_info: "SQ *BLUE BOTTLE OAK",
    high_confidence_only: true,
  });
  assert.deepEqual(await result.json(), {
    name: "Blue Bottle Coffee", domain: "bluebottlecoffee.com", description: "Coffee shops",
  });
});

test("unresolved descriptions stay unresolved and repeated calls use cache", async () => {
  resetCache();
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return Response.json({ error_code: "NOT_FOUND" }, { status: 400 });
  };
  const makeRequest = () => new Request("https://bow.example/identify", {
    method: "POST", body: JSON.stringify({ descriptor: "UNKNOWN MERCHANT 123" }),
  });
  assert.equal((await worker.fetch(makeRequest(), environment())).status, 404);
  assert.equal((await worker.fetch(makeRequest(), environment())).status, 404);
  assert.equal(calls, 1);
});

test("rate limits block an uncached lookup before it reaches either provider", async () => {
  resetCache();
  let called = false;
  globalThis.fetch = async () => { called = true; throw new Error("Should not call provider"); };
  const denied = { limit: async () => ({ success: false }) };
  const result = await worker.fetch(new Request("https://bow.example/search?q=Target"), environment(denied));
  assert.equal(result.status, 429);
  assert.equal(called, false);
});

test("missing rate limiting binding fails closed", async () => {
  resetCache();
  let called = false;
  globalThis.fetch = async () => { called = true; throw new Error("Should not call provider"); };
  const env = environment();
  delete env.SEARCH_LIMITER;
  const result = await worker.fetch(new Request("https://bow.example/search?q=Target"), env);
  assert.equal(result.status, 503);
  assert.equal(called, false);
});
