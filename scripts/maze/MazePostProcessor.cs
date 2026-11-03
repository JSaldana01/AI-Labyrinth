using System;
using System.Collections.Generic;

namespace Maze;

public static class MazePostProcessor
{
	public static void Apply(MazeDefinition def, MazeGenerationProfile profile, Random? rng = null)
	{
		rng ??= Random.Shared;
		double maxRatio = profile.Constraints?.MaxPlayerBlockingRatio ?? 0.05;
		ClampPlayerBlocking(def, maxRatio, rng);
		EnforceTriviaTags(def, profile, rng);
	}

	private static void ClampPlayerBlocking(MazeDefinition def, double maxRatio, Random rng)
	{
		int maxCount = (int)Math.Floor(def.Width * def.Height * maxRatio);
		var blocking = new List<(int X, int Y)>();
		for (int y = 0; y < def.Height; y++)
		for (int x = 0; x < def.Width; x++)
			if (def.Cells[y][x].PlayerBlocking)
				blocking.Add((x, y));

		if (blocking.Count <= maxCount)
			return;

		Shuffle(blocking, rng);
		for (int i = maxCount; i < blocking.Count; i++)
		{
			var (x, y) = blocking[i];
			def.Cells[y][x].PlayerBlocking = false;
		}
	}

	private static void EnforceTriviaTags(MazeDefinition def, MazeGenerationProfile profile, Random rng)
	{
		int forkMin = profile.ForkMinOpenSides;
		int keysRequired = profile.KeysRequired;
		int sx = def.Spawn[0];
		int sy = def.Spawn[1];
		int ex = def.Exit[0];
		int ey = def.Exit[1];

		for (int y = 0; y < def.Height; y++)
		for (int x = 0; x < def.Width; x++)
			def.Cells[y][x].Tags.RemoveAll(t => t == "trivia");

		var forks = new List<(int X, int Y)>();
		var others = new List<(int X, int Y)>();
		for (int y = 0; y < def.Height; y++)
		{
			for (int x = 0; x < def.Width; x++)
			{
				if (x == sx && y == sy) continue;
				if (x == ex && y == ey) continue;
				if (def.Cells[y][x].PlayerBlocking) continue;
				if (OpenSideCount(def.Cells[y][x]) >= forkMin)
					forks.Add((x, y));
				else
					others.Add((x, y));
			}
		}

		var chosen = new List<(int X, int Y)>(forks);
		if (chosen.Count < keysRequired)
		{
			Shuffle(others, rng);
			foreach (var p in others)
			{
				if (chosen.Count >= keysRequired) break;
				chosen.Add(p);
			}
		}
		else
		{
			Shuffle(chosen, rng);
			if (chosen.Count > keysRequired)
				chosen.RemoveRange(keysRequired, chosen.Count - keysRequired);
		}

		foreach (var (x, y) in chosen)
			def.Cells[y][x].Tags.Add("trivia");
	}

	private static int OpenSideCount(MazeCell cell)
	{
		int n = 0;
		if (!cell.Walls.N) n++;
		if (!cell.Walls.S) n++;
		if (!cell.Walls.E) n++;
		if (!cell.Walls.W) n++;
		return n;
	}

	private static void Shuffle<T>(List<T> list, Random rng)
	{
		for (int i = list.Count - 1; i > 0; i--)
		{
			int j = rng.Next(i + 1);
			(list[i], list[j]) = (list[j], list[i]);
		}
	}
}
