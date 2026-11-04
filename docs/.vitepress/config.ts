import { defineConfig } from "vitepress";
import { withMermaid } from "vitepress-plugin-mermaid";

// https://vitepress.dev/reference/site-config
export default withMermaid(
  defineConfig({
    title: "luau-signals",
    description: "Luau Port of alien-signals — the lightest signal library, now for Luau and Roblox",
    lang: "en-US",
    base: "/luau-signals/",
    head: [["link", { rel: "icon", href: "/luau-signals/logo.svg" }]],

    cleanUrls: true,

    mermaid: {
      // https://mermaid.js.org/config/schema-docs/config-schema.html
    },

    vite: {
      optimizeDeps: {
        include: ["mermaid"],
      },
    },

    themeConfig: {
      logo: "/logo.svg",
      search: {
        provider: "local",
      },

      outline: {
        level: [2, 3],
      },

      footer: {
        message: "Released under the MIT License.",
      },

      nav: [
        { text: "Home", link: "/" },
        { text: "Tutorial", link: "/tutorials/introduction" },
        { text: "API", link: "/api/" },
      ],

      sidebar: {
        "/tutorials/": [
          {
            text: "Tutorial",
            items: [
              { text: "Introduction", link: "/tutorials/introduction" },
              { text: "Getting Started", link: "/tutorials/getting-started" },
              { text: "Signals & Effects", link: "/tutorials/signals-and-effects" },
              { text: "Computed Values", link: "/tutorials/computed" },
              { text: "Batches", link: "/tutorials/batches" },
              { text: "Effect Scopes", link: "/tutorials/effect-scopes" },
              { text: "Trigger", link: "/tutorials/trigger" },
              { text: "How It Works", link: "/tutorials/how-it-works" },
            ],
          },
        ],
        "/api/": [
          {
            text: "API Reference",
            items: [
              { text: "Overview", link: "/api/" },
              { text: "signal", link: "/api/signal" },
              { text: "computed", link: "/api/computed" },
              { text: "effect", link: "/api/effect" },
              { text: "effectScope", link: "/api/effect-scope" },
              { text: "trigger", link: "/api/trigger" },
              { text: "Batching", link: "/api/batching" },
              { text: "Type Guards", link: "/api/type-guards" },
              { text: "Advanced", link: "/api/advanced" },
            ],
          },
        ],
      },

      socialLinks: [
        { icon: "github", link: "https://github.com/maneetoo/luau-signals" },
        { icon: "discord", link: "https://discord.gg/vtUJdtUK2J" },
      ],
    },
  })
);
