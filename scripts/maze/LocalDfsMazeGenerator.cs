using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace Maze;

/// <summary>Ports procedural DFS from maze_generator.gd for offline / fallback generation.</summary>
public sealed class LocalDfsMazeGenerator : IMazeGenerator
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

	public Task<MazeDefinition> GenerateAsync(MazeGenerationContext ctx, CancellationToken cancellationToken)
	{
		cancellationToken.ThrowIfCancellationRequested();
		var profile = ctx.Profile;
		var rng = CreateRng(ctx.SeedHint);

		int w = profile.Width;
		int h = profile.Height;
		var grid = new MazeCell[w, h];
		for (int x = 0; x < w; x++)
		for (int y = 0; y < h; y++)
			grid[x, y] = NewCell(profile);

		var visited = new HashSet<(int X, int Y)>();
		var stack = new Stack<(int X, int Y)>();
		stack.Push((0, 0));
		visited.Add((0, 0));

		while (stack.Count > 0)
		{
			cancellationToken.ThrowIfCancellationRequested();
			var current = stack.Peek();
			var candidates = UnvisitedNeighborDirs(current.X, current.Y, w, h, visited);
			if (candidates.Count == 0)
			{
				stack.Pop();
				continue;
			}

			string dir = candidates[rng.Next(candidates.Count)];
			var (dx, dy) = Dirs[dir];
			int nx = current.X + dx;
			int ny = current.Y + dy;
			SetWall(grid, current.X, current.Y, dir, false);
			SetWall(grid, nx, ny, Opposite[dir], false);
			visited.Add((nx, ny));
			stack.Push((nx, ny));
		}

		var def = GridToDefinition(profile, grid);
		MazePostProcessor.Apply(def, profile, rng);
		return Task.FromResult(def);
	}

	public static MazeDefinition CreateDefaultProfileDefinition(string? seedHint = null)
	{
		var profile = DefaultProfile();
		var gen = new LocalDfsMazeGenerator();
		return gen.GenerateAsync(new MazeGenerationContext
		{
			Profile = profile,
			SeedHint = seedHint,
		}, CancellationToken.None).GetAwaiter().GetResult();
	}

	public static MazeGenerationProfile DefaultProfile() => new()
	{
		SchemaVersion = 1,
		Width = 9,
		Height = 9,
		KeysRequired = 3,
		ForkMinOpenSides = 3,
		Spawn = [0, 0],
		Exit = [8, 8],
		Constraints = new MazeProfileConstraints(),
		CellDefaults = new MazeCellDefaults(),
	};

	private static Random CreateRng(string? seedHint)
	{
		if (string.IsNullOrEmpty(seedHint))
			return new Random();
		int seed = 0;
		foreach (char c in seedHint)
			seed = seed * 31 + c;
		return new Random(seed);
	}

	private static MazeCell NewCell(MazeGenerationProfile profile) => new()
	{
		Walls = new WallSet(),
		PlayerBlocking = profile.CellDefaults?.PlayerBlocking ?? false,
		Tags = new List<string>(),
		Properties = new Dictionary<string, object?>(),
	};

	private static List<string> UnvisitedNeighborDirs(int x, int y, int w, int h,
		HashSet<(int X, int Y)> visited)
	{
		var result = new List<string>();
		foreach (var (dir, offset) in Dirs)
		{
			int nx = x + offset.Dx;
			int ny = y + offset.Dy;
			if (nx < 0 || nx >= w || ny < 0 || ny >= h)
				continue;
			if (visited.Contains((nx, ny)))
				continue;
			result.Add(dir);
		}

		return result;
	}

	private static void SetWall(MazeCell[,] grid, int x, int y, string dir, bool value)
	{
		var walls = grid[x, y].Walls;
		switch (dir)
		{
			case "N": walls.N = value; break;
			case "S": walls.S = value; break;
			case "E": walls.E = value; break;
			case "W": walls.W = value; break;
		}
	}

	private static MazeDefinition GridToDefinition(MazeGenerationProfile profile, MazeCell[,] grid)
	{
		int w = profile.Width;
		int h = profile.Height;
		var spawn = profile.Spawn ?? [0, 0];
		var exit = profile.Exit ?? [w - 1, h - 1];
		var cells = new List<List<MazeCell>>();
		for (int y = 0; y < h; y++)
		{
			var row = new List<MazeCell>();
			for (int x = 0; x < w; x++)
			{
				var src = grid[x, y];
				row.Add(new MazeCell
				{
					Walls = new WallSet
					{
						N = src.Walls.N,
						S = src.Walls.S,
						E = src.Walls.E,
						W = src.Walls.W,
					},
					PlayerBlocking = src.PlayerBlocking,
					Tags = new List<string>(src.Tags),
					Properties = new Dictionary<string, object?>(src.Properties),
				});
			}

			cells.Add(row);
		}

		return new MazeDefinition
		{
			SchemaVersion = 1,
			Width = w,
			Height = h,
			Spawn = spawn,
			Exit = exit,
			Cells = cells,
			Metadata = new Dictionary<string, object?> { ["source"] = "local_dfs" },
		};
	}
}
