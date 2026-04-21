import cors from "cors";
import express from "express";

import { config } from "./config.js";
import { normalizeRunOutput } from "./normalize.js";
import { providers } from "./providers.js";

const app = express();

app.use(cors());

function parsePositiveInt(value) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  const parsed = Number.parseInt(String(value), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

function buildMediaFromQuery(query) {
  const type = query.type === "tv" ? "show" : query.type;
  const tmdbId = parsePositiveInt(query.tmdbId);
  const year = parsePositiveInt(query.year);
  const season = parsePositiveInt(query.season);
  const episode = parsePositiveInt(query.episode);
  const title = typeof query.title === "string" ? query.title.trim() : "";

  if (type !== "movie" && type !== "show") {
    return { error: "Query parameter 'type' must be 'movie' or 'show'." };
  }

  if (!tmdbId) {
    return { error: "Query parameter 'tmdbId' must be a positive integer." };
  }

  if (!title) {
    return { error: "Query parameter 'title' is required." };
  }

  if (type === "show" && ((season && !episode) || (!season && episode))) {
    return { error: "TV scraping requires both 'season' and 'episode' when either is provided." };
  }

  return {
    media: {
      type,
      tmdbId: String(tmdbId),
      title,
      ...(year ? { releaseYear: year } : {}),
      ...(season ? { season: String(season) } : {}),
      ...(episode ? { episode: String(episode) } : {}),
    },
  };
}

function parseSourceOrder(queryValue) {
  if (typeof queryValue !== "string" || !queryValue.trim()) {
    return undefined;
  }

  const parts = queryValue
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

  return parts.length > 0 ? parts : undefined;
}

function withTimeout(promise, timeoutMs) {
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error(`Scrape timed out after ${timeoutMs}ms`)), timeoutMs);
    }),
  ]);
}

async function runScrape(query) {
  const parsed = buildMediaFromQuery(query);
  if (parsed.error) {
    const error = new Error(parsed.error);
    error.statusCode = 400;
    throw error;
  }

  const sourceOrder = parseSourceOrder(query.sourceOrder);
  const output = await withTimeout(
    providers.runAll({
      media: parsed.media,
      ...(sourceOrder ? { sourceOrder } : {}),
    }),
    config.requestTimeoutMs,
  );

  if (!output) {
    return null;
  }

  const sourceMeta = providers.getMetadata(output.sourceId);
  const embedMeta = output.embedId ? providers.getMetadata(output.embedId) : null;
  return normalizeRunOutput(output, sourceMeta, embedMeta);
}

function writeSse(res, event, payload) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    service: "providers-api",
    target: "native",
    port: config.port,
    timeoutMs: config.requestTimeoutMs,
    simpleProxyUrl: config.simpleProxyUrl || null,
  });
});

app.get("/sources", (_req, res) => {
  res.json({
    sources: providers.listSources(),
    embeds: providers.listEmbeds(),
  });
});

app.get("/scrape", async (req, res) => {
  try {
    const result = await runScrape(req.query);
    if (!result) {
      res.status(404).json({
        ok: false,
        error: "No stream found.",
      });
      return;
    }

    res.json({
      ok: true,
      result,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      ok: false,
      error: error.message || "Unknown scrape failure.",
    });
  }
});

app.get("/scrape/stream", async (req, res) => {
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.flushHeaders();

  writeSse(res, "init", {
    sources: providers.listSources(),
  });

  try {
    const result = await runScrape(req.query);

    if (!result) {
      writeSse(res, "done", {
        ok: false,
        error: "No stream found.",
      });
      res.end();
      return;
    }

    writeSse(res, "done", {
      ok: true,
      result,
    });
    res.end();
  } catch (error) {
    writeSse(res, "error", {
      ok: false,
      error: error.message || "Unknown scrape failure.",
    });
    res.end();
  }
});

app.listen(config.port, () => {
  console.log(`providers-api listening on :${config.port}`);
});
