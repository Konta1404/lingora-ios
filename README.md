# Lingora for iPhone

A calm, low-pressure language-learning app. ChatGPT builds a weekly plan for every language you study, adapts each day's tasks to how you're doing, and plays a roleplay tutor. It also has a **German vocabulary game** built on the Goethe-Institut A1 → A2 → B1 word lists.

```
Lingora/            iOS app (SwiftUI, iOS 17+)
backend/            Firebase: Cloud Functions (OpenAI proxy), Firestore rules
tools/vocab/        Scripts that built the German word list
tools/l10n/         Translations + script that builds Localizable.xcstrings
```

## What's new in this version

- **Accounts through Firebase Auth**: Apple, Google, OpenAI (OpenID Connect) and email/password, with password reset and account deletion.
- **Backend**: every ChatGPT feature runs in Cloud Functions. The OpenAI key is a server secret, not on the phone. Each user has a daily limit (300 calls by default).
- **Sync**: plans, progress and vocab progress are saved to Firestore, so they follow the user to a new phone.
- **German vocab game** (Today → *German words*, or Me):
  - Words appear in random order, never alphabetically.
  - Nouns: type the meaning, pick **der / die / das**, and give the **plural** (or tick *No plural*).
  - Verbs: type the meaning and the **Perfekt** (`hat gemacht`, `ist gefahren`).
  - The meaning is asked in **the phone's language**. ChatGPT translates the words once, caches them for all users, and checks answers that don't match exactly.
  - **No A2 word appears until every A1 word is mastered** (and the same for B1). A word is mastered after 3 right answers in a row, spread over at least two days.
- **Localization**: the whole UI is in English, Serbian/Montenegrin (Latin, ijekavian), German, Spanish, French, Italian, Portuguese (Brazil) and Russian. Dates, weekdays and language names follow the phone's locale. ChatGPT answers (plans, feedback, corrections, translations) come back in the user's language, whatever it is.

## 1. Run the app without a backend

Open `Lingora.xcodeproj` in Xcode 16.3 or later, pick your Team under *Signing & Capabilities*, and press Run.

Without `GoogleService-Info.plist` the app runs in **offline mode**:

- Email accounts stay on the device.
- Plans and lessons use the built-in content.
- In the vocab game you grade your own translations.

## 2. Set up Firebase (once)

1. Create a project at <https://console.firebase.google.com> and add an **iOS app** with bundle ID `com.veselin.lingora` (or whatever you set in Xcode).
2. Download **GoogleService-Info.plist** and drag it into the `Lingora/` folder in Xcode. It's git-ignored.
3. In Xcode → target **Lingora** → *Build Settings*, set **GOOGLE_REVERSED_CLIENT_ID** to the `REVERSED_CLIENT_ID` value from that plist. Google Sign-In needs it to return to the app.
4. Firebase console:
   - **Build → Firestore Database**: create a database (production mode, region `eur3` or `europe-west1`).
   - **Build → Authentication → Sign-in method**: enable **Email/Password**, **Google** and **Apple**.
   - Upgrade the project to the **Blaze** plan. Cloud Functions with secrets need it; light use stays inside the free tier.

## 3. Deploy the backend

```bash
npm install -g firebase-tools
cd backend
firebase login
firebase use --add                      # pick your project
firebase functions:secrets:set OPENAI_API_KEY   # paste your OpenAI key
cd functions && npm install && cd ..
firebase deploy --only functions,firestore
```

Optional settings, in `backend/functions/.env.<project-id>`:

```
OPENAI_MODEL=gpt-5-mini
DAILY_AI_LIMIT=300
```

### Optional: pre-translate the word list

The game translates words on the fly in small batches. To fill the cache ahead of time, for example for Serbian:

```bash
cd backend/functions
export GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/service-account.json   # Project settings → Service accounts
export OPENAI_API_KEY=sk-...
npm run seed -- sr-Latn A1
```

## 4. Sign-in providers

| Provider | What you need |
|---|---|
| Email | Nothing extra. |
| Google | Steps 2 and 3 above. |
| Apple | A **paid** Apple Developer account. In Xcode, *Signing & Capabilities* → **+ Capability → Sign in with Apple**. Free "Personal Team" accounts can't use it, so the button shows an error until then. |
| OpenAI | "Sign in with ChatGPT" is a limited OpenAI preview that requires approval. Once you have OpenID Connect client credentials from OpenAI, upgrade Firebase Auth to **Identity Platform** and add an **OpenID Connect** provider with the id `oidc.openai`. Until then, the button explains that it isn't available yet. |

## Data model (Firestore)

| Path | Who can access | Contents |
|---|---|---|
| `users/{uid}` | Owner only | `state` (plans, settings, chats as JSON), `name` |
| `users/{uid}/data/vocab` | Owner only | Vocab progress (box, due date, counts per word) |
| `vocabTranslations/{lang}/words/{wordId}` | Read: signed-in users. Write: functions only | Cached translations, shared by everyone |
| `usage/{uid}_{day}` | Functions only | Daily call counter |

## The German word list

`Lingora/Resources/vocab_de.json` has **2,692 words**:

| Level | Words |
|---|---|
| A1 | 655 |
| A2 | 575 (new after A1) |
| B1 | 1,462 (new after A2) |

How it was built (`tools/vocab/`):

- Headwords, plurals and verb forms come from the official Goethe-Institut PDFs.
- Example sentences come from the [goethe-institute-wordlist](https://github.com/ilkermeliksitki/goethe-institute-wordlist) TSVs.
- Missing plurals and genders are filled from [german-nouns](https://github.com/gambolputty/german-nouns) (Wiktionary, CC BY-SA 4.0).
- Missing Partizip II forms are filled from [german-verbs-dict](https://www.npmjs.com/package/german-verbs-dict) (Apache-2.0).
- Each word is placed in the lowest level it appears in.

A few dozen entries were resolved by rules, such as homonyms (`die Bank` → `Banken`) and adjectival nouns (`der/die Erwachsene`). Spot-check before relying on it for exam prep. The word lists themselves are © Goethe-Institut.

## Localization

- UI strings live in `tools/l10n/translations.tsv`, one row per English key, with columns sr-Latn, de, es, fr, it, pt-BR, ru.
- After you add or change a string, run `python3 tools/l10n/build_catalog.py`. It regenerates `Lingora/Localizable.xcstrings` and fails if any `L("…")` key in the code has no translation.
- To add a language, add a column, list it in `LANGS` in the script, and add it to the project's *Localizations* in Xcode.
