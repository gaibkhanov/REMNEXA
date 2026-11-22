// Offline HTTP transport fixtures: never opens a socket or changes real AV files.
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
namespace Remnexa.Tests {
    public sealed class DownloadHandler : HttpMessageHandler {
        public string Mode="Known";
        public int Requests;
        public readonly byte[] Payload=new byte[131073];
        public DownloadHandler(){for(int i=0;i<Payload.Length;i++)Payload[i]=(byte)(i%251);}
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token){
            Requests++;
            if(Mode=="Timeout")await Task.Delay(30000,token).ConfigureAwait(false);
            if(Mode=="Downgrade"||Mode=="RedirectLoop"){
                var redirect=new HttpResponseMessage(HttpStatusCode.Redirect);
                redirect.Headers.Location=new Uri(Mode=="Downgrade"?"http://invalid.example/package.zip":"https://invalid.example/again.zip");
                return redirect;
            }
            var response=new HttpResponseMessage(Mode=="Failure"?HttpStatusCode.ServiceUnavailable:HttpStatusCode.OK);
            response.Content=Mode=="Unknown"?(HttpContent)new UnknownContent(Payload):new ByteArrayContent(Payload);
            if(Mode=="Truncated")response.Content.Headers.ContentLength=Payload.Length+10;
            if(Mode=="Oversize")response.Content.Headers.ContentLength=2147483648;
            return response;
        }
        sealed class UnknownContent : HttpContent {
            readonly byte[] bytes;
            public UnknownContent(byte[] payload){bytes=payload;}
            protected override bool TryComputeLength(out long length){length=0;return false;}
            protected override Task SerializeToStreamAsync(Stream stream,System.Net.TransportContext context){return stream.WriteAsync(bytes,0,bytes.Length);}
        }
    }
}
