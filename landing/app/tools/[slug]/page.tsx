import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Nav } from "../../_sections/Nav";
import { Footer } from "../../_sections/Footer";
import { JsonLd } from "../../_seo/JsonLd";
import { abs } from "../../../lib/site";
import { graph, toolWebAppSchema, howToSchema, faqPageSchema, breadcrumbSchema } from "../../../lib/schema";
import { ToolPageLayout } from "../_components";
import { TOOLS, getTool } from "../_data";
import { ReadingTime } from "../panels/ReadingTime";
import { NoiseRemover } from "../panels/NoiseRemover";
import { MicTest } from "../panels/MicTest";
import { VoiceRecorder } from "../panels/VoiceRecorder";
import { SilenceRemover } from "../panels/SilenceRemover";

const PANELS: Record<string, React.ComponentType> = {
  "script-reading-time-calculator": ReadingTime,
  "audio-noise-remover": NoiseRemover,
  "mic-test": MicTest,
  "voice-recorder": VoiceRecorder,
  "silence-remover": SilenceRemover,
};

export function generateStaticParams() {
  return TOOLS.filter((t) => t.live).map((t) => ({ slug: t.slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const tool = getTool(slug);
  if (!tool) return { title: "Free audio tools" };
  const url = abs(`/tools/${slug}/`);
  return {
    title: tool.metaTitle ?? tool.name,
    description: tool.metaDescription,
    alternates: { canonical: url },
    keywords: tool.keywords,
    openGraph: { type: "website", url, title: tool.metaTitle ?? tool.name, description: tool.metaDescription },
  };
}

export default async function ToolPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const tool = getTool(slug);
  if (!tool) notFound();
  const Panel = PANELS[slug];

  return (
    <main>
      <JsonLd
        data={graph(
          toolWebAppSchema({ slug: tool.slug, name: tool.name, description: tool.metaDescription ?? "", howto: tool.howto }),
          howToSchema({ slug: tool.slug, name: tool.name, description: tool.metaDescription ?? "", howto: tool.howto }),
          tool.faqs ? faqPageSchema(tool.faqs) : null,
          breadcrumbSchema([
            { name: "Home", path: "/" },
            { name: "Tools", path: "/tools/" },
            { name: tool.name, path: `/tools/${slug}/` },
          ]),
        )}
      />
      <Nav active="Tools" />
      <ToolPageLayout tool={tool} panel={Panel ? <Panel /> : null} />
      <Footer />
    </main>
  );
}
