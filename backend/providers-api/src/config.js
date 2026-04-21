function trimTrailingSlash(value) {
  return value ? value.replace(/\/+$/, "") : "";
}

export const config = {
  port: Number(process.env.PORT || 3001),
  requestTimeoutMs: Number(process.env.REQUEST_TIMEOUT_MS || 90000),
  simpleProxyUrl: trimTrailingSlash(process.env.SIMPLE_PROXY_URL || ""),
};
