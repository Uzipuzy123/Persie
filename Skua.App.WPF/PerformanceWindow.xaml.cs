using CommunityToolkit.Mvvm.DependencyInjection;
using Skua.Core.Interfaces;
using System;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Skua.App.WPF;

public partial class PerformanceWindow : Window
{
    private const int HISTORY = 60;

    private readonly IFlashUtil _flash;
    private readonly DispatcherTimer _timer;
    private readonly Process _proc = Process.GetCurrentProcess();

    private readonly double[] _pingHistory  = new double[HISTORY];
    private readonly double[] _frameHistory = new double[HISTORY];
    private readonly double[] _cpuHistory   = new double[HISTORY];
    private readonly double[] _ramHistory   = new double[HISTORY];
    private int _histIdx = 0;
    private int _count   = 0;

    private int    _latestPing     = -1;
    private double _latestFrameAvg = 0;
    private int    _latestFPS      = 0;
    private double _latestCpu      = 0;
    private double _latestRamMB    = 0;

    private DateTime  _lastCpuCheck;
    private TimeSpan  _lastCpuTime;
    private int       _pingTick = 2; // fire first ping immediately

    private class FrameStats { public double avg { get; set; } public int fps { get; set; } }

    public PerformanceWindow()
    {
        InitializeComponent();
        _flash = Ioc.Default.GetRequiredService<IFlashUtil>();
        _proc.Refresh();
        _lastCpuCheck = DateTime.UtcNow;
        _lastCpuTime  = _proc.TotalProcessorTime;

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += OnTick;
        _timer.Start();
    }

    private void OnTick(object? sender, EventArgs e)
    {
        CollectFrameTime();
        CollectCpuRam();

        _pingTick++;
        if (_pingTick >= 2)
        {
            _pingTick = 0;
            _ = PingAsync();
        }

        // Store sample
        double storedPing = _latestPing >= 0
            ? _latestPing
            : (_count > 0 ? _pingHistory[(_histIdx - 1 + HISTORY) % HISTORY] : 0);

        _pingHistory[_histIdx]  = storedPing;
        _frameHistory[_histIdx] = _latestFrameAvg;
        _cpuHistory[_histIdx]   = _latestCpu;
        _ramHistory[_histIdx]   = _latestRamMB;

        _histIdx = (_histIdx + 1) % HISTORY;
        _count   = Math.Min(_count + 1, HISTORY);

        UpdateLabels();
        RedrawAll();
    }

    private void CollectFrameTime()
    {
        try
        {
            var stats = _flash.Call<FrameStats>("getFrameTimeStats");
            if (stats != null)
            {
                _latestFrameAvg = stats.avg;
                _latestFPS      = stats.fps;
            }
        }
        catch { }
    }

    private void CollectCpuRam()
    {
        try
        {
            var now = DateTime.UtcNow;
            _proc.Refresh();
            double elapsed  = (now - _lastCpuCheck).TotalMilliseconds;
            double cpuUsed  = (_proc.TotalProcessorTime - _lastCpuTime).TotalMilliseconds;
            _lastCpuCheck   = now;
            _lastCpuTime    = _proc.TotalProcessorTime;

            if (elapsed > 0)
                _latestCpu = Math.Max(0, Math.Min(100,
                    cpuUsed / (elapsed * Environment.ProcessorCount) * 100));

            _latestRamMB = _proc.WorkingSet64 / (1024.0 * 1024.0);
        }
        catch { }
    }

    private async System.Threading.Tasks.Task PingAsync()
    {
        try
        {
            using var ping  = new Ping();
            var reply       = await ping.SendPingAsync("8.8.8.8", 2000);
            _latestPing     = reply.Status == IPStatus.Success ? (int)reply.RoundtripTime : -1;
        }
        catch { _latestPing = -1; }
    }

    private void UpdateLabels()
    {
        PingLabel.Text  = _latestPing >= 0 ? $"{_latestPing} ms" : "-- ms";
        FrameLabel.Text = $"{_latestFrameAvg:F1} ms";
        FPSLabel.Text   = $"  {_latestFPS} FPS";
        CpuLabel.Text   = $"{_latestCpu:F1}%";
        RamLabel.Text   = $"{_latestRamMB:F0} MB";
    }

    private void RedrawAll()
    {
        int n = _count;
        if (n < 2) return;

        var ping  = GetOrdered(_pingHistory,  n);
        var frame = GetOrdered(_frameHistory, n);
        var cpu   = GetOrdered(_cpuHistory,   n);
        var ram   = GetOrdered(_ramHistory,   n);

        DrawGraph(PingCanvas,  ping,  Ceil(ping,  200), Color.FromRgb(0x33, 0x88, 0xFF), 30);
        DrawGraph(FrameCanvas, frame, Ceil(frame, 33),  Color.FromRgb(0xC8, 0xA0, 0x40), 30);
        DrawGraph(CpuCanvas,   cpu,   100,              Color.FromRgb(0xFF, 0x44, 0x44), 25);
        DrawGraph(RamCanvas,   ram,   Ceil(ram,   512), Color.FromRgb(0xAA, 0x44, 0xFF), 25);
    }

    private double[] GetOrdered(double[] src, int n)
    {
        var result = new double[n];
        int start  = n < HISTORY ? 0 : _histIdx;
        for (int i = 0; i < n; i++)
            result[i] = src[(start + i) % HISTORY];
        return result;
    }

    private static double Ceil(double[] data, double floor)
    {
        double max = floor;
        foreach (var v in data)
            if (v > max) max = v;
        return max * 1.1;
    }

    private static void DrawGraph(Canvas canvas, double[] data, double yMax,
                                  Color line, byte fillAlpha)
    {
        canvas.Children.Clear();
        int n = data.Length;
        if (n < 2) return;

        double w = canvas.ActualWidth;
        double h = canvas.ActualHeight;
        if (w <= 0 || h <= 0) return;

        double step   = w / (n - 1);
        double pad    = 3;
        double drawH  = h - pad * 2;
        double yScale = yMax > 0 ? 1.0 / yMax : 0;

        var pts = new PointCollection(n);
        for (int i = 0; i < n; i++)
        {
            double x    = i * step;
            double norm = Math.Min(1.0, data[i] * yScale);
            double y    = pad + drawH * (1.0 - norm);
            pts.Add(new Point(x, y));
        }

        var fillPts = new PointCollection(pts)
        {
            new Point(w, h),
            new Point(0, h)
        };
        canvas.Children.Add(new Polygon
        {
            Points          = fillPts,
            Fill            = new SolidColorBrush(Color.FromArgb(fillAlpha, line.R, line.G, line.B)),
            StrokeThickness = 0
        });
        canvas.Children.Add(new Polyline
        {
            Points          = pts,
            Stroke          = new SolidColorBrush(line),
            StrokeThickness = 1.5,
            StrokeLineJoin  = PenLineJoin.Round
        });
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }

    private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

    protected override void OnClosed(EventArgs e)
    {
        _timer.Stop();
        base.OnClosed(e);
    }
}
