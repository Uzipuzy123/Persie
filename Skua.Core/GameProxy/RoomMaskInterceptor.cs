using System.Text.RegularExpressions;
using Skua.Core.Interfaces;
using Skua.Core.Models;

namespace Skua.Core.GameProxy;

public class RoomMaskInterceptor : IInterceptor
{
    private static readonly Regex _namePattern =
        new(@"bludrutbrawl-\d+", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    // Matches the numeric room ID as a JSON value or a bare %-delimited field.
    private Regex? _roomNumPattern;

    public int Priority => 100;

    public void SetRoom(string roomNumber)
    {
        // Matches e.g. "curRoom":1234  or  %1234%  or  |1234|
        _roomNumPattern = new Regex(
            $@"(?<=[:""|%|]){Regex.Escape(roomNumber)}(?=[,""\s%|}}])",
            RegexOptions.Compiled);
    }

    public void Intercept(MessageInfo message, bool outbound)
    {
        // Only mask inbound packets — server needs the real name for routing.
        if (outbound) return;

        if (_namePattern.IsMatch(message.Content))
            message.Content = _namePattern.Replace(message.Content, "bludrutbrawl-????");

        if (_roomNumPattern != null && _roomNumPattern.IsMatch(message.Content))
            message.Content = _roomNumPattern.Replace(message.Content, "????");
    }
}
