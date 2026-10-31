// Offline protocol fixture: no network, credentials, browser or configuration writes.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Text;
using System.Web.Script.Serialization;

class FakeAppServer {
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    static int Turns;
    static void Send(object value) {
        Console.WriteLine(Json.Serialize(value));
        Console.Out.Flush();
    }
    static void Main(string[] args) {
        Console.InputEncoding = Encoding.UTF8;
        Console.OutputEncoding = new UTF8Encoding(false);
        string line;
        while ((line = Console.ReadLine()) != null) {
            var request = Json.Deserialize<Dictionary<string, object>>(line);
            if (!request.ContainsKey("id")) continue;
            object id = request["id"];
            string method = (string)request["method"];
            var p = request.ContainsKey("params") ? (Dictionary<string, object>)request["params"] : new Dictionary<string, object>();
            object result = new {};
            string error = null;
            switch (method) {
                case "initialize": result = new { userAgent = "Lucky offline fixture" }; break;
                case "account/read": result = new { account = new { type = "chatgpt", planType = "fixture" } }; break;
                case "model/list":
                    result = new { data = new object[] {
                        new { id = "fixture-fast", model = "fixture-fast", displayName = "Fixture Fast", supportedReasoningEfforts = new[] { new { reasoningEffort = "medium" } }, serviceTiers = new[] { new { id = "priority", name = "Fast" } } },
                        new { id = "fixture-standard", model = "fixture-standard", displayName = "Fixture Standard", supportedReasoningEfforts = new[] { new { reasoningEffort = "low" } }, serviceTiers = new object[0] }
                    }, nextCursor = (string)null };
                    break;
                case "mcpServerStatus/list": result = new { data = new[] { new { name = "fixture-mcp", authStatus = "notLoggedIn" } }, nextCursor = (string)null }; break;
                case "thread/start": result = new { thread = new { id = "fixture-thread" } }; break;
                case "turn/start":
                    Turns++;
                    if (!p.ContainsKey("serviceTier") || (Turns == 1 && (string)p["serviceTier"] != "priority") || (Turns == 2 && p["serviceTier"] != null)) error = "Incorrect Fast on/off mapping";
                    if (((Dictionary<string, object>)p["sandboxPolicy"])["type"].ToString() != "readOnly") error = "Read-only policy missing";
                    if (Turns == 1 && ((IList)p["input"]).Count != 2) error = "Text attachment missing";
                    result = new { turn = new { id = "fixture-turn-" + Turns } };
                    break;
                case "config/value/write":
                    if ((string)p["keyPath"] != "mcp_servers.fixture" || (string)p["mergeStrategy"] != "upsert" || (string)((Dictionary<string, object>)p["value"])["url"] != "https://mcp.example.test/mcp") error = "Incorrect MCP configuration payload";
                    break;
                case "config/mcpServer/reload": break;
                case "turn/interrupt": break;
                default: error = "Unknown fixture method: " + method; break;
            }
            if (error != null) {
                Send(new { id = id, error = new { code = -32602, message = error } });
                continue;
            }
            Send(new { id = id, result = result });
            if (method == "turn/start") {
                string turn = "fixture-turn-" + Turns;
                string item = "fixture-message-" + Turns;
                Send(new { method = "item/agentMessage/delta", @params = new { threadId = "fixture-thread", turnId = turn, itemId = item, delta = "Hello Lucky \u2605" } });
                Send(new { method = "item/completed", @params = new { threadId = "fixture-thread", turnId = turn, item = new { type = "agentMessage", id = item, text = "Hello Lucky \u2605" } } });
                Send(new { method = "turn/completed", @params = new { threadId = "fixture-thread", turn = new { id = turn, status = "completed" } } });
            }
        }
    }
}
