// mimic-paymongo-relay — Cloudflare Worker (deployed to your workers.dev URL)
//
// Why this exists: Google Apps Script does NOT expose HTTP request headers to
// doPost() (proved empirically 2026-10-12: e.headers === undefined), but
// PayMongo signs webhooks ONLY via the Paymongo-Signature header. This tiny
// relay sits in front of the Apps Script endpoint:
//
//   PayMongo --[signed request]--> THIS WORKER --[proof query params]--> GAS /exec
//
// The worker verifies HMAC-SHA256(t + "." + rawBody, WHSK_SECRET) against the
// te/li signatures, checks the ±300 s replay window, then forwards the UNCHANGED
// body to GAS with proof = HMAC-SHA256(t + "." + rawBody, RELAY_SECRET).
// GAS independently verifies that proof over its own copy of the body — so an
// attacker who finds the GAS URL still cannot mint without RELAY_SECRET.
//
// Required (Worker → Settings → Variables & Secrets):
//   Secret: WHSK_SECRET     = the whsk_… PayMongo signing secret
//   Secret: RELAY_SECRET    = a fresh 64-hex random string (shared with GAS)
//   Plain:  GAS_EXEC_URL    = https://script.google.com/macros/s/<DEPLOY_ID>/exec
//
// Direct hits on the worker without a valid PayMongo signature → 401.

const TOLERANCE_SECONDS = 300;

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return new Response('Mimic PayMongo relay: POST only', { status: 200 });
    }

    const raw = await request.text();

    // --- parse Paymongo-Signature: t=…,te=…(test),li=…(live) ---
    const header = request.headers.get('Paymongo-Signature') || '';
    const parts = {};
    header.split(',').forEach(function (kv) {
      const i = kv.indexOf('=');
      if (i > 0) parts[kv.slice(0, i).trim()] = kv.slice(i + 1).trim();
    });
    const t = parts.t || '';
    const te = parts.te || '';
    const li = parts.li || '';
    if (!t || (!te && !li)) return new Response('missing signature', { status: 401 });

    // --- replay window ---
    if (Math.abs(Math.floor(Date.now() / 1000) - Number(t)) > TOLERANCE_SECONDS) {
      return new Response('stale timestamp', { status: 401 });
    }

    // --- verify against BOTH test and live signatures (constant-time) ---
    // WHSK_SECRET holds the LIVE endpoint's signing secret; WHSK_SECRET_TEST
    // (optional) holds the TEST endpoint's secret — PayMongo may issue a
    // different whsk_ per webhook endpoint, and both must verify so the
    // test and live webhooks can coexist without swapping anything.
    let ok = matchHex(await hmacHex(t + '.' + raw, env.WHSK_SECRET), te) ||
             matchHex(await hmacHex(t + '.' + raw, env.WHSK_SECRET), li);
    if (!ok && env.WHSK_SECRET_TEST) {
      ok = matchHex(await hmacHex(t + '.' + raw, env.WHSK_SECRET_TEST), te) ||
           matchHex(await hmacHex(t + '.' + raw, env.WHSK_SECRET_TEST), li);
    }
    if (!ok) {
      return new Response('bad signature', { status: 401 });
    }

    // --- forward to Apps Script with our own HMAC proof ---
    const proof = await hmacHex(t + '.' + raw, env.RELAY_SECRET);
    const fwd = env.GAS_EXEC_URL +
      '?pmsig=1&t=' + encodeURIComponent(t) + '&proof=' + proof;
    try {
      await fetch(fwd, {
        method: 'POST',
        body: raw,
        headers: { 'Content-Type': 'application/json' },
      });
    } catch (e) {
      // GAS unreachable — answer 200 anyway to stop PayMongo's retry storm;
      // the payment event can be recovered from PayMongo's delivery log.
    }
    return new Response('ok', { status: 200 });
  },
};

async function hmacHex(data, secret) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(data));
  return [...new Uint8Array(sig)]
    .map(function (b) { return b.toString(16).padStart(2, '0'); }).join('');
}

function matchHex(a, b) {
  if (typeof b !== 'string' || b.length !== 64 || a.length !== b.length) return false;
  const bb = b.toLowerCase();
  let d = 0;
  for (let i = 0; i < 64; i++) d |= a.charCodeAt(i) ^ bb.charCodeAt(i);
  return d === 0;
}
