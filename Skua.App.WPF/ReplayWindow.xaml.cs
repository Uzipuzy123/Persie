using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Skua.App.WPF;

public partial class ReplayWindow : Window
{
    private readonly DeathReplayBuffer.FrameRecord[] _frames;
    private readonly string _killer;

    private WriteableBitmap? _bitmap;
    private readonly DispatcherTimer _timer;

    private int    _frameIdx  = 0;
    private bool   _playing   = true;
    private double _speed     = 1.0;
    private bool   _suppressScrub = false;

    public ReplayWindow(DeathReplayBuffer.FrameRecord[] frames, string killer)
    {
        InitializeComponent();
        _frames = frames;
        _killer = killer;

        _speed = 1.0;
        _timer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(50)
        };
        _timer.Tick += OnTick;

        ScrubBar.Maximum = Math.Max(0, frames.Length - 1);

        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        KillerText.Text = string.IsNullOrEmpty(_killer)
            ? "Killed by: Unknown"
            : $"Killed by: {_killer}";

        FrameCountText.Text = $"{_frames.Length} frames  ({_frames.Length / 20.0:F1}s)";
        BuildHpTimeline();

        if (_frames.Length > 0)
        {
            ShowFrame(0);
            _timer.Start();
        }
    }

    // ── playback ──────────────────────────────────────────────────────────────

    private void OnTick(object? sender, EventArgs e)
    {
        if (!_playing) return;
        _frameIdx++;
        if (_frameIdx >= _frames.Length)
        {
            _timer.Stop();
            Close();
            return;
        }
        ShowFrame(_frameIdx);
    }

    private void ShowFrame(int idx)
    {
        if (_frames.Length == 0) return;
        idx = Math.Clamp(idx, 0, _frames.Length - 1);
        var f = _frames[idx];

        if (_bitmap == null || _bitmap.PixelWidth != f.Width || _bitmap.PixelHeight != f.Height)
        {
            _bitmap = new WriteableBitmap(f.Width, f.Height, 96, 96, PixelFormats.Bgra32, null);
            FrameImage.Source = _bitmap;
        }

        var raw = DeathReplayBuffer.Decompress(f.Compressed);
        _bitmap.Lock();
        try
        {
            Marshal.Copy(raw, 0, _bitmap.BackBuffer, raw.Length);
            _bitmap.AddDirtyRect(new Int32Rect(0, 0, f.Width, f.Height));
        }
        finally { _bitmap.Unlock(); }

        // Overlay text
        HpText.Text      = f.Hp > 0 ? $"HP: {f.Hp:N0}" : "";
        double totalSec   = _frames.Length / 20.0;
        double currentSec = idx / 20.0;
        TimestampText.Text = $"{currentSec:F1}s / {totalSec:F1}s";

        // Sync scrub bar without triggering the ValueChanged handler
        _suppressScrub = true;
        ScrubBar.Value = idx;
        _suppressScrub = false;
    }

    // ── HP timeline ───────────────────────────────────────────────────────────

    private void BuildHpTimeline()
    {
        HpTimeline.Children.Clear();
        if (_frames.Length == 0) return;

        // Find max HP across all frames for scaling
        int maxHp = 1;
        foreach (var f in _frames)
            if (f.Hp > maxHp) maxHp = f.Hp;

        // One bar per second (every 10 frames)
        int seconds = (int)Math.Ceiling(_frames.Length / 20.0);
        double barW = HpTimeline.ActualWidth > 0
            ? HpTimeline.ActualWidth / Math.Max(1, seconds)
            : (Width - 24) / Math.Max(1, seconds);

        for (int s = 0; s < seconds; s++)
        {
            int frameForSecond = Math.Min(s * 20, _frames.Length - 1);
            int hp = _frames[frameForSecond].Hp;

            double ratio = hp > 0 ? (double)hp / maxHp : 0;
            byte r = (byte)(255 * (1.0 - ratio));
            byte g = (byte)(200 * ratio);
            var color = Color.FromRgb(r, g, 40);

            var rect = new Rectangle
            {
                Width   = Math.Max(1, barW - 1),
                Height  = 14,
                Fill    = new SolidColorBrush(color),
                ToolTip = hp > 0 ? $"t={s}s  HP:{hp:N0}" : $"t={s}s"
            };

            System.Windows.Controls.Canvas.SetLeft(rect, s * barW);
            System.Windows.Controls.Canvas.SetTop(rect, 1);
            HpTimeline.Children.Add(rect);
        }
    }

    // ── controls ─────────────────────────────────────────────────────────────

    private void PlayPause_Click(object sender, RoutedEventArgs e)
    {
        _playing = !_playing;
        PlayPauseBtn.Content = _playing ? "II" : ">";
        if (_playing)
        {
            if (_frameIdx >= _frames.Length - 1) _frameIdx = 0;
            _timer.Start();
        }
        else
        {
            _timer.Stop();
        }
    }

    private void HalfSpeed_Click(object sender, RoutedEventArgs e)
    {
        _speed = 0.5;
        _timer.Interval = TimeSpan.FromMilliseconds(100);
    }

    private void NormalSpeed_Click(object sender, RoutedEventArgs e)
    {
        _speed = 1.0;
        _timer.Interval = TimeSpan.FromMilliseconds(50);
    }

    private void DoubleSpeed_Click(object sender, RoutedEventArgs e)
    {
        _speed = 2.0;
        _timer.Interval = TimeSpan.FromMilliseconds(25);
    }

    private void ScrubBar_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_suppressScrub) return;
        _playing = false;
        _timer.Stop();
        PlayPauseBtn.Content = "▶";
        _frameIdx = (int)e.NewValue;
        ShowFrame(_frameIdx);
    }

    // ── window chrome ─────────────────────────────────────────────────────────

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape || e.Key == Key.Return || e.Key == Key.Space)
            Close();
    }

    private void Window_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        _timer.Stop();
        DeathReplayBuffer.Instance.Resume();
    }
}
