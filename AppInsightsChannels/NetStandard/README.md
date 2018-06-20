# TODO: Add doc of how to enable the Channels
# .Asp Net Core, console App

``` C#
public void Configure(IApplicationBuilder app, IHostingEnvironment env)
{
    ...

    var config = app.ApplicationServices.GetService<TelemetryConfiguration>();
    config.TelemetryChannel = new HttpChannel("http://localhost:8887/ApplicationInsightsHttpChannel");
}
```

NOTE: saying that custom channel needs to be disposed explicitly
``` C#
using (var httpChannel = new HttpChannel("http://localhost:8887/AppInsightsHttpChannel"))
{
    var config = new TelemetryConfiguration();
    config.TelemetryChannel = httpChannel;

    var client = new TelemetryClient(config);
    client.TrackTrace("The time is " + DateTime.Now);
}
```