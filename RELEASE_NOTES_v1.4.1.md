## v1.4.1

### 🔐 Security & reliability
- **Fixed recovery-phrase confirmation re-entrancy.** Rapidly tapping "Confirm & Save" could crash the app and — more seriously — interleave the encrypted blob and salt writes, leaving the recovery phrase permanently undecryptable. The confirm and done actions are now guarded and the blob write is serialized.
- **PIN lockout (M3) verified on-device:** progressive escalation (30s → 60s → 5m → 15m → 30m → 60m), clock-tamper resistance (moving the system clock forward can't shorten a lockout), lockout persistence across reboot, duress PIN, and intruder-preserving reset on successful unlock.

### 🧪 Tests
- Added re-entrancy regression tests (exactly-once confirm + done). Full suite green at 228.

### 🐞 Known issues (tracked for next update)
- Unlock can feel laggy / slow cold start (PBKDF2 runs on the main thread).
- Intruder log not captured on the lockout that first requests camera permission.