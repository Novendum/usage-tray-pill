using System;
using System.Net;
using System.Threading;

// ReadWriteTimeout is per stream read. This deadline also bounds a slow trickle.
public sealed class UtpRequestDeadline : IDisposable
{
    private readonly Timer timer;
    public UtpRequestDeadline(WebRequest request, int milliseconds)
    {
        timer = new Timer(delegate { try { request.Abort(); } catch { } }, null, milliseconds, Timeout.Infinite);
    }
    public void Dispose() { timer.Dispose(); }
}
