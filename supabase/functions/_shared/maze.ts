/** Maze grid matches Godot maze_generator.gd: cells[x][y], true = wall present. */

export const DEFAULT_GEMINI_MODEL = "gemini-3.5-flash-lite";
const GEMINI_TIMEOUT_MS = 10_000;
const DIR_KEYS = ["N", "S", "E", "W"] as const;
type DirKey = (typeof DIR_KEYS)[number];

const DIRS: Record<DirKey, [number, number]> = {
  N: [0, 1],
  S: [0, -1],
  E: [1, 0],
  W: [-1, 0],
};
const OPPOSITE: Record<DirKey, DirKey> = {
  N: "S",
  S: "N",
  E: "W",
  W: "E",
};

export interface CellWalls {
  N: boolean;
  S: boolean;
  E: boolean;
  W: boolean;
}

export interface MazeDefinition {
  width: number;
  height: number;
  spawn: [number, number];
  exit: [number, number];
  cells: CellWalls[][];
  metadata?: { source?: string; seed?: string };
}

export interface MazeGenerationProfile {
  width: number;
  height: number;
  keys_required?: number;
  fork_min_open_sides?: number;
  spawn?: [number, number];
  exit?: [number, number];
}

export interface GeminiAttemptReport {
  attempted: boolean;
  success: boolean;
  model: string;
  reason?: string;
  detail?: string;
  http_status?: number;
  validation_errors?: string[];
}

function cellKey(x: number, y: number): string {
  return `${x},${y}`;
}

function parseCellKey(k: string): [number, number] {
  const [xs, ys] = k.split(",");
  return [Number(xs), Number(ys)];
}

/** Deterministic mulberry32 PRNG from seed string. */
export function seededRng(seed: string): () => number {
  let h = 0;
  for (let i = 0; i < seed.length; i++) {
    h = (Math.imul(31, h) + seed.charCodeAt(i)) | 0;
  }
  return () => {
    h |= 0;
    h = (h + 0x6d2b79f5) | 0;
    let t = Math.imul(h ^ (h >>> 15), 1 | h);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function emptyCells(width: number, height: number): CellWalls[][] {
  const cells: CellWalls[][] = [];
  for (let x = 0; x < width; x++) {
    const col: CellWalls[] = [];
    for (let y = 0; y < height; y++) {
      col.push({ N: true, S: true, E: true, W: true });
    }
    cells.push(col);
  }
  return cells;
}

function carveOpening(cells: CellWalls[][], x: number, y: number, dir: DirKey): void {
  const [dx, dy] = DIRS[dir];
  const nx = x + dx;
  const ny = y + dy;
  if (nx < 0 || ny < 0 || nx >= cells.length || ny >= cells[0].length) {
    return;
  }
  cells[x][y][dir] = false;
  cells[nx][ny][OPPOSITE[dir]] = false;
}

function unvisitedNeighborDirs(
  x: number,
  y: number,
  width: number,
  height: number,
  visited: Set<string>,
): DirKey[] {
  const result: DirKey[] = [];
  for (const dir of DIR_KEYS) {
    const [dx, dy] = DIRS[dir];
    const nx = x + dx;
    const ny = y + dy;
    const inBounds = nx >= 0 && nx < width && ny >= 0 && ny < height;
    if (inBounds && !visited.has(cellKey(nx, ny))) {
      result.push(dir);
    }
  }
  return result;
}

/** Same stack DFS as maze_generator.gd _carve_maze. */
export function dfsCarveMaze(
  cells: CellWalls[][],
  width: number,
  height: number,
  rng: () => number,
): void {
  const visited = new Set<string>();
  const stack: [number, number][] = [[0, 0]];
  visited.add(cellKey(0, 0));

  while (stack.length > 0) {
    const [cx, cy] = stack[stack.length - 1];
    const candidates = unvisitedNeighborDirs(cx, cy, width, height, visited);
    if (candidates.length === 0) {
      stack.pop();
      continue;
    }
    const dir = candidates[Math.floor(rng() * candidates.length)];
    const [dx, dy] = DIRS[dir];
    const nx = cx + dx;
    const ny = cy + dy;
    carveOpening(cells, cx, cy, dir);
    visited.add(cellKey(nx, ny));
    stack.push([nx, ny]);
  }
}

export function validatePath(
  path: string[],
  width: number,
  height: number,
): { ok: boolean; errors: string[] } {
  const errors: string[] = [];
  let x = 0;
  let y = 0;
  const visited = new Set<string>([cellKey(0, 0)]);
  for (let i = 0; i < path.length; i++) {
    const step = path[i];
    if (!DIR_KEYS.includes(step as DirKey)) {
      errors.push(`invalid direction at step ${i}: ${step}`);
      continue;
    }
    const [dx, dy] = DIRS[step as DirKey];
    x += dx;
    y += dy;
    if (x < 0 || y < 0 || x >= width || y >= height) {
      errors.push(`out of bounds at step ${i}`);
      break;
    }
    const k = cellKey(x, y);
    if (visited.has(k)) {
      errors.push(`revisit at step ${i}`);
    }
    visited.add(k);
  }
  const exitX = width - 1;
  const exitY = height - 1;
  if (x !== exitX || y !== exitY) {
    errors.push(`path ends at (${x},${y}), expected (${exitX},${exitY})`);
  }
  return { ok: errors.length === 0, errors };
}

/** Carve Gemini path cells, then DFS-fill the rest (perfect maze). */
export function completeMazeFromPath(
  profile: MazeGenerationProfile,
  path: string[],
  seed: string,
): MazeDefinition | null {
  const width = profile.width;
  const height = profile.height;
  const check = validatePath(path, width, height);
  if (!check.ok) return null;

  const cells = emptyCells(width, height);
  let x = 0;
  let y = 0;
  const pathVisited = new Set<string>([cellKey(0, 0)]);
  for (const step of path) {
    const dir = step as DirKey;
    carveOpening(cells, x, y, dir);
    const [dx, dy] = DIRS[dir];
    x += dx;
    y += dy;
    pathVisited.add(cellKey(x, y));
  }

  const rng = seededRng(seed);
  const stack: [number, number][] = [[0, 0]];
  const visited = new Set(pathVisited);
  while (stack.length > 0) {
    const [cx, cy] = stack[stack.length - 1];
    const candidates = unvisitedNeighborDirs(cx, cy, width, height, visited);
    if (candidates.length === 0) {
      stack.pop();
      continue;
    }
    const dir = candidates[Math.floor(rng() * candidates.length)];
    const [dx, dy] = DIRS[dir];
    const nx = cx + dx;
    const ny = cy + dy;
    carveOpening(cells, cx, cy, dir);
    visited.add(cellKey(nx, ny));
    stack.push([nx, ny]);
  }

  const spawn: [number, number] = profile.spawn ?? [0, 0];
  const exit: [number, number] = profile.exit ?? [width - 1, height - 1];
  const def: MazeDefinition = {
    width,
    height,
    spawn,
    exit,
    cells,
    metadata: { source: "gemini_path", seed },
  };
  const val = validateDefinition(def);
  if (val.length > 0 || !hasPath(def)) return null;
  return def;
}

export function localDfsDefinition(
  profile: MazeGenerationProfile,
  seedHint?: string,
): MazeDefinition {
  const width = profile.width;
  const height = profile.height;
  const seed = seedHint ?? `local-${Date.now()}`;
  const cells = emptyCells(width, height);
  dfsCarveMaze(cells, width, height, seededRng(seed));
  return {
    width,
    height,
    spawn: profile.spawn ?? [0, 0],
    exit: profile.exit ?? [width - 1, height - 1],
    cells,
    metadata: { source: "local_dfs", seed },
  };
}

export function validateDefinition(def: MazeDefinition): string[] {
  const errors: string[] = [];
  if (def.cells.length !== def.width) {
    errors.push(`width mismatch: cells columns ${def.cells.length} vs ${def.width}`);
  }
  for (let x = 0; x < def.width; x++) {
    if (!def.cells[x] || def.cells[x].length !== def.height) {
      errors.push(`column ${x} height mismatch`);
      continue;
    }
    for (let y = 0; y < def.height; y++) {
      const c = def.cells[x][y];
      for (const dir of DIR_KEYS) {
        if (typeof c[dir] !== "boolean") {
          errors.push(`cell (${x},${y}) missing ${dir}`);
        }
      }
    }
  }
  for (let x = 0; x < def.width; x++) {
    for (let y = 0; y < def.height; y++) {
      for (const dir of DIR_KEYS) {
        if (def.cells[x][y][dir]) continue;
        const [dx, dy] = DIRS[dir];
        const nx = x + dx;
        const ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= def.width || ny >= def.height) continue;
        if (def.cells[nx][ny][OPPOSITE[dir]]) {
          errors.push(`wall mismatch (${x},${y}) ${dir} vs (${nx},${ny})`);
        }
      }
    }
  }
  return errors;
}

export function hasPath(def: MazeDefinition): boolean {
  const start = def.spawn;
  const goal = def.exit;
  const queue: [number, number][] = [[start[0], start[1]]];
  const seen = new Set<string>([cellKey(start[0], start[1])]);
  let head = 0;
  while (head < queue.length) {
    const [x, y] = queue[head++];
    if (x === goal[0] && y === goal[1]) return true;
    for (const dir of DIR_KEYS) {
      if (def.cells[x][y][dir]) continue;
      const [dx, dy] = DIRS[dir];
      const nx = x + dx;
      const ny = y + dy;
      const k = cellKey(nx, ny);
      if (!seen.has(k)) {
        seen.add(k);
        queue.push([nx, ny]);
      }
    }
  }
  return false;
}

export function buildGeminiPrompt(
  profile: MazeGenerationProfile,
  seedHint?: string,
): string {
  const w = profile.width;
  const h = profile.height;
  return [
    `Return ONLY JSON: {"path":["E","N",...]}`,
    `Maze is ${w}x${h} cells. Start at (0,0). End at (${w - 1},${h - 1}).`,
    `Each step is one of N,S,E,W (one cell move, stay in bounds).`,
    `Prefer a simple route without revisiting cells. Length can vary.`,
    seedHint ? `Theme hint: ${seedHint}` : "",
  ].filter(Boolean).join("\n");
}

const PATH_RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    path: {
      type: "array",
      items: { type: "string", enum: ["N", "S", "E", "W"] },
    },
  },
  required: ["path"],
};

export async function attemptGeminiMaze(
  profile: MazeGenerationProfile,
  options: { seedHint?: string; model?: string } = {},
): Promise<{ definition: MazeDefinition | null; report: GeminiAttemptReport }> {
  const model = options.model ?? Deno.env.get("GEMINI_MODEL") ?? DEFAULT_GEMINI_MODEL;
  const apiKey = Deno.env.get("GEMINI_API_KEY");

  if (!apiKey) {
    return {
      definition: null,
      report: {
        attempted: true,
        success: false,
        model,
        reason: "missing_api_key",
      },
    };
  }

  const prompt = buildGeminiPrompt(profile, options.seedHint);
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);

  try {
    const res = await fetch(url, {
      method: "POST",
      signal: controller.signal,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: PATH_RESPONSE_SCHEMA,
          temperature: 0.4,
          maxOutputTokens: 512,
        },
      }),
    });
    clearTimeout(timeout);

    if (!res.ok) {
      const detail = await res.text();
      return {
        definition: null,
        report: {
          attempted: true,
          success: false,
          model,
          reason: "api_error",
          http_status: res.status,
          detail: detail.slice(0, 500),
        },
      };
    }

    const body = await res.json();
    const text = body?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
      return {
        definition: null,
        report: {
          attempted: true,
          success: false,
          model,
          reason: "empty_response",
        },
      };
    }

    let parsed: { path?: string[] };
    try {
      parsed = JSON.parse(text);
    } catch {
      return {
        definition: null,
        report: {
          attempted: true,
          success: false,
          model,
          reason: "invalid_json",
          detail: text.slice(0, 200),
        },
      };
    }

    const path = parsed.path ?? [];
    const seed = options.seedHint ?? `gemini-${Date.now()}`;
    const def = completeMazeFromPath(profile, path, seed);
    if (!def) {
      return {
        definition: null,
        report: {
          attempted: true,
          success: false,
          model,
          reason: "validation_failed",
          validation_errors: validatePath(path, profile.width, profile.height).errors,
        },
      };
    }
    def.metadata = { source: "gemini", seed };

    return {
      definition: def,
      report: {
        attempted: true,
        success: true,
        model,
        reason: "ok",
      },
    };
  } catch (e) {
    clearTimeout(timeout);
    const isAbort = e instanceof DOMException && e.name === "AbortError";
    return {
      definition: null,
      report: {
        attempted: true,
        success: false,
        model,
        reason: isAbort ? "timeout" : "network_error",
        detail: String(e).slice(0, 200),
      },
    };
  }
}

/** Identity pass — forks/keys stay on client. */
export function postProcessDefinition(
  def: MazeDefinition,
  _profile: MazeGenerationProfile,
): MazeDefinition {
  return def;
}