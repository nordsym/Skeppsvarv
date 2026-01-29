-- =============================================
-- SKEPPA.NU - Supabase Schema
-- Kör detta i Supabase SQL Editor
-- =============================================

-- 1. PROFILES (extends auth.users)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    total_points INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. BATCHES (Månadsomgångar)
CREATE TABLE batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    month TEXT UNIQUE NOT NULL, -- "2026-01"
    theme TEXT,
    description TEXT,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. SUBMISSIONS (Skeppningar)
CREATE TABLE submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    url TEXT NOT NULL,
    repo_url TEXT,
    tags TEXT[] DEFAULT '{}',
    thumbnail_url TEXT,
    points_earned INTEGER DEFAULT 0,
    batch_month TEXT NOT NULL,
    is_featured BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. BADGES (Utmärkelser)
CREATE TABLE badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    icon TEXT DEFAULT 'trophy',
    points_value INTEGER DEFAULT 2,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. USER_BADGES (Junction)
CREATE TABLE user_badges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    badge_id UUID NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
    earned_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, badge_id)
);

-- =============================================
-- INDEXES
-- =============================================
CREATE INDEX idx_submissions_user ON submissions(user_id);
CREATE INDEX idx_submissions_batch ON submissions(batch_month);
CREATE INDEX idx_submissions_created ON submissions(created_at DESC);
CREATE INDEX idx_profiles_points ON profiles(total_points DESC);
CREATE INDEX idx_user_badges_user ON user_badges(user_id);

-- =============================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE batches ENABLE ROW LEVEL SECURITY;

-- PROFILES policies
CREATE POLICY "Profiles are viewable by everyone"
    ON profiles FOR SELECT
    USING (true);

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- SUBMISSIONS policies
CREATE POLICY "Submissions are viewable by everyone"
    ON submissions FOR SELECT
    USING (true);

CREATE POLICY "Users can insert own submissions"
    ON submissions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own submissions"
    ON submissions FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own submissions"
    ON submissions FOR DELETE
    USING (auth.uid() = user_id);

-- BADGES policies (read-only for users)
CREATE POLICY "Badges are viewable by everyone"
    ON badges FOR SELECT
    USING (true);

-- USER_BADGES policies
CREATE POLICY "User badges are viewable by everyone"
    ON user_badges FOR SELECT
    USING (true);

-- BATCHES policies
CREATE POLICY "Batches are viewable by everyone"
    ON batches FOR SELECT
    USING (true);

-- =============================================
-- FUNCTIONS
-- =============================================

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id, username, display_name, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'username', 'user_' || LEFT(NEW.id::text, 8)),
        COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.raw_user_meta_data->>'username'),
        NEW.raw_user_meta_data->>'avatar_url'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Calculate points for submission
CREATE OR REPLACE FUNCTION calculate_submission_points(p_user_id UUID, p_batch_month TEXT)
RETURNS INTEGER AS $$
DECLARE
    submission_count INTEGER;
    points INTEGER;
BEGIN
    -- Count existing submissions this month
    SELECT COUNT(*) INTO submission_count
    FROM submissions
    WHERE user_id = p_user_id AND batch_month = p_batch_month;

    -- First submission = 10 points, rest = 5 points (max 5 submissions)
    IF submission_count = 0 THEN
        points := 10;
    ELSIF submission_count < 5 THEN
        points := 5;
    ELSE
        points := 0; -- Max reached
    END IF;

    RETURN points;
END;
$$ LANGUAGE plpgsql;

-- Update user total points
CREATE OR REPLACE FUNCTION update_user_points()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE profiles
        SET total_points = total_points + NEW.points_earned,
            updated_at = NOW()
        WHERE id = NEW.user_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE profiles
        SET total_points = total_points - OLD.points_earned,
            updated_at = NOW()
        WHERE id = OLD.user_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_submission_points_change
    AFTER INSERT OR DELETE ON submissions
    FOR EACH ROW EXECUTE FUNCTION update_user_points();

-- =============================================
-- SEED DATA
-- =============================================

-- Insert default badges
INSERT INTO badges (slug, name, description, icon, points_value) VALUES
    ('jungfrufard', 'Jungfrufärd', 'Din första skeppning någonsin', 'anchor', 2),
    ('dubbellast', 'Dubbellast', 'Två skeppningar samma månad', 'stack', 2),
    ('hattrick', 'Hattrick', 'Tre skeppningar samma månad', 'trophy', 5),
    ('kapten', 'Kapten', 'Fem skeppningar samma månad', 'crown', 10),
    ('ai-arkitekt', 'AI-Arkitekt', 'Skeppat projekt med AI-tagg', 'robot', 2),
    ('streak-3', '3-Månaders Streak', 'Skeppat tre månader i rad', 'fire', 5),
    ('early-bird', 'Early Bird', 'Skeppat inom första 7 dagarna', 'bird', 2),
    ('open-source', 'Open Source Hero', 'Delat repo-länk', 'git-branch', 2);

-- Insert current batch
INSERT INTO batches (month, theme, description, starts_at, ends_at, is_active) VALUES
    ('2026-01', 'Fri Tema', 'Januari 2026 - Bygg vad du vill!', '2026-01-01 00:00:00+00', '2026-01-31 23:59:59+00', true);

-- =============================================
-- VIEWS (för enklare queries)
-- =============================================

-- Leaderboard view
CREATE OR REPLACE VIEW leaderboard AS
SELECT
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.total_points,
    COUNT(s.id) as submission_count,
    ARRAY_AGG(DISTINCT b.slug) FILTER (WHERE b.slug IS NOT NULL) as badges
FROM profiles p
LEFT JOIN submissions s ON p.id = s.user_id
LEFT JOIN user_badges ub ON p.id = ub.user_id
LEFT JOIN badges b ON ub.badge_id = b.id
GROUP BY p.id, p.username, p.display_name, p.avatar_url, p.total_points
ORDER BY p.total_points DESC;

-- Recent submissions view
CREATE OR REPLACE VIEW recent_submissions AS
SELECT
    s.*,
    p.username,
    p.display_name,
    p.avatar_url
FROM submissions s
JOIN profiles p ON s.user_id = p.id
ORDER BY s.created_at DESC;
