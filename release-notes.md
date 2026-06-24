# Mimic v1.3.1

## New features
- **Notes — Search:** find notes instantly (matches title and body).
- **Notes — Markdown editor:** formatting toolbar (bold, italic, headings, bullets,
  checklists, code) with a live preview toggle.
- **Notes — Auto-save:** "Saving…/Saved" status and automatic save when you leave or
  background the app.
- **Documents — Search & sort:** search and sort by date, name, size, or type.
- **Documents — Folders:** organize into folders, filter by folder, and move documents
  between folders.
- **Documents — Share / export:** send any document out via the system share sheet.
- **Accessibility:** high-contrast editor palette (white background, bolder text) for easier
  reading and typing.

## Fixes
- Changing your PIN no longer makes existing photos/videos unrecoverable (vault data key is
  preserved and re-wrapped under the new PIN).
- Opening a document no longer re-encrypts it (read-only access).
- "End Game" now returns correctly to the home screen.

## Security
- Shared/exported files are decrypted only to a temporary location and wiped immediately after
  sharing — no plaintext left behind.