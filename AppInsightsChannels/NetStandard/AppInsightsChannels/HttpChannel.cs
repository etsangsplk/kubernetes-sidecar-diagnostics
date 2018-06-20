using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Collections.Concurrent;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Microsoft.ApplicationInsights.Channel
{
    public class HttpChannel : ITelemetryChannel
    {
        // TODO: Remove after testing
        private static int batchCount = 0;
        private static int itemCount = 0;

        private HttpClient client;
        private Uri endpointAddress;
        private ConcurrentQueue<ITelemetry> buffer;
        private bool disposed = false;
        private bool? developerMode = false;
        private int capacity_backup;

        private object sendingLockObj = new object();
        private AutoResetEvent startRunnerEvent;
        private bool enabled = true;

        public HttpChannel(string endpointAddress)
        {
            this.client = new HttpClient();
            this.buffer = new ConcurrentQueue<ITelemetry>();
            this.EndpointAddress = endpointAddress;

            // Starting the Runner
            Task.Factory.StartNew(this.Runner, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default)
                .ContinueWith(
                    task =>
                    {
                        Log($"InMemoryTransmitter: Unhandled exception in Runner: {task.Exception}");
                    },
                    TaskContinuationOptions.OnlyOnFaulted);
        }

        public bool? DeveloperMode
        {
            get
            {
                return this.developerMode;
            }

            set
            {
                if (value != this.developerMode)
                {
                    if (value.HasValue && value.Value)
                    {
                        this.capacity_backup = this.Capacity;
                        this.Capacity = 1;
                    }
                    else
                    {
                        this.Capacity = this.capacity_backup;
                    }

                    this.developerMode = value;
                }
            }
        }

        public string EndpointAddress
        {
            get { return this.endpointAddress.ToString(); }
            set { this.endpointAddress = new Uri(value); }
        }

        /// <summary>
        /// Send interval in seconds.
        /// </summary>
        public int SendInterval { get; set; } = 5;

        /// <summary>
        /// The number of events to be stored in the buffer before sending an event.
        /// </summary>
        public int Capacity { get; set; } = 500;

        /// <summary>
        /// The maximum number of events to be stored in the buffer.
        /// New events will be dropped if the buffer exceeds this limit.
        /// </summary>
        public int MaxBufferSize { get; set; } = 1000000;

        /// <summary>
        /// Timeout for sending/flushing the events.
        /// </summary>
        public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(100);

        public void Flush()
        {
            this.DequeueAndSend();
        }

        public void Send(ITelemetry item)
        {
            if (disposed)
            {
                Log($"Telemetry item is dropped since the channel has been disposed.");
                return;
            }

            if (this.buffer.Count >= this.MaxBufferSize)
            {
                Log($"Telemetry item is dropped since the buffer has reached the maximum size: {this.MaxBufferSize}");
                return;
            }

            this.buffer.Enqueue(item);
            if (this.buffer.Count == this.Capacity)
            {
                this.startRunnerEvent.Set();
            }
        }

        public void Dispose()
        {
            if (this.disposed)
            {
                return;
            }
            this.disposed = true;

            // Stops the runner loop.
            this.enabled = false;

            if (this.startRunnerEvent != null)
            {
                // Call Set to prevent waiting for the next interval in the runner.
                try
                {
                    this.startRunnerEvent.Set();
                }
                catch (ObjectDisposedException)
                {
                    // We need to try catch the Set call in case the auto-reset event wait interval occurs between setting enabled
                    // to false and the call to Set then the auto-reset event will have already been disposed by the runner thread.
                }
            }

            this.Flush();

            this.client.Dispose();
        }

        private void Runner()
        {
            using (this.startRunnerEvent = new AutoResetEvent(false))
            {
                while (this.enabled)
                {
                    // Pulling all items from the buffer and sending as one transmission.
                    this.DequeueAndSend();

                    // Waiting for the flush delay to elapse
                    this.startRunnerEvent.WaitOne(this.SendInterval * 1000);
                }
            }
        }

        private void DequeueAndSend()
        {
            // Make sure there is only one thread sending the events.
            lock (this.sendingLockObj)
            {
                try
                {
                    // We have to get a temporary reference to the buffer and call ToArray() after a new buffer is created.
                    // Otherwise, if we call ToArray() first and new events are added to the buffer, creating a new buffer will cause data lost.
                    var tmpBuffer = this.buffer;
                    this.buffer = new ConcurrentQueue<ITelemetry>();
                    var itemsToSend = tmpBuffer.ToArray();

                    if (itemsToSend.Length == 0)
                    {
                        return;
                    }

                    batchCount++;
                    itemCount += itemsToSend.Length;
                    Console.WriteLine($"Batch index: {batchCount}, total items: {itemCount}, items in batch: {itemsToSend.Length}");

                    this.SendItems(itemsToSend).Wait();
                }
                catch (Exception ex)
                {
                    Log($"Failed to send telemetry {ex}");
                }
            }
        }

        private async Task SendItems(ITelemetry[] itemsToSend)
        {
            var content = GetRequestContent(itemsToSend);
            var tokenSource = new CancellationTokenSource();
            var sendTask = client.PostAsync(this.endpointAddress, new StringContent(content, Encoding.UTF8, "application/json"), tokenSource.Token);
            var timeoutTask = Task.Delay(this.Timeout).ContinueWith(task =>
             {
                 if (!sendTask.IsCompleted)
                 {
                     tokenSource.Cancel();
                     Log("Telemetry sending task is cancelled due to timeout");
                 }
             });

            await Task.WhenAny(timeoutTask, sendTask).ConfigureAwait(false);

            if (sendTask.IsCompleted && !sendTask.Result.IsSuccessStatusCode)
            {
                Log($"Failed to send telemetry: {sendTask.Result.ReasonPhrase}");
            }
        }

        private string GetRequestContent(ITelemetry[]  itemsToSend)
        {
            string content = null;

            if (itemsToSend.Count() == 1)
            {
                var data = Microsoft.ApplicationInsights.Extensibility.Implementation.JsonSerializer.Serialize(itemsToSend, compress: false);
                content = Encoding.UTF8.GetString(data, 0, data.Length);
            }
            else
            {
                // We need some special handling if there are multiple items to be sent.
                // 1. The serialized items are line separated. We need to convert it into a json array so it can be consumed by the fluentd http input.
                // 2. We need to change the time format to be float, otherwise it will fail to parse the time and the event will be dropped. See this issue for more details https://github.com/fluent/fluentd/issues/2018
                var builder = new StringBuilder();
                builder.Append("[");

                for (int i = 0; i < itemsToSend.Length; i++)
                {
                    if (i != 0)
                    {
                        builder.Append(",");
                    }

                    var item = itemsToSend[i];
                    var data = Microsoft.ApplicationInsights.Extensibility.Implementation.JsonSerializer.Serialize(new[] { item }, compress: false);
                    var serialized = Encoding.UTF8.GetString(data, 0, data.Length);

                    // TODO: Remove the time format conversion part and the dependency on NewtonSoft once the fluentd issue is addressed.
                    var jobject = JsonConvert.DeserializeObject<JObject>(serialized);
                    var millisecond = 1.0 * (item.Timestamp.Ticks % TimeSpan.TicksPerSecond) / (TimeSpan.TicksPerMillisecond * 1000);
                    jobject["time"] = item.Timestamp.ToUnixTimeSeconds() + millisecond;

                    builder.Append(JsonConvert.SerializeObject(jobject));
                }

                builder.Append("]");
                content = builder.ToString();
            }

            return content;
        }

        private void Log(string message)
        {
            Console.WriteLine(message);
        }
    }
}
