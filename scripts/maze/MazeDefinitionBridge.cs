using System.Text.Json;
using Godot;
using Godot.Collections;

namespace Maze;

public static class MazeDefinitionBridge
{
	private static readonly JsonSerializerOptions JsonOptions = new()
	{
		PropertyNameCaseInsensitive = true,
	};

	public static Dictionary ToGodotDictionary(MazeDefinition def)
	{
		string json = JsonSerializer.Serialize(def, JsonOptions);
		var parsed = Json.ParseString(json);
		if (parsed.VariantType == Variant.Type.Dictionary)
			return parsed.AsGodotDictionary();
		return new Dictionary();
	}
}
