using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

// A private Windows job owns the CLI and all descendants, including after the
// CLI exits. Assign the suspended process before any provider code can run.
public sealed class UtpOwnedUsageProcess : IDisposable
{
    private IntPtr process, job;
    public StreamWriter StandardInput { get; private set; }
    public StreamReader StandardOutput { get; private set; }
    public StreamReader StandardError { get; private set; }
    public bool HasExited { get { return WaitForSingleObject(process, 0) == 0; } }
    public int ExitCode { get { uint code; Require(GetExitCodeProcess(process, out code)); return unchecked((int)code); } }
    public bool WaitForExit(int milliseconds) { return WaitForSingleObject(process, (uint)milliseconds) == 0; }
    public void Kill() { Require(TerminateJobObject(job, 1)); }

    public static UtpOwnedUsageProcess Start(string fileName, string arguments, string directory)
    {
        return Start(fileName, arguments, directory, null);
    }

    public static UtpOwnedUsageProcess Start(string fileName, string arguments, string directory, IDictionary overrides)
    {
        var result = new UtpOwnedUsageProcess();
        IntPtr inputRead = IntPtr.Zero, inputWrite = IntPtr.Zero;
        IntPtr outputRead = IntPtr.Zero, outputWrite = IntPtr.Zero;
        IntPtr errorRead = IntPtr.Zero, errorWrite = IntPtr.Zero;
        IntPtr attributes = IntPtr.Zero, handles = IntPtr.Zero, thread = IntPtr.Zero;
        IntPtr environment = IntPtr.Zero;
        int environmentCharacters = 0;
        bool initialized = false;
        try
        {
            if (overrides != null) environment = BuildEnvironmentBlock(overrides, out environmentCharacters);
            result.job = CreateJobObject(IntPtr.Zero, null);
            Require(result.job != IntPtr.Zero);
            var limits = new ExtendedLimits();
            limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            Require(SetInformationJobObject(result.job, 9, ref limits, (uint)Marshal.SizeOf(limits)));
            var security = new SecurityAttributes();
            security.Length = Marshal.SizeOf(security);
            security.Inherit = true;
            Require(CreatePipe(out inputRead, out inputWrite, ref security, 0));
            Require(CreatePipe(out outputRead, out outputWrite, ref security, 0));
            Require(CreatePipe(out errorRead, out errorWrite, ref security, 0));
            Require(SetHandleInformation(inputWrite, 1, 0));
            Require(SetHandleInformation(outputRead, 1, 0));
            Require(SetHandleInformation(errorRead, 1, 0));

            // Inherit only these three pipe ends, never another worker's handles.
            IntPtr size = IntPtr.Zero;
            InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
            attributes = Marshal.AllocHGlobal(size);
            Require(InitializeProcThreadAttributeList(attributes, 1, 0, ref size));
            initialized = true;
            handles = Marshal.AllocHGlobal(IntPtr.Size * 3);
            Marshal.WriteIntPtr(handles, 0, inputRead);
            Marshal.WriteIntPtr(handles, IntPtr.Size, outputWrite);
            Marshal.WriteIntPtr(handles, IntPtr.Size * 2, errorWrite);
            Require(UpdateProcThreadAttribute(attributes, 0, new IntPtr(0x20002), handles,
                new IntPtr(IntPtr.Size * 3), IntPtr.Zero, IntPtr.Zero));
            var startup = new StartupInfoEx();
            startup.Info.Size = Marshal.SizeOf(startup);
            startup.Info.Flags = 0x100; // STARTF_USESTDHANDLES
            startup.Info.Input = inputRead;
            startup.Info.Output = outputWrite;
            startup.Info.Error = errorWrite;
            startup.Attributes = attributes;
            ProcessInformation info;
            Require(CreateProcess(fileName, new StringBuilder("\"" + fileName + "\" " + arguments),
                IntPtr.Zero, IntPtr.Zero, true, 0x08080404, environment, directory, ref startup, out info));
            // CREATE_NO_WINDOW | EXTENDED_STARTUPINFO_PRESENT | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT
            result.process = info.Process;
            thread = info.Thread;
            Require(AssignProcessToJobObject(result.job, result.process));
            result.StandardInput = new StreamWriter(TakePipe(ref inputWrite, FileAccess.Write), new UTF8Encoding(false));
            result.StandardInput.AutoFlush = true;
            result.StandardOutput = new StreamReader(TakePipe(ref outputRead, FileAccess.Read), Encoding.UTF8);
            result.StandardError = new StreamReader(TakePipe(ref errorRead, FileAccess.Read), Encoding.UTF8);
            Require(ResumeThread(thread) != uint.MaxValue);
            return result;
        }
        catch { result.Dispose(); throw; }
        finally
        {
            Close(ref thread);
            Close(ref inputRead); Close(ref inputWrite);
            Close(ref outputRead); Close(ref outputWrite);
            Close(ref errorRead); Close(ref errorWrite);
            if (initialized) DeleteProcThreadAttributeList(attributes);
            if (attributes != IntPtr.Zero) Marshal.FreeHGlobal(attributes);
            if (handles != IntPtr.Zero) Marshal.FreeHGlobal(handles);
            if (environment != IntPtr.Zero)
            {
                for (int i = 0; i < environmentCharacters; i++) Marshal.WriteInt16(environment, i * 2, 0);
                Marshal.FreeHGlobal(environment);
            }
        }
    }

    private static IntPtr BuildEnvironmentBlock(IDictionary overrides, out int characters)
    {
        var values = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables())
            values[(string)entry.Key] = (string)entry.Value;
        foreach (DictionaryEntry entry in overrides)
        {
            var name = entry.Key as string;
            var value = entry.Value as string;
            if (string.IsNullOrEmpty(name) || name.IndexOfAny(new[] { '\0', '=' }) >= 0 ||
                value == null || value.IndexOf('\0') >= 0)
                throw new ArgumentException("Environment overrides require valid string names and values.");
            values[name] = value;
        }
        characters = 1;
        foreach (var entry in values) characters = checked(characters + entry.Key.Length + entry.Value.Length + 2);
        var block = new char[Math.Max(2, characters)];
        characters = block.Length;
        IntPtr memory = IntPtr.Zero;
        try
        {
            int offset = 0;
            foreach (var entry in values)
            {
                entry.Key.CopyTo(0, block, offset, entry.Key.Length);
                offset += entry.Key.Length;
                block[offset++] = '=';
                entry.Value.CopyTo(0, block, offset, entry.Value.Length);
                offset += entry.Value.Length + 1;
            }
            memory = Marshal.AllocHGlobal(checked(characters * 2));
            Marshal.Copy(block, 0, memory, characters);
            return memory;
        }
        catch
        {
            if (memory != IntPtr.Zero)
            {
                for (int i = 0; i < characters; i++) Marshal.WriteInt16(memory, i * 2, 0);
                Marshal.FreeHGlobal(memory);
            }
            throw;
        }
        finally { Array.Clear(block, 0, block.Length); }
    }

    private static FileStream TakePipe(ref IntPtr handle, FileAccess access)
    {
        var safe = new SafeFileHandle(handle, true);
        handle = IntPtr.Zero;
        try { return new FileStream(safe, access, 4096, false); }
        catch { safe.Dispose(); throw; }
    }
    private static void Require(bool succeeded)
    {
        if (!succeeded) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    private static void Close(ref IntPtr handle)
    {
        if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; }
    }
    public void Dispose()
    {
        // Job close also stops descendants whose immediate parent already exited.
        Close(ref job);
        if (process != IntPtr.Zero)
        {
            // Covers a failure to assign a still-suspended process to its job.
            if (!HasExited) TerminateProcess(process, 1);
            WaitForSingleObject(process, 1000);
            Close(ref process);
        }
        try { if (StandardInput != null) StandardInput.Dispose(); }
        finally
        {
            StandardInput = null;
            try { if (StandardOutput != null) StandardOutput.Dispose(); }
            finally
            {
                StandardOutput = null;
                try { if (StandardError != null) StandardError.Dispose(); }
                finally { StandardError = null; }
            }
        }
    }

    [StructLayout(LayoutKind.Sequential)] private struct SecurityAttributes
    { public int Length; public IntPtr Descriptor; [MarshalAs(UnmanagedType.Bool)] public bool Inherit; }
    [StructLayout(LayoutKind.Sequential)] private struct BasicLimits
    {
        public long ProcessTime, JobTime; public uint Flags;
        public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
        public uint ActiveProcesses; public UIntPtr Affinity; public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] private struct IoCounters
    { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimits
    {
        public BasicLimits Basic; public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct StartupInfo
    {
        public int Size; public string Reserved, Desktop, Title;
        public uint X, Y, Width, Height, XChars, YChars, Fill, Flags;
        public ushort ShowWindow, ReservedLength; public IntPtr ReservedBytes, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)] private struct StartupInfoEx
    { public StartupInfo Info; public IntPtr Attributes; }
    [StructLayout(LayoutKind.Sequential)] private struct ProcessInformation
    { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CreatePipe(out IntPtr read, out IntPtr write, ref SecurityAttributes attributes, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, uint flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returnedSize);
    [DllImport("kernel32.dll")] private static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll", EntryPoint = "CreateProcessW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CreateProcess(string application, StringBuilder commandLine, IntPtr processAttributes,
        IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string directory,
        ref StartupInfoEx startup, out ProcessInformation info);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll")] private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll")] private static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
}
