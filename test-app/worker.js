const express = require("express");
const app = express();
const PORT = process.env.PORT || 4000;

// Simulate a service that crashes on startup after a few seconds.
// This mimics a common deploy failure: the process starts, logs some output,
// then dies before the health check passes.

console.log("worker service starting up...");
console.log("worker: connecting to database...");
console.log("worker: running migrations...");

setTimeout(() => {
  console.error("worker: FATAL - failed to connect to database at DB_HOST:5432");
  console.error("worker: error: connection refused (ECONNREFUSED)");
  console.error("worker: shutting down");
  process.exit(1);
}, 3000);

// Health check endpoint -- will never respond 200 because the process exits first
app.get("/health", (req, res) => {
  res.status(503).json({ status: "unhealthy", reason: "database not connected" });
});

app.get("/", (req, res) => {
  res.status(503).json({ error: "service unavailable" });
});

app.listen(PORT, () => {
  console.log(`worker service listening on port ${PORT} (will crash shortly)`);
});
