// SPDX-License-Identifier: GPL-2.0-or-later
// Optional, separate-process libclamav adapter. See COPYING.txt in this folder.
using System;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading.Tasks;

namespace Remnexa.Worker {
    public sealed class NativeEngine : IDisposable {
        [StructLayout(LayoutKind.Sequential)] private struct ScanOptions {public uint General,Parse,Heuristic,Mail,Dev;}
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int Init(uint options);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr NewEngine();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int EngineCall(IntPtr engine);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SetNum(IntPtr engine,int field,long value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SetString(IntPtr engine,int field,[MarshalAs(UnmanagedType.LPUTF8Str)]string value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int Load([MarshalAs(UnmanagedType.LPUTF8Str)]string path,IntPtr engine,out uint signatures,uint options);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr StringCall();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr ErrorText(int error);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr OpenMap(IntPtr start,UIntPtr length);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void CloseMap(IntPtr map);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int ScanMap(IntPtr map,[MarshalAs(UnmanagedType.LPUTF8Str)]string name,out IntPtr signature,out uint scanned,IntPtr engine,ref ScanOptions options,IntPtr context);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void Message(int severity,IntPtr full,IntPtr text,IntPtr context);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void SetMessage(Message callback);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
        private IntPtr library;
        private IntPtr engine;
        private readonly EngineCall free;
        private readonly OpenMap openMap;
        private readonly CloseMap closeMap;
        private readonly ScanMap scan;
        private readonly ErrorText errorText;
        private readonly Message messages;
        public string Version {get;private set;}
        public uint Signatures {get;private set;}
        private T Export<T>(string name) where T:Delegate {return Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(library,name));}
        private void Check(int code){if(code!=0)throw new IOException("libclamav: "+Wire.Clean(Marshal.PtrToStringUTF8(errorText(code))));}
        public NativeEngine(Frame config) {
            Wire.SafePath(config.EnginePath);Wire.SafePath(config.DatabasePath);Wire.SafePath(config.TempPath);
            library=LoadLibraryEx(config.EnginePath,IntPtr.Zero,0x100|0x1000);
            if(library==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not load configured libclamav.");
            try {
                Version=Marshal.PtrToStringUTF8(Export<StringCall>("cl_retver")());
                // Explicit ABI support; an unknown update uses the CLI fallback.
                if(Version!="1.5.4")throw new NotSupportedException("Private engine currently validated for ClamAV 1.5.4 only.");
                errorText=Export<ErrorText>("cl_strerror");free=Export<EngineCall>("cl_engine_free");
                openMap=Export<OpenMap>("cl_fmap_open_memory");closeMap=Export<CloseMap>("cl_fmap_close");scan=Export<ScanMap>("cl_scanmap_callback");
                messages=(severity,full,text,context)=>{if(severity>=64)Console.Error.WriteLine(Wire.Clean(Marshal.PtrToStringUTF8(full)));};Export<SetMessage>("cl_set_clcb_msg")(messages);
                Check(Export<Init>("cl_init")(0));engine=Export<NewEngine>("cl_engine_new")();
                if(engine==IntPtr.Zero)throw new OutOfMemoryException("Could not allocate ClamAV engine.");
                var set=Export<SetNum>("cl_engine_set_num");
                Check(set(engine,0,400L*1024*1024)); // CL_ENGINE_MAX_SCANSIZE
                Check(set(engine,1,config.MaxBytes)); // CL_ENGINE_MAX_FILESIZE
                Check(Export<SetString>("cl_engine_set_str")(engine,13,config.TempPath)); // CL_ENGINE_TMPDIR
                string certificates=Path.Combine(Path.GetDirectoryName(config.EnginePath),"certs");
                Wire.SafePath(certificates);
                Check(Export<SetString>("cl_engine_set_str")(engine,37,certificates)); // CL_ENGINE_CVDCERTSDIR
                Check(set(engine,31,120000)); // CL_ENGINE_MAX_SCANTIME, ms
                uint count;Check(Export<Load>("cl_load")(config.DatabasePath,engine,out count,0x2|0x8|0x2000|(config.IncludePUA?0x10u:0)));
                if(count==0)throw new IOException("No signatures loaded.");Signatures=count;
                Check(Export<EngineCall>("cl_engine_compile")(engine));
            }catch{Dispose();throw;}
        }
        public Frame Scan(Frame request,byte[] bytes) {
            if(bytes.Length==0)return new Frame{Kind="result",Id=request.Id,Code=0};
            GCHandle pinned=GCHandle.Alloc(bytes,GCHandleType.Pinned);IntPtr map=IntPtr.Zero;
            try {
                map=openMap(pinned.AddrOfPinnedObject(),(UIntPtr)bytes.Length);
                if(map==IntPtr.Zero)throw new IOException("Could not map scan data.");
                // All parsers present in the validated 1.5.4 header, normal
                // heuristics, and visible resource-limit alerts. No all-match.
                ScanOptions options=new ScanOptions{General=0x4|0x10,Parse=0x1fff,Heuristic=0x4};
                int code=scan(map,request.Name,out IntPtr signature,out _,engine,ref options,IntPtr.Zero);
                return new Frame{Kind="result",Id=request.Id,Code=(code==0?0:code==1?1:2),Signature=(code==1?Wire.Clean(Marshal.PtrToStringUTF8(signature)):""),Message=(code>1?Wire.Clean(Marshal.PtrToStringUTF8(errorText(code))):"")};
            }finally{if(map!=IntPtr.Zero)closeMap(map);pinned.Free();}
        }
        public void Dispose() {if(engine!=IntPtr.Zero){free(engine);engine=IntPtr.Zero;}if(library!=IntPtr.Zero){NativeLibrary.Free(library);library=IntPtr.Zero;}}
    }
    public static class Server {
        public static void Run() {
            using(var identity=WindowsIdentity.GetCurrent()) {
                if(new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))throw new InvalidOperationException("Elevated worker refused.");
            }
            Stream input=Console.OpenStandardInput(),output=Console.OpenStandardOutput();
            Frame config=Wire.Read(input);
            if(config.Kind!="init" || config.Threads<1 || config.Threads>4 || config.MaxBytes<1 || config.MaxBytes>128L*1024*1024 || config.IdleSeconds<15 || config.IdleSeconds>600)throw new InvalidDataException("Invalid engine initialization.");
            using(var engine=new NativeEngine(config)) {
                Wire.Write(output,new Frame{Kind="ready",Version=engine.Version,SignatureCount=engine.Signatures,Threads=config.Threads});
                object writer=new object();
                int expected=0,received=0,completed=0;
                bool inBatch=false;
                var failures=new ConcurrentQueue<Exception>();
                using(var jobs=new BlockingCollection<Tuple<Frame,byte[]>>(config.Threads)) {
                    Task[] scanners=new Task[config.Threads];
                    for(int i=0;i<scanners.Length;i++)scanners[i]=Task.Run(()=>{
                        try {
                        foreach(var work in jobs.GetConsumingEnumerable()) {
                            Frame reply;
                            try{reply=engine.Scan(work.Item1,work.Item2);}catch(Exception ex){reply=new Frame{Kind="result",Id=work.Item1.Id,Code=2,Message=Wire.Clean(ex.Message)};}
                            lock(writer)Wire.Write(output,reply);
                            System.Threading.Interlocked.Increment(ref completed);
                        }
                        }catch(Exception ex){failures.Enqueue(ex);}
                    });
                    try {
                        while(true) {
                            Task<Frame> read=Task.Run(()=>Wire.Read(input));
                            while(!read.Wait(config.IdleSeconds*1000)) {
                                if(failures.TryPeek(out Exception failed))throw new IOException("Scan thread failed.",failed);
                                // Inactivity applies between batches, never to a
                                // long native scan or producer backpressure.
                                if(!inBatch)return;
                            }
                            Frame frame=read.GetAwaiter().GetResult();
                            if(frame.Kind=="file") {
                                if(frame.Id<=expected || frame.Length<0 || frame.Length>config.MaxBytes || String.IsNullOrEmpty(frame.Name) || frame.Name.Length>1024 || frame.Name.IndexOfAny(new[]{'\r','\n','\0','\\','/'})>=0)throw new InvalidDataException("Invalid scan request.");
                                inBatch=true;expected=frame.Id;received++;
                                byte[] bytes=new byte[(int)frame.Length];Wire.Exact(input,bytes,bytes.Length);
                                while(!jobs.TryAdd(Tuple.Create(frame,bytes),100))if(failures.TryPeek(out Exception failed))throw new IOException("Scan thread failed.",failed);
                            } else if(frame.Kind=="end") {
                                if(frame.Id<expected)throw new InvalidDataException("Incomplete scan batch.");
                                while(System.Threading.Volatile.Read(ref completed)<received) {
                                    if(failures.TryPeek(out Exception failed))throw new IOException("Scan thread failed.",failed);
                                    System.Threading.Thread.Sleep(10);
                                }
                                lock(writer)Wire.Write(output,new Frame{Kind="end",Id=frame.Id});
                                expected=0;received=0;completed=0;inBatch=false;
                            } else if(frame.Kind=="stop")return;
                            else throw new InvalidDataException("Unsupported worker command.");
                        }
                    }finally{jobs.CompleteAdding();Task.WaitAll(scanners);}
                }
            }
        }
    }
}
