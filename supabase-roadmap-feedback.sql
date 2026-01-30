-- =============================================
-- SKEPPA.NU - ROADMAP FEEDBACK SYSTEM
-- Kör i: https://supabase.com/dashboard/project/qjouribmhkkhqdsieprs/sql
-- =============================================

-- =============================================
-- 1. ROADMAP_ITEMS - Befintliga roadmap-items
-- =============================================
CREATE TABLE IF NOT EXISTS roadmap_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'planned' CHECK (status IN ('planned', 'in_progress', 'completed', 'considering')),
    category TEXT DEFAULT 'feature' CHECK (category IN ('feature', 'improvement', 'bug', 'community')),
    priority INTEGER DEFAULT 0,
    votes_up INTEGER DEFAULT 0,
    votes_down INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_roadmap_items_status ON roadmap_items(status);
CREATE INDEX IF NOT EXISTS idx_roadmap_items_priority ON roadmap_items(priority DESC);

-- RLS
ALTER TABLE roadmap_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read roadmap_items" ON roadmap_items FOR SELECT USING (true);

-- =============================================
-- 2. ROADMAP_VOTES - User votes (👍/👎)
-- =============================================
CREATE TABLE IF NOT EXISTS roadmap_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID NOT NULL REFERENCES roadmap_items(id) ON DELETE CASCADE,
    user_fingerprint TEXT NOT NULL,
    vote INTEGER NOT NULL CHECK (vote IN (-1, 1)), -- -1 = down, 1 = up
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- En röst per user per item
    UNIQUE(item_id, user_fingerprint)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_roadmap_votes_item ON roadmap_votes(item_id);
CREATE INDEX IF NOT EXISTS idx_roadmap_votes_fingerprint ON roadmap_votes(user_fingerprint);

-- RLS
ALTER TABLE roadmap_votes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read roadmap_votes" ON roadmap_votes FOR SELECT USING (true);
CREATE POLICY "Anyone can insert roadmap_votes" ON roadmap_votes FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can update own votes" ON roadmap_votes FOR UPDATE USING (true);
CREATE POLICY "Anyone can delete own votes" ON roadmap_votes FOR DELETE USING (true);

-- =============================================
-- 3. ROADMAP_SUGGESTIONS - User suggestions
-- =============================================
CREATE TABLE IF NOT EXISTS roadmap_suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_fingerprint TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'implemented')),
    upvotes INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_roadmap_suggestions_status ON roadmap_suggestions(status);
CREATE INDEX IF NOT EXISTS idx_roadmap_suggestions_upvotes ON roadmap_suggestions(upvotes DESC);

-- RLS
ALTER TABLE roadmap_suggestions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read approved suggestions" ON roadmap_suggestions FOR SELECT USING (status IN ('approved', 'implemented') OR true);
CREATE POLICY "Anyone can insert suggestions" ON roadmap_suggestions FOR INSERT WITH CHECK (true);

-- =============================================
-- 4. SUGGESTION_VOTES - Votes on suggestions
-- =============================================
CREATE TABLE IF NOT EXISTS suggestion_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    suggestion_id UUID NOT NULL REFERENCES roadmap_suggestions(id) ON DELETE CASCADE,
    user_fingerprint TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(suggestion_id, user_fingerprint)
);

-- Index
CREATE INDEX IF NOT EXISTS idx_suggestion_votes_suggestion ON suggestion_votes(suggestion_id);

-- RLS
ALTER TABLE suggestion_votes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read suggestion_votes" ON suggestion_votes FOR SELECT USING (true);
CREATE POLICY "Anyone can insert suggestion_votes" ON suggestion_votes FOR INSERT WITH CHECK (true);
CREATE POLICY "Anyone can delete own suggestion_votes" ON suggestion_votes FOR DELETE USING (true);

-- =============================================
-- 5. TRIGGER: Update vote counts on roadmap_items
-- =============================================
CREATE OR REPLACE FUNCTION update_roadmap_vote_counts()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE roadmap_items SET
            votes_up = votes_up + CASE WHEN NEW.vote = 1 THEN 1 ELSE 0 END,
            votes_down = votes_down + CASE WHEN NEW.vote = -1 THEN 1 ELSE 0 END,
            updated_at = NOW()
        WHERE id = NEW.item_id;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE roadmap_items SET
            votes_up = votes_up - CASE WHEN OLD.vote = 1 THEN 1 ELSE 0 END + CASE WHEN NEW.vote = 1 THEN 1 ELSE 0 END,
            votes_down = votes_down - CASE WHEN OLD.vote = -1 THEN 1 ELSE 0 END + CASE WHEN NEW.vote = -1 THEN 1 ELSE 0 END,
            updated_at = NOW()
        WHERE id = NEW.item_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE roadmap_items SET
            votes_up = votes_up - CASE WHEN OLD.vote = 1 THEN 1 ELSE 0 END,
            votes_down = votes_down - CASE WHEN OLD.vote = -1 THEN 1 ELSE 0 END,
            updated_at = NOW()
        WHERE id = OLD.item_id;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_roadmap_vote_counts ON roadmap_votes;
CREATE TRIGGER trigger_roadmap_vote_counts
AFTER INSERT OR UPDATE OR DELETE ON roadmap_votes
FOR EACH ROW EXECUTE FUNCTION update_roadmap_vote_counts();

-- =============================================
-- 6. TRIGGER: Update suggestion upvotes
-- =============================================
CREATE OR REPLACE FUNCTION update_suggestion_upvotes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE roadmap_suggestions SET upvotes = upvotes + 1 WHERE id = NEW.suggestion_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE roadmap_suggestions SET upvotes = upvotes - 1 WHERE id = OLD.suggestion_id;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_suggestion_upvotes ON suggestion_votes;
CREATE TRIGGER trigger_suggestion_upvotes
AFTER INSERT OR DELETE ON suggestion_votes
FOR EACH ROW EXECUTE FUNCTION update_suggestion_upvotes();

-- =============================================
-- 7. INITIAL ROADMAP ITEMS (Seed data)
-- =============================================
INSERT INTO roadmap_items (title, description, status, category, priority) VALUES
    ('Team battles', 'Skapa team och tävla mot andra lag i månadsutmaningar', 'planned', 'feature', 10),
    ('Achievements & badges system', 'Fler badges baserat på aktivitet, streaks, och community-bidrag', 'in_progress', 'feature', 9),
    ('Discord integration', 'Koppla ditt Discord-konto för notiser och community-features', 'considering', 'feature', 7),
    ('Project comments', 'Kommentera och ge feedback på andras projekt', 'planned', 'community', 8),
    ('Weekly mini-challenges', 'Små utmaningar varje vecka utöver månadsutmaningen', 'considering', 'feature', 6),
    ('Mobile app', 'Native app för iOS och Android', 'planned', 'feature', 5),
    ('Dark mode improvements', 'Finjustera dark mode för bättre läsbarhet', 'in_progress', 'improvement', 4),
    ('AI-powered project feedback', 'Få automatisk feedback på ditt projekt via AI', 'considering', 'feature', 3)
ON CONFLICT DO NOTHING;

-- =============================================
-- 8. ENABLE REALTIME
-- =============================================
-- Run these in SQL Editor separately if needed:
-- ALTER PUBLICATION supabase_realtime ADD TABLE roadmap_items;
-- ALTER PUBLICATION supabase_realtime ADD TABLE roadmap_votes;
-- ALTER PUBLICATION supabase_realtime ADD TABLE roadmap_suggestions;
-- ALTER PUBLICATION supabase_realtime ADD TABLE suggestion_votes;

-- =============================================
-- DONE! Verifiera med:
-- SELECT * FROM roadmap_items ORDER BY priority DESC;
-- SELECT * FROM roadmap_votes;
-- SELECT * FROM roadmap_suggestions ORDER BY upvotes DESC;
-- =============================================
