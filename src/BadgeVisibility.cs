using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

public enum UtpTaskbarHit { Unknown, Taskbar, Desktop, OwnWindow, Application }

public struct UtpTaskbarSample
{
    public UtpTaskbarHit Kind;
    public Rectangle Bounds;
    public UtpTaskbarSample(UtpTaskbarHit kind, Rectangle bounds) { Kind = kind; Bounds = bounds; }
}

// Reads only. Foreground focus is intentionally absent: a modal over a fullscreen
// browser does not expose the taskbar beneath that browser.
public sealed class UtpBadgeVisibility
{
    public bool Hidden { get; private set; }
    private int agreement;
    public void Reset(bool hidden) { Hidden = hidden; agreement = 0; }
    public bool Update(bool? candidate)
    {
        if (!candidate.HasValue || candidate.Value == Hidden) { agreement = 0; return Hidden; }
        if (++agreement >= 2) { Hidden = candidate.Value; agreement = 0; }
        return Hidden;
    }

    private static bool Valid(Rectangle rect) { return rect.Width > 0 && rect.Height > 0; }
    private static bool Collapsed(Rectangle monitor, Rectangle taskbar)
    {
        Rectangle visible = Rectangle.Intersect(monitor, taskbar);
        return taskbar.Width >= taskbar.Height ? visible.Height <= 2 : visible.Width <= 2;
    }
    private static bool Covers(Rectangle window, Rectangle monitor)
    {
        return Valid(window) && window.Left <= monitor.Left + 2 && window.Top <= monitor.Top + 2 &&
            window.Right >= monitor.Right - 2 && window.Bottom >= monitor.Bottom - 2;
    }
    public static bool? Classify(Rectangle monitor, Rectangle taskbar, bool autoHide, UtpTaskbarSample[] samples)
    {
        if (!Valid(monitor) || !Valid(taskbar)) return null;
        if (autoHide && Collapsed(monitor, taskbar)) return true;
        if (!Valid(Rectangle.Intersect(monitor, taskbar)) || samples == null || samples.Length == 0) return null;
        bool unknown = false, covered = false;
        foreach (UtpTaskbarSample sample in samples) {
            if (sample.Kind == UtpTaskbarHit.Taskbar || sample.Kind == UtpTaskbarHit.Desktop || sample.Kind == UtpTaskbarHit.OwnWindow) return false;
            if (sample.Kind == UtpTaskbarHit.Unknown || !Valid(sample.Bounds)) unknown = true;
            else if (Covers(sample.Bounds, monitor)) covered = true;
        }
        return unknown ? (bool?)null : covered;
    }

    [StructLayout(LayoutKind.Sequential)] private struct PointNative { public int X, Y; public PointNative(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] private struct RectNative {
        public int Left, Top, Right, Bottom;
        public Rectangle Rectangle { get { return Rectangle.FromLTRB(Left, Top, Right, Bottom); } }
    }
    [StructLayout(LayoutKind.Sequential)] private struct AppBarData {
        public uint Size; public IntPtr Window; public uint Callback, Edge; public RectNative Rect; public IntPtr Parameter;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindow(string className, string title);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out RectNative rect);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(PointNative point);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] private static extern IntPtr GetDesktopWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder text, int length);
    [DllImport("shell32.dll")] private static extern UIntPtr SHAppBarMessage(uint message, ref AppBarData data);

    private static UtpTaskbarSample ReadPoint(Point point, IntPtr taskbar, IntPtr own)
    {
        IntPtr hit = WindowFromPoint(new PointNative(point.X, point.Y));
        if (hit == IntPtr.Zero) return new UtpTaskbarSample();
        IntPtr root = GetAncestor(hit, 2); // GA_ROOT, including XAML taskbar children.
        if (root == IntPtr.Zero) return new UtpTaskbarSample();
        RectNative rect;
        if (!GetWindowRect(root, out rect)) return new UtpTaskbarSample();
        if (root == own && own != IntPtr.Zero) return new UtpTaskbarSample(UtpTaskbarHit.OwnWindow, rect.Rectangle);
        if (root == taskbar) return new UtpTaskbarSample(UtpTaskbarHit.Taskbar, rect.Rectangle);
        var name = new StringBuilder(256);
        if (GetClassName(root, name, name.Capacity) == 0) return new UtpTaskbarSample();
        string kind = name.ToString();
        if (root == GetShellWindow() || root == GetDesktopWindow() || kind == "Progman" || kind == "WorkerW")
            return new UtpTaskbarSample(UtpTaskbarHit.Desktop, rect.Rectangle);
        return new UtpTaskbarSample(UtpTaskbarHit.Application, rect.Rectangle);
    }

    public static bool? ReadHideCandidate(Rectangle monitor, Rectangle pill, IntPtr pillWindow)
    {
        try {
            IntPtr taskbar = FindWindow("Shell_TrayWnd", null);
            RectNative rect;
            if (taskbar == IntPtr.Zero || !GetWindowRect(taskbar, out rect)) return null;
            Rectangle bar = rect.Rectangle;
            var data = new AppBarData { Size = (uint)Marshal.SizeOf(typeof(AppBarData)), Window = taskbar };
            bool autoHide = (SHAppBarMessage(4, ref data).ToUInt64() & 1) != 0; // ABM_GETSTATE / ABS_AUTOHIDE.
            if (!Valid(monitor) || !Valid(bar)) return null;
            if (autoHide && Collapsed(monitor, bar)) return true;
            Rectangle visible = Rectangle.Intersect(monitor, bar);
            if (!Valid(visible)) return null;
            var samples = new List<UtpTaskbarSample>();
            // Two separated points, with alternatives when the pill covers one.
            foreach (double fraction in new double[] { 0.05, 0.95, 0.25, 0.75, 0.5 }) {
                Point point = bar.Width >= bar.Height
                    ? new Point(visible.Left + (int)((visible.Width - 1) * fraction), visible.Top + visible.Height / 2)
                    : new Point(visible.Left + visible.Width / 2, visible.Top + (int)((visible.Height - 1) * fraction));
                if (pill.Contains(point)) continue;
                samples.Add(ReadPoint(point, taskbar, pillWindow));
                if (samples.Count == 2) break;
            }
            return Classify(monitor, bar, autoHide, samples.ToArray());
        } catch { return null; }
    }
}
