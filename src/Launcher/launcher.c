/* SPDX-License-Identifier: MIT
 * Small Win32 launcher. No CRT, shell interpolation, policy override or elevation.
 */
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <shellapi.h>

#define CAP 32768
static WCHAR *AllocText(void) { return HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, CAP * sizeof(WCHAR)); }
static BOOL FileExists(const WCHAR *p) { DWORD a=GetFileAttributesW(p); return a!=INVALID_FILE_ATTRIBUTES && !(a&FILE_ATTRIBUTE_DIRECTORY); }
static BOOL Append(WCHAR *out, const WCHAR *s) {
    if(lstrlenW(out)+lstrlenW(s)>=CAP) return FALSE;
    lstrcatW(out,s);return TRUE;
}
static WCHAR *Join(const WCHAR *root,const WCHAR *relative) {
    WCHAR *p=AllocText();if(!p)return NULL;
    if(!Append(p,root)||!Append(p,L"\\")||!Append(p,relative)){HeapFree(GetProcessHeap(),0,p);return NULL;}return p;
}
static BOOL Quote(WCHAR *out,const WCHAR *s) {
    if(!Append(out,L"\""))return FALSE;
    while(*s) {
        unsigned int slashes=0,i;while(*s==L'\\'){slashes++;s++;}
        if(*s==L'\"'||!*s)slashes*=2;
        for(i=0;i<slashes;i++)if(!Append(out,L"\\"))return FALSE;
        if(!*s)break;
        if(*s==L'\"'&&!Append(out,L"\\"))return FALSE;
        { WCHAR character[2]={*s++,0};if(!Append(out,character))return FALSE; }
    }
    return Append(out,L"\"");
}
static void Print(const WCHAR *text) {
    DWORD written;int size=WideCharToMultiByte(CP_UTF8,0,text,-1,NULL,0,NULL,NULL);
    char *bytes=HeapAlloc(GetProcessHeap(),0,size);if(!bytes)return;
    WideCharToMultiByte(CP_UTF8,0,text,-1,bytes,size,NULL,NULL);
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),bytes,size-1,&written,NULL);HeapFree(GetProcessHeap(),0,bytes);
}
static void JsonText(const WCHAR *text) {
    Print(L"\"");while(*text){WCHAR c[3]={*text++,0,0};if(c[0]>=0xd800&&c[0]<=0xdbff&&*text>=0xdc00&&*text<=0xdfff)c[1]=*text++;if(c[0]==L'\\'||c[0]==L'\"')Print(L"\\");if(c[0]>=32)Print(c);}Print(L"\"");
}
static BOOL Probe(const WCHAR *runtime,WCHAR *version) {
    SECURITY_ATTRIBUTES sa={sizeof(sa),NULL,TRUE};HANDLE readPipe=NULL,writePipe=NULL;
    STARTUPINFOW si={0};PROCESS_INFORMATION pi={0};WCHAR *command=AllocText();DWORD code=1,read=0;char result[128]={0};BOOL valid=FALSE;
    if(!command||!CreatePipe(&readPipe,&writePipe,&sa,0))goto cleanup;
    SetHandleInformation(readPipe,HANDLE_FLAG_INHERIT,0);
    if(!Quote(command,runtime)||!Append(command,L" -NoLogo -NoProfile -NonInteractive -Command \"if($PSVersionTable.PSEdition -ne 'Core' -or $PSVersionTable.PSVersion -lt [version]'7.5' -or $PSVersionTable.PSVersion.ToString().Contains('-')){exit 3};[Console]::Write($PSVersionTable.PSVersion.ToString())\""))goto cleanup;
    si.cb=sizeof(si);si.dwFlags=STARTF_USESTDHANDLES;si.hStdOutput=writePipe;si.hStdError=writePipe;si.hStdInput=GetStdHandle(STD_INPUT_HANDLE);
    if(!CreateProcessW(runtime,command,NULL,NULL,TRUE,CREATE_NO_WINDOW,NULL,NULL,&si,&pi))goto cleanup;
    CloseHandle(writePipe);writePipe=NULL;
    if(WaitForSingleObject(pi.hProcess,15000)!=WAIT_OBJECT_0){TerminateProcess(pi.hProcess,124);WaitForSingleObject(pi.hProcess,2000);goto cleanup;}
    GetExitCodeProcess(pi.hProcess,&code);
    if(code==0&&ReadFile(readPipe,result,sizeof(result)-1,&read,NULL)&&read>0) {
        DWORD i;valid=TRUE;
        for(i=0;i<read;i++)if((result[i]<'0'||result[i]>'9')&&result[i]!='.')valid=FALSE;
        if(valid){
            unsigned int major=0,minor=0;DWORD j=0;
            while(result[j]>='0'&&result[j]<='9'&&major<100){major=major*10+(result[j++]-'0');}
            if(result[j++]!='.')valid=FALSE;
            while(result[j]>='0'&&result[j]<='9'&&minor<100){minor=minor*10+(result[j++]-'0');}
            valid=valid&&(major>7||(major==7&&minor>=5));
            if(valid)MultiByteToWideChar(CP_UTF8,0,result,-1,version,128);
        }
    }
cleanup:
    if(pi.hThread)CloseHandle(pi.hThread);if(pi.hProcess)CloseHandle(pi.hProcess);
    if(readPipe)CloseHandle(readPipe);if(writePipe)CloseHandle(writePipe);if(command)HeapFree(GetProcessHeap(),0,command);return valid;
}
static BOOL Candidate(WCHAR **chosen,WCHAR *version,const WCHAR *root,const WCHAR *relative) {
    WCHAR *path=Join(root,relative);if(!path)return FALSE;
    if(FileExists(path)&&Probe(path,version)){*chosen=path;return TRUE;}
    HeapFree(GetProcessHeap(),0,path);return FALSE;
}
static BOOL FindRuntime(const WCHAR *root,WCHAR **chosen,WCHAR *version) {
    WCHAR *buffer=AllocText(),*start,*p;DWORD length;
    if(Candidate(chosen,version,root,L"runtime\\pwsh.exe"))return TRUE;
    if(!buffer)return FALSE;
    if(GetEnvironmentVariableW(L"ProgramW6432",buffer,CAP)&&Candidate(chosen,version,buffer,L"PowerShell\\7\\pwsh.exe"))return TRUE;
    if(GetEnvironmentVariableW(L"ProgramFiles",buffer,CAP)&&Candidate(chosen,version,buffer,L"PowerShell\\7\\pwsh.exe"))return TRUE;
    length=GetEnvironmentVariableW(L"PATH",buffer,CAP);
    if(length==0||length>=CAP)return FALSE;
    start=buffer;
    for(p=buffer;;p++) {
        if(*p==L';'||!*p){WCHAR saved=*p;*p=0;
            if(start[0]==L'\"'){start++;if(lstrlenW(start)>0&&start[lstrlenW(start)-1]==L'\"')start[lstrlenW(start)-1]=0;}
            /* Ignore empty/relative PATH entries: never search the current directory. */
            if(lstrlenW(start)>2&&((start[1]==L':'&&start[2]==L'\\')||(start[0]==L'\\'&&start[1]==L'\\')))
                if(Candidate(chosen,version,start,L"pwsh.exe"))return TRUE;
            if(!saved)break;start=p+1;
        }
    }
    HeapFree(GetProcessHeap(),0,buffer);return FALSE;
}
static int Error(const WCHAR *message,int code,BOOL diagnostic) {
    if(diagnostic){Print(L"{\"ok\":false,\"message\":");JsonText(message);Print(L"}\n");}
    else MessageBoxW(NULL,message,L"REMNEXA",MB_OK|MB_ICONERROR);
    return code;
}
static BOOL SupportedWindows(void) {
    typedef LONG (WINAPI *VersionProc)(OSVERSIONINFOEXW *);
    HMODULE module=GetModuleHandleW(L"ntdll.dll");
    VersionProc query=module?(VersionProc)GetProcAddress(module,"RtlGetVersion"):NULL;
    OSVERSIONINFOEXW version={0};version.dwOSVersionInfoSize=sizeof(version);
    if(!query||query(&version)!=0)return FALSE;
    return version.wProductType==VER_NT_WORKSTATION &&
        (version.dwMajorVersion>10||(version.dwMajorVersion==10&&
            (version.dwMinorVersion>0||(version.dwMinorVersion==0&&version.dwBuildNumber>=22000))));
}
static int Run(void) {
    WCHAR *root=AllocText(),*script=NULL,*runtime=NULL,*version=AllocText(),*command=AllocText(),*last;int argc=0,i;WCHAR **args=CommandLineToArgvW(GetCommandLineW(),&argc);
    BOOL diagnostic=argc==2&&lstrcmpW(args[1],L"--diagnose")==0;STARTUPINFOW si={0};PROCESS_INFORMATION pi={0};DWORD exitCode=1;
    if(!root||!version||!command||!args)return 1;
    if(!SupportedWindows())return Error(L"REMNEXA benoetigt Windows 11 oder neuer (Client-Build ab 22000). Windows 10 und Windows Server werden nicht unterstuetzt.\nREMNEXA requires Windows 11 or newer (client build 22000+). Windows 10 and Windows Server are not supported.",14,diagnostic);
    SetLastError(0);if(!GetModuleFileNameW(NULL,root,CAP)||GetLastError()==ERROR_INSUFFICIENT_BUFFER)return 1;
    last=root;for(WCHAR *p=root;*p;p++)if(*p==L'\\')last=p;*last=0;
    SetConsoleTitleW(L"REMNEXA");SetConsoleOutputCP(CP_UTF8);SetConsoleCP(CP_UTF8);
    { HWND window=GetConsoleWindow();HINSTANCE instance=GetModuleHandleW(NULL);
      if(window){SendMessageW(window,WM_SETICON,ICON_SMALL,(LPARAM)LoadImageW(instance,MAKEINTRESOURCEW(101),IMAGE_ICON,16,16,LR_DEFAULTCOLOR));SendMessageW(window,WM_SETICON,ICON_BIG,(LPARAM)LoadImageW(instance,MAKEINTRESOURCEW(101),IMAGE_ICON,32,32,LR_DEFAULTCOLOR));} }
    script=Join(root,L"app\\REMNEXA.ps1");
    if(!script||!FileExists(script)){if(script)HeapFree(GetProcessHeap(),0,script);script=Join(root,L"REMNEXA.ps1");}
    if(!script||!FileExists(script))return Error(L"REMNEXA.ps1 fehlt. Bitte das gesamte Paket entpacken.\nREMNEXA.ps1 is missing. Extract the complete package.",11,diagnostic);
    if(!FindRuntime(root,&runtime,version))return Error(L"PowerShell 7.5 oder neuer (stabile Version) fehlt. Bitte PowerShell installieren oder die kompatible Laufzeit unter runtime\\pwsh.exe bereitstellen.\nPowerShell 7.5 or newer (stable) is required. Install PowerShell or provide the compatible runtime at runtime\\pwsh.exe.",10,diagnostic);
    if(diagnostic) {
        HANDLE token;TOKEN_ELEVATION elevation={0};DWORD size;
        if(OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)){GetTokenInformation(token,TokenElevation,&elevation,sizeof(elevation),&size);CloseHandle(token);}
        Print(L"{\"ok\":true,\"runtime\":");JsonText(runtime);Print(L",\"version\":");JsonText(version);Print(L",\"script\":");JsonText(script);Print(L",\"elevated\":");Print(elevation.TokenIsElevated?L"true":L"false");Print(L"}\n");return 0;
    }
    if(!Quote(command,runtime)||!Append(command,L" -NoLogo -NoProfile -File ")||!Quote(command,script))return Error(L"Startpfad ist zu lang. / Launch path is too long.",12,FALSE);
    for(i=1;i<argc;i++)if(!Append(command,L" ")||!Quote(command,args[i]))return Error(L"Zu viele Argumente. / Too many arguments.",12,FALSE);
    si.cb=sizeof(si);
    if(!CreateProcessW(runtime,command,NULL,NULL,FALSE,0,NULL,root,&si,&pi))return Error(L"PowerShell konnte nicht gestartet werden. / PowerShell could not be started.",13,FALSE);
    CloseHandle(pi.hThread);WaitForSingleObject(pi.hProcess,INFINITE);GetExitCodeProcess(pi.hProcess,&exitCode);CloseHandle(pi.hProcess);LocalFree(args);
    if(exitCode!=0&&GetConsoleWindow())MessageBoxW(NULL,L"REMNEXA wurde mit einem Fehler beendet. Bitte Konsolenausgabe und Protokolle pruefen.\nREMNEXA exited with an error. Review the console output and logs.",L"REMNEXA",MB_OK|MB_ICONWARNING);
    return (int)exitCode;
}
void WINAPI Entry(void) { ExitProcess((UINT)Run()); }
