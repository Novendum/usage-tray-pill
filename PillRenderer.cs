using System;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// The window and all of its content share one alpha surface. No binary HRGN
// and no opaque child windows can cut into the antialiased outside curve.
public class UtpPillForm : Form
{
    [StructLayout(LayoutKind.Sequential)] private struct PointNative { public int X, Y; public PointNative(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] private struct SizeNative { public int Width, Height; public SizeNative(int w, int h) { Width = w; Height = h; } }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] private struct Blend { public byte Operation, Flags, Alpha, Format; }
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr dc, IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr value);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UpdateLayeredWindow(IntPtr window, IntPtr screen, ref PointNative destination,
        ref SizeNative size, IntPtr source, ref PointNative origin, int key, ref Blend blend, int flags);

    public bool PresentEnabled { get; set; }
    public UtpPillForm() { PresentEnabled = true; }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { var p = base.CreateParams; p.ExStyle |= 0x00080000 | 0x08000000 | 0x00000080; return p; }
    }
    protected override void OnPaintBackground(PaintEventArgs e) { }
    protected override void OnPaint(PaintEventArgs e) { }

    public void Present(Bitmap bitmap)
    {
        if (!PresentEnabled || IsDisposed) return;
        IntPtr screen = GetDC(IntPtr.Zero);
        IntPtr memory = IntPtr.Zero, nativeBitmap = IntPtr.Zero, previous = IntPtr.Zero;
        try {
            memory = CreateCompatibleDC(screen);
            nativeBitmap = bitmap.GetHbitmap(Color.FromArgb(0));
            previous = SelectObject(memory, nativeBitmap);
            var location = new PointNative(Left, Top);
            var origin = new PointNative(0, 0);
            var size = new SizeNative(bitmap.Width, bitmap.Height);
            var blend = new Blend { Operation = 0, Flags = 0, Alpha = 255, Format = 1 };
            if (!UpdateLayeredWindow(Handle, screen, ref location, ref size, memory, ref origin, 0, ref blend, 2))
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        finally {
            if (previous != IntPtr.Zero && memory != IntPtr.Zero) SelectObject(memory, previous);
            if (nativeBitmap != IntPtr.Zero) DeleteObject(nativeBitmap);
            if (memory != IntPtr.Zero) DeleteDC(memory);
            if (screen != IntPtr.Zero) ReleaseDC(IntPtr.Zero, screen);
        }
    }

    public static Bitmap RenderSurface(int width, int height, Color surfaceColor, Color borderColor)
    {
        var bitmap = new Bitmap(Math.Max(2, width), Math.Max(2, height), PixelFormat.Format32bppPArgb);
        using (var g = Graphics.FromImage(bitmap)) {
            g.Clear(Color.Transparent);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            // Fractional bounds leave room for edge coverage on every side.
            var bounds = new RectangleF(0.75f, 0.75f, width - 1.5f, height - 1.5f);
            float diameter = bounds.Height;
            using (var path = new GraphicsPath())
            using (var body = new SolidBrush(surfaceColor))
            using (var edge = new Pen(borderColor, 0.8f)) {
                path.AddArc(bounds.X, bounds.Y, diameter, diameter, 90, 180);
                path.AddArc(bounds.Right - diameter, bounds.Y, diameter, diameter, 270, 180);
                path.CloseFigure();
                g.FillPath(body, path);
                g.DrawPath(edge, path);
            }
        }
        return bitmap;
    }

    public static void DrawViewport(Bitmap bitmap, Control viewport)
    {
        if (viewport == null || viewport.IsDisposed) return;
        DrawChildren(bitmap, viewport, viewport.Left, viewport.Top, viewport.Bounds);
    }

    private static void DrawChildren(Bitmap bitmap, Control parent, int left, int top, Rectangle clip)
    {
        foreach (Control control in parent.Controls) {
            var rect = new Rectangle(left + control.Left, top + control.Top, control.Width, control.Height);
            if (rect.Width <= 0 || rect.Height <= 0) continue;
            var picture = control as PictureBox;
            var label = control as Label;
            if (picture != null && picture.Image != null) {
                using (var graphics = Graphics.FromImage(bitmap)) {
                    graphics.SetClip(clip);
                    if (picture.Image.Width == rect.Width && picture.Image.Height == rect.Height)
                        graphics.DrawImageUnscaled(picture.Image, rect.Left, rect.Top);
                    else {
                        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        graphics.DrawImage(picture.Image, rect);
                    }
                }
            } else if (label != null && !String.IsNullOrEmpty(label.Text)) {
                DrawNativeText(bitmap, label, rect, clip);
            }
            DrawChildren(bitmap, control, rect.Left, rect.Top, clip);
        }
    }

    private static void DrawNativeText(Bitmap target, Label label, Rectangle rect, Rectangle viewport)
    {
        Rectangle area = Rectangle.Intersect(Rectangle.Intersect(rect, viewport), new Rectangle(Point.Empty, target.Size));
        if (area.Width <= 0 || area.Height <= 0) return;
        // ClearType needs an opaque known background. Render at final pixel size
        // using the same GDI text engine as native labels, then copy glyph pixels
        // into the opaque interior. Never overwrite the capsule's alpha edge.
        using (var text = new Bitmap(rect.Width, rect.Height, PixelFormat.Format32bppRgb)) {
            Color background = label.BackColor;
            using (var graphics = Graphics.FromImage(text)) {
                graphics.Clear(background);
                var flags = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter;
                flags |= label.TextAlign == ContentAlignment.MiddleRight ? TextFormatFlags.Right : TextFormatFlags.Left;
                TextRenderer.DrawText(graphics, label.Text, label.Font, new Rectangle(Point.Empty, text.Size), label.ForeColor, background, flags);
            }
            var sourceRect = new Rectangle(area.Left - rect.Left, area.Top - rect.Top, area.Width, area.Height);
            BitmapData source = null, destination = null;
            try {
                source = text.LockBits(sourceRect, ImageLockMode.ReadOnly, PixelFormat.Format32bppRgb);
                destination = target.LockBits(area, ImageLockMode.ReadWrite, PixelFormat.Format32bppPArgb);
                int count = area.Width * 4;
                var from = new byte[count];
                var to = new byte[count];
                for (int y = 0; y < area.Height; y++) {
                    Marshal.Copy(IntPtr.Add(source.Scan0, y * source.Stride), from, 0, count);
                    Marshal.Copy(IntPtr.Add(destination.Scan0, y * destination.Stride), to, 0, count);
                    for (int x = 0; x < count; x += 4) {
                        if (to[x + 3] != 255 || (from[x] == background.B && from[x + 1] == background.G && from[x + 2] == background.R)) continue;
                        to[x] = from[x]; to[x + 1] = from[x + 1]; to[x + 2] = from[x + 2];
                    }
                    Marshal.Copy(to, 0, IntPtr.Add(destination.Scan0, y * destination.Stride), count);
                }
            }
            finally {
                if (source != null) text.UnlockBits(source);
                if (destination != null) target.UnlockBits(destination);
            }
        }
    }
}
