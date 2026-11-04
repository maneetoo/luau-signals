---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "luau-signals"
  text: "The lightest signal library, now in Luau"
  tagline: "A faithful Luau port of alien-signals — push-pull reactivity whose core algorithm was adopted by Vue 3.6. Signals, computed values, effects and effect scopes, with lazy, glitch-free semantics."
  actions:
    - theme: brand
      text: Tutorial
      link: /tutorials/introduction
    - theme: alt
      text: API Reference
      link: /api/

features:
  - icon: ⚡
    title: "Push–pull reactivity"
    details: "Writes push dirty flags through the dependency graph; reads pull fresh values only when needed. Unobserved computed chains are never touched."
  - icon: 🦭
    title: "Idiomatic Luau"
    details: "Nodes are callable tables — the node is the API. No per-node closures, no wrapper allocations. Flag math goes through bit32 with precomputed, compile-time-folded masks."
  - icon: 🧊
    title: "Glitch-free by design"
    details: "Every value is consistent inside an effect run: diamond dependencies settle before your callback fires, and batches collapse many writes into a single effect restart."
  - icon: 🌲
    title: "One-call disposal"
    details: "effectScope groups effects — and nested scopes — into a tree that can be torn down with a single call. Ideal for components, UI and cleanup-heavy code."
---
