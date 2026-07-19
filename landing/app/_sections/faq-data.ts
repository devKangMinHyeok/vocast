// FAQ 문항 단일 소스. FAQ UI(Faq.tsx)와 FAQPage JSON-LD가 함께 참조한다.
export interface FaqItem {
  q: string;
  a: string;
}

export const FAQ_ITEMS: FaqItem[] = [
  { q: "Is it really not a subscription?", a: "Yes. $49 once. You get a year of free updates and can keep the app plus your last version forever, renewal after that is optional, not required." },
  { q: "Where is my voice data stored?", a: "On your Mac, in your user folder. There is no account and no server: your voiceprint, scripts and renders never leave the device." },
  { q: "Which Mac do I need?", a: "An Apple Silicon Mac (M1 or newer) on macOS 12+. Voice cloning uses on-device Metal acceleration; noise removal works everywhere." },
  { q: "How do I connect an AI agent?", a: "Vocast exposes a local MCP server over stdio. Point Claude, or any MCP-capable agent, at it and it can call denoise, clone_voice and the rest directly." },
  { q: "Can I clone any voice?", a: "Only your own voice, or a voice you have explicit consent to use. Cloning is built for creators narrating their own work, not for impersonation." },
  { q: "Is the source public?", a: "The engine, quality methodology and MCP server are open on GitHub. You can read exactly how cloning, scoring and denoising work." },
  { q: "What's the refund policy?", a: "14 days, no questions asked. If it doesn't fit your workflow, email us within two weeks for a full refund." },
];
