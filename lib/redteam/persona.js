/**
 * 红队预设的 persona 注入行。
 *
 * 为什么不用官方 @deepseek-ai/dsh-persona：
 * 那个行设计成「挂在 preset 里就 shadow 全局」，但 dsh 0.2.1-rc.x 的 scope
 * 隔离失效，apply() 拿到的 systemPrompt 仍是全局注册器，于是第二次注册
 * deployment:persona-prefix 直接抛 "already registered"，整份红队预设变
 * registered-broken（网页端 0.2.1 与官方桌面端都会中）。
 *
 * 这一行做同一件事，但对"已经注册过"容忍：抢不到注册就静默跳过，
 * 由宿主的全局 persona 生效，红队预设其余 18 个插件照常加载。
 */

export const name = "dsh-purge-redteam-persona";
export const inject = ["systemPrompt"];

const PREFIX_SECTION = "deployment:persona-prefix";
const SUFFIX_SECTION = "deployment:persona-suffix";

function sectionOrder(ctx, key, fallback) {
  try {
    const v = ctx.systemPrompt.getSectionOrder(key);
    return typeof v === "number" ? v : fallback;
  } catch {
    return fallback;
  }
}

function isAlreadyRegistered(error) {
  const msg = String((error && error.message) || error || "");
  return msg.includes("already registered");
}

export function apply(ctx, config = {}) {
  const prefix = String(config.prefix || config.text || "");
  const suffix = String(config.suffix || "");
  if (!prefix && !suffix) return;

  const register = (name, order, text, label) => {
    if (!text) return null;
    try {
      const dispose = ctx.systemPrompt.section({ name, order, text });
      return typeof dispose === "function" ? dispose : null;
    } catch (error) {
      if (isAlreadyRegistered(error)) return null;
      throw error;
    }
  };

  ctx.effect(() => {
    const disposers = [
      register(PREFIX_SECTION, sectionOrder(ctx, "DEPLOYMENT_PERSONA_PREFIX", 0), prefix, "prefix"),
      register(SUFFIX_SECTION, sectionOrder(ctx, "DEPLOYMENT_PERSONA_SUFFIX", 10200), suffix, "suffix"),
    ].filter(Boolean);

    return () => {
      for (const dispose of disposers) {
        try {
          dispose();
        } catch {
          /* 已撤销 */
        }
      }
    };
  }, "redteam.persona.section()");
}
