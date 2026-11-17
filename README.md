# Project Demo (CSE 3311)

Welcome to our game repository! Below are the instructions for playing the compiled demo as well as building the project from source.

---

## 🎮 How to Play the Demo

### Prerequisite: .NET Runtime

Because this game is built with **Godot 4 (.NET / C#)**, ensure you have the **.NET 8.0 SDK / Desktop Runtime** (or newer) installed on your machine before launching.

- [Download .NET 8.0 Here](https://dotnet.microsoft.com/en-us/download/dotnet/8.0)

### 1. Download via GitHub Releases (Recommended)

1. Go to the **[Releases](../../releases)** page on the right side of this GitHub repository.
2. Under the latest release, download the attached `.zip` file.
3. **Extract the entire `.zip` folder** to a location on your computer. _(Do not run the `.exe` directly from inside the unextracted `.zip` preview window!)_
4. Open the extracted folder and double-click the `.exe` file to start the game.

### Run from source

1. Install the [Godot 4.7.2 .NET editor](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) and the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).
2. Clone this repository and import `project.godot` in Godot.
3. Build the C# project in Godot, then press **F5** to run the game.
4. Choose **Skip Login** to play without an account. Without Supabase configuration, the game logs missing configuration and falls back to local maze generation.

## Tests

The counts below are test cases, including individual xUnit theory inputs.

| File | Tests | Type | What it covers |
| --- | ---: | --- | --- |
| [test_game_state.gd](tests/test_game_state.gd) | 24 | Unit and state-based | Difficulty, keys, hearts, game over, exit handling, completion counts, rewards, speed boost timing and movement, and hint persistence. |
| [test_maze_generation.gd](tests/test_maze_generation.gd) | 22 | Integration and randomized property checks | Maze connectivity, walls, coordinates, pathfinding, trigger placement, exit and roof geometry, loading animation, and applying a maze fixture. Several checks repeat across generated mazes. |
| [test_enemy.gd](tests/test_enemy.gd) | 9 | Integration and behavioral | Enemy spawning, difficulty speeds, pause and game-over behavior, and chasing through open passages. See the known test issues below. |
| [test_trivia.gd](tests/test_trivia.gd) | 11 | Unit and interaction | Question data, shuffle bag, answers and rewards, and using hints in the trivia popup. |
| [test_triggers_and_exit.gd](tests/test_triggers_and_exit.gd) | 9 | Component and interaction | Key triggers, answer responses, exit requirements, player proximity, and staircase collision. See the known test issues below. |
| [AuthValidatorTests.cs](tests/AuthTests/AuthValidatorTests.cs) | 29 | Unit | Email and password validation, error messages, whitespace, length limits, control characters, injection-style inputs, large inputs, and Unicode passwords. |
| [maze_generation.test.ts](tests/maze_generation.test.ts) | 13 | Unit and optional integration | Edge maze logic (`supabase/functions/_shared/maze.ts`): path validation, local DFS, Gemini prompt, and an optional live call to Gemini 3.5 Flash-Lite when `GEMINI_API_KEY` is set. |

### Prerequisites

| Suite | Install |
| --- | --- |
| Godot GUT | [Godot 4.7.2 .NET editor](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) and [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) (same as running from source). GUT is vendored in `addons/gut`. |
| Auth (xUnit) | [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) (`tests/AuthTests/AuthTests.csproj`, same as the game). |
| Deno maze | [Deno](https://docs.deno.com/runtime/getting_started/installation/) 2.x (e.g. `winget install DenoLand.Deno` on Windows). No Godot required. |

Run all commands below from the **repository root** (the folder that contains `project.godot` and `deno.json`).

### 1. Godot GUT tests (`tests/test_*.gd`)

These exercise the game in-engine (maze scene, enemy, trivia, triggers, `GameState`). In-maze GUT tests use **local DFS only**; they do not call the Gemini API.

**One-time setup** (build C# so scenes compile):

```powershell
godot --headless --editor --path . --quit
dotnet build .\3311.csproj
```

**Run the full GUT suite (headless CLI)** — uses [`.gutconfig.json`](.gutconfig.json) (`res://tests/`, files named `test_*.gd`):

```powershell
godot --headless --path . -s res://addons/gut/gut_cmdln.gd
```

Equivalent if you prefer explicit flags:

```powershell
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Replace `godot` with the full path to the Godot **.NET** executable if it is not on your PATH. On Windows, prefer the `_console.exe` build so output appears in the terminal.

**Run a single script** (example — maze tests only):

```powershell
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gselect test_maze_generation
```

**From the Godot editor:** open the project, ensure the **Gut** plugin is enabled, open the GUT bottom panel, confirm the test directory is `res://tests/`, and choose **Run All**.

The maze generation script is the slowest suite (many random rebuilds).

### 2. Authentication tests (`tests/AuthTests/`)

Standalone xUnit project; no Godot or Deno.

```powershell
dotnet test .\tests\AuthTests\AuthTests.csproj
```

Verbose output:

```powershell
dotnet test .\tests\AuthTests\AuthTests.csproj --verbosity normal
```

### 3. Deno maze tests (`tests/maze_generation.test.ts`)

These test the same TypeScript maze code used by the Supabase edge function: `validatePath`, `completeMazeFromPath`, `localDfsDefinition`, and `attemptGeminiMaze`. Gemini layout is verified on the server with path + grid checks before the client ever receives a `generator: "gemini"` response.

**Install Deno** if needed, then verify:

```powershell
deno --version
```

**Offline / CI (recommended default):** 12 tests run; the live Gemini test is **skipped** without an API key.

```powershell
deno task test:unit
```

Same as:

```powershell
deno test --allow-env tests/maze_generation.test.ts
```

**Full run including live Gemini:** create a root [`.env`](.env) with `GEMINI_API_KEY=...` (do not commit secrets), then:

```powershell
deno task test
```

Same as:

```powershell
deno test --allow-env --allow-net --env-file=.env tests/maze_generation.test.ts
```

| Flag | Purpose |
| --- | --- |
| `--allow-env` | Tests read and temporarily clear `GEMINI_API_KEY` |
| `--allow-net` | Live Gemini HTTP request |
| `--env-file=.env` | Loads `GEMINI_API_KEY` from the project root |

Success looks like `ok | 13 passed | 0 failed` (full run) or `12 passed | 1 ignored` (unit run).

### Suggested order for a full local check

1. `dotnet test .\tests\AuthTests\AuthTests.csproj`
2. `deno task test:unit`
3. `dotnet build .\3311.csproj` then `godot --headless --path . -s res://addons/gut/gut_cmdln.gd`
4. Optional: `deno task test` if you have a valid `GEMINI_API_KEY` in `.env`

A fresh clone has no `.env`. The game logs missing Supabase configuration and uses local maze generation; GUT maze tests still pass offline. If you add `.env` for Deno or Supabase, keep credentials out of git.

### Licenses and Acknowledgements:

Pixelated heart: https://www.citypng.com/png-download/29976
Enemy model: https://kaylousberg.itch.io/kaykit-skeletons
Background Music (Hidden in Havana): https://www.epidemicsound.com/music/tracks/be27536b-178b-4807-ae32-b1fda3fa5295/
Staircase model: https://sketchfab.com/3d-models/ancient-stone-staircase-1a0ad575885848278d93f9dd8c02a923
Key model: https://sketchfab.com/3d-models/low-poly-key-86feedcb9a25455a913a690e22ef10d7
Maze generation: Gemini 3.5 Flash-Lite
