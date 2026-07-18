import type { Meta, StoryObj } from "@storybook/react";
import { BlogCard } from "./BlogCard";

const meta: Meta<typeof BlogCard> = {
  title: "Marketing/BlogCard",
  component: BlogCard,
  args: {
    title: "Natural enough to publish",
    excerpt: "How we measure naturalness, and what it takes to ship a voice you can put your name on.",
    author: "Vocast Team",
    date: "Jul 19, 2026",
    category: "Voices",
    readTime: "6 min read",
  },
};
export default meta;
type Story = StoryObj<typeof BlogCard>;
export const Default: Story = { render: (a) => <div style={{ width: 380 }}><BlogCard {...a} /></div> };
