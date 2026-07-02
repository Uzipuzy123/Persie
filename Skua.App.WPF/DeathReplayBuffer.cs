using System;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Threading;
using Skua.Core.Interfaces;

namespace Skua.App.WPF;

public sealed class DeathReplayBuffer : IDisposable
{
    #region Win32
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rc);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
    [DllImport("gdi32.dll")]  static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")]  static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int cx, int cy);
    [DllImport("gdi32.dll")]  static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);
    [DllImport("gdi32.dll")]  static extern bool BitBlt(IntPtr dst, int x, int y, int cx, int cy, IntPtr src, int x1, int y1, uint rop);
    [DllImport("gdi32.dll")]  static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")]  static extern bool DeleteObject(IntPtr ho);
    [DllImport("gdi32.dll")]  static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint s, uint lines, byte[] bits, ref BITMAPINFO bmi, uint usage);

    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public uint biSize; public int biWidth; public int biHeight;
        public ushort biPlanes; public ushort biBitCount; public uint biCompression;
        public uint biSizeImage, biXPPM, biYPPM, biClrUsed, biClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFO
    {
        public BITMAPINFOHEADER bmiHeader;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public uint[] bmiColors;
    }

    private const uint SRCCOPY = 0x00CC0020;
    #endregion

    public readonly struct FrameRecord
    {
        public readonly byte[] Compressed;
        public readonly int Width, Height, Hp;
        public readonly long TimestampMs;

        public FrameRecord(byte[] c, int w, int h, int hp, long ts)
        { Compressed = c; Width = w; Height = h; Hp = hp; TimestampMs = ts; }
    }

    // ── singleton ─────────────────────────────────────────────────────────────

    private static readonly Lazy<DeathReplayBuffer> _lazy = new(() => new DeathReplayBuffer());
    public static DeathReplayBuffer Instance => _lazy.Value;

    private DeathReplayBuffer() { }

    // ── ring buffer ───────────────────────────────────────────────────────────

    private const int CAPACITY = 80;  // 4 seconds × 20 fps
    private const int INTERVAL = 50;  // ms between captures

    private readonly FrameRecord[] _ring = new FrameRecord[CAPACITY];
    private int  _head  = 0;
    private int  _count = 0;
    private readonly object _ringLock = new();

    // ── state ─────────────────────────────────────────────────────────────────

    private volatile bool   _frozen = false;
    private volatile int    _drainFrames = 0; // capture this many more frames after Freeze() before stopping
    private string          _killer = "";
    private volatile int    _currentHp;

    private Thread? _thread;
    private volatile bool _running;
    private IntPtr _flashHwnd;
    private int    _w, _h;
    private IFlashUtil? _flashUtil;

    public bool   HasReplay  => _frozen && _count > 0;
    public string LastKiller => _killer;

    // ── public API ────────────────────────────────────────────────────────────

    public void Start(IFlashUtil flashUtil)
    {
        _flashUtil = flashUtil;
        if (_thread != null) return;
        _running = true;
        _thread  = new Thread(Loop) { IsBackground = true, Name = "DeathReplay" };
        _thread.Start();
    }

    // Called from HP poll every 250 ms
    public void UpdateHp(int hp) => _currentHp = hp;

    // Called when "skua.onDeath" FlashCall fires
    public void Freeze(string killer)
    {
        _killer = killer;
        _drainFrames = 14; // ~0.7s of extra capture at 20fps to include death animation
    }

    // Called when ReplayWindow is closed — resumes recording
    public void Resume()
    {
        lock (_ringLock) { _head = 0; _count = 0; }
        _killer = "";
        _drainFrames = 0;
        _frozen = false;
    }

    // Returns frames oldest-first (chronological order)
    public FrameRecord[] GetSnapshot()
    {
        lock (_ringLock)
        {
            var result = new FrameRecord[_count];
            for (int i = 0; i < _count; i++)
                result[i] = _ring[(_head - _count + i + CAPACITY) % CAPACITY];
            return result;
        }
    }

    public static byte[] Decompress(byte[] data)
    {
        using var src = new MemoryStream(data);
        using var gz  = new GZipStream(src, CompressionMode.Decompress);
        using var dst = new MemoryStream(data.Length * 6);
        gz.CopyTo(dst);
        return dst.ToArray();
    }

    // ── capture loop ──────────────────────────────────────────────────────────

    private void Loop()
    {
        while (_running)
        {
            if (!_frozen)
            {
                if (_flashHwnd == IntPtr.Zero || !IsWindow(_flashHwnd))
                    _flashHwnd = _flashUtil?.FlashWindowHandle ?? IntPtr.Zero;

                if (_flashHwnd != IntPtr.Zero)
                    CaptureFrame();

                if (_drainFrames > 0)
                {
                    _drainFrames--;
                    if (_drainFrames == 0) _frozen = true;
                }
            }
            Thread.Sleep(INTERVAL);
        }
    }

    private void CaptureFrame()
    {
        GetWindowRect(_flashHwnd, out var rc);
        int w = rc.Right - rc.Left, h = rc.Bottom - rc.Top;
        if (w <= 0 || h <= 0) return;
        _w = w; _h = h;

        IntPtr srcDC = GetDC(_flashHwnd);
        IntPtr memDC = CreateCompatibleDC(srcDC);
        IntPtr bmp   = CreateCompatibleBitmap(srcDC, w, h);
        IntPtr old   = SelectObject(memDC, bmp);

        bool ok = BitBlt(memDC, 0, 0, w, h, srcDC, 0, 0, SRCCOPY);
        byte[] raw = new byte[w * h * 4];

        if (ok)
        {
            var bi = new BITMAPINFO
            {
                bmiHeader = new BITMAPINFOHEADER
                {
                    biSize    = (uint)Marshal.SizeOf<BITMAPINFOHEADER>(),
                    biWidth   = w, biHeight = -h,
                    biPlanes  = 1, biBitCount = 32
                },
                bmiColors = new uint[4]
            };
            GetDIBits(memDC, bmp, 0, (uint)h, raw, ref bi, 0);
            for (int i = 3; i < raw.Length; i += 4) raw[i] = 255;
        }

        SelectObject(memDC, old);
        DeleteObject(bmp);
        DeleteDC(memDC);
        ReleaseDC(_flashHwnd, srcDC);

        if (!ok) return;

        var frame = new FrameRecord(Compress(raw), w, h, _currentHp, Environment.TickCount64);
        lock (_ringLock)
        {
            _ring[_head] = frame;
            _head = (_head + 1) % CAPACITY;
            if (_count < CAPACITY) _count++;
        }
    }

    public static byte[] CompressPublic(byte[] data) => Compress(data);
    private static byte[] Compress(byte[] data)
    {
        using var ms = new MemoryStream(data.Length / 5);
        using (var gz = new GZipStream(ms, CompressionLevel.Fastest))
            gz.Write(data, 0, data.Length);
        return ms.ToArray();
    }


    public void Dispose()
    {
        _running = false;
        _thread?.Join(500);
    }
}
