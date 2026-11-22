/**
 * Lingora backend — Firebase Cloud Functions (2nd gen).
 *
 * Every function is a callable that requires a signed-in Firebase user (Apple, Google, OpenAI or email).
 * The OpenAI key is stored as the secret OPENAI_API_KEY:  firebase functions:secrets:set OPENAI_API_KEY
 */
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret, defineString, defineInt } from "firebase-functions/params";
import { setGlobalOptions } from "firebase-functions/v2";
import { complete, obj, str, arr, bool, int, taskSchema, AIError, TASK_TYPES } from "./openai";
import { translateWords as translate, checkTranslation as checkTr, vocab } from "./vocab";

initializeApp();
setGlobalOptions({ region: "europe-west1", maxInstances: 10 });

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const OPENAI_MODEL = defineString("OPENAI_MODEL", { default: "gpt-5-mini" });
const DAILY_LIMIT = defineInt("DAILY_AI_LIMIT", { default: 300 });

const TONE =
  "You are Lingora's language coach. Calm, encouraging, low-pressure. Never shame mistakes. " +
  "Respond only with JSON that matches the schema.";

// ---------- shared plumbing ----------

interface Lang { key: string; name: string; isCustom?: boolean }

const uiLang = (data: { uiLanguage?: string }) => String(data.uiLanguage || "en").slice(0, 20);
const inLang = (data: { uiLanguage?: string }) =>
  `Write every explanation, note, title and label in the learner's interface language (BCP-47: ${uiLang(data)}). ` +
  "Only text in the language being learned stays in that language.";

function clip(s: unknown, n = 400): string {
  return String(s ?? "").slice(0, n);
}

async function guard(req: CallableRequest<unknown>): Promise<string> {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to use ChatGPT features.");
  const day = new Date().toISOString().slice(0, 10);
  const ref = getFirestore().collection("usage").doc(`${uid}_${day}`);
  const count = await getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const n = ((snap.get("count") as number) ?? 0) + 1;
    tx.set(ref, { count: n, uid, day, at: FieldValue.serverTimestamp() }, { merge: true });
    return n;
  });
  if (count > DAILY_LIMIT.value()) {
    throw new HttpsError("resource-exhausted", "Daily ChatGPT limit reached. It resets tomorrow.");
  }
  return uid;
}

function callable<I, O>(handler: (data: I, key: string, model: string) => Promise<O>) {
  return onCall({ secrets: [OPENAI_API_KEY], timeoutSeconds: 120, memory: "256MiB" }, async (req) => {
    await guard(req);
    try {
      return await handler((req.data ?? {}) as I, OPENAI_API_KEY.value(), OPENAI_MODEL.value());
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      const msg = e instanceof Error ? e.message : String(e);
      console.error("AI call failed", msg);
      throw new HttpsError(e instanceof AIError && e.status === 429 ? "resource-exhausted" : "internal", msg);
    }
  });
}

const langLine = (l: Lang) => `${clip(l.name, 60)}${l.isCustom ? " (a language the learner typed in themselves)" : ""}`;

// ---------- plans ----------

export const weeklyPlan = callable<
  { language: Lang; level: string; goals: string[]; minutesPerDay: number; todayIndex: number; uiLanguage?: string },
  unknown
>(async (d, apiKey, model) =>
  complete({
    apiKey,
    model,
    name: "weekly_plan",
    schema: obj({
      rationale: str("2 sentences, addressed to the learner, explaining why the week looks like this."),
      days: arr(
        obj({ focus: str("Short focus label, e.g. 'Grammar & writing'."), tasks: arr(taskSchema(false), "1-3 tasks.") }),
        "Exactly 7 days, Monday first.",
      ),
    }),
    system: TONE,
    user:
      `Build a 7-day study plan (Monday first) for ${langLine(d.language)}.\n` +
      `Level: ${clip(d.level, 4)}. Goals: ${(d.goals ?? []).map((g) => clip(g, 40)).join(", ")}.\n` +
      `Time per day for this language: about ${Number(d.minutesPerDay) || 15} minutes in total, split into 1-3 tasks.\n` +
      `Today is day ${(Number(d.todayIndex) || 0) + 1} of the week. Mix ${TASK_TYPES.join(", ")}.\n` +
      `Task titles are short and concrete (e.g. "Ordering tapas in Madrid", "Ser vs. estar").\n${inLang(d)}`,
  }),
);

export const adaptToday = callable<
  {
    languages: { key: string; name: string; level: string; tasks: { type: string; title: string; minutes: number }[] }[];
    recent: { langKey: string; type: string; title: string; score: number }[];
    uiLanguage?: string;
  },
  unknown
>(async (d, apiKey, model) =>
  complete({
    apiKey,
    model,
    name: "daily_adaptation",
    schema: obj({
      note: str("One or two calm sentences explaining what changed today and why."),
      languages: arr(obj({ key: str("The language key exactly as given."), tasks: arr(taskSchema(true), "1-3 tasks.") })),
    }),
    system: TONE,
    user:
      "Adapt today's tasks to how the learner has been doing. Keep total minutes roughly the same. " +
      "Only change what the results justify; mark changed or added tasks with adapted=true.\nLanguages:\n" +
      (d.languages ?? [])
        .slice(0, 8)
        .map((l) => `- key ${clip(l.key, 40)}: ${clip(l.name, 60)} ${clip(l.level, 4)}. Planned: ` +
          (l.tasks ?? []).map((t) => `${t.type} '${clip(t.title, 80)}' ${t.minutes}m`).join("; "))
        .join("\n") +
      "\nRecent results (score out of 3):\n" +
      ((d.recent ?? []).slice(-12).map((r) => `${clip(r.langKey, 40)} ${r.type} '${clip(r.title, 80)}': ${r.score}/3`).join("\n") || "none yet") +
      `\n${inLang(d)}`,
  }),
);

// ---------- lessons ----------

export const lesson = callable<
  { language: Lang; level: string; task: { type: string; title: string; minutes: number }; uiLanguage?: string },
  unknown
>(async (d, apiKey, model) => {
  const name = clip(d.language?.name, 60);
  return complete({
    apiKey,
    model,
    name: "lesson",
    schema: obj({
      card: obj({
        front: str(`A word or short phrase in ${name}, native script.`),
        back: str("Its meaning in the learner's interface language."),
        example: str(`A short example sentence in ${name}.`),
      }),
      question: obj({
        prompt: str(`A gap-fill sentence in ${name} with ___ for the gap, or a short question.`),
        options: arr(str("Answer option."), "Exactly 4 options."),
        answer: int("0-based index of the correct option."),
        why: str("One-sentence explanation in the learner's interface language."),
      }),
      writing: obj({
        prompt: str("A short writing task in the learner's interface language, e.g. Translate: “…”."),
        modelAnswer: str(`A natural model answer in ${name}.`),
      }),
    }),
    system: TONE,
    user:
      `Create a 3-step micro-lesson for a ${clip(d.level, 4)} learner of ${langLine(d.language)}.\n` +
      `Task: ${clip(d.task?.type, 20)} — "${clip(d.task?.title, 120)}" (${Number(d.task?.minutes) || 6} min).\n` +
      "Step 1 flashcard, step 2 a 4-option gap fill with exactly one correct answer, step 3 a one-sentence writing task.\n" +
      inLang(d),
  });
});

export const checkWriting = callable<
  { language: Lang; prompt: string; modelAnswer: string; answer: string; uiLanguage?: string },
  unknown
>(async (d, apiKey, model) =>
  complete({
    apiKey,
    model,
    name: "writing_check",
    schema: obj({
      correct: bool(),
      feedback: str("1-2 kind sentences: what was good, what to fix."),
      modelAnswer: str(`The most natural version in ${clip(d.language?.name, 60)}, ideally close to the learner's wording.`),
    }),
    system: TONE,
    user:
      `Language: ${langLine(d.language)}. Task: ${clip(d.prompt)}\nReference answer: ${clip(d.modelAnswer)}\n` +
      `Learner wrote: ${clip(d.answer) || "(nothing)"}\n${inLang(d)}`,
  }),
);

// ---------- tutor & chat ----------

export const tutorTurn = callable<
  { language: Lang; level: string; scene: string; history: { role: string; text: string }[]; uiLanguage?: string },
  unknown
>(async (d, apiKey, model) => {
  const name = clip(d.language?.name, 60);
  const transcript = (d.history ?? [])
    .slice(-20)
    .filter((m) => m.role === "ai" || m.role === "me")
    .map((m) => `${m.role === "ai" ? "Tutor" : "Learner"}: ${clip(m.text, 500)}`)
    .join("\n");
  return complete({
    apiKey,
    model,
    name: "tutor_turn",
    schema: obj({
      hasCorrection: bool("True only if the learner's last message has a real mistake."),
      wrong: str("The exact wrong fragment from the learner's last message, or empty."),
      right: str("The corrected fragment, or empty."),
      note: str("One short explanation in the learner's interface language, or empty."),
      reply: str(`Your next in-character line in ${name}, suited to the learner's level.`),
      suggestions: arr(str(`A short reply the learner could send next, in ${name}.`), "Exactly 3."),
    }),
    system: TONE,
    user:
      `Roleplay scene: ${clip(d.scene, 120)}. You play the other person and stay in character in ${name}.\n` +
      `Learner level: ${clip(d.level, 4)}. Keep replies to one or two short sentences.\nConversation so far:\n${transcript}\n${inLang(d)}`,
  });
});

export const correctMessage = callable<{ language: Lang; message: string; uiLanguage?: string }, unknown>(
  async (d, apiKey, model) =>
    complete({
      apiKey,
      model,
      name: "correction",
      schema: obj({
        hasCorrection: bool(),
        wrong: str("Exact wrong fragment, or empty."),
        right: str("Corrected fragment, or empty."),
        note: str("One short explanation, or empty."),
      }),
      system: TONE,
      user:
        `The learner sent this ${clip(d.language?.name, 60)} message to a friend: "${clip(d.message, 500)}". ` +
        `Point out at most one real mistake. Ignore style and punctuation.\n${inLang(d)}`,
    }),
);

// ---------- German vocabulary ----------

export const translateWords = callable<{ ids: string[]; targetLanguage: string }, unknown>(async (d, apiKey, model) =>
  translate((d.ids ?? []).map(String), d.targetLanguage || "en", apiKey, model),
);

export const checkTranslation = callable<
  { id: string; answer: string; targetLanguage: string; accepted?: string[] },
  unknown
>(async (d, apiKey, model) => {
  if (!vocab().has(String(d.id))) throw new HttpsError("invalid-argument", "Unknown word.");
  return checkTr(String(d.id), clip(d.answer, 120), d.targetLanguage || "en", (d.accepted ?? []).map((a) => clip(a, 60)), apiKey, model);
});
