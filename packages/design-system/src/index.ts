// @timbre/design-system — public API.
// Consumers must also import the token/font CSS once:
//   import "@timbre/design-system/styles.css";

// Shared primitives (safe on both marketing site and product app)
export { Button } from "./components/shared/Button";
export type { ButtonProps } from "./components/shared/Button";
export { Badge } from "./components/shared/Badge";
export type { BadgeProps } from "./components/shared/Badge";
export { PillTab } from "./components/shared/PillTab";
export type { PillTabProps } from "./components/shared/PillTab";
export { GradientText } from "./components/shared/GradientText";
export type { GradientTextProps } from "./components/shared/GradientText";
export { InlineLink } from "./components/shared/InlineLink";
export type { InlineLinkProps } from "./components/shared/InlineLink";
export { InstallButton } from "./components/shared/InstallButton";
export type { InstallButtonProps } from "./components/shared/InstallButton";
export { InstallCommand } from "./components/shared/InstallCommand";
export type { InstallCommandProps } from "./components/shared/InstallCommand";
export { Logo } from "./components/shared/Logo";
export type { LogoProps } from "./components/shared/Logo";
export { Avatar } from "./components/shared/Avatar";
export type { AvatarProps } from "./components/shared/Avatar";

// Marketing (website only — do not use in the product app)
export { FeatureCard } from "./components/marketing/FeatureCard";
export type { FeatureCardProps } from "./components/marketing/FeatureCard";
export { SectionHeading } from "./components/marketing/SectionHeading";
export type { SectionHeadingProps } from "./components/marketing/SectionHeading";
export { PromoCard } from "./components/marketing/PromoCard";
export type { PromoCardProps } from "./components/marketing/PromoCard";
export { TakeoffCTA } from "./components/marketing/TakeoffCTA";
export type { TakeoffCTAProps } from "./components/marketing/TakeoffCTA";

// Blog (marketing) — index + post
export { CategoryTag } from "./components/marketing/CategoryTag";
export type { CategoryTagProps } from "./components/marketing/CategoryTag";
export { AuthorStack } from "./components/marketing/AuthorStack";
export type { AuthorStackProps, BlogAuthor } from "./components/marketing/AuthorStack";
export { BlogCard } from "./components/marketing/BlogCard";
export type { BlogCardProps } from "./components/marketing/BlogCard";
export { BlogFeatured } from "./components/marketing/BlogFeatured";
export type { BlogFeaturedProps } from "./components/marketing/BlogFeatured";
export { Prose } from "./components/marketing/Prose";
export type { ProseProps, ProseHeadingProps, ProseFigureProps } from "./components/marketing/Prose";
export { BlogPostLayout } from "./components/marketing/BlogPostLayout";
export type { BlogPostLayoutProps } from "./components/marketing/BlogPostLayout";
