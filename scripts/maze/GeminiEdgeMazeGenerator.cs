using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace Maze;

public sealed class GeminiEdgeMazeGenerator
{
	private static readonly JsonSerializerOptions JsonOptions = new()
	{
		PropertyNameCaseInsensitive = true,
	};

	public async Task<MazeLoadResult> GenerateAsync(MazeGenerationContext ctx, CancellationToken cancellationToken)
	{
		await DBManager.EnsureInitializedAsync(cancellationToken);

		var payload = new Dictionary<string, object?>
		{
			["profile_slug"] = ctx.ProfileSlug ?? "default-9x9",
			["persist"] = ctx.Persist,
			["use_local_only"] = false,
		};
		if (!string.IsNullOrEmpty(ctx.SeedHint))
			payload["seed_hint"] = ctx.SeedHint;

		string jsonBody = JsonSerializer.Serialize(payload);
		string functionSlug = string.IsNullOrWhiteSpace(EnvManager.Instance.MazeEdgeFunction)
			? "bright-service"
			: EnvManager.Instance.MazeEdgeFunction.Trim();
		string url = $"{EnvManager.Instance.SupabaseUrl.TrimEnd('/')}/functions/v1/{functionSlug}";

		var session = DBManager.Supabase?.Auth.CurrentSession;
		bool usingUserJwt = session != null && !string.IsNullOrEmpty(session.AccessToken);
		string bearer = usingUserJwt ? session!.AccessToken! : EnvManager.Instance.SupabaseKey;

		MazeDebug.Log("Edge",
			$"POST {functionSlug} persist={ctx.Persist} auth={(usingUserJwt ? "user JWT" : "anon/publishable key")}");
		MazeDebug.Log("Edge", $"body={jsonBody}");

		using var request = new HttpRequestMessage(HttpMethod.Post, url);
		request.Content = new StringContent(jsonBody, Encoding.UTF8, "application/json");
		request.Headers.TryAddWithoutValidation("apikey", EnvManager.Instance.SupabaseKey);
		request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {bearer}");

		var sw = Stopwatch.StartNew();
		MazeDebug.Log("Edge", "SendAsync starting (waiting for bright-service + Gemini on server)…");
		using var response = await DBManager.SharedHttpClient.SendAsync(request, cancellationToken);
		MazeDebug.Log("Edge", $"SendAsync headers received ({sw.ElapsedMilliseconds} ms), reading body…");
		string responseText = await response.Content.ReadAsStringAsync(cancellationToken);
		sw.Stop();

		MazeDebug.Log("Edge", $"HTTP {(int)response.StatusCode} {response.StatusCode} ({sw.ElapsedMilliseconds} ms)");
		MazeDebug.Log("Edge", "Response received — 3D maze not built until maze_ready on client");

		if (!response.IsSuccessStatusCode)
		{
			LogHttpFailure(functionSlug, response.StatusCode, responseText);
			throw new InvalidOperationException("Edge maze generation failed.");
		}

		using var doc = JsonDocument.Parse(responseText);
		if (doc.RootElement.TryGetProperty("error", out var errEl))
		{
			string errMsg = errEl.ValueKind == JsonValueKind.String
				? errEl.GetString() ?? "unknown"
				: errEl.ToString();
			MazeDebug.Error("Edge", $"Response error field: {errMsg}");
			throw new InvalidOperationException("Edge maze generation returned error.");
		}

		if (!doc.RootElement.TryGetProperty("definition", out var defEl))
		{
			MazeDebug.Error("Edge", "Response missing 'definition' property");
			throw new InvalidOperationException("Missing definition in edge response.");
		}

		var definition = defEl.Deserialize<MazeDefinition>(JsonOptions);
		if (definition == null || definition.SchemaVersion != 1)
		{
			MazeDebug.Error("Edge", $"Invalid definition schema_version={definition?.SchemaVersion}");
			throw new InvalidOperationException("Invalid maze definition from edge.");
		}

		string? instanceId = null;
		if (doc.RootElement.TryGetProperty("maze_instance_id", out var idEl) &&
		    idEl.ValueKind == JsonValueKind.String)
			instanceId = idEl.GetString();

		string generator = "gemini";
		if (doc.RootElement.TryGetProperty("generator", out var genEl) &&
		    genEl.ValueKind == JsonValueKind.String)
			generator = genEl.GetString() ?? generator;

		if (doc.RootElement.TryGetProperty("request_id", out var reqIdEl) &&
		    reqIdEl.ValueKind == JsonValueKind.String)
			MazeDebug.Log("Edge", $"request_id={reqIdEl.GetString()}");

		if (doc.RootElement.TryGetProperty("gemini_attempt", out var geminiAttempt))
			MazeDebug.LogGeminiAttempt(geminiAttempt);

		return new MazeLoadResult
		{
			Success = true,
			Definition = definition,
			MazeInstanceId = instanceId,
			Generator = generator,
		};
	}

	private static void LogHttpFailure(string functionSlug, System.Net.HttpStatusCode status, string responseText)
	{
		if (status == System.Net.HttpStatusCode.NotFound)
		{
			if (responseText.Contains("profile not found", StringComparison.OrdinalIgnoreCase))
			{
				MazeDebug.Error("Edge",
					"HTTP 404 profile not found — run migration/seed (default-9x9 in maze_generation_profiles). " +
					"See supabase/DEPLOY.md");
				return;
			}

			if (responseText.Contains("NOT_FOUND", StringComparison.OrdinalIgnoreCase) ||
			    responseText.Contains("Requested function was not found", StringComparison.OrdinalIgnoreCase))
			{
				MazeDebug.Error("Edge",
					$"HTTP 404 function '{functionSlug}' not deployed. Run: supabase functions deploy {functionSlug}");
				return;
			}
		}

		string snippet = responseText.Length > 400 ? responseText[..400] + "..." : responseText;
		MazeDebug.Error("Edge", $"HTTP {(int)status}: {snippet}");
	}
}
