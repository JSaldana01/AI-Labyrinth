-- Maze generation: profiles, instances, runs, and player_stats bootstrap

CREATE TABLE public.maze_generation_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    profile JSONB NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.maze_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES public.maze_generation_profiles(id) ON DELETE SET NULL,
    created_by UUID REFERENCES public."Profile"(id) ON DELETE SET NULL,
    definition JSONB NOT NULL,
    generator TEXT NOT NULL CHECK (generator IN ('gemini', 'local')),
    model TEXT,
    prompt_hash TEXT,
    status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('ready', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.player_maze_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public."Profile"(id) ON DELETE CASCADE,
    maze_instance_id UUID NOT NULL REFERENCES public.maze_instances(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    keys_collected INT NOT NULL DEFAULT 0,
    run_state JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX idx_maze_instances_created_by ON public.maze_instances (created_by, created_at DESC);
CREATE INDEX idx_maze_instances_profile ON public.maze_instances (profile_id, created_at DESC);
CREATE INDEX idx_maze_instances_definition ON public.maze_instances USING GIN (definition);
CREATE INDEX idx_player_maze_runs_user ON public.player_maze_runs (user_id, started_at DESC);

ALTER TABLE public.maze_generation_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maze_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_maze_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read active maze profiles"
    ON public.maze_generation_profiles
    FOR SELECT
    TO authenticated
    USING (is_active = true);

CREATE POLICY "Anon read active maze profiles"
    ON public.maze_generation_profiles
    FOR SELECT
    TO anon
    USING (is_active = true);

CREATE POLICY "Read own or shared maze instances"
    ON public.maze_instances
    FOR SELECT
    TO authenticated
    USING (created_by IS NULL OR created_by = auth.uid());

CREATE POLICY "Anon read shared maze instances"
    ON public.maze_instances
    FOR SELECT
    TO anon
    USING (created_by IS NULL);

CREATE POLICY "Players manage own maze runs select"
    ON public.player_maze_runs
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "Players manage own maze runs insert"
    ON public.player_maze_runs
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Players manage own maze runs update"
    ON public.player_maze_runs
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Players manage own maze runs delete"
    ON public.player_maze_runs
    FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

-- Create player_stats when Profile row is created
CREATE OR REPLACE FUNCTION private.sync_profile_to_player_stats()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.player_stats (id, mazes_completed)
    VALUES (NEW.id, 0)
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_profile_created_player_stats
    AFTER INSERT ON public."Profile"
    FOR EACH ROW
    EXECUTE PROCEDURE private.sync_profile_to_player_stats();

-- Optional RPC: fetch maze + ensure run row exists
CREATE OR REPLACE FUNCTION public.get_maze_for_play(p_instance_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_definition JSONB;
    v_run_id UUID;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'not authenticated';
    END IF;

    SELECT definition INTO v_definition
    FROM public.maze_instances
    WHERE id = p_instance_id
      AND status = 'ready'
      AND (created_by IS NULL OR created_by = v_user);

    IF v_definition IS NULL THEN
        RAISE EXCEPTION 'maze instance not found or not accessible';
    END IF;

    SELECT id INTO v_run_id
    FROM public.player_maze_runs
    WHERE user_id = v_user AND maze_instance_id = p_instance_id
    ORDER BY started_at DESC
    LIMIT 1;

    IF v_run_id IS NULL THEN
        INSERT INTO public.player_maze_runs (user_id, maze_instance_id)
        VALUES (v_user, p_instance_id)
        RETURNING id INTO v_run_id;
    END IF;

    RETURN jsonb_build_object(
        'maze_instance_id', p_instance_id,
        'player_maze_run_id', v_run_id,
        'definition', v_definition
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_maze_for_play(UUID) TO authenticated;
