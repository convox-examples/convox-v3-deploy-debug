const express = require("express");
const app = express();
const PORT = process.env.PORT || 3000;

app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok", service: "web" });
});

app.get("/", (req, res) => {
  res.json({ message: "Hello from the web service" });
});

app.listen(PORT, () => {
  console.log(`web service listening on port ${PORT}`);
});
