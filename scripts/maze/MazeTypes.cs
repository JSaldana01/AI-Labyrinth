using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Empty.scripts.maze;

public sealed class CellWalls
{
	[JsonPropertyName("N")] public bool N { get; set; } = true;
	[JsonPropertyName("S")] public bool S { get; set; } = true;
	[JsonPropertyName("E")] public bool E { get; set; } = true;
	[JsonPropertyName("W")] public bool W { get; set; } = true;
}

public sealed class MazeDefinitionDto
{
	[JsonPropertyName("width")] public int Width { get; set; }
	[JsonPropertyName("height")] public int Height { get; set; }
	[JsonPropertyName("spawn")] public int[] Spawn { get; set; } = [0, 0];
	[JsonPropertyName("exit")] public int[] Exit { get; set; } = [0, 0];
	[JsonPropertyName("cells")] public List<List<CellWalls>> Cells { get; set; } = [];
}

public sealed class GeminiAttemptDto
{
	[JsonPropertyName("attempted")] public bool Attempted { get; set; }
	[JsonPropertyName("success")] public bool Success { get; set; }
	[JsonPropertyName("model")] public string? Model { get; set; }
	[JsonPropertyName("reason")] public string? Reason { get; set; }
	[JsonPropertyName("detail")] public string? Detail { get; set; }
}

public sealed class MazeGenerateResponse
{
	[JsonPropertyName("definition")] public MazeDefinitionDto? Definition { get; set; }
	[JsonPropertyName("generator")] public string? Generator { get; set; }
	[JsonPropertyName("error")] public string? Error { get; set; }
	[JsonPropertyName("gemini_attempt")] public GeminiAttemptDto? GeminiAttempt { get; set; }
	[JsonPropertyName("maze_instance_id")] public string? MazeInstanceId { get; set; }
	[JsonPropertyName("request_id")] public string? RequestId { get; set; }
}