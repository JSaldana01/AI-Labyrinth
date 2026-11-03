using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json;

namespace Maze;

public sealed class CachedMazeGenerator : IMazeGenerator
{
	public async Task<MazeDefinition> GenerateAsync(MazeGenerationContext ctx, CancellationToken cancellationToken)
	{
		if (string.IsNullOrEmpty(ctx.MazeInstanceId))
			throw new InvalidOperationException("MazeInstanceId is required for cached generation.");

		await DBManager.EnsureInitializedAsync(cancellationToken);
		var response = await DBManager.Supabase!.Rpc(
			"get_maze_for_play",
			new Dictionary<string, object> { { "p_instance_id", ctx.MazeInstanceId } });

		if (response.Content == null)
			throw new InvalidOperationException("Cached maze not found.");

		var json = response.Content.ToString();
		if (string.IsNullOrWhiteSpace(json))
			throw new InvalidOperationException("Empty cached maze response.");

		using var doc = System.Text.Json.JsonDocument.Parse(json);
		if (!doc.RootElement.TryGetProperty("definition", out var defEl))
			throw new InvalidOperationException("Cached response missing definition.");

		var definition = defEl.Deserialize<MazeDefinition>();
		if (definition == null || definition.SchemaVersion != 1)
			throw new InvalidOperationException("Invalid cached maze definition.");

		return definition;
	}
}
