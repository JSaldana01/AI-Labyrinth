# AI Labyrinth – UML

Diagrams use [Mermaid](https://mermaid.js.org/) (renders on GitHub and in VS Code's Markdown preview).
Elements marked "planned" are not implemented yet (Gemini maze generation).

## Class diagram

```mermaid
classDiagram
    direction LR

    class EnvManager {
        <<autoload>>
        +SupabaseUrl: string
        +SupabaseKey: string
        +GeminiApiKey: string
        +_EnterTree()
    }
    class DBManager {
        <<static>>
        +Supabase: Client
        +Initialize()
    }
    class SupabaseAuth {
        <<external>>
        +SignUp(email, password)
        +SignIn(email, password)
    }
    class GeminiMazeService {
        <<planned, Gemini 3.5 Flash>>
        +GenerateMaze(width, height, difficulty) MazeLayout
        -BuildPrompt()
        -ParseResponse() MazeLayout
    }
    class MazeLayout {
        <<planned>>
        +grid: Cell[][]
        +Validate() bool
    }

    class AuthMenu {
        <<Control, C#>>
        -OnLoginButtonPressed()
        -OnSignUpButtonPressed()
        -OnTestLoginButtonPressed()
    }
    class DifficultySelect {
        <<Control>>
        -_start(level)
    }
    class PauseMenu {
        <<CanvasLayer>>
        -_open()
        -_resume()
    }
    class GameOverMenu {
        <<CanvasLayer>>
        -_restart(difficulty)
    }
    class HUD {
        <<CanvasLayer>>
        -_on_key_count_changed()
        -_on_lives_changed()
    }

    class GameState {
        <<autoload>>
        +difficulty: Difficulty
        +keys_required: int
        +keys_collected: int
        +lives: int
        +mazes_completed: Dictionary
        +is_game_over: bool
        +set_difficulty(d)
        +add_key()
        +damage_player()
        +try_open_exit()
        +reset_keys()
        +get_setting(key)
    }
    class Difficulty {
        <<enumeration>>
        EASY
        MEDIUM
        HARD
    }

    class TriviaManager {
        <<autoload>>
        +answered(was_correct)
        +ask_random_question()
    }
    class TriviaPopup {
        <<Control>>
    }

    class MazeGenerator {
        <<Node3D>>
        +grid_width: int
        +grid_height: int
        +cell_size: float
        +wall_height: float
        -_rebuild_maze()
        -_carve_maze()
        -_build_walls()
        -_build_roof()
        -_build_fog()
        -_place_fork_triggers()
        -_place_exit_gate()
        -_spawn_enemy()
        +next_cell_toward(from, to) Vector2i
        +farthest_cell_center_from(pos) Vector3
    }
    class ForkTrigger {
        <<Area3D>>
        +relocate_requested(trigger)
        -_on_body_entered()
        -_on_answered(was_correct)
    }
    class ExitGate {
        <<Area3D, stairs>>
        +setup(cell_size, wall_height, angle)
        -_on_body_entered()
    }
    class WallSegment {
        <<StaticBody3D>>
    }
    class Enemy {
        <<Area3D, skeleton>>
        +speed: float
        +setup(maze, player, speed)
        -_chase(delta)
        -_try_hit_player()
    }
    class Player {
        <<CharacterBody3D>>
        +move_speed: float
        +mouse_sensitivity: float
    }
    class Flashlight {
        <<SpotLight3D>>
    }

    EnvManager --> DBManager : initializes
    DBManager --> SupabaseAuth : exposes client
    AuthMenu ..> DBManager : sign in / sign up
    AuthMenu --> DifficultySelect : on success

    DifficultySelect --> GameState : set_difficulty()
    DifficultySelect --> MazeGenerator : loads maze scene
    GameState --> Difficulty
    GameState --> MazeGenerator : level_completed, difficulty_changed
    GameState --> HUD : keys and lives signals
    GameState --> GameOverMenu : game_over
    PauseMenu ..> GameState : difficulty, mazes_completed
    GameOverMenu ..> GameState : set_difficulty()

    MazeGenerator ..> GeminiMazeService : requests layout
    GeminiMazeService --> MazeLayout : returns
    GeminiMazeService ..> EnvManager : API key
    MazeGenerator *-- WallSegment : many
    MazeGenerator *-- ForkTrigger : many
    MazeGenerator *-- ExitGate : 1
    MazeGenerator *-- Enemy : 0..1
    MazeGenerator *-- Player : 1
    Player *-- Flashlight

    ForkTrigger ..> TriviaManager : ask_random_question()
    TriviaManager *-- TriviaPopup
    TriviaManager ..> GameState : add_key()
    ExitGate ..> GameState : try_open_exit()
    Enemy ..> GameState : damage_player()
    Enemy ..> MazeGenerator : pathfinding
    Enemy ..> Player : chases
```

## Sequence: login, play, escape

```mermaid
sequenceDiagram
    actor User
    participant Auth as AuthMenu
    participant SB as Supabase Auth
    participant Diff as DifficultySelect
    participant GS as GameState
    participant Gem as Gemini 3.5 Flash (planned)
    participant Maze as MazeGenerator
    participant Triv as TriviaManager
    participant Exit as ExitGate

    User->>Auth: email + password
    Auth->>SB: SignIn / SignUp
    SB-->>Auth: session
    Auth->>Diff: show difficulty screen
    User->>Diff: choose Easy / Medium / Hard
    Diff->>GS: set_difficulty(level)
    Diff->>Maze: load maze scene
    Maze->>Gem: request maze layout (size, difficulty)
    Gem-->>Maze: maze layout (JSON)
    Note over Maze: Fall back to built-in DFS carving if the response is invalid
    Maze->>Maze: build walls, roof, fog, keys, stairs, enemy

    loop Exploring
        User->>Maze: reach a key
        Maze->>Triv: ask_random_question() (tree paused, enemy frozen)
        User->>Triv: answer
        alt correct
            Triv->>GS: add_key()
        else wrong
            Triv-->>Maze: relocate key
        end
    end

    User->>Exit: reach stairs
    Exit->>GS: try_open_exit()
    alt enough keys
        GS->>GS: mazes_completed[difficulty]++
        GS-->>Maze: level_completed (new maze, keys and hearts reset)
    else not enough keys
        GS-->>User: Locked message
    end
```

## State: game flow

```mermaid
stateDiagram-v2
    [*] --> Login
    Login --> DifficultySelect : authenticated (Supabase)
    DifficultySelect --> Playing : choose difficulty
    Playing --> Paused : Esc
    Paused --> Playing : Resume
    Paused --> Playing : change difficulty (new maze)
    Paused --> [*] : Quit
    Playing --> Question : reach key
    Question --> Playing : answer
    Playing --> Playing : escape stairs (new maze)
    Playing --> GameOver : hearts = 0
    GameOver --> Playing : Replay / change difficulty
    GameOver --> [*] : Quit
```
