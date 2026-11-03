#nullable enable
using System;
using System.IO;
using Maze;

string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
string outPath = Path.Combine(root, "scripts", "maze", "fixtures", "local-default-9x9.json");
MazeFixtureExporter.ExportDefaultFixture(outPath);
Console.WriteLine($"Wrote {outPath}");

int code = MazeFixtureValidation.RunSelfTest();
code |= MazeFixtureValidation.ValidateFixtureFile(outPath);
Environment.Exit(code);
