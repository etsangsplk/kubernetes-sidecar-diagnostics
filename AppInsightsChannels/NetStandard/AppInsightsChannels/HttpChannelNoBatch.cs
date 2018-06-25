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
    public class HttpChannelNoBatch : ITelemetryChannel
    {
        private HttpClient client;
        private Uri endpointAddress;

        public HttpChannelNoBatch(string endpointAddress)
        {
            this.client = new HttpClient();
            this.EndpointAddress = endpointAddress;
        }

        public bool? DeveloperMode { get; set; }

        public string EndpointAddress
        {
            get { return this.endpointAddress.ToString(); }
            set { this.endpointAddress = new Uri(value); }
        }

        public void Flush()
        {
        }

        public void Send(ITelemetry item)
        {
            var data = Microsoft.ApplicationInsights.Extensibility.Implementation.JsonSerializer.Serialize(new[] { item }, compress: false);
            var content = Encoding.UTF8.GetString(data, 0, data.Length);
            var response = client.PostAsync(this.endpointAddress, new StringContent(content, Encoding.UTF8, "application/json")).Result;

            if (!response.IsSuccessStatusCode)
            {
                Log($"Failed to send telemetry: {response.ReasonPhrase}");
            }
        }

        public void Dispose()
        {
        }

        private void Log(string message)
        {
            Console.WriteLine(message);
        }
    }
}
