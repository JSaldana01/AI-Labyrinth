using System;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace Maze;

public sealed class MazeGenerationService
{
	private readonly GeminiEdgeMazeGenerator _edge = new();
	private readonly LocalDfsMazeGenerator _local = new();

	public async Task<MazeLoadResult> RequestMazeAsync(
		string profileSlug = "default-9x9",
		bool preferLocalOnly = false,
		string? seedHint = null,
		CancellationToken cancellationToken = default)
	{
		MazeDebug.Log("Service", $"RequestMazeAsync profile={profileSlug} preferLocalOnly={preferLocalOnly}");

		var profile = LocalDfsMazeGenerator.DefaultProfile();
		var ctx = new MazeGenerationContext
		{
			Profile = profile,
			ProfileSlug = profileSlug,
			SeedHint = seedHint,
			Persist = !preferLocalOnly,
			PreferLocalOnly = preferLocalOnly,
		};

		if (preferLocalOnly || string.IsNullOrEmpty(EnvManager.Instance.SupabaseUrl))
		{
			string reason = preferLocalOnly
				? "PreferLocalOnly or no auth session"
				: "SUPABASE_URL missing in .env";
			MazeDebug.Log("Service", $"Using client local DFS ({reason}), persist=false");
			return await LoadLocalAsync(ctx, "client-local", cancellationToken);
		}

		MazeDebug.Log("Service",
			$"Calling edge function '{EnvManager.Instance.MazeEdgeFunction}' persist={ctx.Persist}");

		try
		{
			var edgeResult = await _edge.GenerateAsync(ctx, cancellationToken);
			if (edgeResult.Definition != null)
				MazeDebug.LogDefinitionSummary(edgeResult.Definition, $"edge/{edgeResult.Generator}");
			MazeDebug.Log("Service",
				$"Edge OK generator={edgeResult.Generator} maze_instance_id={edgeResult.MazeInstanceId ?? "(none)"}");
			return edgeResult;
		}
		catch (Exception ex)
		{
			MazeDebug.Warn("Service", $"Edge failed ({ex.Message}); falling back to client local DFS");
			return await LoadLocalAsync(ctx, "client-fallback", cancellationToken);
		}
	}

	private async Task<MazeLoadResult> LoadLocalAsync(
		MazeGenerationContext ctx,
		string sourceLabel,
		CancellationToken cancellationToken)
	{
		MazeDebug.Log("Service", $"LocalDfsMazeGenerator ({sourceLabel})...");
		var definition = await _local.GenerateAsync(ctx, cancellationToken);
		MazeDebug.LogDefinitionSummary(definition, sourceLabel);
		return new MazeLoadResult
		{
			Success = true,
			Definition = definition,
			Generator = "local",
		};
	}
}
