using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Threading.Tasks.Dataflow;

namespace Microsoft.ApplicationInsights.Channel
{
    public class HttpChannelDataFlow : ITelemetryChannel
    {
        // TODO: Remove after testing
        private static int batchCount = 0;
        private static int itemCount = 0;

        private HttpClient client;
        private Uri endpointAddress;
        private bool? developerMode = false;
        private int capacity_backup;
        private bool disposed = false;

        private IDataflowBlock pipelineHead;
        private BufferBlock<ITelemetry> inputBlock;
        private BatchBlock<ITelemetry> batchBlock;
        private ActionBlock<ITelemetry[]> outputBlock;
        private CancellationTokenSource cancellationTokenSource = new CancellationTokenSource();
        private Timer batcherTimer;

        public HttpChannelDataFlow(string endpointAddress)
        {
            this.client = new HttpClient();
            this.EndpointAddress = endpointAddress;

            CreatePipeline();
        }

        // TODO: Change the pipeline options on the fly is not supported
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

        /// <summary>
        /// Max number of concurrent threads sending data
        /// </summary>
        public int MaxConcurrency { get; set; } = 8;

        public void Flush()
        {
            this.batchBlock.TriggerBatch();
        }

        public void Send(ITelemetry item)
        {
            if (!inputBlock.Post(item))
            {
                Log("Failed to add item to input buffer block");
            }
        }

        public void Dispose()
        {
            if (this.disposed)
            {
                return;
            }
            this.disposed = true;

            this.pipelineHead.Complete();
            Task.WaitAny(this.outputBlock.Completion, Task.Delay(Timeout));

            if (!this.outputBlock.Completion.IsCompleted)
            {
                this.cancellationTokenSource.Cancel();
                Log($"Channel dipose timed out.");
            }

            this.batcherTimer.Dispose();
            this.client.Dispose();
        }

        private void CreatePipeline()
        {
            var propagateCompletion = new DataflowLinkOptions() { PropagateCompletion = true };
            this.inputBlock = new BufferBlock<ITelemetry>(
                new DataflowBlockOptions()
                {
                    BoundedCapacity = MaxBufferSize,
                    CancellationToken = this.cancellationTokenSource.Token
                });
            this.pipelineHead = this.inputBlock;

            this.batchBlock = new BatchBlock<ITelemetry>(
                Capacity,
                new GroupingDataflowBlockOptions()
                {
                    BoundedCapacity = MaxBufferSize,
                    CancellationToken = this.cancellationTokenSource.Token,
                    Greedy = true
                }
            );
            this.inputBlock.LinkTo(this.batchBlock, propagateCompletion);

            this.outputBlock = new ActionBlock<ITelemetry[]>(this.SendDataAsync,
                new ExecutionDataflowBlockOptions
                {
                    BoundedCapacity = MaxBufferSize,
                    MaxDegreeOfParallelism = MaxConcurrency,
                    SingleProducerConstrained = false,
                    CancellationToken = this.cancellationTokenSource.Token,
                });
            this.batchBlock.LinkTo(this.outputBlock, propagateCompletion);

            this.batcherTimer = new Timer(
                (unused) => { try { this.batchBlock.TriggerBatch(); } catch { } },
                state: null,
                dueTime: TimeSpan.FromSeconds(SendInterval),
                period: TimeSpan.FromSeconds(SendInterval));
        }

        private async Task SendDataAsync(ITelemetry[] telemetries)
        {
            this.batcherTimer.Change(TimeSpan.FromSeconds(SendInterval), TimeSpan.FromSeconds(SendInterval));

            if (telemetries.Length == 0)
            {
                return;
            }

            batchCount++;
            itemCount += telemetries.Length;
            Console.WriteLine($"Batch index: {batchCount}, total items: {itemCount}, items in batch: {telemetries.Length}");

            var content = GetRequestContent(telemetries);
            await client.PostAsync(this.endpointAddress, new StringContent(content, Encoding.UTF8, "application/json"));
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
