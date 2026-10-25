const os = require("os");
const express = require("express");
const mysql = require("mysql2/promise");
const { SecretsManagerClient, GetSecretValueCommand } = require("@aws-sdk/client-secrets-manager");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");

const region = process.env.AWS_REGION || "ap-south-1";
const VERSION = process.env.APP_VERSION || "local";
const COLOR = process.env.APP_COLOR || "local";
const app = express();
app.use(express.json());
let writer; // primary: all writes
let reader; // read replica: read-only queries

// Forwards errors from async routes to the error handler instead of crashing
const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// On AWS: credentials come from Secrets Manager (DB_SECRET_ARN is set by Terraform).
// Locally: falls back to plain DB_* env vars (see docker-compose.yml).
async function getDbConfigs() {
  if (process.env.DB_SECRET_ARN) {
    const sm = new SecretsManagerClient({ region });
    const res = await sm.send(new GetSecretValueCommand({ SecretId: process.env.DB_SECRET_ARN }));
    const s = JSON.parse(res.SecretString);
    const base = {
      port: 3306, user: s.username, password: s.password, database: s.dbname,
      ssl: { rejectUnauthorized: false }, connectionLimit: 5,
    };
    return { writer: { ...base, host: s.host }, reader: { ...base, host: s.reader_host || s.host } };
  }
  const base = {
    host: process.env.DB_HOST || "127.0.0.1",
    port: Number(process.env.DB_PORT) || 3307, // docker-compose maps MySQL to 3307
    user: process.env.DB_USER || "root",
    password: process.env.DB_PASSWORD || "localpass",
    database: process.env.DB_NAME || "appdb",
    connectionLimit: 5,
  };
  return { writer: base, reader: { ...base, host: process.env.DB_READ_HOST || base.host } };
}

async function initDb() {
  const cfg = await getDbConfigs();
  writer = mysql.createPool(cfg.writer);
  reader = mysql.createPool(cfg.reader);
  await writer.query(
    "CREATE TABLE IF NOT EXISTS notes (id INT AUTO_INCREMENT PRIMARY KEY, text VARCHAR(255) NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"
  );
}

// Liveness check used by the ALB target groups
app.get("/health", (_req, res) => res.json({ status: "ok", host: os.hostname() }));

// Deep check: writer AND reader must answer (used by the deployment smoke test)
app.get("/health/db", async (_req, res) => {
  try {
    await writer.query("SELECT 1");
    await reader.query("SELECT 1");
    res.json({ status: "ok", db: "connected", writer: "ok", reader: "ok" });
  } catch (e) {
    res.status(503).json({ status: "error", db: e.message });
  }
});

// Shows which DB host each pool talks to. On AWS the reader reports read_only = 1.
app.get("/db/status", wrap(async (_req, res) => {
  const q = "SELECT @@hostname AS host, @@read_only AS read_only";
  const [[w]] = await writer.query(q);
  const [[r]] = await reader.query(q);
  res.json({ writer: w, reader: r });
}));

// Which release / colour served the request (proves blue/green traffic switching)
app.get("/version", (_req, res) => res.json({ version: VERSION, color: COLOR, host: os.hostname() }));

app.get("/", (_req, res) =>
  res.send(`<!doctype html><html><body style="font-family:sans-serif;padding:2rem">
<h1>DevOps Task App</h1>
<p>Environment: <b style="color:${COLOR === "green" ? "green" : COLOR === "blue" ? "royalblue" : "gray"}">${COLOR.toUpperCase()}</b></p>
<p>Release: <code>${VERSION}</code></p>
<p>Served by: ${os.hostname()}</p>
<p><a href="/api/notes">/api/notes</a> | <a href="/db/status">/db/status</a> | <a href="/health/db">/health/db</a> | <a href="/version">/version</a></p>
</body></html>`)
);

// READ -> replica (may lag the primary by a moment)
app.get("/api/notes", wrap(async (_req, res) => {
  const [rows] = await reader.query("SELECT * FROM notes ORDER BY id DESC LIMIT 50");
  res.set("X-Served-From", "reader").json(rows);
}));

// WRITE -> primary
app.post("/api/notes", wrap(async (req, res) => {
  const text = (req.body.text || "").toString().slice(0, 255);
  if (!text) return res.status(400).json({ error: "text required" });
  const [r] = await writer.query("INSERT INTO notes (text) VALUES (?)", [text]);
  res.status(201).set("X-Served-From", "writer").json({ id: r.insertId, text });
}));

// Writes a small object to the application S3 bucket (proves IAM role -> S3 access)
app.post("/api/upload", wrap(async (req, res) => {
  if (!process.env.APP_BUCKET) {
    return res.status(501).json({ error: "APP_BUCKET not set (S3 disabled locally)" });
  }
  const key = `uploads/${Date.now()}.txt`;
  await new S3Client({ region }).send(
    new PutObjectCommand({
      Bucket: process.env.APP_BUCKET, Key: key,
      Body: JSON.stringify(req.body || {}), ServerSideEncryption: "AES256",
    })
  );
  res.status(201).json({ key });
}));

// Central error handler (must come after all routes)
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: "internal error" });
});

initDb()
  .then(() => {
    const server = app.listen(process.env.PORT || 3000, () => console.log("listening"));
    process.on("SIGTERM", () => {
      console.log("SIGTERM received, shutting down");
      server.close(async () => { await writer.end(); await reader.end(); process.exit(0); });
    });
  })
  .catch((e) => {
    console.error("startup failed", e);
    process.exit(1);
  });
