# Lingora for iPhone

A calm, low-pressure language-learning app. ChatGPT builds a weekly plan for every language you study, adapts each day's tasks to how you're doing, and plays a roleplay tutor. You can learn any number of languages at once, and learn with friends.

This is a native SwiftUI app built from the "Lingora v2" design handoff (Soft cards direction, sage accent).

## Run it

1. Open `Lingora.xcodeproj` in **Xcode 16 or later**.
2. Select the **Lingora** target → *Signing & Capabilities* → pick your Team.
3. Choose an iPhone simulator or your device and press **Run**.

Requirements: iOS 17+, iPhone only (portrait).

> **Sign in with Apple** needs a paid Apple Developer team. With a free personal team, delete `Config/Lingora.entitlements` from *Code Signing Entitlements* in Build Settings; Apple sign-in will then show an error, and email or ChatGPT sign-in still work.

## ChatGPT / OpenAI

"Sign in with ChatGPT" is a limited OpenAI preview, so this build connects with an **OpenAI API key**:

- *Continue with ChatGPT* on the welcome screen, *Connect ChatGPT account* in setup, or **Me → ChatGPT → Connect**.
- The key is checked against `GET /v1/models`, then stored in the iOS Keychain.
- Model defaults to `gpt-5-mini` and can be changed in **Me → Model**.

With a key, these run through the Chat Completions API using strict JSON-schema Structured Outputs (`Lingora/Services/OpenAIService.swift`):

| Feature | When |
|---|---|
| Weekly plan per language | "Build my plans", "Redo", "Ask ChatGPT to re-plan" |
| Daily adaptation | Once a day on Today (pull to refresh), from your recent lesson scores |
| Lesson content | Opening a non-roleplay task (flashcard, gap fill, writing) |
| Writing check | "Check my answer" |
| Tutor replies + corrections + suggestions | Every message in Tutor |
| Private corrections in friend chats | Every message you send to a friend |

Without a key, or if a request fails, the app falls back to the prototype's built-in content, so everything still works offline.

> ⚠️ Calling OpenAI from the device with a user-supplied key is fine for testing. Before the App Store, move these calls behind your own backend (same JSON schemas) so no key lives on device.

## What's real and what's sample data

- **Real:** Sign in with Apple, local email account (validation per spec), OpenAI features above, Keychain, on-device persistence (`Application Support/lingora-state.json`), daily reminder notifications (19:00), text-to-speech "Listen", QR code generation, share/copy invite link, haptics, Dynamic Type via Figtree with `relativeTo:`.
- **Sample data (needs a backend):** friends, activity feed, leaderboard, nudges, challenges, shared plans, and friends' chat replies. The design suggests Supabase or Firebase plus APNs.

## Project layout

```
Lingora/
  App/            App entry, root view, tab bar
  Design/         Theme (OKLCH colour recipe, tokens), shared components
  Model/          Codable models, sample data from the prototype, AppModel (state + actions)
  Services/       OpenAIService, Keychain
  Screens/
    Onboarding/   Welcome, Email, Connect ChatGPT, Languages, Levels & goals
    Main/         Plan, Today, Lesson, Tutor, Friends + friend chat, Me
    Sheets/       ChatGPT sign-in/connect, Add friends
  Resources/Fonts Figtree 400/500/600/700 (SIL OFL)
Config/           Entitlements
```

The project uses Xcode 16 synchronized folders: any file you add under `Lingora/` is picked up automatically.

## Design notes

- Colours follow the handoff recipe: base `oklch(0.58 0.07 H)`, deep `oklch(0.40 0.06 H)`, tint `oklch(0.94 0.03 H)`, converted to sRGB at runtime (`Color.oklch`).
- Me → Appearance switches accent (sage, dusty blue, soft terracotta, muted lavender), style (Soft cards / Open) and per-language colours, matching the prototype's Tweaks panel.
- Not yet built: iPad/Mac split-view layouts and Android (see the design handoff README).
