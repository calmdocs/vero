using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Controls;
using Vero;

namespace VeroExample;

// What the worker pushes: the same shape as Status and Job in main.go.
public record Job(
    [property: JsonPropertyName("id")]       int Id,
    [property: JsonPropertyName("name")]     string Name,
    [property: JsonPropertyName("phase")]    string Phase,
    [property: JsonPropertyName("progress")] int Progress);

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

    private void Apply(Status status)
    {
        _jobs.Clear();
        foreach (var job in status.Jobs) _jobs.Add(job);
    }

    // CallAsync names the handler on the worker - "restartJob" is the
    // vero.UpdateWith in main.go - and the reply is the new status, so the
    // window redraws without waiting for the next event.
    private async void Restart_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not int id) return;
        try
        {
            Apply(await _vero.CallAsync<object, Status>("restartJob", new { id }));
        }
        catch (VeroException)
        {
            // The worker refused it, or is restarting. The next event redraws.
        }
    }
}
