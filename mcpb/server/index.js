#!/usr/bin/env node

// Bridges Claude Desktop's stdio transport to an activeadmin_mcp server's HTTP
// endpoint, injecting the API token on the way through.
//
// Every message is forwarded verbatim, so this proxy needs no knowledge of the
// MCP protocol and gains no new capabilities when the server does.
//
// stdout carries the protocol. Diagnostics go to stderr, never stdout.

const SERVER_URL = process.env.MCP_SERVER_URL
const API_TOKEN = process.env.MCP_API_TOKEN
const AUTH_HEADER = process.env.MCP_AUTH_HEADER || "Authorization"

const REQUEST_TIMEOUT_MS = 120_000

const PARSE_ERROR = -32_700
const INTERNAL_ERROR = -32_603

function fail(message) {
  log(message)
  process.exit(1)
}

function log(message) {
  process.stderr.write(`[activeadmin_mcp] ${message}\n`)
}

if (!SERVER_URL) fail("MCP_SERVER_URL is not set — check the extension's Server URL setting.")
if (!API_TOKEN) fail("MCP_API_TOKEN is not set — check the extension's API token setting.")

function write(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`)
}

// JSON-RPC forbids replying to a notification, which has no id to reply to.
function writeError(id, code, message) {
  if (id === undefined || id === null) {
    log(message)
    return
  }
  write({ jsonrpc: "2.0", id, error: { code, message } })
}

function describeFailure(status, body) {
  if (status === 401 || status === 403) {
    return `The server rejected the API token (HTTP ${status}). Generate a new token in the admin panel and update the extension's settings.`
  }
  return `The server returned HTTP ${status}: ${body.slice(0, 500) || "(empty response)"}`
}

async function forward(line) {
  let id
  try {
    id = JSON.parse(line).id
  } catch (error) {
    write({ jsonrpc: "2.0", id: null, error: { code: PARSE_ERROR, message: error.message } })
    return
  }

  let response
  try {
    response = await fetch(SERVER_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "User-Agent": "activeadmin_mcp-mcpb",
        [AUTH_HEADER]: `Bearer ${API_TOKEN}`,
      },
      body: line,
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    })
  } catch (error) {
    writeError(id, INTERNAL_ERROR, `Could not reach ${SERVER_URL}: ${error.message}`)
    return
  }

  const body = await response.text()

  if (!response.ok) {
    writeError(id, INTERNAL_ERROR, describeFailure(response.status, body))
    return
  }

  // The server answers notifications with 204 No Content; there is nothing to relay.
  if (!body.trim()) return

  process.stdout.write(body.endsWith("\n") ? body : `${body}\n`)
}

let buffer = ""

process.stdin.setEncoding("utf8")

process.stdin.on("data", (chunk) => {
  buffer += chunk

  let newline
  while ((newline = buffer.indexOf("\n")) !== -1) {
    const line = buffer.slice(0, newline).trim()
    buffer = buffer.slice(newline + 1)
    if (line) forward(line)
  }
})

process.stdin.on("end", () => {
  const line = buffer.trim()
  if (line) forward(line)
})

process.stdout.on("error", (error) => {
  if (error.code === "EPIPE") process.exit(0)
  throw error
})
