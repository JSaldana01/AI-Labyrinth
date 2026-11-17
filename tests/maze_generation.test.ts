import {
  assert,
  assertEquals,
  assertExists,
} from "jsr:@std/assert@1";
import {
  attemptGeminiMaze,
  buildGeminiPrompt,
  completeMazeFromPath,
  DEFAULT_GEMINI_MODEL,
  dfsCarveMaze,
  emptyCells,
  hasPath,
  localDfsDefinition,
  seededRng,
  validateDefinition,
  validatePath,
  type MazeGenerationProfile,
} from "../supabase/functions/_shared/maze.ts";

const PROFILE_5X5: MazeGenerationProfile = {
  width: 5,
  height: 5,
  keys_required: 2,
  fork_min_open_sides: 3,
  spawn: [0, 0],
  exit: [4, 4],
};

Deno.test("DEFAULT_GEMINI_MODEL is gemini-3.5-flash-lite", () => {
  assertEquals(DEFAULT_GEMINI_MODEL, "gemini-3.5-flash-lite");
});

Deno.test("validatePath rejects out of bounds", () => {
  const r = validatePath(["W"], 5, 5);
  assert(!r.ok);
  assert(r.errors.length > 0);
});

Deno.test("validatePath accepts valid 5x5 spawn-to-exit route", () => {
  const path = ["E", "E", "E", "E", "N", "N", "N", "N"];
  const r = validatePath(path, 5, 5);
  assert(r.ok, r.errors.join("; "));
  assertEquals(r.errors.length, 0);
});

Deno.test("completeMazeFromPath returns null for invalid path", () => {
  const def = completeMazeFromPath(PROFILE_5X5, ["N"], "bad-path");
  assertEquals(def, null);
});

Deno.test("buildGeminiPrompt includes grid size and exit cell", () => {
  const prompt = buildGeminiPrompt(PROFILE_5X5, "dungeon-seed");
  assert(prompt.includes("5x5"));
  assert(prompt.includes("(4,4)"));
  assert(prompt.includes("Theme hint: dungeon-seed"));
  assert(prompt.includes('"path"'));
});

Deno.test("seededRng is deterministic for the same seed", () => {
  const a = seededRng("repeat-me");
  const b = seededRng("repeat-me");
  const samples = 8;
  for (let i = 0; i < samples; i++) {
    assertEquals(a(), b());
  }
});

Deno.test("localDfsDefinition is deterministic for a fixed seed", () => {
  const a = localDfsDefinition(PROFILE_5X5, "fixed-local-seed");
  const b = localDfsDefinition(PROFILE_5X5, "fixed-local-seed");
  assertEquals(a.cells, b.cells);
  assertEquals(a.metadata?.source, "local_dfs");
  assertEquals(a.metadata?.seed, "fixed-local-seed");
});

Deno.test("localDfsDefinition satisfies perfect maze on 7x7 profile", () => {
  const profile: MazeGenerationProfile = {
    width: 7,
    height: 7,
    spawn: [0, 0],
    exit: [6, 6],
  };
  const def = localDfsDefinition(profile, "seven-by-seven");
  assertEquals(validateDefinition(def).length, 0);
  assert(hasPath(def));
  let openSides = 0;
  for (let x = 0; x < def.width; x++) {
    for (let y = 0; y < def.height; y++) {
      const c = def.cells[x][y];
      for (const d of ["N", "S", "E", "W"] as const) {
        if (!c[d]) openSides++;
      }
    }
  }
  assertEquals(openSides, 2 * (def.width * def.height - 1));
});

Deno.test("dfsCarveMaze alone produces valid reachable grid", () => {
  const width = 5;
  const height = 5;
  const cells = emptyCells(width, height);
  dfsCarveMaze(cells, width, height, seededRng("dfs-only"));
  const def = {
    width,
    height,
    spawn: [0, 0] as [number, number],
    exit: [4, 4] as [number, number],
    cells,
  };
  assertEquals(validateDefinition(def).length, 0);
  assert(hasPath(def));
});

Deno.test("completeMazeFromPath builds perfect 5x5 maze", () => {
  const path = ["E", "E", "E", "E", "N", "N", "N", "N"];
  const def = completeMazeFromPath(PROFILE_5X5, path, "test-seed")!;
  assertExists(def);
  assertEquals(validateDefinition(def).length, 0);
  assert(hasPath(def));
  let openSides = 0;
  for (let x = 0; x < def.width; x++) {
    for (let y = 0; y < def.height; y++) {
      const c = def.cells[x][y];
      for (const d of ["N", "S", "E", "W"] as const) {
        if (!c[d]) openSides++;
      }
    }
  }
  assertEquals(openSides, 2 * (def.width * def.height - 1));
});

Deno.test("localDfsDefinition matches perfect maze invariant", () => {
  const def = localDfsDefinition(PROFILE_5X5, "dfs-seed");
  assertEquals(validateDefinition(def).length, 0);
  assert(hasPath(def));
});

Deno.test("attemptGeminiMaze without API key reports missing_api_key", async () => {
  const prev = Deno.env.get("GEMINI_API_KEY");
  Deno.env.delete("GEMINI_API_KEY");
  try {
    const { definition, report } = await attemptGeminiMaze(PROFILE_5X5, {
      model: DEFAULT_GEMINI_MODEL,
    });
    assertEquals(definition, null);
    assertEquals(report.model, "gemini-3.5-flash-lite");
    assertEquals(report.reason, "missing_api_key");
  } finally {
    if (prev !== undefined) Deno.env.set("GEMINI_API_KEY", prev);
  }
});

Deno.test({
  name: "attemptGeminiMaze live gemini-3.5-flash-lite",
  ignore: !Deno.env.get("GEMINI_API_KEY"),
  sanitizeOps: false,
  sanitizeResources: false,
}, async () => {
  const { definition, report } = await attemptGeminiMaze(PROFILE_5X5, {
    model: DEFAULT_GEMINI_MODEL,
    seedHint: `deno-test-${Date.now()}`,
  });
  assertEquals(report.model, "gemini-3.5-flash-lite");
  assertEquals(report.success, true, JSON.stringify(report));
  assertExists(definition);
  assertEquals(validateDefinition(definition!).length, 0);
  assert(hasPath(definition!));
});