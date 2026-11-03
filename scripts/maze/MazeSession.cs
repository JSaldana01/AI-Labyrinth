using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using Godot;
using Godot.Collections;

namespace Maze;

public partial class MazeSession : Node
{
	[Signal]
	public delegate void MazeReadyEventHandler();

	[Export] public string ProfileSlug { get; set; } = "default-9x9";

	[Export] public bool PreferLocalOnly { get; set; }

	[Export] public bool UseLocalFallbackOnError { get; set; } = true;

	public MazeDefinition? CurrentDefinition { get; private set; }

	public string? MazeInstanceId { get; private set; }

	public string Generator { get; private set; } = "local";

	public bool MazeDefinitionReady { get; private set; }

	/// <summary>Godot ticks when this scene started loading (shared with GDScript timeline).</summary>
	public ulong LoadStartedTicksMsec { get; private set; }

	/// <summary>Last edge/network round-trip only (Gemini runs inside this).</summary>
	public long LastNetworkLoadMs { get; private set; }

	public Dictionary DefinitionDictionary =>
		CurrentDefinition != null
			? MazeDefinitionBridge.ToGodotDictionary(CurrentDefinition)
			: new Dictionary();

	private readonly MazeGenerationService _service = new();

	public override void _Ready()
	{
		LoadStartedTicksMsec = Time.GetTicksMsec();
		MazeDebug.LogTimeline(
			"scene entered — waiting on network/Gemini (Walls node still empty)",
			LoadStartedTicksMsec);
		MazeDebug.Log("Session", "MazeSession _Ready — starting load");
		_ = LoadWhenReadyAsync();
	}

	private async Task LoadWhenReadyAsync()
	{
		await DBManager.EnsureInitializedAsync();
		if (!PreferLocalOnly && DBManager.Supabase?.Auth.CurrentSession == null)
		{
			PreferLocalOnly = true;
			MazeDebug.Log("Session", "No Supabase user session → PreferLocalOnly=true (test/guest path)");
		}
		else if (!PreferLocalOnly)
		{
			var user = DBManager.Supabase?.Auth.CurrentUser;
			MazeDebug.Log("Session", $"Authenticated user id={user?.Id ?? "?"} → will call edge");
		}

		await LoadMazeAsync();
	}

	public Dictionary GetDefinitionDictionary() => DefinitionDictionary;

	/// <summary>Callable from GDScript as <c>is_maze_definition_ready()</c> (avoids Godot Node.is_ready name clash).</summary>
	public bool IsMazeDefinitionReady() => MazeDefinitionReady;

	public async Task LoadMazeAsync(CancellationToken cancellationToken = default)
	{
		MazeDefinitionReady = false;
		MazeDebug.Log("Session", $"LoadMazeAsync profile={ProfileSlug}");

		var sw = Stopwatch.StartNew();
		var result = await _service.RequestMazeAsync(
			ProfileSlug,
			PreferLocalOnly,
			seedHint: null,
			cancellationToken);
		sw.Stop();

		if (!result.Success || result.Definition == null)
		{
			Callable.From(() =>
				MazeDebug.Error("Session", result.ErrorMessage ?? "Maze load failed.")).CallDeferred();
			return;
		}

		// Assign state on this thread; Godot node/builder notification must run on main thread.
		var captured = result;
		Callable.From(() => ApplyLoadResult(captured, sw.ElapsedMilliseconds)).CallDeferred();
	}

	private void ApplyLoadResult(MazeLoadResult result, long elapsedMs)
	{
		CurrentDefinition = result.Definition;
		MazeInstanceId = result.MazeInstanceId;
		Generator = result.Generator;
		MazeDefinitionReady = true;
		LastNetworkLoadMs = elapsedMs;

		MazeDebug.LogTimeline(
			$"edge+Gemini finished (network {LastNetworkLoadMs}ms) — JSON in memory, 3D walls NOT built yet",
			LoadStartedTicksMsec);
		MazeDebug.Log("Session",
			$"MazeReady generator={Generator} maze_instance_id={MazeInstanceId ?? "(none)"} " +
			$"load_time_ms={LastNetworkLoadMs}");
		MazeDebug.LogTimeline(
			"scheduling builder on_maze_session_ready on main thread",
			LoadStartedTicksMsec);

		FinishLoadOnMainThread(LoadStartedTicksMsec);
	}

	private void FinishLoadOnMainThread(ulong loadStart)
	{
		MazeDebug.LogTimeline("notifying builder (on_maze_session_ready)", loadStart);
		EmitSignal(SignalName.MazeReady);
		NotifyBuilderParent();
	}

	/// <summary>GDScript on parent cannot reliably connect to C# [Signal]; invoke builder directly.</summary>
	private void NotifyBuilderParent()
	{
		var parent = GetParent();
		if (parent == null)
		{
			MazeDebug.Error("Session", "No parent node to notify for maze build");
			return;
		}

		// Leading-underscore GDScript methods are not callable from C# — use public name.
		const string builderMethod = "on_maze_session_ready";
		if (!parent.HasMethod(builderMethod))
		{
			MazeDebug.Error("Session",
				$"Parent '{parent.Name}' missing {builderMethod}() — attach maze_generator.gd to Maze root");
			return;
		}

		parent.Call(builderMethod, DefinitionDictionary, Generator, MazeInstanceId ?? "", LastNetworkLoadMs);
		MazeDebug.Log("Session",
			$"Called parent.{builderMethod}(definition, …) — 3D build should start now");
	}
}