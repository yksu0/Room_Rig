export type Profile = {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
  is_admin?: boolean;
};

export type PublishedLayout = {
  id: string;
  author_id: string | null;
  title: string;
  description?: string | null;
  layout: unknown;
  scores: Record<string, number> | null;
  tags: string[];
  is_admin_baseline: boolean;
  featured_until: string | null;
  published_at: string;
  hidden: boolean;
};

export type LayoutRatingStats = {
  layout_id: string;
  up_count: number;
  down_count: number;
  net_score: number;
};

export type CommunityProfile = {
  id: string;
  display_name: string | null;
  avatar_url: string | null;
};
