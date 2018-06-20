using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace WebFrontEnd
{
    public class Program
    {
        public static void Main(string[] args)
        {
            //Task.Run(() =>
            //{
            //    HttpClient client = new HttpClient();
            //    while (true)
            //    {
            //        client.PostAsync("http://localhost:8887/sometag", new StringContent("{\"message\": \"tick from webfrontend\"}", Encoding.UTF8, "application/json"));
            //        System.Threading.Thread.Sleep(2000);
            //    }
            //});

            BuildWebHost(args).Run();
        }

        public static IWebHost BuildWebHost(string[] args) =>
            WebHost.CreateDefaultBuilder(args)
                .UseStartup<Startup>()
                .ConfigureLogging((hostingContext, logging) =>
                {
                    logging.AddConfiguration(hostingContext.Configuration.GetSection("Logging"));
                    //logging.AddHttp("http://localhost:8887");
                })
                .UseApplicationInsights()
                .Build();
    }
}
