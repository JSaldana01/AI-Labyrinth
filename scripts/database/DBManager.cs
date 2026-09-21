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
