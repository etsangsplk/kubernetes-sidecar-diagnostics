using Microsoft.ApplicationInsights.Channel;
using Microsoft.ApplicationInsights.DataContracts;
using Microsoft.ApplicationInsights.Extensibility.Implementation;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;

namespace WebFrontEnd
{
    public class FluentdHttpChannel : ITelemetryChannel
    {
        private HttpClient client;
        private Uri requestUri;

        public FluentdHttpChannel(string endpoint = "http://localhost:8887")
        {
            this.client = new HttpClient();
            this.EndpointAddress = endpoint;

            // append channel name as tag
            this.requestUri = new Uri(new Uri(this.EndpointAddress), "ApplicationInsightsHttpChannel");
        }

        public bool? DeveloperMode { get; set; }
        public string EndpointAddress { get; set; }

        public void Dispose()
        {
            this.client.Dispose();
        }

        public void Flush()
        {
        }

        public void Send(ITelemetry item)
        {
            var buffer = JsonSerializer.Serialize(new []{ item }, compress: false);
            var content = Encoding.UTF8.GetString(buffer, 0, buffer.Length);

            client.PostAsync(this.requestUri, new StringContent(content, Encoding.UTF8, "application/json"));
        }
    }
}
