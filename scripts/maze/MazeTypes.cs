using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Maze;

public sealed class WallSet
{
	[JsonPropertyName("N")] public bool N { get; set; } = true;
	[JsonPropertyName("S")] public bool S { get; set; } = true;
	[JsonPropertyName("E")] public bool E { get; set; } = true;
	[JsonPropertyName("W")] public bool W { get; set; } = true;
}

public sealed class MazeCell
{
	[JsonPropertyName("walls")] public WallSet Walls { get; set; } = new();
	[JsonPropertyName("player_blocking")] public bool PlayerBlocking { get; set; }
	[JsonPropertyName("tags")] public List<string> Tags { get; set; } = new();
	[JsonPropertyName("properties")] public Dictionary<string, object?> Properties { get; set; } = new();
}

public sealed class MazeDefinition
{
	[JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = 1;
	[JsonPropertyName("width")] public int Width { get; set; }
	[JsonPropertyName("height")] public int Height { get; set; }
	[JsonPropertyName("spawn")] public int[] Spawn { get; set; } = [0, 0];
	[JsonPropertyName("exit")] public int[] Exit { get; set; } = [0, 0];
	[JsonPropertyName("cells")] public List<List<MazeCell>> Cells { get; set; } = new();
	[JsonPropertyName("metadata")] public Dictionary<string, object?>? Metadata { get; set; }
}

public sealed class MazeGenerationProfile
{
	[JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = 1;
	[JsonPropertyName("width")] public int Width { get; set; }
	[JsonPropertyName("height")] public int Height { get; set; }
	[JsonPropertyName("keys_required")] public int KeysRequired { get; set; } = 3;
	[JsonPropertyName("fork_min_open_sides")] public int ForkMinOpenSides { get; set; } = 3;
	[JsonPropertyName("prompt")] public string? Prompt { get; set; }
	[JsonPropertyName("constraints")] public MazeProfileConstraints? Constraints { get; set; }
	[JsonPropertyName("cell_defaults")] public MazeCellDefaults? CellDefaults { get; set; }
	[JsonPropertyName("allowed_tags")] public List<string>? AllowedTags { get; set; }
	[JsonPropertyName("spawn")] public int[]? Spawn { get; set; }
	[JsonPropertyName("exit")] public int[]? Exit { get; set; }
}

public sealed class MazeProfileConstraints
{
	[JsonPropertyName("must_be_solvable")] public bool MustBeSolvable { get; set; } = true;
	[JsonPropertyName("max_player_blocking_ratio")] public double MaxPlayerBlockingRatio { get; set; } = 0.05;
}

public sealed class MazeCellDefaults
{
	[JsonPropertyName("player_blocking")] public bool PlayerBlocking { get; set; }
}

public sealed class MazeLoadResult
{
	public bool Success { get; init; }
	public MazeDefinition? Definition { get; init; }
	public string? MazeInstanceId { get; init; }
	public string Generator { get; init; } = "local";
	public string? ErrorMessage { get; init; }
}

public sealed class MazeGenerationContext
{
	public MazeGenerationProfile Profile { get; init; } = new();
	public string? ProfileSlug { get; init; }
	public string? SeedHint { get; init; }
	public string? MazeInstanceId { get; init; }
	public bool Persist { get; init; } = true;
	public bool PreferLocalOnly { get; init; }
}
