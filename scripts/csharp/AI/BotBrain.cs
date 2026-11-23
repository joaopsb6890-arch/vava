using Godot;

/// <summary>
/// Small C# decision component used by bot.gd.
/// Movement, perception, physics and visuals remain in GDScript/Godot.
/// </summary>
[GlobalClass]
public partial class BotBrain : RefCounted
{
    // A small retention bonus prevents bots from switching targets because
    // two visible enemies are almost exactly the same distance away.
    private const double CurrentTargetRetentionBonus = 0.75;

    /// <summary>
    /// Higher scores are preferred. The caller remains responsible for
    /// filtering dead, friendly, invisible and out-of-range candidates.
    /// </summary>
    public double ScoreCandidate(double distance, bool isCurrentTarget)
    {
        if (double.IsNaN(distance) || double.IsInfinity(distance) || distance < 0.0)
            return double.NegativeInfinity;

        return -distance + (isCurrentTarget ? CurrentTargetRetentionBonus : 0.0);
    }
}
