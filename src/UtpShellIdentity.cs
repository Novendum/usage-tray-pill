using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

// UTP runs inside powershell.exe. Without its own AppUserModelID, Windows groups the
// overview window under PowerShell and shows PowerShell's icon on the taskbar.
// This helper gives UTP's windows (and optionally the process) a stable identity,
// and lets the Start-menu shortcut carry the same identity for notifications.
public static class UtpShellIdentity
{
    public const string AppId = "Novendum.UsageTrayPill";

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct PropertyKey
    {
        public Guid FormatId;
        public uint PropertyId;
        public PropertyKey(Guid formatId, uint propertyId) { FormatId = formatId; PropertyId = propertyId; }
    }

    // PROPVARIANT is 16 bytes on x86 and 24 bytes on x64; the pointer union sits at offset 8.
    [StructLayout(LayoutKind.Explicit)]
    private struct PropVariant
    {
        [FieldOffset(0)] public ushort ValueType;
        [FieldOffset(8)] public IntPtr Pointer;
        [FieldOffset(16)] public IntPtr Padding;
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink { }

    private static readonly Guid AppUserModelFormat = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
    private static PropertyKey RelaunchCommand = new PropertyKey(AppUserModelFormat, 2);
    private static PropertyKey RelaunchIconResource = new PropertyKey(AppUserModelFormat, 3);
    private static PropertyKey RelaunchDisplayName = new PropertyKey(AppUserModelFormat, 4);
    private static PropertyKey AppUserModelId = new PropertyKey(AppUserModelFormat, 5);
    private const ushort VtEmpty = 0;
    private const ushort VtLpwstr = 31;

    [DllImport("shell32.dll")]
    private static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string appId);

    [DllImport("shell32.dll")]
    private static extern int SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PropVariant value);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

    public static bool SetProcessAppId(string appId)
    {
        return SetCurrentProcessExplicitAppUserModelID(appId) == 0;
    }

    // Windows 10 20H1+ and Windows 11 draw a dark title bar when this attribute is set.
    public static bool SetDarkTitleBar(IntPtr window, bool dark)
    {
        if (window == IntPtr.Zero) return false;
        int value = dark ? 1 : 0;
        try {
            if (DwmSetWindowAttribute(window, 20, ref value, sizeof(int)) == 0) return true;
            return DwmSetWindowAttribute(window, 19, ref value, sizeof(int)) == 0;
        }
        catch (DllNotFoundException) { return false; }
        catch (EntryPointNotFoundException) { return false; }
    }

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr window, string subAppName, string subIdList);

    // Dark scrollbars and combo boxes ("DarkMode_Explorer" / "DarkMode_CFD"); "Explorer" restores light.
    public static void SetControlTheme(IntPtr window, string themeName)
    {
        if (window == IntPtr.Zero) return;
        try { SetWindowTheme(window, themeName, null); }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }

    // Windows 11 rounded corners for borderless flyouts; ignored on Windows 10.
    public static void SetRoundedCorners(IntPtr window)
    {
        if (window == IntPtr.Zero) return;
        int value = 2;
        try { DwmSetWindowAttribute(window, 33, ref value, sizeof(int)); }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }

    // Separate taskbar group with UTP's own icon, name and relaunch command for pinning.
    public static bool SetWindowIdentity(IntPtr window, string appId, string relaunchCommand, string iconResource, string displayName)
    {
        if (window == IntPtr.Zero) return false;
        IPropertyStore store = null;
        try {
            Guid iid = typeof(IPropertyStore).GUID;
            if (SHGetPropertyStoreForWindow(window, ref iid, out store) != 0 || store == null) return false;
            // Relaunch properties must be set before the ID for the taskbar to pick them up.
            if (!String.IsNullOrEmpty(relaunchCommand)) {
                SetString(store, RelaunchCommand, relaunchCommand);
                SetString(store, RelaunchIconResource, iconResource);
                SetString(store, RelaunchDisplayName, displayName);
            }
            SetString(store, AppUserModelId, appId);
            return true;
        }
        catch (COMException) { return false; }
        finally { if (store != null) Marshal.ReleaseComObject(store); }
    }

    public static void ClearWindowIdentity(IntPtr window)
    {
        if (window == IntPtr.Zero) return;
        IPropertyStore store = null;
        try {
            Guid iid = typeof(IPropertyStore).GUID;
            if (SHGetPropertyStoreForWindow(window, ref iid, out store) != 0 || store == null) return;
            foreach (var key in new[] { AppUserModelId, RelaunchCommand, RelaunchIconResource, RelaunchDisplayName }) {
                var empty = new PropVariant { ValueType = VtEmpty };
                var k = key;
                store.SetValue(ref k, ref empty);
            }
        }
        catch (COMException) { }
        finally { if (store != null) Marshal.ReleaseComObject(store); }
    }

    public static string GetShortcutAppId(string shortcutPath)
    {
        object link = null;
        try {
            link = new ShellLink();
            ((IPersistFile)link).Load(shortcutPath, 0);
            var store = (IPropertyStore)link;
            var key = AppUserModelId;
            PropVariant value;
            if (store.GetValue(ref key, out value) != 0) return null;
            try { return value.ValueType == VtLpwstr ? Marshal.PtrToStringUni(value.Pointer) : null; }
            finally { PropVariantClear(ref value); }
        }
        catch (COMException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
        catch (System.IO.IOException) { return null; }
        finally { if (link != null) Marshal.ReleaseComObject(link); }
    }

    public static bool SetShortcutAppId(string shortcutPath, string appId)
    {
        object link = null;
        try {
            link = new ShellLink();
            var file = (IPersistFile)link;
            file.Load(shortcutPath, 2);
            var store = (IPropertyStore)link;
            SetString(store, AppUserModelId, appId);
            if (store.Commit() != 0) return false;
            file.Save(shortcutPath, true);
            return true;
        }
        catch (COMException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
        finally { if (link != null) Marshal.ReleaseComObject(link); }
    }

    private static void SetString(IPropertyStore store, PropertyKey key, string text)
    {
        var value = new PropVariant { ValueType = VtLpwstr, Pointer = Marshal.StringToCoTaskMemUni(text ?? String.Empty) };
        try {
            int result = store.SetValue(ref key, ref value);
            if (result != 0) Marshal.ThrowExceptionForHR(result);
        }
        finally { PropVariantClear(ref value); }
    }
}
