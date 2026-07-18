import type { Meta, StoryObj } from "@storybook/react";
import { Avatar } from "./Avatar";

const meta: Meta<typeof Avatar> = { title: "Shared/Avatar", component: Avatar, args: { initials: "V", size: 40 } };
export default meta;
type Story = StoryObj<typeof Avatar>;
export const Initials: Story = {};
export const Sizes: Story = {
  render: () => (
    <div style={{ display: "flex", gap: 12, alignItems: "center" }}>
      <Avatar initials="V" size={24} /><Avatar initials="K" size={32} /><Avatar initials="T" size={48} />
    </div>
  ),
};
