using System;
using System.Runtime.InteropServices;

namespace Skua.WPF.Flash;

/// <summary>
/// Installs a thread-local WH_MOUSE hook on the Flash HWND that does two things:
///   1. Ensures Flash has keyboard focus before every left-click (prevents the
///      first-click-wasted-on-focus issue that all WPF-hosted Flash clients have).
///   2. Fires 2 additional rapid DOWN+UP pairs after each real click completes,
///      matching what AutoHotkey mouse macros do externally. Because Flash
///      coordinate/focus state is non-deterministic on the first click, repeating
///      the click at the same position massively improves target registration.
/// </summary>
internal sealed class FlashClickFixer : IDisposable
{
    private const int WH_MOUSE       = 7;
    private const int HC_ACTION      = 0;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_LBUTTONUP   = 0x0202;
    private const int WM_RBUTTONDOWN = 0x0204;

    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint tid);
    [DllImport("user32.dll")] static extern bool   UnhookWindowsHookEx(IntPtr hk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hk, int code, IntPtr wp, IntPtr lp);
    [DllImport("user32.dll")] static extern uint   GetCurrentThreadId();
    [DllImport("user32.dll")] static extern IntPtr SetFocus(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetFocus();
    [DllImport("user32.dll")] static extern bool   IsChild(IntPtr parent, IntPtr child);
    [DllImport("user32.dll")] static extern bool   PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool   ScreenToClient(IntPtr hwnd, ref POINT pt);

    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int x, y; }

    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEHOOKSTRUCT
    {
        public POINT  pt;
        public IntPtr hwnd;
        public uint   wHitTestCode;
        public IntPtr dwExtraInfo;
    }

    private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    private readonly IntPtr   _flashHwnd;
    private readonly HookProc _proc;   // must stay rooted — GC cannot collect a delegate used as native callback
    private          IntPtr   _hook;

    private IntPtr _lastClickHwnd;
    private POINT  _lastClientPt;

    public FlashClickFixer(IntPtr flashHwnd)
    {
        _flashHwnd = flashHwnd;
        _proc = HookCallback;
        _hook = SetWindowsHookEx(WH_MOUSE, _proc, IntPtr.Zero, GetCurrentThreadId());
    }

    private IntPtr HookCallback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code == HC_ACTION)
        {
            var hs = Marshal.PtrToStructure<MOUSEHOOKSTRUCT>(lParam);
            bool isFlash = hs.hwnd == _flashHwnd || IsChild(_flashHwnd, hs.hwnd);

            if (isFlash)
            {
                int msg = (int)wParam;

                if (msg == WM_LBUTTONDOWN || msg == WM_RBUTTONDOWN)
                {
                    // Ensure Flash has focus so the click isn't dropped
                    if (GetFocus() != hs.hwnd)
                        SetFocus(hs.hwnd);

                    if (msg == WM_LBUTTONDOWN)
                    {
                        // Store client-space position for the post-click extras
                        POINT pt = hs.pt;
                        ScreenToClient(hs.hwnd, ref pt);
                        _lastClickHwnd = hs.hwnd;
                        _lastClientPt  = pt;
                    }
                }
                else if (msg == WM_LBUTTONUP && _lastClickHwnd == hs.hwnd)
                {
                    // Real click finished — post 2 extra down+up at the same spot.
                    // These land in the queue after the real UP so button state is clean.
                    IntPtr lp = MakeLParam(_lastClientPt.x, _lastClientPt.y);
                    PostMessage(hs.hwnd, WM_LBUTTONDOWN, IntPtr.Zero, lp);
                    PostMessage(hs.hwnd, WM_LBUTTONUP,   IntPtr.Zero, lp);
                    PostMessage(hs.hwnd, WM_LBUTTONDOWN, IntPtr.Zero, lp);
                    PostMessage(hs.hwnd, WM_LBUTTONUP,   IntPtr.Zero, lp);
                    _lastClickHwnd = IntPtr.Zero;
                }
            }
        }
        return CallNextHookEx(_hook, code, wParam, lParam);
    }

    static IntPtr MakeLParam(int x, int y) => (IntPtr)((y << 16) | (x & 0xFFFF));

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
    }
}
