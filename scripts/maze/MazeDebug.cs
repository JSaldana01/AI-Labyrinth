using System;
using System.Text.Json;
using Godot;

namespace Maze;

/// <summary>Structured maze pipeline logs for the Godot Output panel.</summary>
public static class MazeDebug
{
	private const string Prefix = "[Maze]";

	public static void Log(string step, string message)
	{
		GD.Print($"{Prefix} {step}: {message}");
	}

	public static void Warn(string step, string message)
	{
		GD.PushWarning($"{Prefix} {step}: {message}");
	}

	public static void Error(string step, string message)
	{
		GD.PrintErr($"{Prefix} {step}: {message}");
	}

	/// <summary>Monotonic ms since loadStartedTicks (Godot Time.GetTicksMsec).</summary>
	public static void LogTimeline(string phase, ulong loadStartedTicks)
	{
		var elapsed = Time.GetTicksMsec() - loadStartedTicks;
		Log("Timeline", $"t={elapsed}ms {phase}");
	}

	public static void LogDefinitionSummary(MazeDefinition def, string source)
	{
		int trivia = 0;
		int blocking = 0;
		for (int y = 0; y < def.Height; y++)
		{
			for (int x = 0; x < def.Width; x++)
			{
				var cell = def.Cells[y][x];
				if (cell.PlayerBlocking) blocking++;
				if (cell.Tags != null && cell.Tags.Contains("trivia")) trivia++;
			}
		}

		string meta = def.Metadata != null && def.Metadata.TryGetValue("source", out var src)
			? src?.ToString() ?? ""
			: "";
		Log("Definition",
			$"source={source} size={def.Width}x{def.Height} " +
			$"spawn=[{def.Spawn[0]},{def.Spawn[1]}] exit=[{def.Exit[0]},{def.Exit[1]}] " +
			$"trivia_cells={trivia} blocking_cells={blocking}" +
			(string.IsNullOrEmpty(meta) ? "" : $" metadata.source={meta}"));
	}

	public static void LogGeminiAttempt(JsonElement attempt)
	{
		if (attempt.ValueKind != JsonValueKind.Object)
			return;

		string reason = attempt.TryGetProperty("reason", out var r) && r.ValueKind == JsonValueKind.String
			? r.GetString() ?? "?"
			: "?";
		string model = attempt.TryGetProperty("model", out var m) && m.ValueKind == JsonValueKind.String
			? m.GetString() ?? "?"
			: "?";
		bool success = attempt.TryGetProperty("success", out var s) &&
		               s.ValueKind == JsonValueKind.True;
		bool attempted = attempt.TryGetProperty("attempted", out var a) &&
		                 a.ValueKind == JsonValueKind.True;

		if (success)
		{
			string extra = attempt.TryGetProperty("detail", out var det) && det.ValueKind == JsonValueKind.String
				? det.GetString() ?? ""
				: "";
			Log("Gemini", string.IsNullOrEmpty(extra) ? $"SUCCESS model={model}" : $"SUCCESS model={model} ({extra})");
			return;
		}

		string detail = attempt.TryGetProperty("detail", out var d) && d.ValueKind == JsonValueKind.String
			? d.GetString() ?? ""
			: "";

		if (!attempted)
		{
			Warn("Gemini", $"skipped reason={reason} {detail}");
			return;
		}

		int? httpStatus = null;
		if (attempt.TryGetProperty("http_status", out var hs) && hs.TryGetInt32(out int code))
			httpStatus = code;

		var msg = $"FAILED reason={reason} model={model}";
		if (httpStatus.HasValue)
			msg += $" http_status={httpStatus.Value}";
		if (!string.IsNullOrEmpty(detail))
			msg += $" detail={detail}";

		if (attempt.TryGetProperty("validation_errors", out var ve) &&
		    ve.ValueKind == JsonValueKind.Array)
		{
			var parts = new System.Collections.Generic.List<string>();
			foreach (var item in ve.EnumerateArray())
			{
				if (parts.Count >= 5) break;
				parts.Add(item.ToString());
			}
			if (parts.Count > 0)
				msg += " validation_errors=[" + string.Join("; ", parts) + "]";
		}

		Warn("Gemini", msg + " → maze uses server local DFS fallback");
	}
}
