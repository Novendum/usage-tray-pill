using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.IO;
using System.Threading;

// FileSystemWatcher callbacks stay in managed code, not a PowerShell UI runspace.
public sealed class UtpUsageFileMonitor : IDisposable
{
    private readonly List<FileSystemWatcher> watchers = new List<FileSystemWatcher>();
    private int changed = 1;
    private readonly ConcurrentDictionary<string, byte> names = new ConcurrentDictionary<string, byte>();
    public UtpUsageFileMonitor(string directory) { Watch(directory, "*-usage.json"); }
    public void Watch(string directory, string filter)
    {
        if (!Directory.Exists(directory)) return;
        var watcher = new FileSystemWatcher(directory, filter);
        watcher.NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size;
        watcher.Changed += OnChange;
        watcher.Created += OnChange;
        watcher.Deleted += OnChange;
        watcher.Renamed += delegate(object sender, RenamedEventArgs e) { names[e.Name] = 0; Interlocked.Exchange(ref changed, 1); };
        watcher.Error += delegate { names["*"] = 0; Interlocked.Exchange(ref changed, 1); };
        watchers.Add(watcher);
        watcher.EnableRaisingEvents = true;
    }
    private void OnChange(object sender, FileSystemEventArgs e) { names[e.Name] = 0; Interlocked.Exchange(ref changed, 1); }
    public bool ConsumeChanges() { return Interlocked.Exchange(ref changed, 0) != 0; }
    public string[] TakeChangedFiles() { var result = new List<string>(); foreach(var name in names.Keys) { byte value; if(names.TryRemove(name, out value)) result.Add(name); } return result.ToArray(); }
    public void Dispose() { foreach (var watcher in watchers) watcher.Dispose(); watchers.Clear(); }
}
