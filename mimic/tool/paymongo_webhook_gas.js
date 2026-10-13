/**
 * Mimic License + PayMongo Webhook — v2.1.0 (Phase-5 hardening + relay)
 *
 * Fixes implemented (SECURITY_AUDIT_PHASE5 §4 tasks 1, 2, 6, 9):
 *   LIC-01  PayMongo verification via a Cloudflare relay (see below)
 *   LIC-06  Idempotency (Payment-ID dedupe under LockService), livemode gate,
 *           amount ≥ 9900, key NEVER returned in the HTTP response
 *   LIC-07  Email-quota defense: MailApp.getRemainingDailyQuota() + a Pending
 *           Emails queue drained by the daily processPendingEmails() trigger
 *   LIC-04  deviceId format validation + per-key activation rate limits
 *   LIC-08  CSPRNG nonce via Utilities.getUuid()
 *   LIC-02  Secrets come from Script Properties ONLY — no hardcoded fallbacks
 *
 * WHY A RELAY: Google Apps Script does NOT expose HTTP request headers to
 * doPost() (proved empirically 2026-10-12: e.headers === undefined), and
 * PayMongo signs webhooks ONLY via the Paymongo-Signature header. A tiny
 * Cloudflare Worker (see paymongo_signature_relay_worker.js) verifies the
 * real PayMongo signature in front of this script and forwards each verified
 * event with proof = HMAC-SHA256(t + "." + rawBody, RELAY_SECRET) as query
 * params. This script re-verifies that proof over its own copy of the body —
 * so even a leaked GAS URL is useless without RELAY_SECRET.
 *
 * ONE-TIME SETUP (Project Settings > Script Properties):
 *   LICENSE_SECRET           license HMAC secret (must match the app's
 *                            --dart-define=MIMIC_LICENSE_SECRET)
 *   RELAY_SECRET             shared with the Cloudflare Worker (its own secret)
 *   EXPECTED_LIVEMODE        'true' for the production endpoint, 'false' for a
 *                            test-mode endpoint (decision Q4: one endpoint + switch)
 * ALSO: create empty 'Log' and 'Pending Emails' sheets, and add a daily
 * time-driven trigger running processPendingEmails().
 * NOTE: Apps Script always returns HTTP 200 — the JSON 'status' field is the
 * only feedback channel, so every branch returns an explicit status.
 */

const CONFIG = {
  LICENSE_SECRET: PropertiesService.getScriptProperties().getProperty('LICENSE_SECRET'),
  RELAY_SECRET: PropertiesService.getScriptProperties().getProperty('RELAY_SECRET'),
  EXPECTED_LIVEMODE: PropertiesService.getScriptProperties().getProperty('EXPECTED_LIVEMODE'),
  MAX_DEVICES_PER_KEY: 2,
  EMAIL_SUBJECT: '⭐ Your Mimic Pro Lifetime Activation Code',
  SUPPORT_EMAIL: 'support@mimic-app.com',
  MIN_AMOUNT_CENTAVOS: 9900,
  SIG_TOLERANCE_SECONDS: 300,
};

function doGet() {
  return jsonResponse({
    status: 'online',
    service: 'Mimic License Activation Webhook',
    version: '2.1.0',
    // Health booleans only — never expose a secret value.
    licenseSecretConfigured: !!CONFIG.LICENSE_SECRET,
    relaySecretConfigured: !!CONFIG.RELAY_SECRET,
    expectedLivemode: CONFIG.EXPECTED_LIVEMODE || null,
  });
}

function doPost(e) {
  try {
    const raw = (e && e.postData && e.postData.contents) || '';
    let payload = null;
    try { payload = JSON.parse(raw); } catch (_) { return jsonResponse({ status: 'malformed' }); }

    const isEvent = !!(payload && payload.data && payload.data.attributes &&
                       payload.data.attributes.type);
    if (isEvent) {
      // LIC-01 (v2.1.0): Apps Script cannot see request headers (proved
      // 2026-10-12), so a Cloudflare relay verifies PayMongo's
      // Paymongo-Signature header and forwards proof =
      // HMAC-SHA256(t + "." + rawBody, RELAY_SECRET) as query params.
      // This script verifies that proof over its own copy of the body.
      const sig = verifyRelayProof_(e, raw);
      if (!sig.ok) {
        logEvent_('REJECTED', 'relay proof: ' + sig.reason);
        return jsonResponse({ status: 'rejected' });       // generic body — no detail for attackers
      }
      return handlePaymentEvent_(payload);
    }

    if (payload && payload.action === 'activate') return handleActivate_(payload);

    return jsonResponse({ status: 'event_ignored' });
  } catch (err) {
    logEvent_('ERROR', String(err));
    return jsonResponse({ status: 'error' });
  }
}

/**
 * LIC-01 via relay proof: the Cloudflare worker (see
 * paymongo_signature_relay_worker.js) already checked PayMongo's signature;
 * it forwards proof = HMAC-SHA256(t + "." + rawBody, RELAY_SECRET) + the
 * timestamp t as query params. We re-verify the proof over our own body copy
 * (so a leaked GAS URL is still useless without RELAY_SECRET) and re-check
 * the ±300 s replay window.
 */
function verifyRelayProof_(e, rawBody) {
  const secret = PropertiesService.getScriptProperties().getProperty('RELAY_SECRET');
  if (!secret) return { ok: false, reason: 'RELAY_SECRET_NOT_CONFIGURED' };   // fail closed

  const params = (e && e.parameter) || {};
  if (params.pmsig !== '1') return { ok: false, reason: 'NO_RELAY_PROOF' };

  const t = params.t || '';
  const proof = params.proof || '';
  if (!t || !/^[0-9a-f]{64}$/i.test(proof)) return { ok: false, reason: 'MALFORMED_PROOF' };

  const nowSec = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSec - Number(t)) > CONFIG.SIG_TOLERANCE_SECONDS) {
    return { ok: false, reason: 'STALE_TIMESTAMP' };                          // replay window
  }

  const macBytes = Utilities.computeHmacSha256Signature(t + '.' + rawBody, secret);
  const expected = macBytes.map(function (b) {
    return ('0' + (b & 0xFF).toString(16)).slice(-2);
  }).join('');

  return constantTimeHexEqual_(expected, proof)
    ? { ok: true }
    : { ok: false, reason: 'BAD_PROOF' };
}

function constantTimeHexEqual_(expected, provided) {
  if (!/^[0-9a-f]{64}$/i.test(provided)) return false;
  const b = provided.toLowerCase();
  let diff = 0;
  for (let i = 0; i < 64; i++) diff |= expected.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
function handlePaymentEvent_(payload) {
  const attrs = payload.data.attributes || {};
  const type = attrs.type;

  // ---- livemode gate (Q4: EXPECTED_LIVEMODE switch on a single endpoint) ----
  const expected = (CONFIG.EXPECTED_LIVEMODE || '').toLowerCase();
  if (expected !== 'true' && expected !== 'false') {
    logEvent_('ERROR', 'EXPECTED_LIVEMODE not configured — event skipped: ' + (payload.data.id || '?'));
    return jsonResponse({ status: 'misconfigured' });        // fail closed: never mint blind
  }
  const livemode = attrs.livemode === true;
  if (String(livemode) !== expected) {
    logEvent_('IGNORED', 'livemode mismatch: got ' + livemode + ' expected ' + expected);
    return jsonResponse({ status: 'ignored_livemode' });
  }

  if (type !== 'payment.paid' && type !== 'checkout_session.payment.paid') {
    return jsonResponse({ status: 'event_ignored', type: type });
  }

  // ---- amount + currency gate (LIC-06) ----
  const payment = attrs.data || {};
  const pa = payment.attributes || {};
  const paymentId = payment.id || '';
  const amount = Number(pa.amount || 0);
  const currency = pa.currency || '';
  if (amount < CONFIG.MIN_AMOUNT_CENTAVOS || currency !== 'PHP') {
    logEvent_('IGNORED', 'amount/currency ' + amount + ' ' + currency + ' evt=' + (payload.data.id || '?'));
    return jsonResponse({ status: 'ignored_amount' });
  }

  const billing = pa.billing || {};
  const customerEmail = billing.email || pa.customer_email || pa.email;
  if (!customerEmail) {
    logEvent_('IGNORED', 'no email evt=' + (payload.data.id || '?'));
    return jsonResponse({ status: 'ignored_no_email' });
  }

  const secret = CONFIG.LICENSE_SECRET;
  if (!secret) {
    logEvent_('ERROR', 'LICENSE_SECRET not configured — event NOT minted: ' + (payload.data.id || '?'));
    return jsonResponse({ status: 'misconfigured' });        // LIC-02 fail closed
  }

  const customerName = billing.name || 'Valued Supporter';
  const eventId = payload.data.id || '';

  const lock = LockService.getScriptLock();
  try {
    if (!lock.tryLock(15000)) return jsonResponse({ status: 'busy' });

    // ---- idempotency (LIC-06): dedupe on the payment ID, under the lock ----
    if (paymentId && findPaymentId_(paymentId)) {
      logEvent_('IGNORED', 'duplicate payment ' + paymentId);
      return jsonResponse({ status: 'ignored_duplicate' });
    }

    const licenseKey = generateMimicLicenseKey(0x01, secret);
    logNewLicenseToSheet(customerEmail, customerName, licenseKey,
      (amount / 100).toFixed(2), currency, paymentId, eventId);
    sendLicenseEmailSafely_(customerEmail, customerName, licenseKey);  // never fails the webhook

    return jsonResponse({ status: 'received' });   // LIC-01/06: NO key, NO email in the response
  } finally {
    lock.releaseLock();
  }
}
const VALID_DEVICE_ID_ = /^(android-[0-9a-f]{16,64}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;
const VALID_KEY_ = /^MIMIC-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/;

function handleActivate_(payload) {
  const key = String(payload.key || '').trim().toUpperCase();
  const deviceId = String(payload.deviceId || '').trim();

  if (!key || !deviceId) {
    return jsonResponse({ success: false, error: 'MISSING_PARAMS', message: 'Key and device ID are required.' });
  }
  if (!VALID_KEY_.test(key)) {
    return jsonResponse({ success: false, error: 'INVALID_SIGNATURE', message: 'Invalid or unrecognized activation code.' });
  }
  if (!VALID_DEVICE_ID_.test(deviceId)) {                    // LIC-04 layer 1: format validation
    logEvent_('REJECTED', 'malformed deviceId for key ' + key);
    return jsonResponse({ success: false, error: 'INVALID_DEVICE_ID', message: 'Invalid device identifier.' });
  }
  if (!checkRateLimit_('act:' + key, 10, 3600)) {            // LIC-04 layer 2: 10 attempts/key/hour
    logEvent_('REJECTED', 'rate limited for key ' + key);
    return jsonResponse({ success: false, error: 'RATE_LIMITED', message: 'Too many activation attempts. Please try again later.' });
  }

  const secret = CONFIG.LICENSE_SECRET;
  if (!secret) {
    logEvent_('ERROR', 'LICENSE_SECRET not configured');
    return jsonResponse({ success: false, error: 'SERVER_ERROR', message: 'Activation service unavailable.' });
  }
  if (!verifyKeySignature(key, secret)) {
    return jsonResponse({ success: false, error: 'INVALID_SIGNATURE', message: 'Invalid or unrecognized activation code.' });
  }

  const lock = LockService.getScriptLock();
  try {
    if (!lock.tryLock(10000)) {
      return jsonResponse({ success: false, error: 'BUSY', message: 'Server busy, please try again.' });
    }
    return jsonResponse(registerDeviceForKey(key, deviceId));
  } finally {
    lock.releaseLock();
  }
}
// ---- Shared helpers -------------------------------------------------------

/** Sliding-window rate limiter backed by the shared script cache (LIC-04). */
function checkRateLimit_(cacheKey, maxHits, windowSeconds) {
  const cache = CacheService.getScriptCache();
  const raw = cache.get(cacheKey);
  const n = raw ? Number(raw) + 1 : 1;
  cache.put(cacheKey, String(n), windowSeconds);   // GAS caps TTL at 6 h
  return n <= maxHits;
}

/** True when this payment already minted a key (LIC-06 idempotency). */
function findPaymentId_(paymentId) {
  const data = getOrCreateSheet().getDataRange().getValues();
  const col = data[0].indexOf('Payment ID');
  if (col < 0) return false;
  for (let r = 1; r < data.length; r++) {
    if (String(data[r][col]) === paymentId) return true;
  }
  return false;
}

/** Apps Script always answers HTTP 200 — this Log sheet IS our observability. */
function logEvent_(level, message) {
  try {
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = ss.getSheetByName('Log') || ss.insertSheet('Log');
    if (sheet.getLastRow() === 0) sheet.appendRow(['timestamp', 'level', 'message']);
    sheet.appendRow([new Date(), level, String(message).substring(0, 500)]);
  } catch (_) { /* logging must never break the response */ }
}

/**
 * LIC-07: quota-aware sending. If MailApp is exhausted (or errors), the key
 * is queued to the 'Pending Emails' sheet instead of failing the webhook.
 */
function sendLicenseEmailSafely_(email, name, key) {
  try {
    if (MailApp.getRemainingDailyQuota() <= 0) { enqueueEmail_(email, name, key); return; }
    sendLicenseEmail(email, name, key);
  } catch (err) {
    logEvent_('ERROR', 'email failed, queued: ' + err);
    try { enqueueEmail_(email, name, key); } catch (_) {}
  }
}

function enqueueEmail_(email, name, key) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = ss.getSheetByName('Pending Emails') || ss.insertSheet('Pending Emails');
  if (sheet.getLastRow() === 0) sheet.appendRow(['queuedAt', 'to', 'name', 'licenseKey']);
  sheet.appendRow([new Date(), email, name, key]);
  logEvent_('DEFERRED', 'license email queued for ' + email);
}

/** Daily time-driven trigger: drain Pending Emails up to the remaining quota.
 *  Verbose by design (synced from the live deployment 2026-10-13): every
 *  decision is written to the Log sheet, because this ran twice as the
 *  decisive diagnostic during the fix day (wrong-tab lookup; quota exhaustion).
 *  Also matches the queue tab forgivingly (trimmed, case-insensitive) so a
 *  stray space in a tab name can never silently defeat the drain again. */
function processPendingEmails() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const all = ss.getSheets().map(function (s) { return s.getName(); });
  logEvent_('INFO', 'drain-start; tabs=[' + all.join(' | ') + ']');

  let sheet = null;
  ss.getSheets().forEach(function (s) {
    if (s.getName().trim().toLowerCase() === 'pending emails') sheet = s;
  });
  if (!sheet) {
    logEvent_('ERROR', 'drain-abort: no tab named Pending Emails found');
    return;
  }
  if (sheet.getLastRow() < 2) {
    logEvent_('INFO', 'drain-abort: tab "' + sheet.getName() + '" looks empty (lastRow=' + sheet.getLastRow() + ')');
    return;
  }

  const data = sheet.getDataRange().getValues();
  logEvent_('INFO', 'drain: found ' + (data.length - 1) + ' queued row(s) in "' + sheet.getName() + '"');

  let sent = 0;
  for (let r = 1; r < data.length; r++) {
    let quota = -1;
    try { quota = MailApp.getRemainingDailyQuota(); } catch (err) {
      logEvent_('ERROR', 'drain-abort: no mail permission (' + err + ')');
      return;
    }
    if (quota <= 0) { logEvent_('ERROR', 'drain-paused: daily quota exhausted'); break; }
    const to = String(data[r][1] || '').trim();
    const name = data[r][2];
    const key = String(data[r][3] || '').trim();
    if (!to || !key) {
      logEvent_('INFO', 'drain: deleting malformed row ' + (r + 1));
      sheet.deleteRow(r + 1); r--; continue;
    }
    try {
      sendLicenseEmail(to, name, key);
      sheet.deleteRow(r + 1);
      r--; sent++;
      logEvent_('INFO', 'drain: sent to ' + to);
    } catch (err) {
      logEvent_('ERROR', 'drain: FAILED for ' + to + ': ' + err);
      break;
    }
  }
  logEvent_('INFO', 'drain-done: sent ' + sent);
}

function registerDeviceForKey(licenseKey, deviceId) {
  const sheet = getOrCreateSheet();
  const data = sheet.getDataRange().getValues();
  
  const header = data[0];
  const keyCol = header.indexOf('License Key');
  const devicesCol = header.indexOf('Activated Devices');
  const countCol = header.indexOf('Device Count');
  
  let targetRowIndex = -1;
  let currentDevices = [];
  
  for (let r = 1; r < data.length; r++) {
    if (data[r][keyCol] === licenseKey) {
      targetRowIndex = r + 1;
      const devicesStr = String(data[r][devicesCol] || '');
      currentDevices = devicesStr ? devicesStr.split(',').map(s => s.trim()).filter(s => s.length > 0) : [];
      break;
    }
  }
  
  if (targetRowIndex !== -1) {
    if (currentDevices.indexOf(deviceId) !== -1) {
      return { success: true, message: 'Device verified (already registered)', count: currentDevices.length };
    }
    
    if (currentDevices.length >= CONFIG.MAX_DEVICES_PER_KEY) {
      return { 
        success: false, 
        error: 'DEVICE_LIMIT_REACHED', 
        message: `This activation code has already reached its limit of ${CONFIG.MAX_DEVICES_PER_KEY} devices.` 
      };
    }
    
    currentDevices.push(deviceId);
    sheet.getRange(targetRowIndex, devicesCol + 1).setValue(currentDevices.join(', '));
    sheet.getRange(targetRowIndex, countCol + 1).setValue(currentDevices.length);
    
    return { success: true, message: 'Device registered successfully', count: currentDevices.length };
  }
  
  currentDevices = [deviceId];
  sheet.appendRow([
    new Date(),
    'Direct/CLI Issued',
    'User',
    licenseKey,
    '99.00',
    'PHP',
    'CLI-MANUAL',
    currentDevices.join(', '),
    1
  ]);
  
  return { success: true, message: 'Key registered and device activated', count: 1 };
}

function verifyKeySignature(rawKey, secret) {
  if (!secret) return false;   // LIC-02: never "verify" against an empty secret
  let clean = rawKey.replace(/^MIMIC-/, '').replace(/^MIMIC/, '').replace(/[^0-9A-F]/g, '');
  if (clean.length !== 16) return false;
  
  const bytes = [];
  for (let i = 0; i < 16; i += 2) {
    bytes.push(parseInt(clean.substring(i, i + 2), 16));
  }
  
  const payloadBytes = bytes.slice(0, 4);
  const providedTag = bytes.slice(4, 8);
  
  const payloadHex = payloadBytes.map(b => ('0' + (b & 0xFF).toString(16)).slice(-2)).join('');
  const signatureBytes = Utilities.computeHmacSha256Signature(payloadHex, secret);
  const expectedTag = signatureBytes.slice(0, 4);
  
  let diff = 0;
  for (let i = 0; i < 4; i++) {
    diff |= (providedTag[i] ^ (expectedTag[i] & 0xFF));
  }
  return diff === 0;
}

function generateMimicLicenseKey(typeCode, secret) {
  // LIC-08: CSPRNG nonce (Utilities.getUuid, OS-backed) instead of Math.random().
  // Key format unchanged: 1 type byte + 3 nonce bytes + 4-byte HMAC tag.
  const nonceHex = Utilities.getUuid().replace(/-/g, '').substring(0, 6);
  const payloadHex = ('0' + (typeCode & 0xFF).toString(16)).slice(-2) + nonceHex;
  const signatureBytes = Utilities.computeHmacSha256Signature(payloadHex, secret);
  const tagHex = signatureBytes.slice(0, 4).map(function (b) {
    return ('0' + (b & 0xFF).toString(16)).slice(-2);
  }).join('');
  const all = (payloadHex + tagHex).toUpperCase();
  return `MIMIC-${all.substring(0, 4)}-${all.substring(4, 8)}-${all.substring(8, 12)}-${all.substring(12, 16)}`;
}

function getOrCreateSheet() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  if (sheet.getLastRow() === 0) {
    sheet.appendRow([
      'Timestamp',
      'Customer Email',
      'Customer Name',
      'License Key',
      'Amount',
      'Currency',
      'Payment ID',
      'Activated Devices',
      'Device Count',
      'Event ID',
    ]);
  } else if (sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].indexOf('Event ID') < 0) {
    sheet.getRange(1, sheet.getLastColumn() + 1).setValue('Event ID');   // migrate older sheets
  }
  return sheet;
}

function logNewLicenseToSheet(email, name, key, amount, currency, paymentId, eventId) {
  const sheet = getOrCreateSheet();
  sheet.appendRow([
    new Date(),
    email,
    name,
    key,
    amount,
    currency,
    paymentId,
    '',
    0,
    eventId || '',
  ]);
}

function sendLicenseEmail(email, name, licenseKey) {
  const bodyText = `Hi ${name},

Thank you for upgrading to Mimic Pro! Your support directly fuels independent privacy tools built without ads, subscriptions, or telemetry.

Here is your permanent Lifetime Pro Activation Code:

====================================
${licenseKey}
====================================
(Valid for up to ${CONFIG.MAX_DEVICES_PER_KEY} of your personal devices)

HOW TO ACTIVATE IN MIMIC:
1. Open the Mimic app on your phone.
2. Tap Settings (gear icon in the vault) or open the Pro Paywall.
3. Tap "Redeem Activation Code".
4. Paste your code: ${licenseKey}
5. Tap "Activate Pro".

Once redeemed, Pro is unlocked offline forever on your device—no internet or account required!

If you ever need assistance, reply directly to this email.

Warm regards,
The Mimic Team
`;

  MailApp.sendEmail({
    to: email,
    replyTo: CONFIG.SUPPORT_EMAIL,
    subject: CONFIG.EMAIL_SUBJECT,
    body: bodyText,
  });
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
