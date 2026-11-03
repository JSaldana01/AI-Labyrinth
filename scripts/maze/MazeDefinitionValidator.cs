using System.Collections.Generic;

namespace Maze;

public static class MazeDefinitionValidator
{
	private static readonly Dictionary<string, (int Dx, int Dy)> Dirs = new()
	{
		["N"] = (0, 1),
		["S"] = (0, -1),
		["E"] = (1, 0),
		["W"] = (-1, 0),
	};

	private static readonly Dictionary<string, string> Opposite = new()
	{
		["N"] = "S",
		["S"] = "N",
		["E"] = "W",
		["W"] = "E",
	};

	public static IReadOnlyList<string> Validate(MazeDefinition def)
	{
		var errors = new List<string>();
		if (def.SchemaVersion != 1)
			errors.Add($"unsupported schema_version {def.SchemaVersion}");

		if (def.Cells == null || def.Cells.Count != def.Height)
			errors.Add("cells height mismatch");

		for (int y = 0; y < def.Height && def.Cells != null; y++)
		{
			if (def.Cells[y].Count != def.Width)
			{
				errors.Add($"cells width mismatch at row {y}");
				break;
			}
		}

		if (def.Spawn == null || def.Spawn.Length < 2 || def.Exit == null || def.Exit.Length < 2)
		{
			errors.Add("spawn/exit missing");
			return errors;
		}

		if (!InBounds(def, def.Spawn[0], def.Spawn[1]))
			errors.Add("spawn out of bounds");
		if (!InBounds(def, def.Exit[0], def.Exit[1]))
			errors.Add("exit out of bounds");

		for (int y = 0; y < def.Height; y++)
		for (int x = 0; x < def.Width; x++)
		{
			var cell = def.Cells[y][x];
			foreach (var (dir, offset) in Dirs)
			{
				int nx = x + offset.Dx;
				int ny = y + offset.Dy;
				if (!InBounds(def, nx, ny))
					continue;
				string opp = Opposite[dir];
				bool a = GetWall(cell, dir);
				bool b = GetWall(def.Cells[ny][nx], opp);
				if (a != b)
					errors.Add($"wall mismatch {x},{y} {dir}");
			}
		}

		return errors;
	}

	public static bool HasPath(MazeDefinition def)
	{
		int sx = def.Spawn[0];
		int sy = def.Spawn[1];
		int ex = def.Exit[0];
		int ey = def.Exit[1];
		if (def.Cells[sy][sx].PlayerBlocking || def.Cells[ey][ex].PlayerBlocking)
			return false;

		var seen = new HashSet<(int X, int Y)>();
		var q = new Queue<(int X, int Y)>();
		q.Enqueue((sx, sy));
		seen.Add((sx, sy));

		while (q.Count > 0)
		{
			var (x, y) = q.Dequeue();
			if (x == ex && y == ey)
				return true;
			foreach (var (dir, offset) in Dirs)
			{
				if (GetWall(def.Cells[y][x], dir))
					continue;
				int nx = x + offset.Dx;
				int ny = y + offset.Dy;
				if (!InBounds(def, nx, ny))
					continue;
				if (def.Cells[ny][nx].PlayerBlocking)
					continue;
				if (!seen.Add((nx, ny)))
					continue;
				q.Enqueue((nx, ny));
			}
		}

		return false;
	}

	private static bool InBounds(MazeDefinition def, int x, int y) =>
		x >= 0 && x < def.Width && y >= 0 && y < def.Height;

	private static bool GetWall(MazeCell cell, string dir) => dir switch
	{
		"N" => cell.Walls.N,
		"S" => cell.Walls.S,
		"E" => cell.Walls.E,
		"W" => cell.Walls.W,
		_ => true,
	};
}
