using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
namespace Remnexa.Scan {
    public sealed class Resources {
        [StructLayout(LayoutKind.Sequential)] private struct MemoryStatus {
            public uint Length, Load; public ulong TotalPhysical, AvailablePhysical, TotalPage, AvailablePage, TotalVirtual, AvailableVirtual, AvailableExtended;
        }
        [DllImport("kernel32.dll")] private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
        [DllImport("kernel32.dll")] private static extern bool GetSystemTimes(out long idle,out long kernel,out long user);
        public long AvailableMemoryBytes;
        public double CpuLoadPercent;
        public static Resources Measure() {
            var memory=new MemoryStatus {Length=(uint)Marshal.SizeOf<MemoryStatus>()};
            if(!GlobalMemoryStatusEx(ref memory)) throw new IOException("Memory measurement failed.");
            long idle1,kernel1,user1,idle2,kernel2,user2;
            if(!GetSystemTimes(out idle1,out kernel1,out user1)) throw new IOException("CPU measurement failed.");
            Thread.Sleep(100);
            if(!GetSystemTimes(out idle2,out kernel2,out user2)) throw new IOException("CPU measurement failed.");
            long elapsed=(kernel2-kernel1)+(user2-user1);
            return new Resources {AvailableMemoryBytes=(long)memory.AvailablePhysical,CpuLoadPercent=elapsed>0?Math.Clamp(100.0*(elapsed-(idle2-idle1))/elapsed,0,100):0};
        }
    }
    public sealed class Cancellation : IDisposable {
        public readonly CancellationTokenSource Source;
        private readonly ConsoleCancelEventHandler handler;
        private readonly bool interactive;
        public Cancellation(CancellationToken token) : this(token,true) { }
        public Cancellation(CancellationToken token,bool interactive) {
            this.interactive=interactive;
            Source=CancellationTokenSource.CreateLinkedTokenSource(token);
            handler=(sender,args)=>{args.Cancel=true;Source.Cancel();};
            if(interactive)Console.CancelKeyPress+=handler;
        }
        public void Poll() {
            try {
                if(interactive && !Console.IsInputRedirected && Console.KeyAvailable) {
                    var key=Console.ReadKey(true).Key;
                    if(key==ConsoleKey.X || key==ConsoleKey.Escape) Source.Cancel();
                }
            } catch(InvalidOperationException) { }
            Source.Token.ThrowIfCancellationRequested();
        }
        public void Dispose() { if(interactive)Console.CancelKeyPress-=handler;Source.Dispose(); }
    }
    public sealed class InventoryResult {
        public long Files, Skipped;
        public int Roots;
        public readonly List<string> Issues = new List<string>();
    }
    // One lazy enumerator per open directory; no arrays of all children.
    public static class Inventory {
        private static bool Within(string path, string root) {
            return path.Equals(root, StringComparison.OrdinalIgnoreCase) || path.StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase);
        }
        private static bool Excluded(string path, string[] excluded) {
            foreach (string root in excluded) if (!String.IsNullOrEmpty(root) && Within(path, root)) return true;
            return false;
        }
        private static void Issue(InventoryResult result, string path, string reason) {
            result.Skipped++;
            if (result.Issues.Count < 20) result.Issues.Add(path + " :: " + reason);
        }
        public static InventoryResult Write(string[] roots, string[] excluded, string list, CancellationToken cancellation, Action<long,long,string> progress) {
            var result = new InventoryResult { Roots=roots.Length };
            var watch=Stopwatch.StartNew(); long last=-1000;
            using (var writer=new StreamWriter(list, false, new UTF8Encoding(false), 65536)) {
                foreach(string root in roots) {
                    var stack=new Stack<IEnumerator<string>>();
                    stack.Push(((IEnumerable<string>)new [] { root }).GetEnumerator());
                    try {
                        while(stack.Count>0) {
                            cancellation.ThrowIfCancellationRequested();
                            string path;
                            try {
                                if (!stack.Peek().MoveNext()) { stack.Pop().Dispose(); continue; }
                                path=stack.Peek().Current;
                            } catch(Exception ex) when(ex is IOException || ex is UnauthorizedAccessException) {
                                Issue(result,root,ex.GetType().Name); stack.Pop().Dispose(); continue;
                            }
                            if(Excluded(path,excluded)) continue;
                            try {
                                var attributes=File.GetAttributes(path);
                                if((attributes & FileAttributes.ReparsePoint)!=0) { Issue(result,path,"ReparsePoint"); continue; }
                                if((attributes & FileAttributes.Directory)!=0) {
                                    if(stack.Count>=1024) { Issue(result,path,"DirectoryDepthLimit"); continue; }
                                    stack.Push(Directory.EnumerateFileSystemEntries(path).GetEnumerator());
                                } else if(path.IndexOfAny(new [] {'\r','\n'})>=0) { Issue(result,path,"UnsupportedLineBreakInPath");
                                } else { writer.WriteLine(path); result.Files++; }
                            } catch(Exception ex) when(ex is IOException || ex is UnauthorizedAccessException) { Issue(result,path,ex.GetType().Name); }
                            if(progress!=null && watch.ElapsedMilliseconds-last>=250) { progress(result.Files,result.Skipped,path);last=watch.ElapsedMilliseconds; }
                        }
                    } finally { while(stack.Count>0) stack.Pop().Dispose(); }
                }
            }
            if(progress!=null) progress(result.Files,result.Skipped,"");
            return result;
        }
    }
}
