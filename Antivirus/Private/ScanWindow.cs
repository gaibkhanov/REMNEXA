// SPDX-License-Identifier: MIT
using System;
using System.Runtime.InteropServices;

namespace Remnexa.ConsoleUi {
    // Owns only the console modes of the calling process's console. No process
    // attachment, input injection, global keyboard hook or console clearing.
    public sealed class ScanWindow : IDisposable {
        [StructLayout(LayoutKind.Sequential)] struct Coord { public short X,Y; public Coord(short x,short y){X=x;Y=y;} }
        [StructLayout(LayoutKind.Sequential)] struct Rect { public short Left,Top,Right,Bottom; }
        [StructLayout(LayoutKind.Sequential)] struct BufferInfo { public Coord Size,Cursor; public ushort Attributes; public Rect Window; public Coord Maximum; }
        [StructLayout(LayoutKind.Explicit,CharSet=CharSet.Unicode,Size=4)] struct Cell { [FieldOffset(0)] public char Character; [FieldOffset(2)] public ushort Attributes; }
        [StructLayout(LayoutKind.Sequential)] struct CursorInfo { public uint Size; [MarshalAs(UnmanagedType.Bool)] public bool Visible; }
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int id);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetConsoleMode(IntPtr handle,out uint mode);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetConsoleMode(IntPtr handle,uint mode);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetConsoleScreenBufferInfo(IntPtr handle,out BufferInfo info);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetConsoleCursorInfo(IntPtr handle,out CursorInfo info);
        [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetConsoleCursorInfo(IntPtr handle,ref CursorInfo info);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool WriteConsoleOutputW(IntPtr handle,[In] Cell[] cells,Coord size,Coord origin,ref Rect region);
        readonly IntPtr input,output;
        readonly uint originalInput;
        readonly bool changedInput,changedCursor;
        readonly CursorInfo originalCursor;
        bool disposed;
        public bool Available {get;private set;}
        public ScanWindow(bool inputOnly=false) {
            if(!OperatingSystem.IsWindows()||Console.IsInputRedirected||Console.IsOutputRedirected)return;
            input=GetStdHandle(-10);output=GetStdHandle(-11);
            uint mode;
            if(!GetConsoleMode(input,out mode))return;
            originalInput=mode;
            // Quick Edit can suspend a classic console when the user clicks.
            // Mouse events are not scan commands and must not fill its queue.
            changedInput=SetConsoleMode(input,(mode|0x0080u)&~(0x0040u|0x0010u));
            BufferInfo buffer;
            Available=GetConsoleScreenBufferInfo(output,out buffer);
            CursorInfo cursor;
            if(!inputOnly&&Available&&GetConsoleCursorInfo(output,out cursor)) {
                originalCursor=cursor;cursor.Visible=false;
                changedCursor=SetConsoleCursorInfo(output,ref cursor);
            }
        }
        public bool Draw(string[] lines,ushort[] colors) {
            if(disposed||!Available)return false;
            BufferInfo info;
            if(!GetConsoleScreenBufferInfo(output,out info))return false;
            int width=Math.Min(512,info.Window.Right-info.Window.Left+1);
            int height=Math.Min(30,info.Window.Bottom-info.Window.Top+1);
            if(width<1||height<1)return false;
            var cells=new Cell[width*height];
            for(int row=0;row<height;row++) {
                string text=row<lines.Length?(lines[row]??""):"";
                ushort attr=(ushort)((info.Attributes&0xfff0)|(row<colors.Length?(colors[row]&15):7));
                int length=Math.Min(width,text.Length);
                if(length>0&&length<text.Length&&char.IsHighSurrogate(text[length-1]))length--;
                for(int column=0;column<width;column++) {
                    char value=column<length?text[column]:' ';
                    if(char.IsControl(value)||char.GetUnicodeCategory(value)==System.Globalization.UnicodeCategory.Format)value=' ';
                    cells[row*width+column].Character=value;
                    cells[row*width+column].Attributes=attr;
                }
                if(text.Length>width&&width>1)cells[(row+1)*width-1].Character='\u2026';
            }
            var region=new Rect {Left=info.Window.Left,Top=info.Window.Top,Right=(short)(info.Window.Left+width-1),Bottom=(short)(info.Window.Top+height-1)};
            // One buffer write replaces the frame, with no blank screen between
            // updates and no cursor movement or scrollback growth.
            return WriteConsoleOutputW(output,cells,new Coord((short)width,(short)height),new Coord(0,0),ref region);
        }
        public void Dispose() {
            if(disposed)return;disposed=true;
            if(changedCursor){var cursor=originalCursor;SetConsoleCursorInfo(output,ref cursor);}
            if(changedInput)SetConsoleMode(input,originalInput);
        }
    }
}
