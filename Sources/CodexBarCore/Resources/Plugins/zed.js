defineProvider({
  id: "zed",
  name: "Zed",
  endpoints: ["https://cloud.zed.dev"],
  settings: [],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["zed.dev"],
  async fetchUsage(ctx) {
    const response = await ctx.http.get("https://cloud.zed.dev/frontend/billing/usage", {
      headers: { Cookie: await ctx.browser.cookieHeader("zed.dev") },
    });
    if (response.status === 401 || response.status === 403) {
      ctx.browser.rejectCookie("zed.dev");
      throw ctx.fail.authenticationExpired(
        "Zed browser session expired. Sign in to zed.dev in Chrome or update the Cookie header.",
      );
    }
    if (response.status === 429) throw ctx.fail.rateLimited("Zed usage requests are rate limited.");
    if (response.status >= 500) {
      throw ctx.fail.providerUnavailable(`Zed cloud API returned HTTP ${response.status}.`);
    }
    if (response.status !== 200) {
      throw ctx.fail.apiFailure(`Zed cloud API returned HTTP ${response.status}.`);
    }

    const fail = () => {
      throw ctx.fail.parseFailure("Could not parse Zed billing response. Its format may have changed.");
    };
    const object = (value) => {
      if (!value || typeof value !== "object" || Array.isArray(value)) return fail();
      return value;
    };
    const count = (value) => {
      if (!Number.isSafeInteger(value) || value < 0) return fail();
      return value;
    };
    const cents = (value) => count(value) / 100;
    const text = (value) => {
      if (typeof value !== "string" || !value.trim()) return fail();
      return value;
    };

    let root;
    try {
      root = object(JSON.parse(response.bodyText));
    } catch {
      return fail();
    }
    const plan = text(root.plan);
    const usage = object(root.current_usage);
    const predictions = object(usage.edit_predictions);
    const used = count(predictions.used);
    const rawLimit = predictions.limit;
    const unlimited = rawLimit === "unlimited" || rawLimit === null;
    const limit = unlimited ? null : count(typeof rawLimit === "object" ? object(rawLimit).limited : rawLimit);
    const snapshot = {
      identity: {
        loginMethod: plan
          .replace(/_/g, " ")
          .split(" ")
          .filter(Boolean)
          .map((word) => word[0].toUpperCase() + word.slice(1).toLowerCase())
          .join(" "),
      },
      dataConfidence: "exact",
      primary: unlimited
        ? { usedPercent: 0, resetDescription: "Unlimited" }
        : limit > 0
          ? {
              usedPercent: ctx.pct(used, limit),
              resetDescription: `${Math.min(used, limit)} / ${limit} predictions`,
            }
          : null,
    };

    const spend = object(usage.token_spend);
    const spent = cents(spend.spend_in_cents);
    const cap = spend.limit_in_cents == null ? null : cents(spend.limit_in_cents);
    if (cap !== null) {
      snapshot.cost = { used: spent, limit: cap, currency: "USD", period: "Current billing period" };
    }
    const rows = [
      { label: "Spent", value: ctx.format.usd(spent), usageValue: spent },
      { label: "Spend limit", value: cap === null ? "Not reported" : ctx.format.usd(cap) },
    ];
    if (cap !== null) {
      rows.push({ label: "Remaining budget", value: ctx.format.usd(Math.max(0, cap - spent)) });
    }
    snapshot.details = [{ title: "Token spend", rows }];
    return snapshot;
  },
});
