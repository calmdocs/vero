using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Vero;

namespace VeroExample;

public record Job(
    [property: JsonPropertyName("id")]       int Id,
    [property: JsonPropertyName("name")]     string Name,
    [property: JsonPropertyName("phase")]    string Phase,
    [property: JsonPropertyName("progress")] int Progress)
{
    // A word rather than a number: "uploading" says more about what is
    // happening than 62% does.
    public string Icon => Name switch
    {
        "Photos" => "▣",
        "Documents" => "▤",
        "Team share" => "▥",
        _ => "□",
    };

}

public record Status(
    [property: JsonPropertyName("jobs")]    Job[] Jobs,
    [property: JsonPropertyName("working")] bool Working);

public partial class MainWindow : Window
{
    private readonly VeroClient _vero;
    private readonly ObservableCollection<Job> _jobs = new();

    public MainWindow()
    {
        InitializeComponent();
        Jobs.ItemsSource = _jobs;

        // vero copies the worker somewhere writable, launches it, restarts it
        // if it dies, and carries messages over the pipes it created.
        _vero = new VeroClient(Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory, "worker.exe"));

        // Pushed the instant anything changes, so nothing polls.
        _ = ReadEvents();
        _ = ReadState();
    }

    private async System.Threading.Tasks.Task ReadEvents()
    {
        await foreach (var element in _vero.Events())
        {
            var status = element.Deserialize<Status>();
            if (status is null) continue;

            // Events arrive off the UI thread, so hop across before touching
            // anything on screen.
            Dispatcher.Invoke(() => Apply(status));
        }
    }

    private async System.Threading.Tasks.Task ReadState()
    {
        while (true)
        {
            var state = _vero.State();
            Dispatcher.Invoke(() =>
            {
                StateText.Text = state;
                StateDot.Fill = new SolidColorBrush(state == "running"
                    ? Color.FromRgb(0x5C, 0x9E, 0x75)
                    : Color.FromRgb(0xC2, 0x8C, 0x4A));
            });
            await System.Threading.Tasks.Task.Delay(1000);
        }
    }

    private void Apply(Status status)
    {
        _jobs.Clear();
        foreach (var job in status.Jobs) _jobs.Add(job);
        JobCount.Text = $"{status.Jobs.Length} job{(status.Jobs.Length == 1 ? "" : "s")}";
    }

    /// <summary>The icon at the left of a row: start that job again.</summary>
    /// <remarks>
    /// CallAsync names the handler on the worker - "restartJob" is registered
    /// there with vero.Handle - and the reply is the new status, so the window
    /// redraws without waiting for the next event.
    /// </remarks>
    private async void Restart_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not int id) return;
        try
        {
            Apply(await _vero.CallAsync<object, Status>("restartJob", new { id }));
        }
        catch (RefusedException refused)
        {
            // The worker got it and said no. It is still there, so this is
            // worth showing; "not running" would not be.
            StateText.Text = refused.Message;
        }
        catch (VeroException)
        {
            // notRunning is already visible through the state dot.
        }
    }

    private void Quit_Click(object sender, RoutedEventArgs e) => Close();

    protected override void OnClosing(CancelEventArgs e)
    {
        // Not required - the worker's standard input closes when this process
        // exits and it stops with it, crash included - but it ends the work a
        // moment sooner.
        _vero.Stop();
        base.OnClosing(e);
    }
}
