/**
 * Minimal OpenAI Chat Completions client using Structured Outputs (strict JSON schema).
 * The API key lives only here, as a Firebase secret — never on the phone.
 */

export type Schema = Record<string, unknown>;

export class AIError extends Error {
  constructor(message: string, readonly status = 500) {
    super(message);
  }
}

export async function complete<T>(opts: {
  apiKey: string;
  model: string;
  name: string;
  schema: Schema;
  system: string;
  user: string;
}): Promise<T> {
  const body: Record<string, unknown> = {
    model: opts.model,
    messages: [
      { role: "system", content: opts.system },
      { role: "user", content: opts.user },
    ],
    response_format: {
      type: "json_schema",
      json_schema: { name: opts.name, strict: true, schema: opts.schema },
    },
  };
  if (/^(gpt-5|o\d)/.test(opts.model)) body.reasoning_effort = "low";

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${opts.apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = (await res.json()) as {
    error?: { message: string };
    choices?: { message: { content?: string; refusal?: string } }[];
  };
  if (!res.ok) throw new AIError(json.error?.message ?? `OpenAI returned ${res.status}`, res.status);
  const msg = json.choices?.[0]?.message;
  if (!msg) throw new AIError("Empty response from OpenAI");
  if (msg.refusal) throw new AIError(msg.refusal, 400);
  return JSON.parse(msg.content ?? "{}") as T;
}

// ---- Schema helpers (strict mode: every property required, no extras) ----

export const obj = (props: Record<string, Schema>): Schema => ({
  type: "object",
  properties: props,
  required: Object.keys(props),
  additionalProperties: false,
});
export const str = (description: string): Schema => ({ type: "string", description });
export const int = (description: string): Schema => ({ type: "integer", description });
export const bool = (description = ""): Schema => ({ type: "boolean", description });
export const arr = (items: Schema, description = ""): Schema => ({ type: "array", items, description });

export const TASK_TYPES = ["vocabulary", "listening", "speaking", "reading", "writing", "grammar", "roleplay"];
export const taskSchema = (adapted: boolean): Schema =>
  obj({
    type: { type: "string", enum: TASK_TYPES },
    title: str("Short task title, written in the learner's interface language."),
    minutes: int("Minutes, 4-15."),
    ...(adapted ? { adapted: bool("True if this task was changed or added today.") } : {}),
  });
