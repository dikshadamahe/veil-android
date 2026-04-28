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

function parseNonEmptyString(value) {
  if (value === undefined || value === null) {
    return undefined;
  }
  const text = String(value).trim();
  return text.length > 0 ? text : undefined;
}

function normalizeImdbId(value) {
  const raw = parseNonEmptyString(value);
  if (!raw) {
    return undefined;
  }
  return raw.startsWith("tt") ? raw : `tt${raw.replace(/^tt/i, "")}`;
}

/**
 * @p-stream/providers expects ShowMedia: nested season/episode with numeric
 * `number` fields. Flat query strings used to break all TV scrapers.
 */
function buildMediaFromQuery(query) {
  const type = query.type === "tv" ? "show" : query.type;
  const tmdbId = parsePositiveInt(query.tmdbId);
  const year = parsePositiveInt(query.year);
  const season = parsePositiveInt(query.season);
  const episode = parsePositiveInt(query.episode);
  const title = typeof query.title === "string" ? query.title.trim() : "";
  const imdbId = normalizeImdbId(query.imdbId);

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

  if (type === "movie") {
    return {
      media: {
        type: "movie",
        tmdbId: String(tmdbId),
        title,
        ...(year ? { releaseYear: year } : {}),
        ...(imdbId ? { imdbId } : {}),
      },
    };
  }

  if (season && episode) {
    const seasonTmdbId =
      parseNonEmptyString(query.seasonTmdbId) || `${tmdbId}-s${season}`;
    const episodeTmdbId =
      parseNonEmptyString(query.episodeTmdbId) ||
      `${tmdbId}-s${season}-e${episode}`;
    const seasonTitle =
      parseNonEmptyString(query.seasonTitle) || `Season ${season}`;

    return {
      media: {
        type: "show",
        tmdbId: String(tmdbId),
        title,
        ...(year ? { releaseYear: year } : {}),
        ...(imdbId ? { imdbId } : {}),
        season: {
          number: season,
          tmdbId: seasonTmdbId,
          title: seasonTitle,
        },
        episode: {
          number: episode,
          tmdbId: episodeTmdbId,
        },
      },
    };
  }

  return {
    media: {
      type: "show",
      tmdbId: String(tmdbId),
      title,
      ...(year ? { releaseYear: year } : {}),
      ...(imdbId ? { imdbId } : {}),
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

function sortEmbedsForSelection(embeds, targetEmbedId) {
  return [...embeds].sort((a, b) => {
    const aScore = a.embedId === targetEmbedId ? 0 : 1;
    const bScore = b.embedId === targetEmbedId ? 0 : 1;
    return aScore - bScore;
  });
}

async function runEmbedFromSource({ media, sourceId, embedId }) {
  const sourceMeta = providers.getMetadata(sourceId);
  const embedMeta = providers.getMetadata(embedId);

  const sourceOutput = await providers.runSourceScraper({
    media,
    id: sourceId,
  });

  const matchingEmbeds = sortEmbedsForSelection(
    (sourceOutput.embeds || []).filter((entry) => entry.embedId === embedId),
    embedId,
  );

  for (const match of matchingEmbeds) {
    try {
      const embedOutput = await providers.runEmbedScraper({
        url: match.url,
        id: embedId,
      });

      if (embedOutput?.stream?.[0]) {
        return normalizeRunOutput(
          {
            sourceId,
            embedId,
            stream: embedOutput.stream[0],
          },
          sourceMeta,
          embedMeta,
        );
      }
    } catch (_) {
      // Try the next matching URL if a source exposes the same embed type more than once.
    }
  }

  return null;
}

async function runExplicitSelection(query, media) {
  const selectedId = parseNonEmptyString(query.selectedId);
  const selectedType = parseNonEmptyString(query.selectedType);

  if (!selectedId || !selectedType) {
    return null;
  }

  if (selectedType === "source") {
    const sourceMeta = providers.getMetadata(selectedId);
    const output = await providers.runSourceScraper({
      media,
      id: selectedId,
    });

    if (output?.stream?.[0]) {
      return normalizeRunOutput(
        {
          sourceId: selectedId,
          stream: output.stream[0],
        },
        sourceMeta,
        null,
      );
    }

    const sourceEmbeds = output?.embeds || [];
    if (sourceEmbeds.length === 0) {
      return null;
    }

    const embedOrder = parseSourceOrder(query.embedOrder);
    const preferredEmbedIds =
      embedOrder && embedOrder.length > 0
        ? embedOrder
        : [...new Set(sourceEmbeds.map((entry) => entry.embedId))];

    for (const embedId of preferredEmbedIds) {
      const result = await runEmbedFromSource({
        media,
        sourceId: selectedId,
        embedId,
      });
      if (result) {
        return result;
      }
    }

    return null;
  }

  if (selectedType === "embed") {
    const parentSourceId = parseNonEmptyString(query.parentSourceId);
    if (!parentSourceId) {
      return null;
    }
    return runEmbedFromSource({
      media,
      sourceId: parentSourceId,
      embedId: selectedId,
    });
  }

  return null;
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

  const explicitSelection = await runExplicitSelection(query, parsed.media);
  if (explicitSelection) {
    return explicitSelection;
  }

  const sourceOrder = parseSourceOrder(query.sourceOrder);
  const embedOrder = parseSourceOrder(query.embedOrder);
  const output = await withTimeout(
    providers.runAll({
      media: parsed.media,
      ...(sourceOrder ? { sourceOrder } : {}),
      ...(embedOrder ? { embedOrder } : {}),
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
  // Tell intermediaries (nginx / CDN / Express compression) not to buffer
  // the SSE response. Without this, `init` can sit in a buffer until the
  // long `runScrape` call completes — clients see a stuck "Loading source
  // catalog" screen for the full request timeout.
  res.setHeader("X-Accel-Buffering", "no");
  res.flushHeaders();

  // Disable Nagle so each `res.write` chunk lands on the wire immediately.
  if (res.socket && typeof res.socket.setNoDelay === "function") {
    res.socket.setNoDelay(true);
  }

  writeSse(res, "init", {
    sources: providers.listSources(),
  });
  if (typeof res.flush === "function") {
    res.flush();
  }

  // Periodic SSE keepalive comments while the long-running scrape executes.
  // Comment lines (":") are ignored by EventSource clients but force the
  // socket to flush, defeating any remaining intermediate buffers.
  const keepAlive = setInterval(() => {
    if (!res.writableEnded) {
      res.write(": ping\n\n");
    }
  }, 15000);
  res.on("close", () => clearInterval(keepAlive));
  res.on("finish", () => clearInterval(keepAlive));

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
