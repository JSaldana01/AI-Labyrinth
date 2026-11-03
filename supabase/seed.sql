-- Default maze generation profile (9x9, matches game keys_required = 3)
INSERT INTO public.maze_generation_profiles (slug, name, profile)
VALUES (
    'default-9x9',
    'Default 9×9 trivia maze',
    '{
        "schema_version": 1,
        "width": 9,
        "height": 9,
        "keys_required": 3,
        "fork_min_open_sides": 3,
        "spawn": [0, 0],
        "exit": [8, 8],
        "prompt": "Generate a solvable maze for an academic trivia game. Place the trivia tag on fork cells where the player chooses direction. Use player_blocking sparingly for obstacles.",
        "constraints": {
            "must_be_solvable": true,
            "max_player_blocking_ratio": 0.05
        },
        "cell_defaults": { "player_blocking": false },
        "allowed_tags": ["trivia"]
    }'::jsonb
)
ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    profile = EXCLUDED.profile,
    updated_at = NOW();
