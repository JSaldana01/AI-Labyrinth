using System;
using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Godot;
using Godot.Collections;

namespace Empty.scripts.maze;

public partial class Generation : Node
{
	private const int HttpTimeoutSeconds = 15;

	private static readonly JsonSerializerOptions JsonOptions = new()
	{
		PropertyNameCaseInsensitive = true,
	};

	private System.Net.Http.HttpClient? _http;

	public override void _Ready()
	{
		_http = new System.Net.Http.HttpClient { Timeout = TimeSpan.FromSeconds(HttpTimeoutSeconds) };
	}

	public override void _ExitTree()
	{
		_http?.Dispose();
		_http = null;
	}

	/// <summary>Called from maze_generator.gd — does not block the main thread.</summary>
	public void RequestMaze(int width, int height, string profileSlug, string? seedHint = null)
	{
		_ = FetchAndDeliverAsync(width, height, profileSlug, seedHint);
	}

	private async Task FetchAndDeliverAsync(
		int width,
		int height,
		string profileSlug,
		string? seedHint)
	{
		var parent = GetParent();
		if (parent == null)
		{
			return;
		}

		var url = EnvManager.Instance?.SupabaseUrl;
		var key = EnvManager.Instance?.SupabaseKey;
		var session = DBManager.Supabase?.Auth.CurrentSession;
		var isSignedIn = !string.IsNullOrEmpty(session?.AccessToken);

		if (_http == null || string.IsNullOrEmpty(url) || string.IsNullOrEmpty(key))
		{
			GD.Print("[Maze] Supabase URL/key missing — will use client DFS.");
			CallDeferredOnParent(parent, null, "client", "missing_supabase_config", "");
			return;
		}

		var endpoint = $"{url.TrimEnd('/')}/functions/v1/bright-service";
		var sw = Stopwatch.StartNew();

		try
		{
			GD.Print(
				$"[Maze] Requesting bright-service profile={profileSlug} size={width}x{height} " +
				$"persist={isSignedIn} seed={seedHint ?? "(none)"}");
			using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
			// @supabase/server: publishable/secret keys go in `apikey`, not Authorization Bearer.
			request.Headers.TryAddWithoutValidation("apikey", key);
			if (isSignedIn)
			{
				request.Headers.Authorization =
					new AuthenticationHeaderValue("Bearer", session.AccessToken);
			}

			request.Content = new StringContent(
				JsonSerializer.Serialize(new
				{
					profile_slug = profileSlug,
					width,
					height,
					persist = isSignedIn,
					use_local_only = false,
					seed_hint = seedHint,
				}),
				Encoding.UTF8,
				"application/json");

			using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(HttpTimeoutSeconds));
			using var response = await _http.SendAsync(request, cts.Token).ConfigureAwait(false);
			var body = await response.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false);

			sw.Stop();
			if (!response.IsSuccessStatusCode)
			{
				GD.PrintErr(
					$"[Maze] HTTP {(int)response.StatusCode} after {sw.ElapsedMilliseconds}ms — client DFS fallback. Body: {body}");
				CallDeferredOnParent(parent, null, "client", "http_error", "");
				return;
			}

			var parsed = JsonSerializer.Deserialize<MazeGenerateResponse>(body, JsonOptions);
			if (parsed?.Definition == null)
			{
				var err = parsed?.Error ?? "no_definition";
				GD.PrintErr($"[Maze] Edge returned no definition ({err}) — client DFS fallback.");
				CallDeferredOnParent(parent, null, "client", err, "");
				return;
			}

			LogEdgeSuccess(parsed, sw.ElapsedMilliseconds);

			var dict = DefinitionToDictionary(parsed.Definition);
			var generator = parsed.Generator ?? "local";
			CallDeferredOnParent(parent, dict, generator, "", FormatDebugDetail(parsed));
		}
		catch (Exception ex)
		{
			sw.Stop();
			GD.PrintErr($"[Maze] Request failed after {sw.ElapsedMilliseconds}ms: {ex.Message} — client DFS fallback.");
			CallDeferredOnParent(parent, null, "client", "exception", ex.Message);
		}
	}

	private static void LogEdgeSuccess(MazeGenerateResponse parsed, long elapsedMs)
	{
		var generator = parsed.Generator ?? "local";
		var ga = parsed.GeminiAttempt;
		var geminiPart = ga == null
			? ""
			: $" | Gemini: attempted={ga.Attempted} success={ga.Success} model={ga.Model} reason={ga.Reason}";
		GD.Print($"[Maze] HTTP 200 OK in {elapsedMs}ms | generator={generator}{geminiPart}");
		if (generator == "gemini")
		{
			GD.Print("[Maze] Maze layout produced by Gemini (path hint + edge DFS completion).");
		}
		else
		{
			GD.Print("[Maze] Maze layout produced on edge by local DFS (Gemini skipped or failed).");
			if (ga != null && !string.IsNullOrEmpty(ga.Detail))
			{
				GD.Print($"[Maze] Gemini detail: {ga.Detail}");
			}
		}

		if (!string.IsNullOrEmpty(parsed.MazeInstanceId))
		{
			GD.Print($"[Maze] Saved maze_instances id={parsed.MazeInstanceId}");
		}
	}

	private static string FormatDebugDetail(MazeGenerateResponse parsed)
	{
		var ga = parsed.GeminiAttempt;
		if (ga == null)
		{
			return "";
		}

		return $"gemini reason={ga.Reason ?? "?"} model={ga.Model ?? "?"}";
	}

	private static Godot.Collections.Dictionary DefinitionToDictionary(MazeDefinitionDto def)
	{
		var cellsArray = new Godot.Collections.Array();
		foreach (var column in def.Cells)
		{
			var col = new Godot.Collections.Array();
			foreach (var cell in column)
			{
				col.Add(new Godot.Collections.Dictionary
				{
					["N"] = cell.N,
					["S"] = cell.S,
					["E"] = cell.E,
					["W"] = cell.W,
				});
			}
			cellsArray.Add(col);
		}

		return new Godot.Collections.Dictionary
		{
			["width"] = def.Width,
			["height"] = def.Height,
			["spawn"] = new Godot.Collections.Array { def.Spawn[0], def.Spawn[1] },
			["exit"] = new Godot.Collections.Array { def.Exit[0], def.Exit[1] },
			["cells"] = cellsArray,
		};
	}

	private void CallDeferredOnParent(
		Node parent,
		Godot.Collections.Dictionary? definition,
		string generator,
		string? failReason,
		string debugDetail)
	{
		Callable.From(() =>
		{
			parent.Call("on_maze_loaded", definition, generator, failReason ?? "", debugDetail);
		}).CallDeferred();
	}
}