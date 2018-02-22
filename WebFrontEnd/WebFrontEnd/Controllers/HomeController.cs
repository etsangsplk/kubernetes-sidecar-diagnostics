using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.ApplicationInsights;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using WebFrontEnd.Models;

namespace WebFrontEnd.Controllers
{
    public class HomeController : Controller
    {
        private readonly TelemetryClient client;
        private readonly ILogger logger;

        public HomeController(TelemetryClient client, ILogger<HomeController> logger, Microsoft.Extensions.Options.IOptions<Microsoft.ApplicationInsights.AspNetCore.Extensions.ApplicationInsightsServiceOptions> options)
        {
            this.client = client;
            this.logger = logger;
        }

        public IActionResult Index(TelemetryClient client)
        {
            this.client.TrackTrace("I'm a trace in Index()...");

            return View();
        }

        public IActionResult About()
        {
            this.logger.LogWarning("I'm ILogger message in About()...");

            ViewData["Message"] = "Your application description page.";

            return View();
        }

        public IActionResult Contact()
        {
            ViewData["Message"] = "Your contact page.";

            return View();
        }

        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }
    }
}
