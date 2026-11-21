// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace Remnexa.Scan {
    public sealed class ScanSnapshot {
        public string State, Phase, Mode, Error;
        public long Files, Total;
        public int Findings, Omitted, ScannerProcessId;
        public double ElapsedSeconds, ActiveSeconds;
        public string[] Evidence;
    }
    // Shared in-memory state only. No scan paths or commands are accepted through IPC.
    public sealed class BackgroundControl : IDisposable {
        private readonly object sync=new object();
        private readonly Stopwatch clock=Stopwatch.StartNew();
        private readonly List<string> evidence=new List<string>();
        public readonly CancellationTokenSource Cancellation=new CancellationTokenSource();
        private bool pause;
        private string state="Starting",phase="Preparing",mode="Balanced",error="";
        private long files,total=-1;
        private int findings,omitted;
        private int scannerProcessId;
        private double pausedSeconds,pauseStarted;
        public double PausedSeconds {get {lock(sync)return pausedSeconds;}}
        public void Pause() {lock(sync){if(state=="Starting"||state=="Running"){pause=true;state="Pausing";}}}
        public void Resume() {lock(sync){pause=false;if(state=="Pausing")state="Running";Monitor.PulseAll(sync);}}
        public void Cancel() {Cancellation.Cancel();Resume();lock(sync){if(!Terminal(state))state="Cancelling";}}
        private static bool Terminal(string value) {return value=="Completed"||value=="Warning"||value=="Cancelled"||value=="Failed";}
        public void Update(string stage,long done,long count,string performance) {
            lock(sync){phase=stage;files=stage=="Discovering"?0:done;total=count;if(!String.IsNullOrEmpty(performance))mode=performance;if(state=="Starting")state="Running";}
        }
        public void AddEvidence(string line,bool finding) {
            lock(sync){if(finding)findings++;if(evidence.Count<1000)evidence.Add(line);else omitted++;}
        }
        public void ObserveScanner(int pid){lock(sync){scannerProcessId=pid;}}
        public IDisposable OwnProcess(Process process){return new OwnedScannerJob(process);}
        public void Finish(string outcome,string message) {lock(sync){state=outcome;error=message;pause=false;clock.Stop();Monitor.PulseAll(sync);}}
        public ScanSnapshot Snapshot() {
            lock(sync){return new ScanSnapshot{State=state,Phase=phase,Mode=mode,Files=files,Total=total,Findings=findings,Omitted=omitted,Error=error,ScannerProcessId=scannerProcessId,
                ElapsedSeconds=clock.Elapsed.TotalSeconds,ActiveSeconds=Math.Max(0,clock.Elapsed.TotalSeconds-pausedSeconds-(state=="Paused"?clock.Elapsed.TotalSeconds-pauseStarted:0)),Evidence=evidence.ToArray()};}
        }
        public void Checkpoint(int ownedScannerPid) {
            Cancellation.Token.ThrowIfCancellationRequested();
            lock(sync){if(!pause)return;}
            // Suspend only the scanner created by this scan, never the REMNEXA host.
            // Every successful suspend is paired with a resume, including cancellation.
            using(var suspended=new SuspendedScanner(ownedScannerPid)) {
                var wait=Stopwatch.StartNew();
                lock(sync){state="Paused";pauseStarted=clock.Elapsed.TotalSeconds;}
                try {lock(sync){while(pause&&!Cancellation.IsCancellationRequested)Monitor.Wait(sync,100);}}
                finally {lock(sync){pausedSeconds+=wait.Elapsed.TotalSeconds;if(!Terminal(state))state=Cancellation.IsCancellationRequested?"Cancelling":"Running";}}
            }
            Cancellation.Token.ThrowIfCancellationRequested();
        }
        public void Dispose(){Cancellation.Dispose();}
    }
    // CLI scans also die with their independent scan host, even when its console
    // is forcibly closed and PowerShell cannot execute finally blocks.
    internal sealed class OwnedScannerJob : IDisposable {
        [StructLayout(LayoutKind.Sequential)] private struct Basic {public long ProcessTime,JobTime;public uint Flags;public UIntPtr Minimum,Maximum;public uint Active;public UIntPtr Affinity;public uint Priority,Scheduling;}
        [StructLayout(LayoutKind.Sequential)] private struct Io {public ulong Read,Write,Other,ReadBytes,WriteBytes,OtherBytes;}
        [StructLayout(LayoutKind.Sequential)] private struct Limits {public Basic Basic;public Io Io;public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;}
        [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr CreateJobObject(IntPtr security,string name);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool SetInformationJobObject(IntPtr job,int type,ref Limits data,uint length);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        private IntPtr job;
        public OwnedScannerJob(Process process) {
            if(process.Id==Environment.ProcessId)throw new InvalidOperationException("Cannot own the application host.");
            job=CreateJobObject(IntPtr.Zero,null);if(job==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());
            try{var limits=new Limits();limits.Basic.Flags=0x2000;
                if(!SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf<Limits>())||!AssignProcessToJobObject(job,process.Handle))throw new Win32Exception(Marshal.GetLastWin32Error());
            }catch{Dispose();throw;}
        }
        public void Dispose(){var handle=Interlocked.Exchange(ref job,IntPtr.Zero);if(handle!=IntPtr.Zero)CloseHandle(handle);GC.SuppressFinalize(this);}
        ~OwnedScannerJob(){Dispose();}
    }
    internal sealed class SuspendedScanner : IDisposable {
        [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr OpenThread(uint rights,bool inherit,uint id);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern uint SuspendThread(IntPtr thread);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool GetExitCodeThread(IntPtr thread,out uint code);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        private readonly List<IntPtr> handles=new List<IntPtr>();
        public SuspendedScanner(int pid) {
            if(pid==0)return; // Inventory / preparation: cooperative pause in the scan runspace.
            if(pid==Environment.ProcessId)throw new InvalidOperationException("Refusing to suspend the application host.");
            try {
                using(var process=Process.GetProcessById(pid)) {
                    var seen=new HashSet<int>();
                    for(int pass=0;pass<8;pass++) {
                        process.Refresh();if(process.HasExited)return;
                        bool added=false;
                        foreach(ProcessThread thread in process.Threads) {
                            using(thread) {
                                if(!seen.Add(thread.Id))continue;
                                IntPtr handle=OpenThread(2|0x0800,false,(uint)thread.Id);
                                if(handle==IntPtr.Zero){if(thread.ThreadState==System.Diagnostics.ThreadState.Terminated)continue;throw new Win32Exception(Marshal.GetLastWin32Error());}
                                if(SuspendThread(handle)==UInt32.MaxValue){int code=Marshal.GetLastWin32Error();CloseHandle(handle);throw new Win32Exception(code);}
                                handles.Add(handle);added=true;
                            }
                        }
                        if(!added)return;
                    }
                    throw new InvalidOperationException("Scanner thread set did not settle; pause refused.");
                }
            }catch(ArgumentException){Dispose();} // Scanner already exited.
            catch{Dispose();throw;}
        }
        public void Dispose(){
            Exception failure=null;
            foreach(IntPtr handle in handles){
                if(ResumeThread(handle)==UInt32.MaxValue){int error=Marshal.GetLastWin32Error();if(!GetExitCodeThread(handle,out uint code)||code==259)failure=new Win32Exception(error);}
                CloseHandle(handle);
            }
            handles.Clear();if(failure!=null)throw failure;
        }
    }
}
