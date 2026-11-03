export type WallSet = { N: boolean; S: boolean; E: boolean; W: boolean };

export type MazeCell = {
  walls: WallSet;
  player_blocking?: boolean;
  tags?: string[];
  properties?: Record<string, unknown>;
};

export type MazeDefinition = {
  schema_version: number;
  width: number;
  height: number;
  spawn: [number, number];
  exit: [number, number];
  cells: MazeCell[][];
  metadata?: Record<string, unknown>;
};

export type MazeGenerationProfile = {
  schema_version: number;
  width: number;
  height: number;
  keys_required: number;
  fork_min_open_sides?: number;
  prompt?: string;
  constraints?: {
    must_be_solvable?: boolean;
    max_player_blocking_ratio?: number;
  };
  cell_defaults?: { player_blocking?: boolean };
  allowed_tags?: string[];
  spawn?: [number, number];
  exit?: [number, number];
};

const DIRS: Record<string, [number, number]> = {
  N: [0, 1],
  S: [0, -1],
  E: [1, 0],
  W: [-1, 0],
};
const OPPOSITE: Record<string, string> = { N: "S", S: "N", E: "W", W: "E" };

export function defaultWalls(): WallSet {
  return { N: true, S: true, E: true, W: true };
}

export function emptyCell(blocking = false): MazeCell {
  return {
    walls: defaultWalls(),
    player_blocking: blocking,
    tags: [],
    properties: {},
  };
}

export function openSideCount(cell: MazeCell): number {
  let n = 0;
  for (const k of ["N", "S", "E", "W"] as const) {
    if (!cell.walls[k]) n++;
  }
  return n;
}

export function validateDefinition(def: MazeDefinition): string[] {
  const errors: string[] = [];
  if (def.schema_version !== 1) {
    errors.push(`unsupported schema_version ${def.schema_version}`);
  }
  if (!def.cells || def.cells.length !== def.height) {
    errors.push("cells height mismatch");
  }
  for (let y = 0; y < def.height; y++) {
    const row = def.cells[y];
    if (!row || row.length !== def.width) {
      errors.push(`cells width mismatch at row ${y}`);
      break;
    }
  }
  const [sx, sy] = def.spawn;
  const [ex, ey] = def.exit;
  if (sx < 0 || sx >= def.width || sy < 0 || sy >= def.height) {
    errors.push("spawn out of bounds");
  }
  if (ex < 0 || ex >= def.width || ey < 0 || ey >= def.height) {
    errors.push("exit out of bounds");
  }

  for (let y = 0; y < def.height; y++) {
    for (let x = 0; x < def.width; x++) {
      const cell = def.cells[y][x];
      if (!cell?.walls) {
        errors.push(`missing walls at ${x},${y}`);
        continue;
      }
      for (const dir of ["N", "S", "E", "W"] as const) {
        const [dx, dy] = DIRS[dir];
        const nx = x + dx;
        const ny = y + dy;
        if (nx < 0 || nx >= def.width || ny < 0 || ny >= def.height) continue;
        const opp = OPPOSITE[dir] as keyof WallSet;
        const a = cell.walls[dir];
        const b = def.cells[ny][nx].walls[opp];
        if (a !== b) {
          errors.push(`wall mismatch ${x},${y} ${dir}`);
        }
      }
    }
  }
  return errors;
}

/** Pad/trim cells to profile size and ensure each cell has boolean walls. */
export function normalizeDefinitionFromProfile(
  def: MazeDefinition,
  profile: MazeGenerationProfile,
): void {
  const w = profile.width;
  const h = profile.height;
  def.schema_version = 1;
  def.width = w;
  def.height = h;
  def.spawn = profile.spawn ?? [0, 0];
  def.exit = profile.exit ?? [w - 1, h - 1];

  if (!def.cells) def.cells = [];
  while (def.cells.length < h) def.cells.push([]);
  def.cells.length = h;

  for (let y = 0; y < h; y++) {
    if (!def.cells[y]) def.cells[y] = [];
    while (def.cells[y].length < w) def.cells[y].push(emptyCell());
    def.cells[y].length = w;

    for (let x = 0; x < w; x++) {
      const raw = def.cells[y][x];
      if (!raw || typeof raw !== "object") {
        def.cells[y][x] = emptyCell();
        continue;
      }
      const cell = raw as MazeCell;
      if (!cell.walls) cell.walls = defaultWalls();
      for (const k of ["N", "S", "E", "W"] as const) {
        if (typeof cell.walls[k] !== "boolean") cell.walls[k] = true;
      }
      if (typeof cell.player_blocking !== "boolean") {
        cell.player_blocking = profile.cell_defaults?.player_blocking ?? false;
      }
      if (!Array.isArray(cell.tags)) cell.tags = [];
      def.cells[y][x] = cell;
    }
  }
}

/**
 * Models often disagree on shared edges. Treat a passage as open only if both
 * sides say open; otherwise both sides get a wall (consistent grid).
 */
export function synchronizeAdjacentWalls(def: MazeDefinition): void {
  for (let y = 0; y < def.height; y++) {
    for (let x = 0; x < def.width; x++) {
      const cell = def.cells[y][x];
      for (const dir of ["N", "S", "E", "W"] as const) {
        const [dx, dy] = DIRS[dir];
        const nx = x + dx;
        const ny = y + dy;
        if (nx < 0 || nx >= def.width || ny < 0 || ny >= def.height) continue;
        const neighbor = def.cells[ny][nx];
        const opp = OPPOSITE[dir] as keyof WallSet;
        const wall = cell.walls[dir] && neighbor.walls[opp];
        cell.walls[dir] = wall;
        neighbor.walls[opp] = wall;
      }
    }
  }
}

export function repairGeminiDefinition(
  def: MazeDefinition,
  profile: MazeGenerationProfile,
): void {
  normalizeDefinitionFromProfile(def, profile);
  synchronizeAdjacentWalls(def);
}

export function isPassable(def: MazeDefinition, x: number, y: number): boolean {
  if (x < 0 || x >= def.width || y < 0 || y >= def.height) return false;
  return !def.cells[y][x].player_blocking;
}

export function canMove(def: MazeDefinition, x: number, y: number, dir: string): boolean {
  const cell = def.cells[y][x];
  if (cell.player_blocking) return false;
  if (cell.walls[dir as keyof WallSet]) return false;
  const [dx, dy] = DIRS[dir];
  const nx = x + dx;
  const ny = y + dy;
  return isPassable(def, nx, ny);
}

export function hasPath(def: MazeDefinition): boolean {
  const [sx, sy] = def.spawn;
  const [ex, ey] = def.exit;
  if (!isPassable(def, sx, sy) || !isPassable(def, ex, ey)) return false;

  const seen = new Set<string>();
  const q: [number, number][] = [[sx, sy]];
  seen.add(`${sx},${sy}`);

  while (q.length) {
    const [x, y] = q.shift()!;
    if (x === ex && y === ey) return true;
    for (const dir of Object.keys(DIRS)) {
      if (!canMove(def, x, y, dir)) continue;
      const [dx, dy] = DIRS[dir];
      const nx = x + dx;
      const ny = y + dy;
      const key = `${nx},${ny}`;
      if (seen.has(key)) continue;
      seen.add(key);
      q.push([nx, ny]);
    }
  }
  return false;
}

/** DFS maze carve (matches game GDScript). Returns wall grid indexed [x][y]. */
export function carveDfs(width: number, height: number, seed?: number): MazeCell[][][] {
  if (seed !== undefined) {
    // Simple LCG for deterministic local fallback
    let s = seed >>> 0;
    const rand = () => {
      s = (s * 1664525 + 1013904223) >>> 0;
      return s / 0x100000000;
    };
    (globalThis as { __mazeRand?: () => number }).__mazeRand = rand;
  }

  const rand = () =>
    (globalThis as { __mazeRand?: () => number }).__mazeRand?.() ?? Math.random();

  const grid: MazeCell[][][] = [];
  for (let x = 0; x < width; x++) {
    const col: MazeCell[][] = [];
    for (let y = 0; y < height; y++) {
      col.push([emptyCell()]);
    }
    grid.push(col);
  }

  const visited = new Set<string>();
  const stack: [number, number][] = [[0, 0]];
  visited.add("0,0");

  while (stack.length) {
    const [cx, cy] = stack[stack.length - 1];
    const candidates: string[] = [];
    for (const dir of Object.keys(DIRS)) {
      const [dx, dy] = DIRS[dir];
      const nx = cx + dx;
      const ny = cy + dy;
      if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
      if (visited.has(`${nx},${ny}`)) continue;
      candidates.push(dir);
    }
    if (!candidates.length) {
      stack.pop();
      continue;
    }
    const dir = candidates[Math.floor(rand() * candidates.length)];
    const [dx, dy] = DIRS[dir];
    const nx = cx + dx;
    const ny = cy + dy;
    grid[cx][cy][0].walls[dir as keyof WallSet] = false;
    grid[nx][ny][0].walls[OPPOSITE[dir] as keyof WallSet] = false;
    visited.add(`${nx},${ny}`);
    stack.push([nx, ny]);
  }

  delete (globalThis as { __mazeRand?: () => number }).__mazeRand;
  return grid;
}

/** Convert internal [x][y] carve grid to definition cells[y][x]. */
export function gridToDefinition(
  profile: MazeGenerationProfile,
  grid: MazeCell[][][],
): MazeDefinition {
  const w = profile.width;
  const h = profile.height;
  const spawn: [number, number] = profile.spawn ?? [0, 0];
  const exit: [number, number] = profile.exit ?? [w - 1, h - 1];
  const cells: MazeCell[][] = [];
  for (let y = 0; y < h; y++) {
    const row: MazeCell[] = [];
    for (let x = 0; x < w; x++) {
      const src = grid[x][y][0];
      row.push({
        walls: { ...src.walls },
        player_blocking: profile.cell_defaults?.player_blocking ?? false,
        tags: [],
        properties: {},
      });
    }
    cells.push(row);
  }
  return {
    schema_version: 1,
    width: w,
    height: h,
    spawn,
    exit,
    cells,
    metadata: { source: "local_dfs" },
  };
}

export function localDfsDefinition(
  profile: MazeGenerationProfile,
  seedHint?: string,
): MazeDefinition {
  let seed: number | undefined;
  if (seedHint) {
    seed = 0;
    for (let i = 0; i < seedHint.length; i++) {
      seed = (seed * 31 + seedHint.charCodeAt(i)) >>> 0;
    }
  }
  const grid = carveDfs(profile.width, profile.height, seed);
  return gridToDefinition(profile, grid);
}

export function enforceTriviaTags(
  def: MazeDefinition,
  profile: MazeGenerationProfile,
): void {
  const forkMin = profile.fork_min_open_sides ?? 3;
  const keysRequired = profile.keys_required;
  const [sx, sy] = def.spawn;
  const [ex, ey] = def.exit;

  const clearTags = () => {
    for (let y = 0; y < def.height; y++) {
      for (let x = 0; x < def.width; x++) {
        def.cells[y][x].tags = (def.cells[y][x].tags ?? []).filter((t) => t !== "trivia");
      }
    }
  };
  clearTags();

  const forks: [number, number][] = [];
  const others: [number, number][] = [];
  for (let y = 0; y < def.height; y++) {
    for (let x = 0; x < def.width; x++) {
      if (x === sx && y === sy) continue;
      if (x === ex && y === ey) continue;
      if (def.cells[y][x].player_blocking) continue;
      if (openSideCount(def.cells[y][x]) >= forkMin) {
        forks.push([x, y]);
      } else {
        others.push([x, y]);
      }
    }
  }

  const chosen: [number, number][] = [...forks];
  if (chosen.length < keysRequired) {
    others.sort(() => Math.random() - 0.5);
    for (const p of others) {
      if (chosen.length >= keysRequired) break;
      chosen.push(p);
    }
  } else {
    chosen.sort(() => Math.random() - 0.5);
    chosen.length = keysRequired;
  }

  for (let i = 0; i < keysRequired && i < chosen.length; i++) {
    const [x, y] = chosen[i];
    def.cells[y][x].tags = [...(def.cells[y][x].tags ?? []), "trivia"];
  }
}

export function clampPlayerBlocking(
  def: MazeDefinition,
  maxRatio: number,
): void {
  const maxCount = Math.floor(def.width * def.height * maxRatio);
  let count = 0;
  const blocking: [number, number][] = [];
  for (let y = 0; y < def.height; y++) {
    for (let x = 0; x < def.width; x++) {
      if (def.cells[y][x].player_blocking) {
        count++;
        blocking.push([x, y]);
      }
    }
  }
  if (count <= maxCount) return;
  blocking.sort(() => Math.random() - 0.5);
  for (let i = maxCount; i < blocking.length; i++) {
    const [x, y] = blocking[i];
    def.cells[y][x].player_blocking = false;
  }
}

export function postProcessDefinition(
  def: MazeDefinition,
  profile: MazeGenerationProfile,
): MazeDefinition {
  const maxRatio = profile.constraints?.max_player_blocking_ratio ?? 0.05;
  clampPlayerBlocking(def, maxRatio);
  enforceTriviaTags(def, profile);
  if (profile.constraints?.must_be_solvable !== false && !hasPath(def)) {
    return localDfsDefinition(profile);
  }
  return def;
}

export function geminiMazeResponseSchema(width: number, height: number) {
  const cellSchema = {
    type: "OBJECT",
    properties: {
      walls: {
        type: "OBJECT",
        properties: {
          N: { type: "BOOLEAN" },
          S: { type: "BOOLEAN" },
          E: { type: "BOOLEAN" },
          W: { type: "BOOLEAN" },
        },
        required: ["N", "S", "E", "W"],
      },
      player_blocking: { type: "BOOLEAN" },
      tags: { type: "ARRAY", items: { type: "STRING" } },
      properties: { type: "OBJECT" },
    },
    required: ["walls"],
  };

  return {
    type: "OBJECT",
    properties: {
      schema_version: { type: "INTEGER" },
      width: { type: "INTEGER" },
      height: { type: "INTEGER" },
      spawn: { type: "ARRAY", items: { type: "INTEGER" } },
      exit: { type: "ARRAY", items: { type: "INTEGER" } },
      cells: {
        type: "ARRAY",
        items: {
          type: "ARRAY",
          items: cellSchema,
        },
      },
      metadata: { type: "OBJECT" },
    },
    required: ["schema_version", "width", "height", "spawn", "exit", "cells"],
  };
}

export function buildGeminiPrompt(
  profile: MazeGenerationProfile,
  seedHint?: string,
): string {
  const spawn = profile.spawn ?? [0, 0];
  const exit = profile.exit ?? [profile.width - 1, profile.height - 1];
  return [
    profile.prompt ??
      "Generate a solvable maze for a trivia game.",
    `Grid size: ${profile.width}x${profile.height}.`,
    `Return cells as a JSON array of exactly ${profile.height} rows; each row is exactly ${profile.width} cells.`,
    `Index: cells[row_y][col_x], row y=0 is the south row, y=${profile.height - 1} is north; x=0 is west, x=${profile.width - 1} is east.`,
    `Spawn at [${spawn[0]}, ${spawn[1]}], exit at [${exit[0]}, ${exit[1]}].`,
    `Each cell: walls N,S,E,W (true = solid wall). If cell (x,y) has N=false, neighbor (x,y+1) must have S=false (same for E/W pairs).`,
    `Prefer a single connected maze; do not leave contradictory walls on shared edges.`,
    `Use player_blocking true on at most ${Math.floor(profile.width * profile.height * (profile.constraints?.max_player_blocking_ratio ?? 0.05))} cells.`,
    `Allowed tags: ${(profile.allowed_tags ?? ["trivia"]).join(", ")}.`,
    `Place tag "trivia" on at least ${profile.keys_required} fork cells (3+ open passages).`,
    seedHint ? `Variety seed hint: ${seedHint}` : "",
    `schema_version must be 1.`,
  ]
    .filter(Boolean)
    .join(" ");
}

export type GeminiAttemptReport = {
  attempted: boolean;
  success: boolean;
  model: string;
  reason:
    | "skipped_use_local_only"
    | "missing_api_key"
    | "api_error"
    | "empty_response"
    | "json_parse_error"
    | "validation_failed"
    | "success";
  detail?: string;
  validation_errors?: string[];
  http_status?: number;
  repaired?: boolean;
};

/** Calls Gemini generateContent for a maze; always returns a diagnostic report. */
export async function attemptGeminiMaze(
  profile: MazeGenerationProfile,
  options: { seedHint?: string; model?: string } = {},
): Promise<{ definition: MazeDefinition | null; report: GeminiAttemptReport }> {
  const model = options.model ??
    Deno.env.get("GEMINI_MODEL") ??
    "gemini-3.5-flash-lite";

  const baseReport = (): GeminiAttemptReport => ({
    attempted: true,
    success: false,
    model,
    reason: "api_error",
  });

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return {
      definition: null,
      report: {
        attempted: true,
        success: false,
        model,
        reason: "missing_api_key",
        detail:
          "Set GEMINI_API_KEY in Supabase Edge Function secrets (not in the Godot .env).",
      },
    };
  }

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const payload = {
    contents: [{
      parts: [{ text: buildGeminiPrompt(profile, options.seedHint) }],
    }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: geminiMazeResponseSchema(profile.width, profile.height),
    },
  };

  let geminiRes: Response;
  const geminiTimeoutMs = 55_000;
  try {
    geminiRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(geminiTimeoutMs),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const timedOut = msg.includes("abort") || msg.includes("timeout");
    console.error("Gemini fetch error", msg);
    return {
      definition: null,
      report: {
        ...baseReport(),
        reason: "api_error",
        detail: timedOut
          ? `Gemini request exceeded ${geminiTimeoutMs / 1000}s — using server local DFS fallback`
          : `Network error: ${msg}`,
      },
    };
  }

  if (!geminiRes.ok) {
    const body = await geminiRes.text();
    console.error("Gemini status", geminiRes.status, body);
    let detail = body.slice(0, 500);
    if (geminiRes.status === 404 && body.includes("models/")) {
      detail =
        `Model '${model}' not found or not available for this API key. ` +
        `List models: GET https://generativelanguage.googleapis.com/v1beta/models?key=YOUR_KEY ` +
        `(see supabase/DEPLOY.md). Raw: ${body.slice(0, 200)}`;
    }
    return {
      definition: null,
      report: {
        attempted: true,
        success: false,
        model,
        reason: "api_error",
        http_status: geminiRes.status,
        detail,
      },
    };
  }

  const data = await geminiRes.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    const block = data?.promptFeedback ?? data?.candidates?.[0]?.finishReason;
    return {
      definition: null,
      report: {
        attempted: true,
        success: false,
        model,
        reason: "empty_response",
        detail: block
          ? `No text in response (${JSON.stringify(block).slice(0, 200)})`
          : "No candidates text in Gemini response",
      },
    };
  }

  let parsed: MazeDefinition;
  try {
    parsed = JSON.parse(text) as MazeDefinition;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("Gemini JSON parse error", msg);
    return {
      definition: null,
      report: {
        attempted: true,
        success: false,
        model,
        reason: "json_parse_error",
        detail: msg,
      },
    };
  }

  repairGeminiDefinition(parsed, profile);
  const validationErrors = validateDefinition(parsed);
  if (validationErrors.length > 0) {
    console.warn("Gemini validation failed", validationErrors);
    return {
      definition: null,
      report: {
        attempted: true,
        success: false,
        model,
        reason: "validation_failed",
        validation_errors: validationErrors.slice(0, 8),
        detail: validationErrors.slice(0, 3).join("; "),
      },
    };
  }

  if (!hasPath(parsed)) {
    return {
      definition: null,
      report: {
        attempted: true,
        success: false,
        model,
        reason: "validation_failed",
        detail: "no path from spawn to exit after wall sync",
        repaired: true,
      },
    };
  }

  parsed.metadata = {
    ...(parsed.metadata ?? {}),
    source: "gemini",
    wall_sync_repaired: true,
  };

  return {
    definition: parsed,
    report: {
      attempted: true,
      success: true,
      model,
      reason: "success",
      repaired: true,
      detail: "Normalized grid size and synchronized shared walls from model output.",
    },
  };
}
