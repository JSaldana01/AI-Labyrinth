CREATE TABLE public."Profile" (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    username TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- RLS
ALTER TABLE public."Profile" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read profiles" ON public."Profile" FOR SELECT USING (true);

CREATE POLICY "Users can update their own profile" ON public."Profile" FOR UPDATE USING (auth.uid() = id); -- Metadata

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.sync_auth_user_to_profile()
       RETURNS TRIGGER AS $$
       BEGIN
        INSERT INTO public."Profile" AS p (
            id,
            email,
            username,
            created_at,
            updated_at
        )
        VALUES (
            NEW.id,
            NEW.email,
            NEW.raw_user_meta_data ->> 'name',
            coalesce(NEW.created_at, now()),
            coalesce(NEW.updated_at, now())
            )
        ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            username = COALESCE(p.username, EXCLUDED.username),
            updated_at = EXCLUDED.updated_at;
        RETURN NEW;
       END;
       $$ LANGUAGE plpgsql SECURITY DEFINER;
          
CREATE TRIGGER on_auth_user_created
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE private.sync_auth_user_to_profile();
                            

CREATE TABLE player_stats (
    id UUID PRIMARY KEY REFERENCES public."Profile"(id),
    mazes_completed INT DEFAULT 0
);

-- RLS
ALTER TABLE player_stats ENABLE ROW LEVEL SECURITY;

-- Policy: Players can only read and update their own progress
CREATE POLICY "Allow individual player read" ON player_stats FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Allow individual player update" ON player_stats FOR UPDATE USING (auth.uid() = id);