function pickBestFile(qualities = {}) {
  const preferredOrder = ["4k", "1080", "720", "480", "360", "unknown"];

  for (const quality of preferredOrder) {
    const file = qualities[quality];
    if (file?.url) {
      return { quality, file };
    }
  }

  const firstEntry = Object.entries(qualities).find(([, file]) => file?.url);
  if (!firstEntry) {
    return null;
  }

  const [quality, file] = firstEntry;
  return { quality, file };
}

function buildPlaybackInfo(stream) {
  if (!stream) {
    return { playbackUrl: null, playbackType: null, selectedQuality: null };
  }

  if (stream.type === "hls") {
    return {
      playbackUrl: stream.playlist ?? null,
      playbackType: "hls",
      selectedQuality: null,
    };
  }

  if (stream.type === "file") {
    const bestFile = pickBestFile(stream.qualities);
    return {
      playbackUrl: bestFile?.file?.url ?? null,
      playbackType: bestFile?.file?.type ?? "file",
      selectedQuality: bestFile?.quality ?? null,
    };
  }

  return { playbackUrl: null, playbackType: stream.type ?? null, selectedQuality: null };
}

export function normalizeStream(stream) {
  return {
    id: stream?.id ?? null,
    type: stream?.type ?? null,
    playlist: stream?.playlist ?? null,
    qualities: stream?.qualities ?? null,
    headers: stream?.headers ?? {},
    preferredHeaders: stream?.preferredHeaders ?? {},
    captions: stream?.captions ?? [],
    flags: stream?.flags ?? [],
    ...buildPlaybackInfo(stream),
  };
}

export function normalizeRunOutput(output, sourceMeta, embedMeta) {
  return {
    sourceId: output.sourceId,
    sourceName: sourceMeta?.name ?? output.sourceId,
    embedId: output.embedId ?? null,
    embedName: embedMeta?.name ?? output.embedId ?? null,
    stream: normalizeStream(output.stream),
  };
}
