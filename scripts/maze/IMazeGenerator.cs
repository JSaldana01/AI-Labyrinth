using System.Threading;
using System.Threading.Tasks;

namespace Maze;

public interface IMazeGenerator
{
	Task<MazeDefinition> GenerateAsync(MazeGenerationContext ctx, CancellationToken cancellationToken);
}
