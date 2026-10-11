const CONFIG = {
  LICENSE_SECRET: PropertiesService.getScriptProperties().getProperty('LICENSE_SECRET') || 'mimic_offline_pro_license_secret_2026_gc_v1',
  MAX_DEVICES_PER_KEY: 2,
  EMAIL_SUBJECT: '⭐ Your Mimic Pro Lifetime Activation Code',
  SUPPORT_EMAIL: 'support@mimic-app.com',
};

function doPost(e) {
  try {
    const postData = JSON.parse(e.postData.contents);
    
    if (postData.action === 'activate') {
      const key = (postData.key || '').trim().toUpperCase();
      const deviceId = (postData.deviceId || '').trim();
      
      if (!key || !deviceId) {
        return jsonResponse({ success: false, error: 'MISSING_PARAMS', message: 'Key and device ID are required.' });
      }
      
      if (!verifyKeySignature(key, CONFIG.LICENSE_SECRET)) {
        return jsonResponse({ success: false, error: 'INVALID_SIGNATURE', message: 'Invalid or unrecognized activation code.' });
      }
      
      const activationResult = registerDeviceForKey(key, deviceId);
      return jsonResponse(activationResult);
    }
    
    const eventType = postData.data?.attributes?.type;
    if (eventType === 'payment.paid' || eventType === 'checkout_session.payment.paid') {
      const paymentData = postData.data.attributes.data;
      const attributes = paymentData.attributes || {};
      
      const billing = attributes.billing || {};
      const customerEmail = billing.email || attributes.customer_email || attributes.email;
      const customerName = billing.name || 'Valued Supporter';
      const paymentId = paymentData.id || 'N/A';
      const amount = (attributes.amount ? attributes.amount / 100 : 99).toFixed(2);
      const currency = attributes.currency || 'PHP';
      
      if (!customerEmail) {
        return jsonResponse({ status: 'ignored_no_email' });
      }
      
      const licenseKey = generateMimicLicenseKey(0x01, CONFIG.LICENSE_SECRET);
      
      logNewLicenseToSheet(customerEmail, customerName, licenseKey, amount, currency, paymentId);
      sendLicenseEmail(customerEmail, customerName, licenseKey);
      
      return jsonResponse({ 
        status: 'success', 
        email: customerEmail, 
        key: licenseKey 
      });
    }
    
    return jsonResponse({ status: 'event_ignored', type: eventType });
      
  } catch (err) {
    return jsonResponse({ success: false, error: 'SERVER_ERROR', message: err.toString() });
  }
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
  let clean = rawKey.replace(/^MIMIC-/, '').replace(/^MIMIC/, '').replace(/[^0-9A-F]/g, '');
  if (clean.length !== 16) return false;
  
  const bytes = [];
  for (let i = 0; i < 16; i += 2) {
    bytes.push(parseInt(clean.substring(i, i + 2), 16));
  }
  
  const payloadBytes = bytes.slice(0, 4);
  const providedTag = bytes.slice(4, 8);
  
  const signatureBytes = Utilities.computeHmacSha256Signature(payloadBytes, secret);
  const expectedTag = signatureBytes.slice(0, 4);
  
  let diff = 0;
  for (let i = 0; i < 4; i++) {
    diff |= (providedTag[i] ^ (expectedTag[i] & 0xFF));
  }
  return diff === 0;
}

function generateMimicLicenseKey(typeCode, secret) {
  const nonceBytes = [];
  for (let i = 0; i < 3; i++) {
    nonceBytes.push(Math.floor(Math.random() * 256));
  }
  const payloadBytes = [typeCode, ...nonceBytes];
  const signatureBytes = Utilities.computeHmacSha256Signature(payloadBytes, secret);
  const tagBytes = signatureBytes.slice(0, 4);
  
  const allBytes = [...payloadBytes, ...tagBytes];
  const hex = allBytes.map(b => ('0' + (b & 0xFF).toString(16)).slice(-2).toUpperCase()).join('');
  return `MIMIC-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}`;
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
      'Device Count'
    ]);
  }
  return sheet;
}

function logNewLicenseToSheet(email, name, key, amount, currency, paymentId) {
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
    0
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
