/* DirectX 5.0 smoke test for Windows 95.
 * Exercises DirectDraw (IDirectDraw2 / IDirectDrawSurface3), Direct3D IM (IDirect3D2),
 * DirectSound (plays a short tone) and DirectInput 5 (IDirectInputDevice2A).
 * IDirectDrawSurface3, IDirect3D2 and IDirectInputDevice2 first shipped in DirectX 5,
 * so getting them proves the DX5 runtime is installed. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>   /* WAVEFORMATEX; excluded by WIN32_LEAN_AND_MEAN */
#include <stdio.h>
#include <ddraw.h>
#include <d3d.h>
#include <dsound.h>
#include <dinput.h>

static int g_fail = 0;

static void report(const char *what, HRESULT hr) {
    printf("  %-44s %s (0x%08lX)\n", what, SUCCEEDED(hr) ? "OK  " : "FAIL", (unsigned long)hr);
    if (FAILED(hr)) g_fail++;
}

static HWND make_window(HINSTANCE hi) {
    WNDCLASSA wc;
    ZeroMemory(&wc, sizeof wc);
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = hi;
    wc.lpszClassName = "DX5TestWnd";
    RegisterClassA(&wc);
    return CreateWindowA("DX5TestWnd", "DX5 test", WS_OVERLAPPEDWINDOW,
                         0, 0, 64, 64, NULL, NULL, hi, NULL);
}

/* ---------------- DirectDraw + Direct3D ---------------- */

static HRESULT WINAPI d3d_enum_cb(GUID *guid, char *desc, char *name,
                                  D3DDEVICEDESC *hal, D3DDEVICEDESC *hel, void *ctx) {
    (void)guid; (void)hel;
    (*(int *)ctx)++;
    printf("    D3D device: %-28s [%s] %s\n", name, hal->dcmColorModel ? "HAL" : "HEL", desc);
    return D3DENUMRET_OK;
}

static void test_ddraw_d3d(HWND hwnd) {
    LPDIRECTDRAW dd = NULL;
    LPDIRECTDRAW2 dd2 = NULL;
    LPDIRECTDRAWSURFACE prim = NULL;
    LPDIRECTDRAWSURFACE3 prim3 = NULL;
    LPDIRECT3D2 d3d2 = NULL;
    DDCAPS caps;
    DDSURFACEDESC sd;
    HRESULT hr;

    printf("DirectDraw / Direct3D\n");
    hr = DirectDrawCreate(NULL, &dd, NULL);
    report("DirectDrawCreate", hr);
    if (FAILED(hr)) return;

    hr = IDirectDraw_QueryInterface(dd, &IID_IDirectDraw2, (void **)&dd2);
    report("QueryInterface(IDirectDraw2)", hr);
    if (FAILED(hr)) goto out;

    hr = IDirectDraw2_SetCooperativeLevel(dd2, hwnd, DDSCL_NORMAL);
    report("SetCooperativeLevel(NORMAL)", hr);

    ZeroMemory(&caps, sizeof caps);
    caps.dwSize = sizeof caps;           /* DDCAPS_DX5 */
    hr = IDirectDraw2_GetCaps(dd2, &caps, NULL);
    report("GetCaps (DDCAPS_DX5)", hr);
    if (SUCCEEDED(hr))
        printf("    video memory: %lu KB total, %lu KB free\n",
               (unsigned long)(caps.dwVidMemTotal / 1024), (unsigned long)(caps.dwVidMemFree / 1024));

    ZeroMemory(&sd, sizeof sd);
    sd.dwSize = sizeof sd;
    hr = IDirectDraw2_GetDisplayMode(dd2, &sd);
    report("GetDisplayMode", hr);
    if (SUCCEEDED(hr))
        printf("    desktop: %lux%lu, %lu bpp\n", (unsigned long)sd.dwWidth,
               (unsigned long)sd.dwHeight, (unsigned long)sd.ddpfPixelFormat.dwRGBBitCount);

    ZeroMemory(&sd, sizeof sd);
    sd.dwSize = sizeof sd;
    sd.dwFlags = DDSD_CAPS;
    sd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    hr = IDirectDraw2_CreateSurface(dd2, &sd, &prim, NULL);
    report("CreateSurface(primary)", hr);
    if (SUCCEEDED(hr)) {
        hr = IDirectDrawSurface_QueryInterface(prim, &IID_IDirectDrawSurface3, (void **)&prim3);
        report("QueryInterface(IDirectDrawSurface3) [DX5]", hr);
    }

    hr = IDirectDraw2_QueryInterface(dd2, &IID_IDirect3D2, (void **)&d3d2);
    report("QueryInterface(IDirect3D2) [DX5]", hr);
    if (SUCCEEDED(hr)) {
        int n = 0;
        hr = IDirect3D2_EnumDevices(d3d2, d3d_enum_cb, &n);
        report("IDirect3D2::EnumDevices", hr);
        printf("    %d device(s); sizeof(D3DDEVICEDESC) = %u\n", n, (unsigned)sizeof(D3DDEVICEDESC));
    }

out:
    if (d3d2) IDirect3D2_Release(d3d2);
    if (prim3) IDirectDrawSurface3_Release(prim3);
    if (prim) IDirectDrawSurface_Release(prim);
    if (dd2) IDirectDraw2_Release(dd2);
    IDirectDraw_Release(dd);
}

/* ---------------- DirectSound ---------------- */

static void check(const char *what, int ok) {
    printf("  %-44s %s\n", what, ok ? "OK  " : "FAIL");
    if (!ok) g_fail++;
}

/* Verifies the tone actually plays without needing to hear it: the play cursor only
 * advances if the Win95 sound driver is consuming the buffer (i.e. feeding the emulated
 * card). Everything after the emulator's host audio backend is out of scope.
 * GetTickCount has ~55 ms granularity on Win9x, hence the loose rate tolerance. */
static void verify_playback(LPDIRECTSOUNDBUFFER buf, DWORD bytes, DWORD rate) {
    DWORD t0 = GetTickCount(), t_first = 0, t_last = 0, first = 0, last = 0;
    DWORD play, write, status = 0, now, stopped_at = 0;
    int samples = 0, backwards = 0, was_playing = 0;

    /* Sample the play cursor for ~300 ms while the 500 ms tone is playing. */
    while ((now = GetTickCount()) - t0 < 300) {
        if (SUCCEEDED(IDirectSoundBuffer_GetCurrentPosition(buf, &play, &write)) &&
            SUCCEEDED(IDirectSoundBuffer_GetStatus(buf, &status))) {
            if (status & DSBSTATUS_PLAYING) was_playing = 1;
            if (samples == 0) { first = play; t_first = now; }
            else if (play < last) backwards++;
            last = play; t_last = now;
            samples++;
        }
        Sleep(30);
    }
    printf("    play cursor: %lu -> %lu bytes over %lu ms (%d samples)\n",
           (unsigned long)first, (unsigned long)last,
           (unsigned long)(t_last - t_first), samples);
    check("Buffer status reports PLAYING", was_playing);
    check("Play cursor advancing", samples > 1 && last > first && backwards == 0);

    if (t_last - t_first >= 100 && last > first) {
        DWORD est = (DWORD)(((last - first) * 1000UL) / (t_last - t_first));
        printf("    estimated rate: %lu B/s (expected %lu)\n", (unsigned long)est, (unsigned long)rate);
        check("Playback rate plausible (0.5x-2x)", est >= rate / 2 && est <= rate * 2);
    }

    /* A non-looping buffer stops on its own at the end; wait up to 2 s from Play. */
    while ((now = GetTickCount()) - t0 < 2000) {
        if (SUCCEEDED(IDirectSoundBuffer_GetStatus(buf, &status)) && !(status & DSBSTATUS_PLAYING)) {
            stopped_at = now - t0;
            break;
        }
        Sleep(20);
    }
    if (stopped_at)
        printf("    buffer stopped after ~%lu ms (tone length %lu ms)\n",
               (unsigned long)stopped_at, (unsigned long)(bytes * 1000UL / rate));
    check("Buffer stopped by itself at end", stopped_at >= 300);
}

static void test_dsound(HWND hwnd) {
    LPDIRECTSOUND ds = NULL;
    LPDIRECTSOUNDBUFFER buf = NULL;
    DSCAPS caps;
    DSBUFFERDESC bd;
    WAVEFORMATEX wf;
    HRESULT hr;
    const DWORD rate = 22050, bytes = 22050 / 2;   /* 0.5 s, 8-bit mono */

    printf("DirectSound\n");
    hr = DirectSoundCreate(NULL, &ds, NULL);
    report("DirectSoundCreate", hr);
    if (FAILED(hr)) return;

    hr = IDirectSound_SetCooperativeLevel(ds, hwnd, DSSCL_NORMAL);
    report("SetCooperativeLevel(NORMAL)", hr);

    ZeroMemory(&caps, sizeof caps);
    caps.dwSize = sizeof caps;
    hr = IDirectSound_GetCaps(ds, &caps);
    report("GetCaps", hr);
    if (SUCCEEDED(hr))
        printf("    %s driver, %lu free HW mixing buffers\n",
               (caps.dwFlags & DSCAPS_EMULDRIVER) ? "emulated" : "native",
               (unsigned long)caps.dwFreeHwMixingAllBuffers);

    ZeroMemory(&wf, sizeof wf);
    wf.wFormatTag = WAVE_FORMAT_PCM;
    wf.nChannels = 1;
    wf.nSamplesPerSec = rate;
    wf.wBitsPerSample = 8;
    wf.nBlockAlign = 1;
    wf.nAvgBytesPerSec = rate;

    ZeroMemory(&bd, sizeof bd);
    bd.dwSize = sizeof bd;               /* 20 bytes: DX5 layout, no guid3DAlgorithm */
    bd.dwFlags = DSBCAPS_STATIC;
    bd.dwBufferBytes = bytes;
    bd.lpwfxFormat = &wf;
    hr = IDirectSound_CreateSoundBuffer(ds, &bd, &buf, NULL);
    report("CreateSoundBuffer", hr);
    if (SUCCEEDED(hr)) {
        void *p1, *p2; DWORD n1, n2, i;
        hr = IDirectSoundBuffer_Lock(buf, 0, bytes, &p1, &n1, &p2, &n2, 0);
        report("Lock", hr);
        if (SUCCEEDED(hr)) {
            /* ~441 Hz square wave: 25 samples high, 25 low */
            for (i = 0; i < n1; i++) ((BYTE *)p1)[i] = ((i / 25) & 1) ? 0x60 : 0xA0;
            IDirectSoundBuffer_Unlock(buf, p1, n1, p2, n2);
            hr = IDirectSoundBuffer_Play(buf, 0, 0, 0);
            report("Play (0.5 s tone)", hr);
            if (SUCCEEDED(hr)) verify_playback(buf, bytes, rate);
        }
        IDirectSoundBuffer_Release(buf);
    }
    IDirectSound_Release(ds);
}

/* ---------------- DirectInput ---------------- */

static BOOL CALLBACK di_enum_cb(LPCDIDEVICEINSTANCEA inst, LPVOID ctx) {
    (*(int *)ctx)++;
    printf("    device: %s (type 0x%08lX)\n", inst->tszInstanceName, (unsigned long)inst->dwDevType);
    return DIENUM_CONTINUE;
}

static void test_dinput(HINSTANCE hi, HWND hwnd) {
    LPDIRECTINPUTA di = NULL;
    LPDIRECTINPUTDEVICEA kbd = NULL;
    LPDIRECTINPUTDEVICE2A kbd2 = NULL;
    HRESULT hr;
    int n = 0;

    printf("DirectInput (version 0x%04X)\n", DIRECTINPUT_VERSION);
    hr = DirectInputCreateA(hi, DIRECTINPUT_VERSION, &di, NULL);
    report("DirectInputCreateA", hr);
    if (FAILED(hr)) {
        if (hr == DIERR_OLDDIRECTINPUTVERSION || hr == DIERR_BETADIRECTINPUTVERSION)
            printf("    -> installed dinput.dll is older than DirectX 5\n");
        return;
    }

    hr = IDirectInput_EnumDevices(di, 0, di_enum_cb, &n, DIEDFL_ATTACHEDONLY);
    report("EnumDevices", hr);

    hr = IDirectInput_CreateDevice(di, &GUID_SysKeyboard, &kbd, NULL);
    report("CreateDevice(SysKeyboard)", hr);
    if (SUCCEEDED(hr)) {
        BYTE keys[256];
        report("SetDataFormat(c_dfDIKeyboard)", IDirectInputDevice_SetDataFormat(kbd, &c_dfDIKeyboard));
        report("SetCooperativeLevel", IDirectInputDevice_SetCooperativeLevel(kbd, hwnd,
                                       DISCL_NONEXCLUSIVE | DISCL_BACKGROUND));
        hr = IDirectInputDevice_QueryInterface(kbd, &IID_IDirectInputDevice2A, (void **)&kbd2);
        report("QueryInterface(IDirectInputDevice2A) [DX5]", hr);
        hr = IDirectInputDevice_Acquire(kbd);
        report("Acquire", hr);
        if (SUCCEEDED(hr)) {
            report("GetDeviceState", IDirectInputDevice_GetDeviceState(kbd, sizeof keys, keys));
            IDirectInputDevice_Unacquire(kbd);
        }
        if (kbd2) IDirectInputDevice2_Release(kbd2);
        IDirectInputDevice_Release(kbd);
    }
    IDirectInput_Release(di);
}

int main(void) {
    HINSTANCE hi = GetModuleHandleA(NULL);
    HWND hwnd = make_window(hi);

    printf("DirectX 5.0 smoke test\n\n");
    if (!hwnd) { printf("CreateWindow failed\n"); return 1; }

    test_ddraw_d3d(hwnd);
    test_dsound(hwnd);
    test_dinput(hi, hwnd);

    printf("\n%s: %d failure(s)\n", g_fail ? "FAILED" : "PASSED", g_fail);
    DestroyWindow(hwnd);
    printf("Press Enter to exit.\n");
    getchar();
    return g_fail ? 1 : 0;
}
