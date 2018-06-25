The App Insights Http channel is intended to forward logs to fluentd http input plugin.  
The default channel support custom endpoint address. However, 1) the default channel will gzip the message which can't be understand by fluentd http input. 2) Because of this [bug](https://github.com/fluent/fluentd/issues/2018), events will be dropped if they are sent in batch.

You can change the default channel by just couple lines of changes.  
NOTE: you need to manage the life cycle of the Http channel on your own, for example, you want to dipose the channel so the telemetries are drained.

### .Asp Net Core
``` C#
public void Configure(IApplicationBuilder app, IHostingEnvironment env)
{
    ...

    var config = app.ApplicationServices.GetService<TelemetryConfiguration>();
    config.TelemetryChannel = new HttpChannel("http://localhost:8887/ApplicationInsightsHttpChannel");
}
```

### Console App
``` C#
using (var httpChannel = new HttpChannel("http://localhost:8887/AppInsightsHttpChannel"))
{
    var config = new TelemetryConfiguration();
    config.TelemetryChannel = httpChannel;
    // Dummy ikey so events are not dropped
    config.InstrumentationKey = "abc";

    var client = new TelemetryClient(config);
    client.TrackTrace("The time is " + DateTime.Now);
}
```