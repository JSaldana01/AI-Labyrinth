using Godot;
using System;
using dotenv.net;

public partial class EnvManager : Node
{
	// CRITICAL!!! When building the exe file, make sure that .env is in file/folders included in the build.
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
		
		string envPath = "res://.env";
		if (FileAccess.FileExists(envPath))
		{
			using var file = FileAccess.Open(envPath, FileAccess.ModeFlags.Read);
			while (!file.EofReached())
			{
				string line = file.GetLine().Trim();
				if (line.StartsWith("SUPABASE_URL=")) 
					SupabaseUrl = line.Substring(13).Trim('"', '\'');
				else if (line.StartsWith("SUPABASE_KEY=")) 
					SupabaseKey = line.Substring(13).Trim('"', '\'');
			}
		}
		else
		{
			GD.PrintErr("CRITICAL: .env file not found.");
		}
		
		if (string.IsNullOrEmpty(SupabaseUrl) || string.IsNullOrEmpty(SupabaseKey))
		{
			GD.PrintErr("CRITICAL: Supabase environment variables are missing.");
		}
		
		//Might not be able to use this
		// // Cache the variables in memory
		// SupabaseUrl = System.Environment.GetEnvironmentVariable("SUPABASE_URL");
		// SupabaseKey = System.Environment.GetEnvironmentVariable("SUPABASE_KEY");
		//
		// if (string.IsNullOrEmpty(SupabaseUrl) || string.IsNullOrEmpty(SupabaseKey))
		// {
		// 	GD.PrintErr("CRITICAL: Supabase environment variables are missing.");
		// }
		
		DBManager.Initialize();
	}
}
