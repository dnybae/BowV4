const logoSearchURL = "https://api.logo.dev/search";
const contextRetrieveURL = "https://api.context.dev/v1/brand/retrieve";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const isSearch = request.method === "GET" && url.pathname === "/search";
    const isIdentify = request.method === "POST" && url.pathname === "/identify";
    if (!isSearch && !isIdentify) return json({ error: "Not found" }, 404);

    let input;
    if (isSearch) {
      input = url.searchParams.get("q")?.trim() ?? "";
      if (input.length < 2 || input.length > 80) return json({ error: "Search must be 2–80 characters" }, 400);
    } else {
      if (Number(request.headers.get("content-length") ?? 0) > 2048) return json({ error: "Request too large" }, 413);
      const raw = await request.text();
      if (raw.length > 2048) return json({ error: "Request too large" }, 413);
      let body;
      try { body = JSON.parse(raw); } catch { return json({ error: "Invalid JSON" }, 400); }
      input = typeof body?.descriptor === "string" ? body.descriptor.trim() : "";
      if (input.length < 3 || input.length > 500) return json({ error: "Description must be 3–500 characters" }, 400);
    }

    const cacheKey = new Request(new URL(
      `/_brand_cache/${isSearch ? "search" : "identify"}/${await digest(input.toLowerCase())}`,
      request.url
    ));
    const cache = typeof caches === "undefined" ? null : caches.default;
    let cached;
    try { cached = await cache?.match(cacheKey); } catch { /* Continue without cache. */ }
    if (cached) return cached;

    const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const limiter = isSearch ? env.SEARCH_LIMITER : env.IDENTIFY_LIMITER;
    if (!limiter) return json({ error: "Rate limiting is not configured" }, 503);
    const limit = await limiter.limit({ key: ip });
    if (!limit.success) return json({ error: "Too many requests" }, 429);

    try {
      const response = isSearch ? await search(input, env) : await identify(input, env);
      if (response.status === 200 || response.status === 404) {
        try { await cache?.put(cacheKey, response.clone()); } catch { /* Cache failure must not hide a valid result. */ }
      }
      return response;
    } catch {
      return json({ error: "Brand lookup is temporarily unavailable" }, 502);
    }
  },
};

async function search(query, env) {
  if (!env.LOGO_DEV_SECRET_KEY) return json({ error: "Search is not configured" }, 503);
  const url = new URL(logoSearchURL);
  url.searchParams.set("q", query);
  url.searchParams.set("strategy", "suggest");
  url.searchParams.set("is_profane", "false");
  const upstream = await fetch(url, {
    headers: { Authorization: `Bearer ${env.LOGO_DEV_SECRET_KEY}` },
  });
  if (!upstream.ok) return json({ error: "Company search is unavailable" }, 502);
  const matches = await upstream.json();
  if (!Array.isArray(matches)) return json({ error: "Invalid company search response" }, 502);
  return json(matches.slice(0, 10).flatMap((item) => {
    if (!validDomain(item?.domain) || typeof item?.name !== "string") return [];
    const logo = typeof item.logo_url === "string" && item.logo_url.startsWith("https://img.logo.dev/")
      ? item.logo_url : null;
    return [{ name: item.name.slice(0, 120), domain: item.domain.toLowerCase(), logo_url: logo }];
  }), 200, 3600);
}

async function identify(descriptor, env) {
  if (!env.CONTEXT_DEV_API_KEY) return json({ error: "Transaction lookup is not configured" }, 503);
  const upstream = await fetch(contextRetrieveURL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.CONTEXT_DEV_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      type: "by_transaction",
      transaction_info: descriptor,
      high_confidence_only: true,
    }),
  });
  if (upstream.status === 400) {
    const error = await upstream.json().catch(() => null);
    if (error?.error_code === "NOT_FOUND") return json({ error: "No reliable match" }, 404, 86400);
  }
  if (!upstream.ok) return json({ error: "Transaction lookup is unavailable" }, 502);
  const result = await upstream.json();
  const brand = result?.brand;
  if (!validDomain(brand?.domain) || typeof brand?.title !== "string") {
    return json({ error: "No reliable match" }, 404, 86400);
  }
  return json({
    name: brand.title.slice(0, 120),
    domain: brand.domain.toLowerCase(),
    description: typeof brand.description === "string" ? brand.description.slice(0, 500) : null,
  }, 200, 604800);
}

function validDomain(value) {
  return typeof value === "string" && value.length <= 253
    && /^(?:[a-z0-9-]+\.)+[a-z]{2,}$/i.test(value);
}

async function digest(value) {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function json(value, status = 200, maxAge = 0) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": maxAge ? `public, max-age=${maxAge}` : "no-store",
    },
  });
}
