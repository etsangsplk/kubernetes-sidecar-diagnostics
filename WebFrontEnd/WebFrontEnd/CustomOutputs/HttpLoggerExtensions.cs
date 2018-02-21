using Microsoft.Extensions.DependencyInjection;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Microsoft.Extensions.Logging
{
    public static class HttpLoggerExtensions
    {
        public static ILoggingBuilder AddHttp(this ILoggingBuilder builder, string endpoint = "http://localhost:8887")
        {
            ServiceCollectionServiceExtensions.AddSingleton<ILoggerProvider, HttpLoggerProvider>(builder.Services,
                provider =>
                {
                    return new HttpLoggerProvider(endpoint);
                });
            return builder;
        }

        public static ILoggerFactory AddHttp(this ILoggerFactory factory, string endpoint = "http://localhost:8887")
        {
            factory.AddProvider(new HttpLoggerProvider(endpoint));
            return factory;
        }
    }
}
