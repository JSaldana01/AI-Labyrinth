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

`MazeTests.cs` is not present in this repository; no separate C# maze test suite is included in these counts.

### Running the tests

In addition to the source prerequisites above, install the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0) for the authentication test project. GUT is included in `addons/gut`; it does not need a separate download.

From the repository root, import the project and build its C# code, then run the GUT suite:

```powershell
godot --headless --editor --path . --quit
dotnet build .\3311.csproj
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Replace `godot` with the path to the Godot .NET executable if it is not on your PATH. On Windows, use the `_console.exe` executable for terminal output.

Run the separate authentication tests with:

```powershell
dotnet test .\tests\AuthTests\AuthTests.csproj
```

A fresh clone has no `.env` file. In that case, startup logs missing Supabase configuration and maze tests use the local fallback. If you have configured `.env`, initialization and the maze fixture test may contact your configured Supabase service; use an isolated copy without `.env` for an offline run. Do not commit credentials.

**Known test issues:** `test_enemy.gd` currently fails to parse because its asynchronous maze helper calls are missing `await`, so GUT skips that file. `test_gate_builds_stairs_with_collision` currently fails because its expected collision node path is not found. Check the GUT output for skipped scripts as well as failed tests.

### Licenses and Acknowledgements:

Pixelated heart: https://www.citypng.com/png-download/29976
Enemy model: https://kaylousberg.itch.io/kaykit-skeletons
Background Music (Hidden in Havana): https://www.epidemicsound.com/music/tracks/be27536b-178b-4807-ae32-b1fda3fa5295/
Staircase model: https://sketchfab.com/3d-models/ancient-stone-staircase-1a0ad575885848278d93f9dd8c02a923
Key model: https://sketchfab.com/3d-models/low-poly-key-86feedcb9a25455a913a690e22ef10d7
Maze generation: Gemini 3.5 Flash-Lite
