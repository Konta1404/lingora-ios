import * as fs from "fs";
import * as path from "path";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { complete, obj, str, arr, bool } from "./openai";

export interface VocabWord {
  id: string;
  level: "A1" | "A2" | "B1";
  pos: "noun" | "verb" | "other";
  de: string;
  article?: string;
  plural?: string | null;
  perfekt?: string;
  example?: string;
  exampleEn?: string;
}

let cache: Map<string, VocabWord> | null = null;

export function vocab(): Map<string, VocabWord> {
  if (!cache) {
    const file = path.join(__dirname, "..", "..", "data", "vocab_de.json");
    const data = JSON.parse(fs.readFileSync(file, "utf8")) as { words: VocabWord[] };
    cache = new Map(data.words.map((w) => [w.id, w]));
  }
  return cache;
}

/** "sr-Latn-ME" → "sr-Latn", "en-US" → "en" (cache key per language/script). */
export function normalizeLang(tag: string): string {
  const parts = (tag || "en").replace("_", "-").split("-");
  const lang = parts[0].toLowerCase();
  const script = parts.find((p) => p.length === 4);
  return script ? `${lang}-${script[0].toUpperCase()}${script.slice(1).toLowerCase()}` : lang;
}

const describe = (w: VocabWord) =>
  `${w.id} | ${w.pos === "noun" ? `${w.article} ${w.de}` : w.de} (${w.pos})${w.example ? ` | e.g. "${w.example}"` : ""}`;

/**
 * Returns accepted translations for each word id in the target language.
 * Reads the shared Firestore cache first, translates the rest with OpenAI in one call, and stores them.
 */
export async function translateWords(ids: string[], lang: string, apiKey: string, model: string) {
  const db = getFirestore();
  const target = normalizeLang(lang);
  const words = ids.map((id) => vocab().get(id)).filter((w): w is VocabWord => !!w).slice(0, 40);
  const col = db.collection("vocabTranslations").doc(target).collection("words");

  const out: Record<string, string[]> = {};
  if (words.length === 0) return { language: target, translations: out };

  const snaps = await db.getAll(...words.map((w) => col.doc(w.id)));
  const missing: VocabWord[] = [];
  snaps.forEach((s, i) => {
    const t = s.get("t") as string[] | undefined;
    if (t?.length) out[words[i].id] = t;
    else missing.push(words[i]);
  });

  if (missing.length) {
    const result = await complete<{ items: { id: string; translations: string[] }[] }>({
      apiKey,
      model,
      name: "vocab_translations",
      schema: obj({
        items: arr(
          obj({
            id: str("The word id exactly as given."),
            translations: arr(str("A translation."), "1-4 common translations, most common first, lowercase unless a proper noun, no articles."),
          }),
        ),
      }),
      system:
        "You translate German learner vocabulary (Goethe-Institut A1-B1 lists) for a language-learning app. " +
        "Give the everyday meanings a learner at this level needs, matching the example sentence when one is given. " +
        "Translate verbs as infinitives. Respond only with JSON that matches the schema.",
      user: `Target language (BCP-47): ${target}\nWords:\n${missing.map(describe).join("\n")}`,
    });
    const batch = db.batch();
    for (const item of result.items) {
      if (!vocab().has(item.id) || !item.translations?.length) continue;
      const t = item.translations.map((x) => x.trim()).filter(Boolean).slice(0, 4);
      out[item.id] = t;
      batch.set(col.doc(item.id), { t, at: FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }
  return { language: target, translations: out };
}

export async function checkTranslation(id: string, answer: string, lang: string, accepted: string[], apiKey: string, model: string) {
  const w = vocab().get(id);
  if (!w) return { correct: false, note: "" };
  return complete<{ correct: boolean; note: string }>({
    apiKey,
    model,
    name: "translation_check",
    schema: obj({
      correct: bool("True if the learner's answer is an acceptable translation of the German word (synonyms and small typos are fine)."),
      note: str("One short sentence in the target language. Empty when correct."),
    }),
    system: "You check vocabulary answers in a language-learning app. Be fair and encouraging. Respond only with JSON.",
    user:
      `German: ${w.pos === "noun" ? `${w.article} ${w.de}` : w.de}${w.example ? ` (example: "${w.example}")` : ""}\n` +
      `Target language: ${normalizeLang(lang)}\nKnown translations: ${accepted.join(", ") || "(none)"}\nLearner answered: "${answer}"`,
  });
}
