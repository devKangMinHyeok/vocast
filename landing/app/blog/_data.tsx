import * as React from "react";
import { Prose } from "@timbre/design-system";
import { asset } from "../../lib/asset";

export type Category = "Voice" | "Engineering" | "Methodology" | "AI (MCP)" | "Privacy";

export interface Author {
  name: string;
  avatar?: string;
  role?: string;
  bio?: string;
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

/** Serializable card fields (safe to hand to a client component, no Body). */
export type PostCard = Omit<Post, "Body">;

const kang: Author = { name: "Minhyeok Kang", avatar: asset("/blog/kang-minhyeok.png"), role: "Founder · Vocast", bio: "Building a local voice studio for creators. Writes about voice cloning, prosody metrics, and shipping on-device." };
const team: Author = { name: "Vocast Team", avatar: asset("/blog/vocast-mark.svg"), role: "Vocast", bio: "Field notes from the people building Vocast." };

// --- Featured: the natural-voice article, as a full Prose body ---
const NaturalVoiceBody: React.FC = () => (
  <Prose>
    <p>
      Almost every voice AI can pass a ten-second demo. The clip sounds clean, the words are clear,
      and for about two sentences you believe it. Then you try to narrate a real script, a chapter,
      a course module, a twenty-minute video, and the illusion cracks. The endings flatten, every
      sentence lands with the same shape, and somewhere around minute three your ear stops hearing a
      person and starts hearing a machine reading.
    </p>
    <p>
      That gap, between a good demo and a narration you can publish, is the only thing that matters.
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
      (PNS), a single number, benchmarked against how a real person reads the same lines.
    </p>

    <Prose.Figure
      pair
      images={[asset("/blog/figure-quality.png"), asset("/blog/figure-audio.png")]}
      caption="Left: the quality report shown after every render. Right: the prosody breakdown per sentence."
    />

    <Prose.Heading id="failure">Where a voice actually breaks</Prose.Heading>
    <p>
      Long-form failure is not one bug, it is four, and none of them are visible in a short clip.
      They only surface once the voice has to keep going:
    </p>
    <ul>
      <li>
        <strong>Pitch collapse.</strong> The melody narrows paragraph by paragraph until the voice is
        reading on a flat line. The first sentence has range; the fortieth does not.
      </li>
      <li>
        <strong>Metronomic cadence.</strong> Pauses stop landing on meaning and start landing on a
        timer, so every sentence takes the same beat and the rhythm turns mechanical.
      </li>
      <li>
        <strong>Boundary breathing.</strong> The tiny breath and settle between sentences disappears,
        and clauses run into each other with no room to think.
      </li>
      <li>
        <strong>Clipped endings.</strong> Final words get chopped or dropped to an identical hard
        stop, instead of decaying the way a person trails off.
      </li>
    </ul>
    <p>
      Each of these has its own named metric in Vocast and its own gate, so a render cannot pass by
      being good on average while quietly failing one of them.
    </p>

    <Prose.Heading id="numbers">The numbers, not the vibes</Prose.Heading>
    <p>Vocast scores every render on four axes, and gates on all of them:</p>
    <ul>
      <li>
        <strong>Speaker similarity (SIM):</strong> our winning configuration lands between 0.917 and
        0.945. Two recordings of the same real person score about 0.909 against each other, so the
        clone sits inside the range of your own voice on two different days.
      </li>
      <li>
        <strong>Word accuracy (CER):</strong> the audio is transcribed back and compared to the
        script. On mixed scripts with numbers and loanwords, character error rate is 0%.
      </li>
      <li>
        <strong>Naturalness (MOS):</strong> a no-reference model rates the clone at 3.50, slightly
        above the 3.24 reference it was cloned from.
      </li>
      <li>
        <strong>Prosody (PNS):</strong> the north-star, held to a human-baseline gate on every take.
      </li>
    </ul>
    <p>
      None of these are cherry-picked. They are enforced in continuous integration, and a render that
      misses a gate is rejected, not shipped. Calling a voice from an agent looks like{" "}
      <code>clone_voice(text, profile_id=&quot;MyVoice&quot;)</code>, and it returns the score with the audio.
    </p>

    <blockquote>
      The honest version of &ldquo;it sounds natural&rdquo; is: we defined natural as a set of
      measurable properties, and then refused to ship anything that missed them.
    </blockquote>

    <Prose.Figure
      src={asset("/blog/figure-karaoke.png")}
      caption="Karaoke proofing: each word colours as it plays; click any word to jump there."
    />

    <Prose.Heading id="usable">So, can you actually use it?</Prose.Heading>
    <p>
      Generation runs at roughly 4&times; realtime on an Apple Silicon Mac, entirely on the machine.
      No upload, no queue, no per-minute meter. A karaoke view colours each word as it plays so you
      proof a long narration by eye and ear at once. And when one paragraph comes out flat, you
      regenerate just that block instead of re-rendering the whole take.
    </p>
    <p>
      The same engine is available to an agent over MCP, so a script written in one tool can be
      narrated, scored and returned without leaving your desk. It is not a voice that fools you for
      ten seconds. It is a voice you can put on a twenty-minute video, in your own name.
    </p>
  </Prose>
);

const ProsodyBody: React.FC = () => (
  <Prose>
    <p>
      Most voice tools report one number, usually word accuracy, and call it quality. Word accuracy
      tells you the words are right. It says nothing about whether the delivery is human. A voice can
      be spelled perfectly and still read like a form letter, and that is exactly the version most
      tools ship because it is the version their one metric approves.
    </p>
    <p>
      Vocast takes the opposite approach. We split naturalness into properties we can measure on their
      own, hold each to a gate, and fail the whole render if any single property regresses. A take
      does not get to pass by being pleasant on average while quietly falling apart in one dimension.
    </p>

    <Prose.Heading id="north-star">A prosody north-star</Prose.Heading>
    <p>
      The headline metric is a prosody naturalness score (PNS). It is not a vibe rating from a model
      guessing at overall quality. It is a composite of three things we can point at:
    </p>
    <ul>
      <li>
        <strong>Pitch dynamics.</strong> How much the melody moves, and whether that range survives
        over a long passage instead of narrowing into a monotone by the fortieth sentence.
      </li>
      <li>
        <strong>Pause rhythm.</strong> Whether silences land on clause boundaries, where a reader
        would actually breathe, rather than on a fixed timer that ignores the sentence.
      </li>
      <li>
        <strong>Ending shape.</strong> Whether final words decay the way a person trails off, instead
        of being cut to an identical hard stop every time.
      </li>
    </ul>
    <p>
      Each of these is benchmarked against a human reading the same lines, so the target is not an
      abstract ideal, it is what a real person actually did with that text. A perfectly clear render
      can still fail PNS, and when it does the failure is legible: you can see which axis dropped.
    </p>

    <Prose.Figure
      src={asset("/blog/figure-prosody-curve.png")}
      caption="Pitch, pause and ending shape for one sentence, scored against a human reading of the same line."
    />

    <Prose.Heading id="family">One score is not enough</Prose.Heading>
    <p>
      PNS sits on top of a family of narrower metrics, each added because it caught a specific way the
      voice went wrong on real scripts:
    </p>
    <ul>
      <li>
        <strong>Boundary breathing.</strong> Scores the small breath and settle between sentences, so
        clauses do not run together with no room to think.
      </li>
      <li>
        <strong>Micro quality.</strong> Watches word endings, tricky pronunciations and the tiny
        breaths inside a phrase, the details that read as human up close.
      </li>
      <li>
        <strong>Energy stress.</strong> Checks that the stressed syllable in a word is actually
        pushed, so emphasis carries meaning instead of flattening out.
      </li>
    </ul>

    <Prose.Heading id="gate">Gated in CI, not in a meeting</Prose.Heading>
    <p>
      These numbers are not a report someone reads and nods at. They run in continuous integration
      against a set of golden takes, and a change that drops any gate fails the build the same way a
      broken test would. Every render carries its scorecard with it:
    </p>
    <pre><code>{`render.score
  sim   0.931   pass   (human baseline 0.909)
  cer   0.0%    pass
  mos   3.50    pass   (reference 3.24)
  pns   0.88    pass   (gate 0.82)`}</code></pre>
    <p>
      When we improve the model, we do it by running a field of candidate configurations, scoring them
      all, and keeping the one that wins on the metrics rather than the one that sounds nice in a
      single clip. The gate is what turns &ldquo;this take feels off&rdquo; into a number we can chase.
    </p>

    <blockquote>We would rather reject a take than ship a flat one.</blockquote>
  </Prose>
);

const CloneBody: React.FC = () => (
  <Prose>
    <p>
      A natural voice model is worthless if getting your voice into it is a chore. Most tools either
      want a studio session and thirty minutes of clean tape, or they take a ten-second snippet and
      give you a thin, brittle clone that only holds up on short lines. Vocast aims for the middle:
      enough audio to be faithful, little enough that you record it once and move on.
    </p>

    <Prose.Heading id="ninety">Ninety seconds, chosen on purpose</Prose.Heading>
    <p>
      A profile is built from ten short guided lines, about ninety seconds in total. The lines are not
      random. They are picked to cover the sounds that trip cloning up: a wide pitch range, hard
      consonants, trailing sentence endings, numbers, and the vowels that carry most of a voice&rsquo;s
      identity. Coverage is why ninety focused seconds beats five unstructured minutes.
    </p>
    <p>
      You read them in the app with the prompt on screen, and the build runs on your machine. When it
      finishes you get a similarity number, not a shrug. Our profiles land between 0.917 and 0.945
      against the source. For context, two separate recordings of the same real person score about
      0.909 against each other, so a finished profile sits inside the range of your own voice on two
      different days.
    </p>

    <Prose.Figure
      src={asset("/blog/figure-guided-capture.png")}
      caption="Ten short guided lines, chosen to cover the sounds that trip cloning up. About ninety seconds in total."
    />

    <Prose.Heading id="reusable">A profile you own</Prose.Heading>
    <p>
      From then on the profile is a reusable asset, not a one-off upload you hope worked. You can:
    </p>
    <ul>
      <li>Narrate against it as often as you like, with no re-recording.</li>
      <li>Reinforce it with more source clips when you want it even closer.</li>
      <li>Version it, so each rebuild is tracked rather than overwriting the last.</li>
      <li>Roll back if a new version drifts, returning to the take you trusted.</li>
    </ul>
    <p>
      And when a specific passage needs a specific delivery, you can read it yourself once and let the
      clone follow your pacing and emphasis. Your voice stops being a snapshot and becomes something
      you build on over time.
    </p>
  </Prose>
);

const LongformBody: React.FC = () => (
  <Prose>
    <p>
      The real test of a voice is length. Anything sounds fine for one sentence. The problems begin
      when a voice has to hold together across a chapter, a course module, a twenty-minute script,
      and they compound: the pitch range narrows, the cadence turns metronomic, and a single flat
      paragraph in the middle poisons a take you otherwise liked.
    </p>
    <p>
      The lazy fix is to render the whole thing again and hope the bad paragraph comes out better.
      That wastes minutes and rolls the dice on the good paragraphs too. Vocast is built so you never
      have to do that.
    </p>

    <Prose.Heading id="architecture">Built to keep going</Prose.Heading>
    <p>
      Under the hood a resident model worker stays warm instead of reloading per request, paragraphs
      are batched and run in parallel, and the whole pipeline is held to a real-time-factor gate so
      that adding length does not quietly blow up the wait. In practice generation runs at roughly
      four times realtime on an Apple Silicon Mac, and scripts can run up to 20,000 characters.
    </p>

    <Prose.Figure
      src={asset("/blog/figure-paragraph-blocks.png")}
      caption="A long script rendered as paragraph blocks. Regenerate one in place while everything around it stays."
    />

    <Prose.Heading id="paragraph">Fix the paragraph, keep the take</Prose.Heading>
    <p>
      A finished narration is not one opaque audio file. It is a set of paragraph blocks, each with
      its own settings and version history. When one block comes out flat, you regenerate just that
      block in place and keep everything around it:
    </p>
    <ul>
      <li>The rest of the take is untouched, so nothing you already approved gets re-rolled.</li>
      <li>Each regeneration is versioned, so you can compare and roll back to an earlier take.</li>
      <li>You proof by eye and ear with a karaoke view that colours each word as it plays.</li>
    </ul>
    <p>
      And for the passages that need a specific reading, there is performance transfer: read the
      passage yourself once, and the clone follows your pacing and emphasis instead of guessing. The
      result is a workflow that scales with the script, not one that punishes you for writing more.
    </p>
  </Prose>
);

const LocalBody: React.FC = () => (
  <Prose>
    <p>
      If you make a living with your voice, where that voice lives is not a privacy nicety. It is the
      whole basis of trusting the tool. A voiceprint is not like a document you can revoke. Once a
      convincing clone of you exists on someone else&rsquo;s server, you have to trust their policy,
      their security and their future business model, forever. Most voice services ask you to do
      exactly that, and to keep paying for the privilege.
    </p>

    <Prose.Heading id="local">On your machine, by design</Prose.Heading>
    <p>
      Vocast runs fully on your Mac. There is no account and no server in the loop, which means:
    </p>
    <ul>
      <li>Your voiceprint, your scripts and your renders never leave the device.</li>
      <li>Nothing is queued on someone else&rsquo;s hardware or logged for &ldquo;model improvement&rdquo;.</li>
      <li>After the first model download it keeps working offline, on a plane or behind a firewall.</li>
    </ul>
    <p>
      This is not a marketing toggle that could be flipped later. There is no upload path in the
      product to flip. The application ships as a sealed bundle with its own runtime and models, so it
      does not phone home for dependencies and does not depend on a service staying online to function.
    </p>

    <Prose.Figure
      src={asset("/blog/figure-on-device.png")}
      caption="Voiceprint, scripts and renders stay on the machine. No account, no upload, no server in the loop."
    />

    <Prose.Heading id="one-time">One-time, not a meter</Prose.Heading>
    <p>
      It is also a one-time purchase, not a subscription with a per-minute meter. Local processing is
      what makes that possible: there is no server cost to pass on to you for every second of audio,
      so there is no reason to rent you your own voice by the minute. You buy the tool, you own the
      workflow, and the voice you build stays yours.
    </p>
  </Prose>
);

export const POSTS: Post[] = [
  {
    slug: "natural-voice-you-can-publish",
    category: "Methodology",
    title: "Natural enough to publish: an AI voice you can actually use",
    excerpt:
      "Most AI voices sound great in a ten-second demo and fall apart over twenty minutes. Here is how we measure naturalness, and what it takes to ship a cloned voice you would put your name on.",
    readTime: "6 min read",
    date: "Jul 19, 2026",
    cover: asset("/blog/figure-cover.png"),
    authors: [kang, team],
    featured: true,
    Body: NaturalVoiceBody,
  },
  {
    slug: "measuring-prosody-not-vibes",
    category: "Engineering",
    title: "Measuring prosody, not vibes",
    excerpt: "Why Vocast scores pitch, pauses and sentence endings separately, and gates every render on all of them.",
    readTime: "6 min read",
    date: "Jul 12, 2026",
    cover: asset("/blog/figure-quality.png"),
    authors: [team],
    Body: ProsodyBody,
  },
  {
    slug: "clone-your-voice-in-ninety-seconds",
    category: "Voice",
    title: "Clone your voice in ninety seconds",
    excerpt: "Ten guided lines, one reusable profile you can version and roll back. Your voice as an asset you own.",
    readTime: "5 min read",
    date: "Jul 4, 2026",
    cover: asset("/blog/figure-profile.png"),
    authors: [kang],
    Body: CloneBody,
  },
  {
    slug: "long-form-without-the-re-record",
    category: "Engineering",
    title: "Long-form without the re-record",
    excerpt: "20,000-character scripts, per-paragraph regeneration, and performance transfer for the passages that need a specific delivery.",
    readTime: "5 min read",
    date: "Jun 26, 2026",
    cover: asset("/blog/figure-longform.png"),
    authors: [team],
    Body: LongformBody,
  },
  {
    slug: "why-one-time-and-fully-local",
    category: "Privacy",
    title: "Why Vocast is one-time and fully local",
    excerpt: "No subscription, no server, no account. Your voice and your words stay on your machine, by design.",
    readTime: "3 min read",
    date: "Jun 18, 2026",
    cover: asset("/blog/figure-audio.png"),
    authors: [kang],
    Body: LocalBody,
  },
];

export const CATEGORIES: ("All" | Category)[] = ["All", "Voice", "Engineering", "Methodology", "AI (MCP)", "Privacy"];

export function getPost(slug: string): Post | undefined {
  return POSTS.find((p) => p.slug === slug);
}

export function postCards(): PostCard[] {
  return POSTS.map(({ Body, ...card }) => card);
}
