import {
  assert,
  assertEquals,
  assertExists,
} from "jsr:@std/assert@1";
import {
  attemptGeminiMaze,
  completeMazeFromPath,
  DEFAULT_GEMINI_MODEL,
  hasPath,
  localDfsDefinition,
  validateDefinition,
  validatePath,
  type MazeGenerationProfile,
} from "./maze.ts";

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