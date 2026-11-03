using Godot;
using Supabase;

// Initialized in EnvManager.cs
public static class DBManager
{
	public static Client Supabase { get; set; }
	
	public static void Initialize()
	{
		string url = EnvManager.Instance.SupabaseUrl;
		string key = EnvManager.Instance.SupabaseKey;

		if (string.IsNullOrEmpty(url) || string.IsNullOrEmpty(key))
		{
			GD.PrintErr("Supabase not initialized: SUPABASE_URL / SUPABASE_KEY missing.");
			return;
		}

		Supabase = new Client(url, key);
		_ = Supabase.InitializeAsync().ContinueWith(t =>
		{
			if (t.IsFaulted)
			{
				GD.PrintErr("Failed to initialize supabase");
			}
			else
			{
				GD.Print("Supabase intiated successfully");
			}
		});
	}
}
