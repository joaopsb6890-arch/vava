using Godot;

/// <summary>
/// Tactical target scoring for the GDScript bot controller.
/// C# owns deterministic decision math; Godot/GDScript owns perception,
/// movement, physics, animation and combat presentation.
/// </summary>
[GlobalClass]
public partial class BotBrain : RefCounted
{
    private const double CurrentTargetRetentionBonus = 0.75;
    private const double MarkedTargetBonus = 4.0;
    private const double LowHealthBonus = 2.5;

    /// <summary>
    /// Higher scores are preferred. Kept as a simple fallback-compatible API.
    /// </summary>
    public double ScoreCandidate(double distance, bool isCurrentTarget)
    {
        return ScoreCandidate(distance, isCurrentTarget, false, 1.0);
    }

    /// <summary>
    /// Scores visible enemy candidates. Marked targets are easier to coordinate
    /// against and weakened targets are slightly preferred to secure eliminations.
    /// </summary>
    public double ScoreCandidate(
        double distance,
        bool isCurrentTarget,
        bool isMarked,
        double healthRatio)
    {
        if (double.IsNaN(distance) || double.IsInfinity(distance) || distance < 0.0)
            return double.NegativeInfinity;

        double safeHealth = double.IsNaN(healthRatio) || double.IsInfinity(healthRatio)
            ? 1.0
            : System.Math.Clamp(healthRatio, 0.0, 1.0);

        double score = -distance;
        if (isCurrentTarget)
            score += CurrentTargetRetentionBonus;
        if (isMarked)
            score += MarkedTargetBonus;

        // Do not make bots ignore nearby threats just to chase a weak enemy.
        score += (1.0 - safeHealth) * LowHealthBonus;
        return score;
    }

    /// <summary>
    /// Returns a bounded reaction delay for difficulty tuning.
    /// </summary>
    public double AdjustReaction(double baseSeconds, double pressure)
    {
        if (double.IsNaN(baseSeconds) || double.IsInfinity(baseSeconds))
            return 0.4;

        double safePressure = double.IsNaN(pressure) || double.IsInfinity(pressure)
            ? 0.0
            : System.Math.Clamp(pressure, 0.0, 1.0);

        return System.Math.Clamp(baseSeconds * (1.0 - safePressure * 0.15), 0.08, 2.0);
    }
}
