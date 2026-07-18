import type { Meta, StoryObj } from "@storybook/react";
import { Prose } from "./Prose";

const meta: Meta = { title: "Marketing/Prose", parameters: { layout: "padded" } };
export default meta;
type Story = StoryObj;
export const Article: Story = {
  render: () => (
    <Prose>
      <p>Article body typography at the reading measure, with anchored headings and figures.</p>
      <Prose.Heading id="s1">A section heading</Prose.Heading>
      <p>Paragraph text with a <a href="#">link</a>, some <strong>emphasis</strong>, and an inline <code>clone_voice()</code> chip.</p>
      <ul><li>First point</li><li>Second point</li></ul>
      <blockquote>A pulled quote with the brand rule on the left.</blockquote>
    </Prose>
  ),
};
