// Test-only observer. It attaches only to the independently launched fixture.
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace Remnexa.Tests {
    public static class ScanConsoleProbe {
        [StructLayout(LayoutKind.Sequential)] struct Coord{public short X,Y;}
        [StructLayout(LayoutKind.Sequential)] struct Rect{public short Left,Top,Right,Bottom;}
        [StructLayout(LayoutKind.Sequential)] struct Buffer{public Coord Size,Cursor;public ushort Attributes;public Rect Window;public Coord Maximum;}
        [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Key{public int Down;public ushort Repeat,VirtualKey,Scan;public char Character;public uint Control;}
        [StructLayout(LayoutKind.Sequential)] struct Mouse{public Coord Position;public uint Buttons,Control,Flags;}
        [StructLayout(LayoutKind.Explicit,Size=20)] struct Input{[FieldOffset(0)]public ushort Type;[FieldOffset(4)]public Key Key;[FieldOffset(4)]public Mouse Mouse;}
        [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint processId);
        [DllImport("kernel32.dll")] public static extern bool FreeConsole();
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFile(string name,uint access,uint sharing,IntPtr security,uint disposition,uint flags,IntPtr template);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr input,out uint mode);
        [DllImport("kernel32.dll")] static extern bool GetConsoleScreenBufferInfo(IntPtr output,out Buffer info);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool ReadConsoleOutputCharacterW(IntPtr output,StringBuilder text,uint length,Coord at,out uint count);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteConsoleInputW(IntPtr input,Input[] events,uint count,out uint written);
        static IntPtr Open(string name){var h=CreateFile(name,0xc0000000,3,IntPtr.Zero,3,0,IntPtr.Zero);if(h==new IntPtr(-1))throw new Win32Exception();return h;}
        public static uint InputMode(){var h=Open("CONIN$");try{uint mode;if(!GetConsoleMode(h,out mode))throw new Win32Exception();return mode;}finally{CloseHandle(h);}}
        public static string Text(){var h=Open("CONOUT$");try{Buffer info;if(!GetConsoleScreenBufferInfo(h,out info))throw new Win32Exception();uint count;var text=new StringBuilder(info.Size.X*8);ReadConsoleOutputCharacterW(h,text,(uint)(info.Size.X*8),new Coord{X=0,Y=info.Window.Top},out count);return text.ToString();}finally{CloseHandle(h);}}
        static void Send(Input[] events){var h=Open("CONIN$");try{uint count;if(!WriteConsoleInputW(h,events,(uint)events.Length,out count)||count!=events.Length)throw new Win32Exception();}finally{CloseHandle(h);}}
        public static void Press(char character){var events=new Input[2];for(int i=0;i<2;i++){events[i].Type=1;events[i].Key.Down=i==0?1:0;events[i].Key.Repeat=1;events[i].Key.VirtualKey=(ushort)char.ToUpperInvariant(character);events[i].Key.Character=character;}Send(events);}
        public static void Click(){var events=new Input[2];for(int i=0;i<2;i++){events[i].Type=2;events[i].Mouse.Position=new Coord{X=5,Y=5};events[i].Mouse.Buttons=i==0?1u:0u;}Send(events);}
    }
}
