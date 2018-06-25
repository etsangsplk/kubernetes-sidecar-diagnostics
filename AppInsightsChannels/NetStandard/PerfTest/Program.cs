using Microsoft.ApplicationInsights;
using Microsoft.ApplicationInsights.Channel;
using Microsoft.ApplicationInsights.Extensibility;
using System;
using System.Threading;

namespace PerfTest
{
    class Program
    {
        static void Main(string[] args)
        {
            var events = 40000;
            var message = new String('a', 1000);
            var startTime = DateTime.Now;

            using (var httpChannel = new HttpChannelDataFlow("http://localhost.:8887/AppInsightsHttpChannel"))
            {
                var config = new TelemetryConfiguration();
                config.TelemetryChannel = httpChannel;

                // NOTE: Add a random instrumentation key otherwise the event will be ignored. This is only needed for AI v2.4 or lower.
                //config.InstrumentationKey = "abc"

                var client = new TelemetryClient(config);

                for (int i = 0; i < events; i++)
                {
                    client.TrackTrace(message);
                }
                client.Flush();
            }

            Console.WriteLine("Finished");
            var endTime = DateTime.Now;
            var duration = (endTime - startTime).TotalMilliseconds;
            var rate = (int)(1000.0 * events / duration);

            Console.WriteLine($"Time elapsed {duration} ms");
            Console.WriteLine($"Sending rate is {rate}");

            Console.ReadLine();
        }
    }
}
