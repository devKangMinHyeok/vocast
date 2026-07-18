import * as React from "react";
import { Prose } from "@timbre/design-system";
import { asset } from "../../lib/asset";

export type Category = "Product" | "Engineering" | "Company" | "Voices";

export interface Author {
  name: string;
  avatar?: string;
}

export interface Post {
  slug: string;
  category: Category;
  title: string;
  excerpt: string;
  readTime: string;
  date: string;
  cover: string;
  authors: Author[];
  featured?: boolean;
  Body: React.FC;
}

/** Serializable card fields (safe to hand to a client component — no Body). */
export type PostCard = Omit<Post, "Body">;

const kang: Author = { name: "Minhyeok Kang", avatar: asset("/blog/avatar-thomas.png") };
const team: Author = { name: "Vocast Team" };

// --- Featured: the natural-voice article, as a full Prose body ---
const NaturalVoiceBody: React.FC = () => (
  <Prose>
    <p>
      Almost every voice AI can pass a ten-second demo. The clip sounds clean, the words are clear,
      and for about two sentences you believe it. Then you try to narrate a real script — a chapter,
      a course module, a twenty-minute video — and the illusion cracks. The endings flatten, every
      sentence lands with the same shape, and somewhere around minute three your ear stops hearing a
      person and starts hearing a machine reading.
    </p>
    <p>
      That gap — between a good demo and a narration you can publish — is the only thing that matters.
      Vocast was built to close it, and to prove it closed with numbers rather than adjectives.
    </p>

    <Prose.Heading id="prosody">&ldquo;Natural&rdquo; is not clarity. It is prosody.</Prose.Heading>
    <p>
      When people say an AI voice sounds robotic, they rarely mean it is hard to understand. Modern
      text-to-speech is almost always intelligible. What they react to is <strong>prosody</strong>:
      the rise and fall of pitch, where the breaths land, how a sentence slows into its final word,
      which syllables get pushed and which get swallowed. Prosody is what makes a voice sound like it
      is thinking, not reciting.
    </p>
    <p>
      So that is what Vocast measures first. Its north-star metric is a prosody naturalness score
      (PNS) — a single number, benchmarked against how a real person reads the same lines.
    </p>

    <Prose.Figure
      pair
      images={[asset("/blog/fresh-look.png"), asset("/blog/api-extensions.png")]}
      caption="Left: the quality report shown after every render. Right: the prosody breakdown per sentence."
    />

    <Prose.Heading id="numbers">The numbers, not the vibes</Prose.Heading>
    <p>Vocast scores every render on four axes, and gates on all of them:</p>
    <ul>
      <li>
        <strong>Speaker similarity (SIM):</strong> our winning configuration lands between 0.917 and
        0.945. Two recordings of the same real person score about 0.909 against each other — so the
        clone sits inside the range of your own voice on two different days.
      </li>
      <li>
        <strong>Word accuracy (CER):</strong> the audio is transcribed back and compared to the
        script. On mixed scripts with numbers and loanwords, character error rate is 0%.
      </li>
      <li>
        <strong>Naturalness (MOS):</strong> a no-reference model rates the clone at 3.50 — slightly
        above the 3.24 reference it was cloned from.
      </li>
      <li>
        <strong>Prosody (PNS):</strong> the north-star, held to a human-baseline gate on every take.
      </li>
    </ul>
    <p>
      None of these are cherry-picked. They are enforced in continuous integration, and a render that
      misses a gate is rejected, not shipped. Calling a voice from an agent looks like{" "}
      <code>clone_voice(text, profile_id=&quot;MyVoice&quot;)</code> — and it returns the score with the audio.
    </p>

    <blockquote>
      The honest version of &ldquo;it sounds natural&rdquo; is: we defined natural as a set of
      measurable properties, and then refused to ship anything that missed them.
    </blockquote>

    <Prose.Heading id="usable">So — can you actually use it?</Prose.Heading>
    <p>
      Generation runs at roughly 4&times; realtime on an Apple Silicon Mac, entirely on the machine —
      no upload, no queue, no per-minute meter. A karaoke view colours each word as it plays so you
      proof a long narration by eye and ear at once. And when one paragraph comes out flat, you
      regenerate just that block instead of re-rendering the whole take. It is not a voice that fools
      you for ten seconds. It is a voice you can put on a twenty-minute video, in your own name.
    </p>
  </Prose>
);

const ProsodyBody: React.FC = () => (
  <Prose>
    <p>
      Most voice tools report one number, usually word accuracy, and call it quality. That measures
      whether the words are right — not whether the delivery is human. We split naturalness into
      properties we can score independently, so a regression in any one of them fails the build.
    </p>
    <Prose.Heading id="north-star">A prosody north-star</Prose.Heading>
    <p>
      PNS blends pitch dynamics, pause rhythm and the shape of sentence endings, benchmarked against a
      human reading of the same text. A perfectly clear render can still fail it — which is the point.
    </p>
    <ul>
      <li>Pitch range that does not collapse into a monotone over long passages.</li>
      <li>Pauses that fall on clause boundaries, not on a fixed timer.</li>
      <li>Endings that decay like a person, instead of a hard identical drop.</li>
    </ul>
    <blockquote>We would rather reject a take than ship a flat one.</blockquote>
  </Prose>
);

const CloneBody: React.FC = () => (
  <Prose>
    <p>
      Naturalness is worthless if getting your voice in is a chore. Vocast builds a profile from ten
      short guided lines — about ninety seconds, designed to cover the sounds that trip up cloning.
    </p>
    <Prose.Heading id="reusable">A profile you own</Prose.Heading>
    <p>
      From then on the profile is reusable. Narrate against it as often as you like, reinforce it with
      more source clips, version it, and roll back if a new version drifts. Your voice becomes an
      asset you keep — not a one-off upload you hope worked.
    </p>
  </Prose>
);

const LongformBody: React.FC = () => (
  <Prose>
    <p>
      The real test of a voice is length. Small errors compound: the pitch range narrows, the cadence
      turns metronomic, and one bad paragraph poisons the whole take.
    </p>
    <Prose.Heading id="paragraph">Fix the paragraph, keep the take</Prose.Heading>
    <p>
      Vocast handles scripts up to 20,000 characters and lets you regenerate a single paragraph in
      place. Find the block that came out flat, swap it, keep the rest. There is also performance
      transfer: read a passage yourself once, and the clone follows your pacing and emphasis.
    </p>
  </Prose>
);

const LocalBody: React.FC = () => (
  <Prose>
    <p>
      If you make a living with your voice, where it lives is not a privacy nicety — it is the whole
      basis of trusting the tool.
    </p>
    <Prose.Heading id="local">One-time, on your machine</Prose.Heading>
    <p>
      Vocast is a one-time purchase that runs fully on your Mac. There is no account and no server:
      your voiceprint, scripts and renders never leave the device, and it keeps working offline after
      the first model download.
    </p>
  </Prose>
);

export const POSTS: Post[] = [
  {
    slug: "natural-voice-you-can-publish",
    category: "Voices",
    title: "Natural enough to publish: an AI voice you can actually use",
    excerpt:
      "Most AI voices sound great in a ten-second demo and fall apart over twenty minutes. Here is how we measure naturalness, and what it takes to ship a cloned voice you would put your name on.",
    readTime: "6 min read",
    date: "Jul 19, 2026",
    cover: asset("/blog/fresh-look.png"),
    authors: [kang, team],
    featured: true,
    Body: NaturalVoiceBody,
  },
  {
    slug: "measuring-prosody-not-vibes",
    category: "Engineering",
    title: "Measuring prosody, not vibes",
    excerpt: "Why Vocast scores pitch, pauses and sentence endings separately — and gates every render on all of them.",
    readTime: "4 min read",
    date: "Jul 12, 2026",
    cover: asset("/blog/api-extensions.png"),
    authors: [team],
    Body: ProsodyBody,
  },
  {
    slug: "clone-your-voice-in-ninety-seconds",
    category: "Product",
    title: "Clone your voice in ninety seconds",
    excerpt: "Ten guided lines, one reusable profile you can version and roll back. Your voice as an asset you own.",
    readTime: "3 min read",
    date: "Jul 4, 2026",
    cover: asset("/blog/teams.png"),
    authors: [kang],
    Body: CloneBody,
  },
  {
    slug: "long-form-without-the-re-record",
    category: "Product",
    title: "Long-form without the re-record",
    excerpt: "20,000-character scripts, per-paragraph regeneration, and performance transfer for the passages that need a specific delivery.",
    readTime: "4 min read",
    date: "Jun 26, 2026",
    cover: asset("/blog/extension-picks.png"),
    authors: [team],
    Body: LongformBody,
  },
  {
    slug: "why-one-time-and-fully-local",
    category: "Company",
    title: "Why Vocast is one-time and fully local",
    excerpt: "No subscription, no server, no account. Your voice and your words stay on your machine — by design.",
    readTime: "3 min read",
    date: "Jun 18, 2026",
    cover: asset("/blog/pro.png"),
    authors: [kang],
    Body: LocalBody,
  },
];

export const CATEGORIES: ("All" | Category)[] = ["All", "Product", "Engineering", "Company", "Voices"];

export function getPost(slug: string): Post | undefined {
  return POSTS.find((p) => p.slug === slug);
}

export function postCards(): PostCard[] {
  return POSTS.map(({ Body, ...card }) => card);
}
