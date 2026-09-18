import { after, before, beforeEach, describe, it } from "node:test"
import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import http from "node:http"
import { once } from "node:events"
import { fileURLToPath } from "node:url"

const SERVER = fileURLToPath(new URL("../server/index.js", import.meta.url))

let upstream
let upstreamUrl
let handler

before(async () => {
  upstream = http.createServer((req, res) => {
    let body = ""
    req.on("data", (chunk) => { body += chunk })
    req.on("end", () => handler(req, res, body))
  })
  upstream.listen(0, "127.0.0.1")
  await once(upstream, "listening")
  upstreamUrl = `http://127.0.0.1:${upstream.address().port}/admin/mcp`
})

after(() => upstream.close())

beforeEach(() => {
  handler = (_req, res) => {
    res.writeHead(200, { "Content-Type": "application/json" })
    res.end(JSON.stringify({ jsonrpc: "2.0", id: 1, result: {} }))
  }
})

// Drives the proxy the way Claude Desktop does: writes `chunks` to its stdin and
// resolves with the lines it wrote to stdout once it exits.
function run(chunks, env = {}) {
  const child = spawn(process.execPath, [SERVER], {
    env: {
      ...process.env,
      MCP_SERVER_URL: upstreamUrl,
      MCP_API_TOKEN: "test-token",
      ...env,
    },
    stdio: ["pipe", "pipe", "pipe"],
  })

  let stdout = ""
  let stderr = ""
  child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk })
  child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk })

  for (const chunk of chunks) child.stdin.write(chunk)
  child.stdin.end()

  return once(child, "close").then(([code]) => ({
    code,
    stderr,
    lines: stdout.split("\n").filter(Boolean).map(JSON.parse),
  }))
}

describe("stdio to HTTP proxy", () => {
  it("forwards the message and returns the upstream response", async () => {
    let received
    handler = (req, res, body) => {
      received = { headers: req.headers, method: req.method, url: req.url, body }
      res.writeHead(200, { "Content-Type": "application/json" })
      res.end(JSON.stringify({ jsonrpc: "2.0", id: 7, result: { ok: true } }))
    }

    const { lines } = await run(['{"jsonrpc":"2.0","id":7,"method":"tools/list"}\n'])

    assert.equal(received.method, "POST")
    assert.equal(received.url, "/admin/mcp")
    assert.equal(received.body, '{"jsonrpc":"2.0","id":7,"method":"tools/list"}')
    assert.deepEqual(lines, [{ jsonrpc: "2.0", id: 7, result: { ok: true } }])
  })

  it("injects the token into the standard Authorization header by default", async () => {
    let headers
    handler = (req, res, _body) => {
      headers = req.headers
      res.writeHead(200, { "Content-Type": "application/json" })
      res.end('{"jsonrpc":"2.0","id":1,"result":{}}')
    }

    await run(['{"jsonrpc":"2.0","id":1,"method":"ping"}\n'])

    assert.equal(headers.authorization, "Bearer test-token")
  })

  it("injects the token into a custom header when one is configured", async () => {
    let headers
    handler = (req, res, _body) => {
      headers = req.headers
      res.writeHead(200, { "Content-Type": "application/json" })
      res.end('{"jsonrpc":"2.0","id":1,"result":{}}')
    }

    await run(
      ['{"jsonrpc":"2.0","id":1,"method":"ping"}\n'],
      { MCP_AUTH_HEADER: "X-MCP-Authorization" },
    )

    assert.equal(headers["x-mcp-authorization"], "Bearer test-token")
    assert.equal(headers.authorization, undefined)
  })

  it("reassembles a message split across stdin chunks", async () => {
    handler = (req, res, body) => {
      res.writeHead(200, { "Content-Type": "application/json" })
      res.end(JSON.stringify({ jsonrpc: "2.0", id: JSON.parse(body).id, result: {} }))
    }

    const { lines } = await run(['{"jsonrpc":"2.0","id":', '7,"method":"ping"}', "\n"])

    assert.deepEqual(lines, [{ jsonrpc: "2.0", id: 7, result: {} }])
  })

  it("handles several messages arriving in a single chunk", async () => {
    handler = (req, res, body) => {
      res.writeHead(200, { "Content-Type": "application/json" })
      res.end(JSON.stringify({ jsonrpc: "2.0", id: JSON.parse(body).id, result: {} }))
    }

    const { lines } = await run([
      '{"jsonrpc":"2.0","id":1,"method":"ping"}\n{"jsonrpc":"2.0","id":2,"method":"ping"}\n',
    ])

    assert.deepEqual(lines.map((line) => line.id).sort(), [1, 2])
  })

  it("writes nothing when the server answers a notification with 204 No Content", async () => {
    handler = (_req, res) => res.writeHead(204).end()

    const { lines } = await run(['{"jsonrpc":"2.0","method":"notifications/initialized"}\n'])

    assert.deepEqual(lines, [])
  })

  it("returns a JSON-RPC error carrying the original id when the server rejects the token", async () => {
    handler = (_req, res) => {
      res.writeHead(401, { "Content-Type": "application/json" })
      res.end('{"jsonrpc":"2.0","id":null,"error":{"code":-32000,"message":"Unauthorized"}}')
    }

    const { lines } = await run(['{"jsonrpc":"2.0","id":9,"method":"tools/list"}\n'])

    assert.equal(lines.length, 1)
    assert.equal(lines[0].id, 9)
    assert.match(lines[0].error.message, /token/i)
  })

  it("returns a JSON-RPC error when the server is unreachable", async () => {
    const { lines } = await run(
      ['{"jsonrpc":"2.0","id":3,"method":"tools/list"}\n'],
      { MCP_SERVER_URL: "http://127.0.0.1:1/admin/mcp" },
    )

    assert.equal(lines.length, 1)
    assert.equal(lines[0].id, 3)
    assert.equal(lines[0].error.code, -32603)
  })

  it("returns a JSON-RPC error when the server returns a non-JSON body", async () => {
    handler = (_req, res) => {
      res.writeHead(502, { "Content-Type": "text/html" })
      res.end("<html>502 Bad Gateway</html>")
    }

    const { lines } = await run(['{"jsonrpc":"2.0","id":4,"method":"tools/list"}\n'])

    assert.equal(lines[0].id, 4)
    assert.match(lines[0].error.message, /502/)
  })

  it("logs to stderr rather than answering a failed notification, which has no id to answer", async () => {
    const { lines, stderr } = await run(
      ['{"jsonrpc":"2.0","method":"notifications/initialized"}\n'],
      { MCP_SERVER_URL: "http://127.0.0.1:1/admin/mcp" },
    )

    assert.deepEqual(lines, [])
    assert.match(stderr, /\[activeadmin_mcp\] Could not reach/)
  })

  it("reports a parse error without contacting the server", async () => {
    let called = false
    handler = (_req, res) => {
      called = true
      res.writeHead(204).end()
    }

    const { lines } = await run(["not json\n"])

    assert.equal(called, false)
    assert.equal(lines[0].error.code, -32700)
    assert.equal(lines[0].id, null)
  })

  it("exits with an explanation when the server URL is missing", async () => {
    const { code, stderr } = await run([], { MCP_SERVER_URL: "" })

    assert.equal(code, 1)
    assert.match(stderr, /MCP_SERVER_URL/)
  })

  it("exits with an explanation when the token is missing", async () => {
    const { code, stderr } = await run([], { MCP_API_TOKEN: "" })

    assert.equal(code, 1)
    assert.match(stderr, /MCP_API_TOKEN/)
  })
})
