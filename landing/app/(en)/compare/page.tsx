import type { Metadata } from "next";
import { CompareBody, COMPARE_META } from "../../compare/_compare-body";
import { pageMetadata } from "../../../lib/metadata";

export const metadata: Metadata = pageMetadata("en", { path: "/compare/", ...COMPARE_META });

export default function ComparePage() {
  return <CompareBody lang="en" />;
}
