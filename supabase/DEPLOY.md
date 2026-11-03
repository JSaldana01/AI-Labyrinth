# Supabase setup (cloud) for AI mazes

This project uses Edge Function slug **`bright-service`**:

`https://YOUR_PROJECT.supabase.co/functions/v1/bright-service`

The game sends:

```json
{ "profile_slug": "default-9x9", "persist": true }
```

and expects:

```json
{
  "definition": { ... },
  "generator": "gemini|local",
  "maze_instance_id": "...",
  "gemini_attempt": {
    "attempted": true,
    "success": false,
    "model": "gemini-3.5-flash-lite",
    "reason": "api_error|missing_api_key|validation_failed|...",
    "detail": "human-readable hint"
  }
}
```

The Godot **Output** panel logs `[Maze] Gemini: ...` from `gemini_attempt` when you redeploy the function.

If edge logs show **`validation_failed`** with many **`wall mismatch`** lines, the model returned inconsistent shared walls. **`bright-service`** now **repairs** output (pad to 9×9, sync neighbor walls) before accepting; redeploy after pulling latest `maze.ts`.

The old **5×5 matrix** demo (`{ "name": "..." }` → `{ "matrix": ... }`) is **not** compatible with the Godot client. Replace it with the code in `supabase/functions/bright-service/`.

---

## 1. Database

```bash
supabase link --project-ref gjtuyfvxdugxrdhtkrfl
supabase db push
```

Or run in SQL editor:

- `supabase/migrations/20261031120000_maze_generation.sql`
- `supabase/seed.sql`

---

## 2. Secrets

Dashboard → Edge Functions → Secrets (or CLI):

```bash
supabase secrets set GEMINI_API_KEY=your_google_ai_key
# Recommended for free tier (cheap, good for structured 9×9 JSON):
supabase secrets set GEMINI_MODEL=gemini-3.5-flash-lite
```

Default in code if unset: **`gemini-3.5-flash-lite`**.

**Why this model:** Flash-Lite is aimed at high volume / lower cost. A 9×9 maze prompt is small; output is bounded JSON. **New Google AI keys often cannot use `gemini-2.5-flash-lite` anymore** (API returns 404 — use `gemini-3.5-flash-lite` instead). Avoid **Pro**, **preview**, **TTS/image**, and **Deep Research** for this task. If `[Maze] Gemini: validation_failed` happens often, try **`gemini-3.5-flash`** or **`gemini-2.5-flash`** only if your key still lists them.

Do **not** log the API key in function code. Do **not** put `GEMINI_API_KEY` in the Godot `.env` (Edge secrets only).

---

## 2b. Which Gemini models can I use?

Google AI Studio’s dashboard often shows **API keys, billing, usage** — not a full model picker. Use one of these:

### List models (authoritative for your key)

Replace `YOUR_GEMINI_API_KEY` with the same key stored in Supabase secrets:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_GEMINI_API_KEY"
```

Look for `"name": "models/gemini-3.5-flash-lite"` (or similar). Set the secret to the **short id** only:

```bash
supabase secrets set GEMINI_MODEL=gemini-3.5-flash-lite
```

| Goal | Model id (from your list) |
|------|---------------------------|
| **Default — free tier, maze JSON (new keys)** | `gemini-3.5-flash-lite` |
| Slightly stronger Flash | `gemini-3.5-flash` |
| Legacy keys only | `gemini-2.5-flash-lite` (404 for many new accounts) |
| Avoid for mazes | `*-pro*`, `*-preview-tts*`, `*-image*`, `deep-research*`, `gemma-*` |

### Documentation

- Model reference: [https://ai.google.dev/gemini-api/docs/models](https://ai.google.dev/gemini-api/docs/models)
- API overview: [https://ai.google.dev/gemini-api/docs](https://ai.google.dev/gemini-api/docs)

### Try a prompt in the browser

Open [https://aistudio.google.com/](https://aistudio.google.com/) → **Chat** or **Build** (wording varies). The model name in the UI often matches the API id (e.g. “Gemini 3.5 Flash Lite” → `gemini-3.5-flash-lite`). If Chat is unavailable in your region, rely on the **List models** curl above.

### Wrong model symptom

`gemini_attempt.reason` = **`api_error`**, `http_status` = **404**, detail mentions **model not found** or **no longer available to new users** → set `GEMINI_MODEL=gemini-3.5-flash-lite` (or another id from list models), then redeploy:

```bash
supabase functions deploy bright-service
```

---

## 3. Deploy `bright-service` (replace matrix handler)

From repo root:

```bash
supabase functions deploy bright-service
```

This uploads `supabase/functions/bright-service/index.ts` and `_shared/maze.ts`.

Alternative name: deploy `generate-maze` instead and set in game `.env`:

```env
MAZE_EDGE_FUNCTION=generate-maze
```

---

## 4. Test

```bash
curl -s -X POST "https://gjtuyfvxdugxrdhtkrfl.supabase.co/functions/v1/bright-service" \
  -H "Authorization: Bearer YOUR_ANON_OR_USER_JWT" \
  -H "apikey: YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"profile_slug\":\"default-9x9\",\"persist\":true}"
```

If you get `"profile not found"`, run the seed migration.

If persist fails, check `maze_instances` exists and RLS allows service-role insert (edge uses service role).

---

## 5. Game `.env`

```env
SUPABASE_URL=https://gjtuyfvxdugxrdhtkrfl.supabase.co
SUPABASE_KEY=your_anon_key
# optional override:
# MAZE_EDGE_FUNCTION=bright-service
```

Rebuild or re-export after changing `.env`.
