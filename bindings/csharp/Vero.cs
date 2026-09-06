// Drive a Go worker from a .NET interface - WinUI, WPF, or a console program.
//
// This is the Windows equivalent of Sources/Vero: a thin layer over the same
// nine C functions, with no logic of its own.  Supervision, restarts, framing
// and reconnection all happen in Go, on the other side of the boundary.
//
// Build the shared library once.  It is the same library for every
// application, because the worker's path arrives at runtime and every message
// is JSON:
//
//     go build -buildmode=c-shared -o vero.dll .\cshim
//     go build -o worker.exe .\your\worker
//
// Build the library for the architecture you will run on.  A windows/amd64 DLL
// loaded into an x64 .NET process under emulation on Windows-on-ARM does not
// work: the first call into Go either does not return, or ends the process with
// 0xC0000409.

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Vero;

/// <summary>Something went wrong talking to the worker.</summary>
public class VeroException : Exception
{
    public VeroException(string message) : base(message) { }
}

/// <summary>
/// The worker received the request and refused it. It is still running, so
/// this is a problem with the request: show the message and carry on.
/// </summary>
public sealed class RefusedException : VeroException
{
    public RefusedException(string message) : base(message) { }
}

/// <summary>
/// The worker is starting, restarting after a crash, or stopped. Nothing you
/// did was wrong: wait, and say so in the interface.
/// </summary>
/// <summary>
/// Another process is already running a worker for this application. Offer to
/// switch to the copy that is running: retrying will not help.
/// </summary>
public sealed class AlreadyRunningException : VeroException
{
    public AlreadyRunningException(string message) : base(message) { }
}

public sealed class NotRunningException : VeroException
{
    public NotRunningException(string message) : base(message) { }
}

/// <summary>Runs a Go worker and talks to it.</summary>
public sealed class VeroClient : IDisposable
{
    private const string Library = "vero";   // vero.dll beside the executable

    // IntPtr rather than string on purpose: the marshaller would copy a
    // returned string and lose the pointer, and then there is nothing left to
    // hand to VeroFree.
    [DllImport(Library)] private static extern IntPtr VeroStart(string workerPath, string argsJson);
    [DllImport(Library)] private static extern IntPtr VeroRequest(string requestJson);
    [DllImport(Library)] private static extern IntPtr VeroCall(string name, string requestJson);
    [DllImport(Library)] private static extern IntPtr VeroLatest();
    [DllImport(Library)] private static extern IntPtr VeroWaitForEvent();
    [DllImport(Library)] private static extern IntPtr VeroState();
    [DllImport(Library)] private static extern void VeroStop();
    [DllImport(Library)] private static extern void VeroFree(IntPtr s);

    private volatile bool stopped;

    /// <summary>Starts the worker and begins supervising it.</summary>
    /// <remarks>
    /// Returns as soon as the launch is under way. Until the worker is up,
    /// requests throw <see cref="NotRunningException"/>.
    /// </remarks>
    public VeroClient(string workerPath, IEnumerable<string>? arguments = null)
    {
        string argsJson = arguments is null ? "" : JsonSerializer.Serialize(arguments);
        Check(VeroStart(workerPath, argsJson));
    }

    /// <summary>Sends a request and waits for the reply.</summary>
    /// <remarks>
    /// There is no timeout: a worker may hold a request for as long as the
    /// work takes, so this runs on a thread pool thread rather than the one
    /// drawing your interface.
    /// </remarks>
    public Task<JsonElement?> SendAsync<T>(T request) =>
        Task.Run(() => Check(VeroRequest(JsonSerializer.Serialize(request))));

    /// <summary>Sends a request to one named handler, matching vero.Handle.</summary>
    /// <remarks>
    /// The worker routes on the name rather than on something inside the
    /// request, so neither side has to agree on a "type" field.
    /// </remarks>
    public Task<JsonElement?> CallAsync<T>(string name, T request) =>
        Task.Run(() => Check(VeroCall(name, JsonSerializer.Serialize(request))));

    /// <summary>Calls a named handler and decodes the reply into your own type.</summary>
    public async Task<TReply> CallAsync<T, TReply>(string name, T request)
    {
        JsonElement? reply = await CallAsync(name, request).ConfigureAwait(false);
        if (reply is null)
        {
            throw new VeroException("the worker answered nothing");
        }
        return reply.Value.Deserialize<TReply>()
            ?? throw new VeroException("could not read the reply");
    }

    /// <summary>Sends a request and decodes the reply into your own type.</summary>
    public async Task<TReply> SendAsync<T, TReply>(T request)
    {
        JsonElement? reply = await SendAsync(request).ConfigureAwait(false);
        if (reply is null)
        {
            throw new VeroException("the worker answered nothing");
        }
        return reply.Value.Deserialize<TReply>()
            ?? throw new VeroException("could not read the reply");
    }

    /// <summary>
    /// The most recent event, without waiting for the next one. Use it to draw
    /// a window that has just opened; <see cref="Events"/> keeps it current.
    /// </summary>
    public JsonElement? Latest() => Check(VeroLatest());

    /// <summary>"starting", "running", "restarting" or "stopped".</summary>
    public string State()
    {
        JsonElement? state = Check(VeroState());
        return state?.GetString() ?? "unknown";
    }

    /// <summary>Every state change the worker reports, as it happens.</summary>
    /// <remarks>
    /// Each call blocks until something changes, so enumerate this away from
    /// the interface thread and marshal back - Dispatcher.InvokeAsync under
    /// WPF, DispatcherQueue.TryEnqueue under WinUI. There is no polling and no
    /// interval to choose.
    /// </remarks>
    public async IAsyncEnumerable<JsonElement> Events()
    {
        while (!stopped)
        {
            JsonElement? next;
            try
            {
                next = await Task.Run(() => Check(VeroWaitForEvent())).ConfigureAwait(false);
            }
            catch (NotRunningException)
            {
                yield break;
            }
            if (next is not null)
            {
                yield return next.Value;
            }
        }
    }

    /// <summary>Stops the worker.</summary>
    /// <remarks>
    /// Not required - the worker's standard input closes when this process
    /// exits and it stops with it, crash included - but it ends the work a
    /// moment sooner.
    /// </remarks>
    public void Stop()
    {
        stopped = true;
        VeroStop();
    }

    public void Dispose() => Stop();

    /// <summary>Reads one envelope, frees it, and throws if it carried an error.</summary>
    private static JsonElement? Check(IntPtr pointer)
    {
        if (pointer == IntPtr.Zero)
        {
            throw new NotRunningException("the library returned nothing");
        }

        string raw;
        try
        {
            raw = Marshal.PtrToStringUTF8(pointer) ?? "{}";
        }
        finally
        {
            VeroFree(pointer);
        }

        using JsonDocument document = JsonDocument.Parse(raw);
        JsonElement root = document.RootElement;

        if (root.TryGetProperty("e", out JsonElement error))
        {
            string message = error.GetString() ?? "unknown error";
            string code = root.TryGetProperty("code", out JsonElement c) ? c.GetString() ?? "" : "";
            throw code switch
            {
                "already_running" => new AlreadyRunningException(message),
                "not_running" => new NotRunningException(message),
                "refused" => new RefusedException(message),
                _ => new VeroException(message),
            };
        }
        if (root.TryGetProperty("p", out JsonElement payload))
        {
            return payload.Clone();   // the document is disposed on the way out
        }
        return null;
    }
}
