/* Test-only OS API replacement. Never compiled into the shipped launcher. */
#define UNICODE
#define _UNICODE
#include <windows.h>
static LONG WINAPI FixtureVersion(OSVERSIONINFOEXW *version) {
    WCHAR mode[64]={0};GetEnvironmentVariableW(L"REMNEXA_TEST_OS",mode,64);
    version->dwMajorVersion=10;version->dwMinorVersion=0;
    version->dwBuildNumber=22000;version->wProductType=VER_NT_WORKSTATION;
    if(lstrcmpW(mode,L"windows10")==0)version->dwBuildNumber=19045;
    if(lstrcmpW(mode,L"boundary")==0)version->dwBuildNumber=21999;
    if(lstrcmpW(mode,L"windows7")==0){version->dwMajorVersion=6;version->dwMinorVersion=1;version->dwBuildNumber=7601;}
    if(lstrcmpW(mode,L"server")==0){version->dwBuildNumber=26100;version->wProductType=VER_NT_SERVER;}
    if(lstrcmpW(mode,L"future")==0){version->dwMajorVersion=11;version->dwBuildNumber=1;}
    if(lstrcmpW(mode,L"query_error")==0)return -1;
    return 0;
}
static FARPROC WINAPI FixtureGetProcAddress(HMODULE module,LPCSTR name) {
    WCHAR mode[64]={0};(void)module;(void)name;
    GetEnvironmentVariableW(L"REMNEXA_TEST_OS",mode,64);
    return lstrcmpW(mode,L"unavailable")==0?NULL:(FARPROC)FixtureVersion;
}
#define GetProcAddress FixtureGetProcAddress
#include "../../src/Launcher/launcher.c"
