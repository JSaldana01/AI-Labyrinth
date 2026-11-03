using Godot;
using System;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Supabase;

// Initialized in EnvManager.cs
public static class DBManager
{
	public static Client Supabase { get; private set; }

	public static System.Net.Http.HttpClient SharedHttpClient { get; } = new()
	{
		// Edge + Gemini can take 30–120s; avoid infinite hang (default 100s).
		Timeout = TimeSpan.FromSeconds(150),
	};

	private static Task? _initTask;

	public static void Initialize()
	{
		if (_initTask != null)
			return;

		string url = EnvManager.Instance.SupabaseUrl;
		string key = EnvManager.Instance.SupabaseKey;

		Supabase = new Client(url, key);
		_initTask = Supabase.InitializeAsync().ContinueWith(t =>
		{
			if (t.IsFaulted)
				GD.PrintErr("Failed to initialize supabase");
			else
				GD.Print("Supabase intiated successfully");
		});
	}

	public static Task EnsureInitializedAsync(CancellationToken cancellationToken = default)
	{
		if (_initTask == null)
			Initialize();
		return _initTask ?? Task.CompletedTask;
	}
}
