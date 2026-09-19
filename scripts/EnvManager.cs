using Godot;
using System;
using dotenv.net;

public partial class EnvManager : Node
{
	public static EnvManager Instance { get; private set; }
	
	public string SupabaseUrl { get; private set; }
	public string SupabaseKey { get; private set; }

	public override void _EnterTree()
	{
		if (Instance != null)
		{
			QueueFree();
			return;
		}
		
		Instance = this;
		
		string env = ProjectSettings.GlobalizePath("res://.env");
		DotEnv.Load(options: new DotEnvOptions(envFilePaths: new[] { env }));

		// Cache the variables in memory
		SupabaseUrl = System.Environment.GetEnvironmentVariable("SUPABASE_URL");
		SupabaseKey = System.Environment.GetEnvironmentVariable("SUPABASE_KEY");

		if (string.IsNullOrEmpty(SupabaseUrl) || string.IsNullOrEmpty(SupabaseKey))
		{
			GD.PrintErr("CRITICAL: Supabase environment variables are missing.");
		}
		
		DBManager.Initialize();
	}
}
