defineProvider({
  id: "openrouter",
  name: "OpenRouter",
  endpoints: ["https://openrouter.ai"],
  auth: { type: "bearer", secret: "OPENROUTER_API_KEY" },
  settings: [{
    key: "OPENROUTER_API_KEY",
    title: "API key",
    subtitle: "OpenRouter API key used for credits and key quota.",
    type: "secure",
  }],

  async fetchUsage(ctx) {
    const creditsResponse = await ctx.http.getJSON("https://openrouter.ai/api/v1/credits", {
      headers: { "X-Title": "CodexBar" },
    });
    if (creditsResponse.status !== 200) {
      throw new Error(`OpenRouter API error: HTTP ${creditsResponse.status}`);
    }
    const credits = creditsResponse.json && creditsResponse.json.data;
    if (!credits || typeof credits !== "object" || Array.isArray(credits)) {
      throw new Error("Failed to parse OpenRouter credits: data must be an object");
    }

    function finite(value, field, optional) {
      if (optional && (value === null || value === undefined)) return null;
      if (typeof value !== "number" || !Number.isFinite(value)) {
        throw new Error(`Failed to parse OpenRouter response: ${field} must be a finite number`);
      }
      return value;
    }

    const totalCredits = finite(credits.total_credits, "total_credits", false);
    const totalUsage = finite(credits.total_usage, "total_usage", false);
    const balance = Math.max(0, totalCredits - totalUsage);
    let keyData = null;
    try {
      const keyResponse = await ctx.http.getJSON("https://openrouter.ai/api/v1/key");
      if (keyResponse.status === 200 && keyResponse.json &&
          keyResponse.json.data && typeof keyResponse.json.data === "object") {
        keyData = keyResponse.json.data;
      }
    } catch (_) {}

    function resetWindowUsage(reset) {
      const windowKey =
        reset === "daily" ? "usage_daily" :
        reset === "weekly" ? "usage_weekly" :
        reset === "monthly" ? "usage_monthly" : null;
      if (!windowKey) return null;
      return finite(keyData[windowKey], `key.${windowKey}`, true);
    }

    // Match the Swift quota path: prefer the server-reported remaining amount, then the
    // usage field matching the declared reset window, and finally cumulative usage.
    function keyUsedForQuota() {
      const limitRemaining = finite(keyData.limit_remaining, "key.limit_remaining", true);
      if (limitRemaining !== null) {
        // Clamp to [0, keyLimit] like Swift so remaining above the configured
        // limit renders 0% used instead of suppressing the meter.
        return keyLimit - Math.min(keyLimit, Math.max(0, limitRemaining));
      }
      const windowUsage = resetWindowUsage(keyData.limit_reset);
      if (windowUsage !== null) return windowUsage;
      return keyUsage;
    }

    let primary;
    let keyLimit = null;
    let keyUsage = null;
    let keyRemaining = null;
    if (keyData) {
      keyLimit = finite(keyData.limit, "key.limit", true);
      keyUsage = finite(keyData.usage, "key.usage", true);
      const used = keyUsedForQuota();
      if (keyLimit !== null && keyLimit > 0 && used !== null && Number.isFinite(used) && used >= 0) {
        primary = { usedPercent: ctx.pct(used, keyLimit) };
        keyRemaining = Math.max(0, keyLimit - used);
      }
    }

    const currency = value => `$${Math.max(0, value).toFixed(2)}`;
    const details = [{
      title: "Credits",
      rows: [
        { label: "Remaining", value: currency(balance) },
        { label: "Used", value: currency(totalUsage) },
        { label: "Total added", value: currency(totalCredits) },
      ],
    }];

    if (keyData) {
      const rows = [];
      if (keyLimit !== null && keyLimit > 0) {
        rows.push({ label: "API key budget", value: currency(keyLimit) });
        if (keyRemaining !== null) rows.push({ label: "API key remaining", value: currency(keyRemaining) });
        if (keyUsage !== null) rows.push({ label: "API key used", value: currency(keyUsage) });
      } else {
        rows.push({ label: "API key budget", value: "No limit configured" });
      }
      const resetWindow = typeof keyData.limit_reset === "string" ? keyData.limit_reset.trim() : "";
      if (resetWindow) rows.push({ label: "Reset window", value: resetWindow });
      const periods = [
        ["Today", "usage_daily"],
        ["This week", "usage_weekly"],
        ["This month", "usage_monthly"],
      ];
      const points = [];
      for (const [label, key] of periods) {
        const value = finite(keyData[key], `key.${key}`, true);
        if (value !== null) {
          rows.push({ label, value: currency(value) });
          points.push({ label, value });
        }
      }
      if (keyData.rate_limit && typeof keyData.rate_limit === "object") {
        const requests = keyData.rate_limit.requests;
        const interval = keyData.rate_limit.interval;
        if (Number.isInteger(requests) && typeof interval === "string") {
          rows.push({ label: "Rate limit", value: `${requests} requests / ${interval}` });
        }
      }
      const section = { title: "API key", rows };
      if (points.length) {
        section.chart = { kind: "bars", title: "Key spend", unit: "USD", points };
      }
      details.push(section);
    } else {
      details.push({
        title: "API key",
        rows: [{ label: "API key budget", value: "Unavailable right now" }],
      });
    }

    const result = {
      identity: { loginMethod: `Balance: ${currency(balance)}` },
      details,
    };
    if (primary) result.primary = primary;
    return result;
  },
});
