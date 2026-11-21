// SPDX-License-Identifier: MIT
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Remnexa.Worker {
    public sealed class Frame {
        public string Kind {get;set;}
        public int Id {get;set;}
        public string Name {get;set;}
        public long Length {get;set;}
        public int Code {get;set;}
        public string Signature {get;set;}
        public string Message {get;set;}
        public string EnginePath {get;set;}
        public string DatabasePath {get;set;}
        public string TempPath {get;set;}
        public long MaxBytes {get;set;}
        public int Threads {get;set;}
        public int IdleSeconds {get;set;}
        public bool IncludePUA {get;set;}
        public string Version {get;set;}
        public uint SignatureCount {get;set;}
    }
    public static class Wire {
        private static readonly JsonSerializerOptions Options=new JsonSerializerOptions {
            MaxDepth=4, UnmappedMemberHandling=System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
        };
        public static Frame Read(Stream stream) {
            byte[] size=new byte[4]; Exact(stream,size,4);
            int length=System.Buffers.Binary.BinaryPrimitives.ReadInt32LittleEndian(size);
            if(length<2 || length>32768) throw new InvalidDataException("Invalid worker frame size.");
            byte[] data=new byte[length]; Exact(stream,data,length);
            return JsonSerializer.Deserialize<Frame>(data,Options) ?? throw new InvalidDataException("Null worker frame.");
        }
        public static void Exact(Stream stream,byte[] data,int count) {
            int offset=0;while(offset<count) {int read=stream.Read(data,offset,count-offset);if(read==0)throw new EndOfStreamException();offset+=read;}
        }
        public static void Write(Stream stream,Frame frame) {
            byte[] data=JsonSerializer.SerializeToUtf8Bytes(frame,Options);
            if(data.Length>32768)throw new InvalidDataException("Worker frame too large.");
            byte[] size=new byte[4];System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(size,data.Length);
            stream.Write(size);stream.Write(data);stream.Flush();
        }
        public static string Clean(string text) {
            if(text==null)return "";
            return new string(text.Take(2048).Select(c=>Char.IsControl(c)?' ':c).ToArray());
        }
        public static void SafePath(string path,bool allowRemote=false) {
            string current=Path.GetFullPath(path);
            if((!allowRemote&&current.StartsWith("\\\\",StringComparison.Ordinal)) || current.IndexOfAny(new[]{'\r','\n','\0'})>=0)
                throw new IOException("Remote or malformed paths are not supported by the private worker.");
            string root=Path.GetPathRoot(current);
            while(!String.IsNullOrEmpty(current)) {
                if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)throw new IOException("Reparse point in scan path.");
                if(current.Equals(root,StringComparison.OrdinalIgnoreCase))break;
                current=Path.GetDirectoryName(current);
            }
        }
    }
    public sealed class Reply {
        public int Id;public string Path;public int Code;public string Signature;public string Message;
    }
    public sealed class Batch : IDisposable {
        internal readonly BlockingCollection<Reply> Results;
        private readonly ConcurrentDictionary<int,string> pending=new ConcurrentDictionary<int,string>();
        private readonly ConcurrentDictionary<int,bool> acknowledged=new ConcurrentDictionary<int,bool>();
        private readonly SemaphoreSlim slots;
        private readonly Client client;
        private readonly Task producer,reader;
        private int disposed;
        public Exception Error {get;private set;}
        public int Submitted {get;private set;}
        public bool Completed {get{return producer.IsCompleted&&reader.IsCompleted;}}
        public int QueuedResults {get{return Results.Count;}}
        internal Batch(Client client,string list,int parallelism) {
            this.client=client;slots=new SemaphoreSlim(parallelism,parallelism);Results=new BlockingCollection<Reply>(parallelism+4);
            producer=Task.Run(()=>Produce(list));reader=Task.Run(Read);
        }
        private void Fail(Exception ex) { Error=ex;client.Broken=true;client.Abort(); }
        private void Produce(string list) {
            try {
                using(var paths=new StreamReader(list,Encoding.UTF8)) {
                    string path;int id=0;
                    while((path=paths.ReadLine())!=null) {
                        while(!slots.Wait(100)) {if(client.Broken)throw new IOException("Worker disconnected.");}
                        id++;Submitted=id;
                        try {
                            Wire.SafePath(path,true);
                            using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read,65536,FileOptions.SequentialScan)) {
                                if(file.Length>client.MaxBytes) {
                                    acknowledged[id]=true;Results.Add(new Reply{Id=id,Path=path,Code=1,Signature="Heuristics.Limits.Exceeded.MaxFileSize"});continue;
                                }
                                if(!pending.TryAdd(id,path))throw new InvalidDataException("Duplicate scan job.");
                                Wire.Write(client.Input,new Frame{Kind="file",Id=id,Name=System.IO.Path.GetFileName(path),Length=file.Length});
                                file.CopyTo(client.Input,65536);client.Input.Flush();
                            }
                        } catch(Exception ex) when(ex is IOException || ex is UnauthorizedAccessException) {
                            // Broken transport cannot be converted into a per-file error.
                            if(pending.ContainsKey(id))throw;
                            acknowledged[id]=true;Results.Add(new Reply{Id=id,Path=path,Code=2,Message=Wire.Clean(ex.Message)});
                        }
                    }
                    Wire.Write(client.Input,new Frame{Kind="end",Id=id});
                }
            } catch(Exception ex){Fail(ex);}
        }
        private void Read() {
            try {
                while(true) {
                    Frame frame=Wire.Read(client.Output);
                    if(frame.Kind=="end") {
                        if(frame.Id!=Submitted || pending.Count!=0)throw new InvalidDataException("Worker lost scan results.");
                        return;
                    }
                    if(frame.Kind!="result" || frame.Code<0 || frame.Code>2 || !pending.TryRemove(frame.Id,out string path))
                        throw new InvalidDataException("Invalid or duplicate worker result.");
                    acknowledged[frame.Id]=true;
                    Results.Add(new Reply{Id=frame.Id,Path=path,Code=frame.Code,Signature=Wire.Clean(frame.Signature),Message=Wire.Clean(frame.Message)});
                }
            } catch(Exception ex){Fail(ex);}
        }
        public Reply Take(int milliseconds) {Results.TryTake(out Reply reply,milliseconds);return reply;}
        public void Acknowledge(int id) {
            if(!acknowledged.TryRemove(id,out _))throw new InvalidDataException("Duplicate acknowledgement.");
            slots.Release();
        }
        public void Dispose() {
            if(Interlocked.Exchange(ref disposed,1)!=0)return;
            try {
                if(!Completed)client.Abort();
                Results.CompleteAdding();
                if(Task.WaitAll(new[]{producer,reader},5000)){Results.Dispose();slots.Dispose();}
                else throw new IOException("Worker I/O cleanup could not be confirmed.");
            } finally {client.ReleaseBatch();}
        }
    }
    public sealed class Client : IDisposable {
        private readonly AnonymousPipeServerStream input,output,error;
        private IntPtr job;
        private Process process;
        private readonly Task stderr;
        private readonly StringBuilder diagnostics=new StringBuilder();
        private int disposed;
        private int batchActive;
        private readonly object lifecycle=new object();
        internal volatile bool Broken;
        internal Stream Input {get{return input;}}
        internal Stream Output {get{return output;}}
        public long MaxBytes {get;private set;}
        public int MaxThreads {get;private set;}
        public int ProcessId {get{return process.Id;}}
        public bool Alive {get{try{return !Broken && !process.HasExited;}catch(InvalidOperationException){return false;}}}
        public Task<Frame> Ready {get;private set;}
        public string TokenMode {get;private set;}
        public int? ExitCode {get{try{return process.HasExited?(int?)process.ExitCode:null;}catch(InvalidOperationException){return null;}}}
        public string Diagnostics {get{lock(diagnostics)return diagnostics.ToString();}}
        public long WorkingSet {get{try{process.Refresh();return process.WorkingSet64;}catch{return 0;}}}
        public Client(string executable,string script,Frame config,long memoryLimit,int cpuRate) {
            if(config.MaxBytes<1 || config.MaxBytes>128L*1024*1024 || config.Threads<1 || config.Threads>4 || config.IdleSeconds<15 || config.IdleSeconds>600)
                throw new ArgumentException("Worker resource configuration outside bounds.");
            MaxBytes=config.MaxBytes;MaxThreads=config.Threads;
            input=new AnonymousPipeServerStream(PipeDirection.Out,HandleInheritability.Inheritable);
            output=new AnonymousPipeServerStream(PipeDirection.In,HandleInheritability.Inheritable);
            error=new AnonymousPipeServerStream(PipeDirection.In,HandleInheritability.Inheritable);
            try {
                process=RestrictedProcess.Start(executable,script,input.ClientSafePipeHandle.DangerousGetHandle(),output.ClientSafePipeHandle.DangerousGetHandle(),error.ClientSafePipeHandle.DangerousGetHandle(),memoryLimit,cpuRate,out job,out string tokenMode);
                TokenMode=tokenMode;
                input.DisposeLocalCopyOfClientHandle();output.DisposeLocalCopyOfClientHandle();error.DisposeLocalCopyOfClientHandle();
                // Drain diagnostics without retaining file paths or unbounded text.
                stderr=Task.Run(()=>{byte[] buffer=new byte[4096];try{int count;while((count=error.Read(buffer,0,buffer.Length))>0){lock(diagnostics){diagnostics.Append(Encoding.UTF8.GetString(buffer,0,count));if(diagnostics.Length>4096)diagnostics.Remove(0,diagnostics.Length-4096);}}}catch(IOException){}});
                Wire.Write(input,config);
                Ready=Task.Run(()=>{Frame frame=Wire.Read(output);if(frame.Kind!="ready")throw new IOException(Wire.Clean(frame.Message));return frame;});
            } catch {Dispose();throw;}
        }
        public Batch BeginBatch(string list,int parallelism) {
            if(!Alive || !Ready.IsCompletedSuccessfully || parallelism<1 || parallelism>MaxThreads)throw new IOException("Worker is not ready.");
            if(Interlocked.CompareExchange(ref batchActive,1,0)!=0)throw new IOException("A scan batch is already active.");
            try{return new Batch(this,list,parallelism);}catch{ReleaseBatch();throw;}
        }
        internal void ReleaseBatch(){Interlocked.Exchange(ref batchActive,0);}
        public void SetPriority(string value) {process.PriorityClass=Enum.Parse<ProcessPriorityClass>(value);}
        public void Abort() {
            Broken=true;
            lock(lifecycle){if(job!=IntPtr.Zero)RestrictedProcess.TerminateJobObject(job,1);}
        }
        public void Dispose() {
            if(Interlocked.Exchange(ref disposed,1)!=0)return;
            try {
                Abort();
                if(process!=null) {
                    if(!process.WaitForExit(5000))throw new IOException("Owned scan worker did not exit.");
                    process.Dispose();
                }
            }finally {
                input.Dispose();output.Dispose();error.Dispose();
                lock(lifecycle){if(job!=IntPtr.Zero){RestrictedProcess.CloseHandle(job);job=IntPtr.Zero;}}
            }
        }
    }
    // Native creation is suspended until the kill-on-close job and strict handle
    // allowlist are in place. No public socket or named pipe is ever created.
    public static class RestrictedProcess {
        [StructLayout(LayoutKind.Sequential)] private struct Startup {
            public int Size;public IntPtr Reserved,Desktop,Title;public uint X,Y,XSize,YSize,XCount,YCount,Fill,Flags;public ushort Show,ReservedSize;public IntPtr ReservedBytes,Input,Output,Error;
        }
        [StructLayout(LayoutKind.Sequential)] private struct StartupEx {public Startup Startup;public IntPtr Attributes;}
        [StructLayout(LayoutKind.Sequential)] private struct ProcessInfo {public IntPtr Process,Thread;public uint Pid,Tid;}
        [StructLayout(LayoutKind.Sequential)] private struct BasicLimit {public long ProcessTime,JobTime;public uint Flags;public UIntPtr MinWorkingSet,MaxWorkingSet;public uint ActiveProcesses;public UIntPtr Affinity;public uint Priority,Scheduling;}
        [StructLayout(LayoutKind.Sequential)] private struct Io {public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes;}
        [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimit {public BasicLimit Basic;public Io Io;public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;}
        [StructLayout(LayoutKind.Sequential)] private struct CpuLimit {public uint Flags,Rate;}
        [StructLayout(LayoutKind.Sequential)] private struct Label {public IntPtr Sid;public uint Attributes;}
        [StructLayout(LayoutKind.Sequential)] private struct SecurityAttributes {public int Size;public IntPtr Descriptor;public int Inherit;}
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool CreateRestrictedToken(IntPtr token,uint flags,uint disabled,IntPtr sids,uint deleted,IntPtr privileges,uint restricted,IntPtr restrictedSids,out IntPtr result);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool SetTokenInformation(IntPtr token,int type,ref Label value,int length);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool SetTokenInformation(IntPtr token,int type,ref IntPtr value,int length);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string sddl,uint revision,out IntPtr descriptor,out uint size);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool GetSecurityDescriptorDacl(IntPtr descriptor,out bool present,out IntPtr dacl,out bool defaulted);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool ConvertStringSidToSid(string value,out IntPtr sid);
        [DllImport("advapi32.dll")] private static extern uint GetLengthSid(IntPtr sid);
        [DllImport("advapi32.dll",SetLastError=true)] private static extern bool GetTokenInformation(IntPtr token,int type,out int value,int length,out int returned);
        [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,uint flags,ref UIntPtr size);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,UIntPtr attribute,IntPtr value,UIntPtr size,IntPtr previous,IntPtr returned);
        [DllImport("kernel32.dll")] private static extern void DeleteProcThreadAttributeList(IntPtr list);
        [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool CreateProcessAsUser(IntPtr token,string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr environment,string directory,ref StartupEx startup,out ProcessInfo info);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern bool CreateProcess(string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr environment,string directory,ref StartupEx startup,out ProcessInfo info);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr CreateJobObject(IntPtr attributes,string name);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool SetInformationJobObject(IntPtr job,int type,IntPtr data,uint length);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll",SetLastError=true)] public static extern bool TerminateJobObject(IntPtr job,uint code);
        [DllImport("kernel32.dll",SetLastError=true)] public static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool TerminateProcess(IntPtr process,uint code);
        private static void Check(bool value,[System.Runtime.CompilerServices.CallerLineNumber]int line=0){if(!value)throw new Win32Exception(Marshal.GetLastWin32Error(),"Windows worker setup failed at line "+line);}
        private static void SetJob<T>(IntPtr job,int type,T value) where T:struct {
            IntPtr data=Marshal.AllocHGlobal(Marshal.SizeOf<T>());
            try{Marshal.StructureToPtr(value,data,false);Check(SetInformationJobObject(job,type,data,(uint)Marshal.SizeOf<T>()));}finally{Marshal.FreeHGlobal(data);}
        }
        private static bool Elevated(IntPtr process) {
            IntPtr token;Check(OpenProcessToken(process,8,out token));
            try{Check(GetTokenInformation(token,20,out int flag,4,out _));return flag!=0;}finally{CloseHandle(token);}
        }
        public static Process Start(string executable,string script,IntPtr input,IntPtr output,IntPtr error,long memory,int cpu,out IntPtr ownedJob,out string tokenMode) {
            if(memory<1536L*1024*1024 || memory>4L*1024*1024*1024 || cpu<100 || cpu>10000)throw new ArgumentException("Invalid job limits.");
            Wire.SafePath(executable);Wire.SafePath(script);
            IntPtr token=IntPtr.Zero,restricted=IntPtr.Zero,sid=IntPtr.Zero,attributes=IntPtr.Zero,handles=IntPtr.Zero,job=IntPtr.Zero,descriptor=IntPtr.Zero,processSecurity=IntPtr.Zero;
            ProcessInfo info=default;bool started=false;ownedJob=IntPtr.Zero;tokenMode="";
            try {
                Check(OpenProcessToken(GetCurrentProcess(),0x0002|0x0008|0x0001|0x0080,out token));
                Check(CreateRestrictedToken(token,0x1|0x4,0,IntPtr.Zero,0,IntPtr.Zero,0,IntPtr.Zero,out restricted));
                // An elevated creator's default DACL can grant only SYSTEM and
                // Administrators. LUA removes the latter from the child's usable
                // groups. Give the user and SYSTEM explicit access to its token
                // defaults, process and initial thread before Windows initializes it.
                string user=WindowsIdentity.GetCurrent().User.Value;
                Check(ConvertStringSecurityDescriptorToSecurityDescriptor("D:P(A;;GA;;;SY)(A;;GA;;;"+user+")",1,out descriptor,out _));
                Check(GetSecurityDescriptorDacl(descriptor,out bool present,out IntPtr dacl,out _));
                if(!present||dacl==IntPtr.Zero)throw new InvalidOperationException("Worker security descriptor has no DACL.");
                Check(SetTokenInformation(restricted,6,ref dacl,IntPtr.Size));
                processSecurity=Marshal.AllocHGlobal(Marshal.SizeOf<SecurityAttributes>());
                Marshal.StructureToPtr(new SecurityAttributes{Size=Marshal.SizeOf<SecurityAttributes>(),Descriptor=descriptor},processSecurity,false);
                Check(ConvertStringSidToSid("S-1-16-8192",out sid));
                Label label=new Label{Sid=sid,Attributes=0x20};Check(SetTokenInformation(restricted,25,ref label,Marshal.SizeOf<Label>()+(int)GetLengthSid(sid)));
                UIntPtr size=UIntPtr.Zero;InitializeProcThreadAttributeList(IntPtr.Zero,1,0,ref size);
                attributes=Marshal.AllocHGlobal((int)size);Check(InitializeProcThreadAttributeList(attributes,1,0,ref size));
                handles=Marshal.AllocHGlobal(3*IntPtr.Size);Marshal.WriteIntPtr(handles,0,input);Marshal.WriteIntPtr(handles,IntPtr.Size,output);Marshal.WriteIntPtr(handles,2*IntPtr.Size,error);
                Check(UpdateProcThreadAttribute(attributes,0,(UIntPtr)0x20002,handles,(UIntPtr)(3*IntPtr.Size),IntPtr.Zero,IntPtr.Zero));
                StartupEx startup=new StartupEx{Startup=new Startup{Size=Marshal.SizeOf<StartupEx>(),Flags=0x100,Input=input,Output=output,Error=error},Attributes=attributes};
                string command="\""+executable+"\" -NoLogo -NoProfile -NonInteractive -File \""+script+"\"";
                uint flags=0x08000000|0x00080000|0x4;
                started=CreateProcessAsUser(restricted,executable,new StringBuilder(command),processSecurity,processSecurity,true,flags,IntPtr.Zero,Path.GetDirectoryName(script),ref startup,out info);
                if(started)tokenMode="restricted";
                else {
                    int failure=Marshal.GetLastWin32Error();
                    // Standard-user fallback never inherits an elevated token.
                    if(Elevated(GetCurrentProcess()))throw new Win32Exception(failure,"Restricted launch failed; elevated fallback refused.");
                    Check(CreateProcess(executable,new StringBuilder(command),processSecurity,processSecurity,true,flags,IntPtr.Zero,Path.GetDirectoryName(script),ref startup,out info));
                    started=true;tokenMode="standard-user";
                }
                if(Elevated(info.Process))throw new InvalidOperationException("Elevated scan worker refused.");
                job=CreateJobObject(IntPtr.Zero,null);if(job==IntPtr.Zero)throw new Win32Exception();
                SetJob(job,9,new ExtendedLimit{Basic=new BasicLimit{Flags=0x2000|0x100|0x8,ActiveProcesses=1},ProcessMemory=(UIntPtr)memory});
                SetJob(job,15,new CpuLimit{Flags=1|4,Rate=(uint)cpu});
                Check(AssignProcessToJobObject(job,info.Process));
                if(ResumeThread(info.Thread)==UInt32.MaxValue)throw new Win32Exception();
                Process process=Process.GetProcessById((int)info.Pid);ownedJob=job;job=IntPtr.Zero;return process;
            } catch {if(started)TerminateProcess(info.Process,1);throw;}
            finally {
                if(info.Thread!=IntPtr.Zero)CloseHandle(info.Thread);if(info.Process!=IntPtr.Zero)CloseHandle(info.Process);
                if(job!=IntPtr.Zero)CloseHandle(job);if(attributes!=IntPtr.Zero){DeleteProcThreadAttributeList(attributes);Marshal.FreeHGlobal(attributes);}
                if(handles!=IntPtr.Zero)Marshal.FreeHGlobal(handles);if(sid!=IntPtr.Zero)LocalFree(sid);if(restricted!=IntPtr.Zero)CloseHandle(restricted);if(token!=IntPtr.Zero)CloseHandle(token);
                if(processSecurity!=IntPtr.Zero)Marshal.FreeHGlobal(processSecurity);if(descriptor!=IntPtr.Zero)LocalFree(descriptor);
            }
        }
    }
}
