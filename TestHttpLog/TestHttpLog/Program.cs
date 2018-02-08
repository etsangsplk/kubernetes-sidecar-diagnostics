using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;

namespace TestHttpLog
{
    class Program
    {
        static void Main(string[] args)
        {
            var endpoint = "http://localhost:8887";
            var count = 0;
            using (var client = new HttpClient())
            {
                while (true)
                {
                    var dict = new Dictionary<string, object>();
                    dict["count"] = count++;
                    dict["stringValue"] = "message" + count;
                    dict["boolValue"] = (new Random()).Next() % 2 == 0 ? true : false;
                    var content = JsonConvert.SerializeObject(dict, Formatting.Indented);

                    client.PostAsync(endpoint + "/sometag", new StringContent(content, Encoding.UTF8, "application/json"));
                    Console.WriteLine("Console Message: " + content);

                    System.Threading.Thread.Sleep(1000);
                }
            }
        }
    }
}
