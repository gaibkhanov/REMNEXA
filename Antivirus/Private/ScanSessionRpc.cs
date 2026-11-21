// SPDX-License-Identifier: MIT
using System;
using System.Collections.Concurrent;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
namespace Remnexa.ScanSession {
    public sealed class Command {
        public string Id {get;set;}
        public string Action {get;set;}
        public string ConfigPath {get;set;}
        public string ScanType {get;set;}
        public string Language {get;set;}
        public string[] Paths {get;set;}
    }
    public sealed class Request {
        public Command Command;
        public uint ClientProcessId;
        internal readonly TaskCompletionSource<string> Response=new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        public void Complete(bool ok,string error){Response.TrySetResult(JsonSerializer.Serialize(new{ok,error}));}
    }
    // Local, same Windows user AND elevation level only. No network endpoint.
    public sealed class Rpc : IDisposable {
        private readonly CancellationTokenSource stop=new CancellationTokenSource();
        private readonly ConcurrentQueue<Request> queue=new ConcurrentQueue<Request>();
        private readonly Task server;
        public readonly TaskCompletionSource<bool> Ready=new TaskCompletionSource<bool>();
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool GetNamedPipeServerProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe,out uint pid);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool GetNamedPipeClientProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe,out uint pid);
        public Rpc(string name){server=Task.Run(()=>Serve(name));}
        public Request Take(){queue.TryDequeue(out Request request);return request;}
        private static async Task<string> Read(Stream stream,CancellationToken token) {
            byte[] length=new byte[4];await stream.ReadExactlyAsync(length,token);
            int size=System.Buffers.Binary.BinaryPrimitives.ReadInt32LittleEndian(length);
            if(size<2||size>65536)throw new InvalidDataException("Invalid scan control frame.");
            byte[] data=new byte[size];await stream.ReadExactlyAsync(data,token);return Encoding.UTF8.GetString(data);
        }
        private static async Task Write(Stream stream,string text,CancellationToken token) {
            byte[] data=Encoding.UTF8.GetBytes(text);if(data.Length>65536)throw new InvalidDataException("Scan control frame too large.");
            byte[] length=new byte[4];System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(length,data.Length);
            await stream.WriteAsync(length,token);await stream.WriteAsync(data,token);await stream.FlushAsync(token);
        }
        private async Task Serve(string name) {
            try {
                while(!stop.IsCancellationRequested) {
                    using(var pipe=new NamedPipeServerStream(name,PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous|PipeOptions.CurrentUserOnly)) {
                        Ready.TrySetResult(true);
                        await pipe.WaitForConnectionAsync(stop.Token);
                        using(var deadline=CancellationTokenSource.CreateLinkedTokenSource(stop.Token)) {
                            deadline.CancelAfter(10000);
                            try {
                                var options=new JsonSerializerOptions{MaxDepth=4,UnmappedMemberHandling=System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow};
                                Command command=JsonSerializer.Deserialize<Command>(await Read(pipe,deadline.Token),options);
                                if(command==null||!Guid.TryParseExact(command.Id,"N",out _)||Array.IndexOf(new[]{"Start","Pause","Resume","Cancel","Detach","Release"},command.Action)<0||command.Paths?.Length>256)
                                    throw new InvalidDataException("Unsupported scan control request.");
                                if(!GetNamedPipeClientProcessId(pipe.SafePipeHandle,out uint clientPid))throw new IOException("Cannot authenticate scan client.");
                                var request=new Request{Command=command,ClientProcessId=clientPid};queue.Enqueue(request);
                                string reply=await request.Response.Task.WaitAsync(deadline.Token);
                                await Write(pipe,reply,deadline.Token);
                            }catch(Exception ex) when(!stop.IsCancellationRequested) {
                                try{await Write(pipe,JsonSerializer.Serialize(new{ok=false,error=ex.Message}),deadline.Token);}catch{}
                            }
                        }
                    }
                }
            }catch(OperationCanceledException){}catch(Exception ex){Ready.TrySetException(ex);}
        }
        public static string Send(string name,int expectedPid,string json,int timeoutMs) {
            return SendAsync(name,expectedPid,json,timeoutMs).GetAwaiter().GetResult();
        }
        private static async Task<string> SendAsync(string name,int expectedPid,string json,int timeoutMs) {
            using(var deadline=new CancellationTokenSource(timeoutMs))
            using(var pipe=new NamedPipeClientStream(".",name,PipeDirection.InOut,PipeOptions.Asynchronous)) {
                await pipe.ConnectAsync(deadline.Token);
                if(!GetNamedPipeServerProcessId(pipe.SafePipeHandle,out uint pid)||pid!=expectedPid)throw new IOException("Unexpected scan controller process.");
                await Write(pipe,json,deadline.Token);return await Read(pipe,deadline.Token);
            }
        }
        public void Dispose(){stop.Cancel();try{server.Wait(2000);}catch{}stop.Dispose();}
    }
}
