/**
 * Pre-fills the shared translation cache so the vocab game works instantly.
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   export OPENAI_API_KEY=sk-...
 *   npm run seed -- sr-Latn A1        # language, optional level (A1 | A2 | B1)
 */
import { initializeApp } from "firebase-admin/app";
import { translateWords, vocab } from "../src/vocab";

async function main() {
  const [lang = "en", level] = process.argv.slice(2);
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new Error("Set OPENAI_API_KEY");
  initializeApp();
  const ids = [...vocab().values()].filter((w) => !level || w.level === level).map((w) => w.id);
  console.log(`Translating ${ids.length} words into ${lang}…`);
  for (let i = 0; i < ids.length; i += 40) {
    const { translations } = await translateWords(ids.slice(i, i + 40), lang, key, process.env.OPENAI_MODEL || "gpt-5-mini");
    console.log(`${Math.min(i + 40, ids.length)}/${ids.length}  (${Object.keys(translations).length} in batch)`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
