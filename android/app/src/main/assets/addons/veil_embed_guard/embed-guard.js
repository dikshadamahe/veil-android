(function () {
  if (window.__veilEmbedGuard) return;
  window.__veilEmbedGuard = true;

  try {
    window.open = function () { return null; };
  } catch (_) {}

  function strip(frame) {
    try {
      if (!frame || frame.tagName !== "IFRAME" ||
          !frame.hasAttribute("sandbox")) return;
      frame.removeAttribute("sandbox");
      const src = frame.getAttribute("src");
      if (src) frame.setAttribute("src", src);
    } catch (_) {}
  }

  const nativeSetAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function (name, value) {
    if (this && this.tagName === "IFRAME" &&
        String(name).toLowerCase() === "sandbox") return;
    return nativeSetAttribute.call(this, name, value);
  };

  function sweep(root) {
    try {
      const frames = (root || document).querySelectorAll("iframe[sandbox]");
      for (const frame of frames) strip(frame);
    } catch (_) {}
  }

  const observer = new MutationObserver(function (mutations) {
    for (const mutation of mutations) {
      if (mutation.type === "attributes" &&
          mutation.attributeName === "sandbox") {
        strip(mutation.target);
        continue;
      }
      for (const node of mutation.addedNodes) {
        if (node && node.nodeType === 1) {
          if (node.tagName === "IFRAME") strip(node);
          if (node.querySelectorAll) sweep(node);
        }
      }
    }
  });

  function start() {
    sweep(document);
    observer.observe(document.documentElement || document, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["sandbox"]
    });
  }

  if (document.documentElement) start();
  else document.addEventListener("readystatechange", start, { once: true });
})();
