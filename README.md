# Reading Notes (MicroLog repurposed)

## Capture pipeline
1. **CaptureProvider** polls foreground app context (browser URL/title via Scripting Bridge for Safari/Chrome, Accessibility text, ScreenCaptureKit + Vision OCR fallback).
2. **CapturePolicy** enforces minimum read time (20s) and word count (150), deny/allow lists, and skips private windows.
3. **DedupeEngine** (pure, tested) runs URL canonicalization, content hash, SimHash, embedding similarity, and thread detection.
4. On a unique/related note, a row appears immediately in "Summarizing..." state; **Summarizer** (local LLM) fills title, summary, key points, "why it matters" and tags in the background.
5. Notes are stored with **SwiftData**.

## Permissions required
- Accessibility (read focused window text)
- Screen Recording (OCR fallback)
- Automation (Safari/Chrome scripting)
- Notifications (ambient pills)

## Privacy
All capture, OCR and summarization run on-device. No analytics, network calls or cloud APIs.
