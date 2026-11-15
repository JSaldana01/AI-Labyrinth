INSERT INTO public.maze_generation_profiles (slug, name, profile) VALUES
(
  'easy-5x5',
  'Easy 5x5',
  '{"width":5,"height":5,"keys_required":2,"fork_min_open_sides":3,"spawn":[0,0],"exit":[4,4]}'::jsonb
),
(
  'medium-6x6',
  'Medium 6x6',
  '{"width":6,"height":6,"keys_required":3,"fork_min_open_sides":3,"spawn":[0,0],"exit":[5,5]}'::jsonb
),
(
  'hard-8x8',
  'Hard 8x8',
  '{"width":8,"height":8,"keys_required":3,"fork_min_open_sides":3,"spawn":[0,0],"exit":[7,7]}'::jsonb
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  profile = EXCLUDED.profile,
  is_active = true,
  updated_at = NOW();