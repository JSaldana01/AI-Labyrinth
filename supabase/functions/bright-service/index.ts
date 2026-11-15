import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { withSupabase } from "jsr:@supabase/server@^1";
import {
  attemptGeminiMaze,
  buildGeminiPrompt,
  localDfsDefinition,
  postProcessDefinition,
  type GeminiAttemptReport,
  type MazeDefinition,
  type MazeGenerationProfile,
} from "../_shared/maze.ts";

interface GenerateMazeRequest {
  profile_slug?: string;
  seed_hint?: string;
  persist?: boolean;
  use_local_only?: boolean;
  width?: number;
  height?: number;
}

const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.5-flash-lite";

console.info("bright-service (maze) started");

async function loadProfile(
  supabaseAdmin: ReturnType<typeof createClient>,
  slug: string,
): Promise<{ id: string; profile: MazeGenerationProfile } | null> {
  const { data, error } = await supabaseAdmin
    .from("maze_generation_profiles")
    .select("id, profile")
    .eq("slug", slug)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    console.error("profile load error", error);
    return null;
  }
  if (!data) return null;
  return { id: data.id as string, profile: data.profile as MazeGenerationProfile };
}

function hashPrompt(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  }
  return h.toString(16);
}

function resolveProfile(
  stored: MazeGenerationProfile,
  body: GenerateMazeRequest,
): MazeGenerationProfile {
  const w = body.width ?? stored.width;
  const h = body.height ?? stored.height;
  return {
    ...stored,
    width: w,
    height: h,
    spawn: stored.spawn ?? [0, 0],
    exit: stored.exit ?? [w - 1, h - 1],
  };
}

/** Lets guests generate when profile rows were never seeded. */
function profileFromRequest(body: GenerateMazeRequest): MazeGenerationProfile | null {
  const w = body.width;
  const h = body.height;
  if (w == null || h == null || w < 2 || h < 2) return null;
  return {
    width: w,
    height: h,
    spawn: [0, 0],
    exit: [w - 1, h - 1],
  };
}

export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      });
    }

    const requestId = crypto.randomUUID();
    let body: GenerateMazeRequest;
    try {
      body = await req.json();
    } catch {
      return Response.json({ error: "invalid json", request_id: requestId }, {
        status: 400,
      });
    }

    const profileSlug = body.profile_slug ?? "medium-6x6";
    const seedHint = body.seed_hint;

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey);

    const userId = ctx.user?.id ?? null;
    // Only signed-in users may persist; client may request persist but server enforces JWT.
    const shouldPersist = body.persist === true && userId != null;

    const loaded = await loadProfile(admin, profileSlug);
    let profileId: string | null = null;
    let profile: MazeGenerationProfile;

    if (loaded) {
      profileId = loaded.id;
      profile = resolveProfile(loaded.profile, body);
    } else {
      const synthetic = profileFromRequest(body);
      if (!synthetic) {
        return Response.json({
          error: "profile not found",
          request_id: requestId,
          hint: "Run maze profile seed migration or send width and height.",
        }, { status: 404 });
      }
      profile = synthetic;
      console.warn(
        `profile slug ${profileSlug} missing; using width=${profile.width} height=${profile.height}`,
      );
    }

    let definition: MazeDefinition | null = null;
    let generator: "gemini" | "local" = "local";
    let geminiAttempt: GeminiAttemptReport;

    if (body.use_local_only) {
      geminiAttempt = {
        attempted: false,
        success: false,
        model: GEMINI_MODEL,
        reason: "skipped_use_local_only",
        detail: "Request set use_local_only=true",
      };
    } else {
      const attempt = await attemptGeminiMaze(profile, {
        seedHint,
        model: GEMINI_MODEL,
      });
      geminiAttempt = attempt.report;
      if (attempt.definition) {
        definition = attempt.definition;
        generator = "gemini";
      }
    }

    if (!definition) {
      definition = localDfsDefinition(profile, seedHint);
      generator = "local";
    }

    definition = postProcessDefinition(definition, profile);

    const promptText = buildGeminiPrompt(profile, seedHint);
    let mazeInstanceId: string | null = null;

    if (shouldPersist) {
      const { data: inserted, error: insertError } = await admin
        .from("maze_instances")
        .insert({
          profile_id: profileId,
          created_by: userId,
          definition,
          generator,
          model: generator === "gemini" ? GEMINI_MODEL : null,
          prompt_hash: hashPrompt(promptText),
          status: "ready",
        })
        .select("id")
        .single();

      if (insertError) {
        console.error("insert maze_instances", insertError);
        return Response.json({
          error: "failed to persist maze",
          request_id: requestId,
        }, { status: 500 });
      }
      mazeInstanceId = inserted.id as string;
    }

    return Response.json({
      maze_instance_id: mazeInstanceId,
      definition,
      generator,
      gemini_attempt: geminiAttempt,
      request_id: requestId,
    });
  }),
};