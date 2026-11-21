// Test-only observation of Windows kernel limits. No allocations or limit changes.
using System;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
namespace Remnexa.Tests {
    public static class WorkerResourceProbe {
        [StructLayout(LayoutKind.Sequential)] struct Basic {public long ProcessTime,JobTime;public uint Flags;public UIntPtr MinSet,MaxSet;public uint Processes;public UIntPtr Affinity;public uint Priority,Scheduling;}
        [StructLayout(LayoutKind.Sequential)] struct Io {public ulong ReadOps,WriteOps,OtherOps,ReadBytes,WriteBytes,OtherBytes;}
        [StructLayout(LayoutKind.Sequential)] struct Extended {public Basic Basic;public Io Io;public UIntPtr ProcessMemory,JobMemory,PeakProcess,PeakJob;}
        [StructLayout(LayoutKind.Sequential)] struct Cpu {public uint Flags,Rate;}
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int type,IntPtr buffer,uint size,out uint returned);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
        [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int type,IntPtr data,uint size,out uint needed);
        static T Query<T>(int type) where T:struct {
            int size=Marshal.SizeOf<T>();IntPtr data=Marshal.AllocHGlobal(size);
            try{if(!QueryInformationJobObject(IntPtr.Zero,type,data,(uint)size,out _))throw new System.ComponentModel.Win32Exception();return Marshal.PtrToStructure<T>(data);}finally{Marshal.FreeHGlobal(data);}
        }
        public static string Snapshot() {
            Extended limit=Query<Extended>(9);Cpu cpu=Query<Cpu>(15);
            IntPtr token;if(!OpenProcessToken(GetCurrentProcess(),8,out token))throw new System.ComponentModel.Win32Exception();
            bool user=false,system=false,admins=false;int count=0;uint bytes;
            try {
                GetTokenInformation(token,6,IntPtr.Zero,0,out bytes);IntPtr data=Marshal.AllocHGlobal((int)bytes);
                try {
                    if(!GetTokenInformation(token,6,data,bytes,out _))throw new System.ComponentModel.Win32Exception();
                    IntPtr pointer=Marshal.ReadIntPtr(data);int size=(ushort)Marshal.ReadInt16(pointer,2);byte[] raw=new byte[size];Marshal.Copy(pointer,raw,0,size);
                    RawAcl acl=new RawAcl(raw,0);string current=WindowsIdentity.GetCurrent().User.Value;
                    foreach(GenericAce ace in acl){if(ace is CommonAce rule && rule.AceQualifier==AceQualifier.AccessAllowed){count++;string sid=rule.SecurityIdentifier.Value;user|=sid==current;system|=sid=="S-1-5-18";admins|=sid=="S-1-5-32-544";}}
                }finally{Marshal.FreeHGlobal(data);}
            }finally{CloseHandle(token);}
            bool admin=new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
            return JsonSerializer.Serialize(new{MemoryLimit=(ulong)limit.ProcessMemory,ActiveProcessLimit=limit.Basic.Processes,KillOnClose=(limit.Basic.Flags&0x2000)!=0,MemoryLimitEnabled=(limit.Basic.Flags&0x100)!=0,CpuRate=cpu.Rate,CpuHardCap=(cpu.Flags&5)==5,ElevatedRole=admin,DefaultDaclEntries=count,CurrentUserAllowed=user,SystemAllowed=system,AdministratorsAllowed=admins});
        }
    }
}
