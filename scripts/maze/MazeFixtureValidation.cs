using System;
using System.IO;
using System.Text.Json;
using Maze;

namespace Maze;

public static class MazeFixtureValidation
{
	public static int RunSelfTest()
	{
		var def = LocalDfsMazeGenerator.CreateDefaultProfileDefinition("self-test");
		var errors = MazeDefinitionValidator.Validate(def);
		if (errors.Count > 0)
		{
			Console.Error.WriteLine("validation errors: " + string.Join("; ", errors));
			return 1;
		}

		if (!MazeDefinitionValidator.HasPath(def))
		{
			Console.Error.WriteLine("maze has no path from spawn to exit");
			return 1;
		}

		Console.WriteLine("MazeDefinitionValidator self-test passed.");
		return 0;
	}

	public static int ValidateFixtureFile(string path)
	{
		if (!File.Exists(path))
		{
			Console.Error.WriteLine("fixture not found: " + path);
			return 1;
		}

		var def = JsonSerializer.Deserialize<MazeDefinition>(File.ReadAllText(path));
		if (def == null)
		{
			Console.Error.WriteLine("fixture deserialize failed");
			return 1;
		}

		var errors = MazeDefinitionValidator.Validate(def);
		if (errors.Count > 0)
		{
			Console.Error.WriteLine("fixture invalid: " + string.Join("; ", errors));
			return 1;
		}

		if (!MazeDefinitionValidator.HasPath(def))
		{
			Console.Error.WriteLine("fixture has no solvable path");
			return 1;
		}

		Console.WriteLine("fixture validation passed: " + path);
		return 0;
	}
}
