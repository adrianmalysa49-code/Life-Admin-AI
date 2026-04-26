-- ============================================================
-- Life Admin AI — PostgreSQL Schema
-- Migration: 001_initial_schema.sql
-- ============================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- fuzzy search
CREATE EXTENSION IF NOT EXISTS "unaccent"; -- Polish chars in search

-- ============================================================
-- USERS
-- ============================================================
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clerk_id        TEXT UNIQUE NOT NULL,
    email           TEXT UNIQUE NOT NULL,
    full_name       TEXT,
    avatar_url      TEXT,
    plan            TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'premium', 'admin')),
    plan_expires_at TIMESTAMPTZ,
    stripe_customer_id TEXT UNIQUE,
    -- Limits tracking
    docs_count      INTEGER NOT NULL DEFAULT 0,
    ai_calls_month  INTEGER NOT NULL DEFAULT 0,
    ai_calls_reset  TIMESTAMPTZ NOT NULL DEFAULT DATE_TRUNC('month', NOW()) + INTERVAL '1 month',
    -- Preferences
    locale          TEXT NOT NULL DEFAULT 'pl',
    timezone        TEXT NOT NULL DEFAULT 'Europe/Warsaw',
    notifications_email BOOLEAN NOT NULL DEFAULT true,
    notifications_push  BOOLEAN NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_clerk_id ON users(clerk_id);
CREATE INDEX idx_users_email ON users(email);

-- ============================================================
-- DOCUMENT TYPES (lookup table)
-- ============================================================
CREATE TABLE document_types (
    id          SERIAL PRIMARY KEY,
    slug        TEXT UNIQUE NOT NULL,  -- 'invoice', 'mandate', 'contract', 'official_letter', etc.
    name_pl     TEXT NOT NULL,
    icon        TEXT,                  -- lucide icon name
    color       TEXT                   -- tailwind color class
);

INSERT INTO document_types (slug, name_pl, icon, color) VALUES
    ('invoice',          'Faktura / Rachunek',     'receipt',       'blue'),
    ('mandate',          'Mandat / Kara',          'alert-triangle','red'),
    ('contract',         'Umowa',                  'file-text',     'purple'),
    ('official_letter',  'Pismo urzędowe',         'building',      'orange'),
    ('tax',              'Dokument podatkowy',     'calculator',    'green'),
    ('insurance',        'Polisa ubezpieczeniowa', 'shield',        'teal'),
    ('medical',          'Dokument medyczny',      'heart-pulse',   'pink'),
    ('utility_bill',     'Rachunek za media',      'zap',           'yellow'),
    ('bank',             'Dokument bankowy',       'landmark',      'slate'),
    ('complaint',        'Reklamacja',             'message-square','amber'),
    ('court',            'Pismo sądowe',           'scale',         'red'),
    ('other',            'Inny',                   'file',          'gray');

-- ============================================================
-- DOCUMENTS (core entity)
-- ============================================================
CREATE TABLE documents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type_id         INTEGER REFERENCES document_types(id),

    -- File info
    original_name   TEXT NOT NULL,
    storage_path    TEXT NOT NULL,          -- Supabase Storage path
    storage_bucket  TEXT NOT NULL DEFAULT 'documents',
    file_size       INTEGER,                -- bytes
    mime_type       TEXT,
    encryption_iv   TEXT,                   -- AES-256 IV (stored as hex)

    -- Content
    raw_text        TEXT,                   -- OCR output
    ocr_confidence  DECIMAL(5,2),           -- 0-100%
    ocr_engine      TEXT,                   -- 'tesseract' | 'google_vision'

    -- AI Analysis
    is_analyzed     BOOLEAN NOT NULL DEFAULT false,
    analysis_summary    TEXT,               -- Plain language summary
    analysis_risks      JSONB,              -- [{level: 'high', description: '...'}]
    analysis_actions    JSONB,              -- [{action: '...', priority: 'urgent'}]
    analysis_amounts    JSONB,              -- [{label: 'Kwota do zapłaty', value: 1234.56, currency: 'PLN'}]
    analysis_parties    JSONB,              -- [{role: 'sender', name: '...', address: '...'}]
    analysis_raw        JSONB,              -- Full Claude response

    -- Status
    status          TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'archived', 'deleted')),
    is_starred      BOOLEAN NOT NULL DEFAULT false,
    notes           TEXT,

    -- FTS vector
    search_vector   TSVECTOR,

    -- Metadata
    document_date   DATE,                   -- data na dokumencie
    issuer          TEXT,                   -- wystawca (ZUS, US, T-Mobile...)
    reference_number TEXT,                  -- numer referencyjny/sprawy

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_documents_user_id ON documents(user_id);
CREATE INDEX idx_documents_type_id ON documents(type_id);
CREATE INDEX idx_documents_status ON documents(status);
CREATE INDEX idx_documents_created_at ON documents(created_at DESC);
CREATE INDEX idx_documents_search_vector ON documents USING GIN(search_vector);
CREATE INDEX idx_documents_issuer ON documents(user_id, issuer);

-- Auto-update search vector
CREATE OR REPLACE FUNCTION documents_search_vector_update() RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector :=
        SETWEIGHT(TO_TSVECTOR('polish', COALESCE(NEW.original_name, '')), 'A') ||
        SETWEIGHT(TO_TSVECTOR('polish', COALESCE(NEW.analysis_summary, '')), 'B') ||
        SETWEIGHT(TO_TSVECTOR('polish', COALESCE(NEW.raw_text, '')), 'C') ||
        SETWEIGHT(TO_TSVECTOR('polish', COALESCE(NEW.issuer, '')), 'A') ||
        SETWEIGHT(TO_TSVECTOR('polish', COALESCE(NEW.notes, '')), 'B');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER documents_search_vector_trigger
    BEFORE INSERT OR UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION documents_search_vector_update();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER documents_updated_at
    BEFORE UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- TAGS
-- ============================================================
CREATE TABLE tags (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    color       TEXT NOT NULL DEFAULT '#6366f1',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, name)
);

CREATE TABLE document_tags (
    document_id UUID REFERENCES documents(id) ON DELETE CASCADE,
    tag_id      UUID REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (document_id, tag_id)
);

-- ============================================================
-- DEADLINES
-- ============================================================
CREATE TABLE deadlines (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id     UUID REFERENCES documents(id) ON DELETE SET NULL,

    title           TEXT NOT NULL,
    description     TEXT,
    due_date        TIMESTAMPTZ NOT NULL,
    category        TEXT CHECK (category IN (
                        'payment', 'response', 'appeal', 'renewal',
                        'tax', 'insurance', 'court', 'other'
                    )),
    priority        TEXT NOT NULL DEFAULT 'medium'
                        CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'completed', 'overdue', 'cancelled')),

    -- Notification settings
    notify_at       TIMESTAMPTZ[],          -- array of notification times
    notified_at     TIMESTAMPTZ[],          -- when actually sent
    is_recurring    BOOLEAN NOT NULL DEFAULT false,
    recurrence_rule TEXT,                   -- iCal RRULE format

    amount          DECIMAL(12,2),          -- if payment deadline
    currency        TEXT DEFAULT 'PLN',

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_deadlines_user_id ON deadlines(user_id);
CREATE INDEX idx_deadlines_due_date ON deadlines(due_date);
CREATE INDEX idx_deadlines_status ON deadlines(status);
CREATE INDEX idx_deadlines_priority ON deadlines(priority);

CREATE TRIGGER deadlines_updated_at
    BEFORE UPDATE ON deadlines
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- BILLS (rachunki cykliczne)
-- ============================================================
CREATE TABLE bills (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    name            TEXT NOT NULL,          -- "T-Mobile", "Orange Energia"
    category        TEXT CHECK (category IN (
                        'phone', 'internet', 'electricity', 'gas', 'water',
                        'rent', 'insurance', 'subscription', 'tax', 'other'
                    )),
    provider        TEXT,
    account_number  TEXT,                   -- numer konta / umowy

    amount          DECIMAL(12,2),
    currency        TEXT DEFAULT 'PLN',
    is_variable     BOOLEAN NOT NULL DEFAULT false,  -- zmienna kwota

    billing_cycle   TEXT NOT NULL DEFAULT 'monthly'
                        CHECK (billing_cycle IN ('weekly', 'monthly', 'quarterly', 'yearly')),
    next_due_date   DATE,
    last_paid_date  DATE,
    last_paid_amount DECIMAL(12,2),

    status          TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'paused', 'cancelled')),
    notes           TEXT,
    document_id     UUID REFERENCES documents(id) ON DELETE SET NULL,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bills_user_id ON bills(user_id);
CREATE INDEX idx_bills_next_due ON bills(next_due_date);

-- Bill payments history
CREATE TABLE bill_payments (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id     UUID NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount      DECIMAL(12,2) NOT NULL,
    currency    TEXT DEFAULT 'PLN',
    paid_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    notes       TEXT
);

-- ============================================================
-- GENERATED LETTERS (pisma AI)
-- ============================================================
CREATE TABLE letters (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id     UUID REFERENCES documents(id) ON DELETE SET NULL,

    letter_type     TEXT NOT NULL CHECK (letter_type IN (
                        'complaint',        -- reklamacja
                        'appeal',           -- odwołanie
                        'termination',      -- wypowiedzenie umowy
                        'official_request', -- wniosek urzędowy
                        'reply',            -- odpowiedź na pismo
                        'demand',           -- wezwanie do zapłaty
                        'other'
                    )),
    title           TEXT NOT NULL,

    -- Input context
    user_description TEXT NOT NULL,
    context_data    JSONB,                  -- dane kontekstowe (adresat, kwoty...)

    -- Generated content
    content         TEXT NOT NULL,          -- treść pisma
    content_html    TEXT,                   -- wersja HTML do druku
    language        TEXT NOT NULL DEFAULT 'pl',

    -- Metadata
    addressee       TEXT,                   -- adresat
    subject         TEXT,                   -- temat pisma
    is_sent         BOOLEAN NOT NULL DEFAULT false,
    sent_at         TIMESTAMPTZ,

    -- Versioning
    version         INTEGER NOT NULL DEFAULT 1,
    parent_id       UUID REFERENCES letters(id),  -- poprzednia wersja

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_letters_user_id ON letters(user_id);
CREATE INDEX idx_letters_type ON letters(letter_type);

-- ============================================================
-- GOVERNMENT ASSISTANT SESSIONS
-- ============================================================
CREATE TABLE assistant_sessions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    problem_description TEXT NOT NULL,
    messages        JSONB NOT NULL DEFAULT '[]',  -- chat history

    -- AI Response
    recommended_office  TEXT,
    recommended_docs    JSONB,          -- [{name, description, required}]
    action_steps        JSONB,          -- [{step, description, deadline}]
    key_deadlines       JSONB,

    status          TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'resolved', 'archived')),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- AUDIT LOGS (każda operacja na danych)
-- ============================================================
CREATE TABLE audit_logs (
    id          BIGSERIAL PRIMARY KEY,
    user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT NOT NULL,              -- 'document.upload', 'letter.generate', etc.
    resource    TEXT,                       -- 'document', 'letter', 'deadline'
    resource_id UUID,
    metadata    JSONB,                      -- dodatkowe dane
    ip_address  INET,
    user_agent  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
CREATE TABLE notifications (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        TEXT NOT NULL CHECK (type IN ('deadline', 'bill', 'system', 'ai_complete')),
    title       TEXT NOT NULL,
    body        TEXT,
    link        TEXT,                   -- URL do kliknięcia
    is_read     BOOLEAN NOT NULL DEFAULT false,
    sent_email  BOOLEAN NOT NULL DEFAULT false,
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id ON notifications(user_id, is_read);

-- ============================================================
-- SUBSCRIPTION / BILLING
-- ============================================================
CREATE TABLE subscriptions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stripe_sub_id       TEXT UNIQUE,
    stripe_price_id     TEXT,
    plan                TEXT NOT NULL CHECK (plan IN ('free', 'premium')),
    status              TEXT NOT NULL,      -- 'active', 'canceled', 'past_due'
    current_period_start TIMESTAMPTZ,
    current_period_end  TIMESTAMPTZ,
    cancel_at_period_end BOOLEAN DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE deadlines ENABLE ROW LEVEL SECURITY;
ALTER TABLE bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE letters ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE assistant_sessions ENABLE ROW LEVEL SECURITY;

-- RLS Policies (for Supabase direct access)
CREATE POLICY "Users see own documents"
    ON documents FOR ALL
    USING (user_id = (SELECT id FROM users WHERE clerk_id = current_setting('app.clerk_user_id', true)));

CREATE POLICY "Users see own deadlines"
    ON deadlines FOR ALL
    USING (user_id = (SELECT id FROM users WHERE clerk_id = current_setting('app.clerk_user_id', true)));

CREATE POLICY "Users see own bills"
    ON bills FOR ALL
    USING (user_id = (SELECT id FROM users WHERE clerk_id = current_setting('app.clerk_user_id', true)));

CREATE POLICY "Users see own letters"
    ON letters FOR ALL
    USING (user_id = (SELECT id FROM users WHERE clerk_id = current_setting('app.clerk_user_id', true)));

-- ============================================================
-- VIEWS (helpful)
-- ============================================================
CREATE VIEW upcoming_deadlines AS
    SELECT d.*, u.email, u.full_name
    FROM deadlines d
    JOIN users u ON d.user_id = u.id
    WHERE d.status = 'pending'
      AND d.due_date BETWEEN NOW() AND NOW() + INTERVAL '7 days'
    ORDER BY d.due_date ASC;

CREATE VIEW overdue_deadlines AS
    SELECT d.*, u.email, u.full_name
    FROM deadlines d
    JOIN users u ON d.user_id = u.id
    WHERE d.status = 'pending'
      AND d.due_date < NOW()
    ORDER BY d.due_date ASC;

CREATE VIEW user_stats AS
    SELECT
        u.id,
        u.clerk_id,
        u.plan,
        COUNT(DISTINCT doc.id) AS total_documents,
        COUNT(DISTINCT dl.id) FILTER (WHERE dl.status = 'pending') AS pending_deadlines,
        COUNT(DISTINCT dl.id) FILTER (WHERE dl.status = 'pending' AND dl.due_date < NOW() + INTERVAL '7 days') AS urgent_deadlines,
        COUNT(DISTINCT b.id) FILTER (WHERE b.status = 'active') AS active_bills,
        COUNT(DISTINCT l.id) AS total_letters
    FROM users u
    LEFT JOIN documents doc ON doc.user_id = u.id AND doc.status = 'active'
    LEFT JOIN deadlines dl ON dl.user_id = u.id
    LEFT JOIN bills b ON b.user_id = u.id
    LEFT JOIN letters l ON l.user_id = u.id
    GROUP BY u.id;

-- ============================================================
-- FUNCTIONS
-- ============================================================

-- Auto-mark overdue deadlines
CREATE OR REPLACE FUNCTION mark_overdue_deadlines() RETURNS void AS $$
BEGIN
    UPDATE deadlines
    SET status = 'overdue', updated_at = NOW()
    WHERE status = 'pending'
      AND due_date < NOW() - INTERVAL '1 day';
END;
$$ LANGUAGE plpgsql;

-- Reset monthly AI call counter
CREATE OR REPLACE FUNCTION reset_monthly_ai_calls() RETURNS void AS $$
BEGIN
    UPDATE users
    SET ai_calls_month = 0,
        ai_calls_reset = DATE_TRUNC('month', NOW()) + INTERVAL '1 month'
    WHERE ai_calls_reset <= NOW();
END;
$$ LANGUAGE plpgsql;

-- Increment AI calls (returns false if limit reached)
CREATE OR REPLACE FUNCTION increment_ai_calls(p_user_id UUID) RETURNS BOOLEAN AS $$
DECLARE
    v_plan TEXT;
    v_calls INTEGER;
    v_limit INTEGER;
BEGIN
    SELECT plan, ai_calls_month INTO v_plan, v_calls
    FROM users WHERE id = p_user_id;

    v_limit := CASE v_plan
        WHEN 'free'    THEN 5
        WHEN 'premium' THEN 999999
        WHEN 'admin'   THEN 999999
        ELSE 5
    END;

    IF v_calls >= v_limit THEN
        RETURN FALSE;
    END IF;

    UPDATE users SET ai_calls_month = ai_calls_month + 1 WHERE id = p_user_id;
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
