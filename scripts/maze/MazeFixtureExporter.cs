using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Maze;

/// <summary>Run via: dotnet run --project tools/ExportMazeFixture/ExportMazeFixture.csproj</summary>
public static class MazeFixtureExporter
{
	private static readonly JsonSerializerOptions JsonOptions = new()
	{
		WriteIndented = true,
		DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
	};

	public static void ExportDefaultFixture(string outputPath)
	{
		var def = LocalDfsMazeGenerator.CreateDefaultProfileDefinition("fixture-seed");
		var errors = MazeDefinitionValidator.Validate(def);
		if (errors.Count > 0)
			throw new InvalidOperationException(string.Join("; ", errors));
		if (!MazeDefinitionValidator.HasPath(def))
			throw new InvalidOperationException("fixture maze has no path");

		Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
		File.WriteAllText(outputPath, JsonSerializer.Serialize(def, JsonOptions));
	}
}
