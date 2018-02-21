using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Microsoft.Extensions.Logging
{
    public class HttpLoggerProvider : ILoggerProvider
    {
        private readonly string endpoint;
        private HttpLogger logger;

        public HttpLoggerProvider(string endpoint)
        {
            this.endpoint = endpoint;
        }

        public ILogger CreateLogger(string categoryName)
        {
            // append category name as tag
            categoryName = categoryName ?? "HttpLoggerProvider";
            var requestUri = new Uri(new Uri(this.endpoint), categoryName);
            this.logger = new HttpLogger(requestUri);

            return this.logger;
        }

        public void Dispose()
        {
            this.logger.Dispose();
        }
    }
}
