-- KomCS PJB PostgreSQL DDL (Hardening + Statistics + Dynamic Target Update)

CREATE TABLE branches (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE,
    target_min NUMERIC(18,2) NOT NULL CHECK (target_min >= 0),
    target_max NUMERIC(18,2) NOT NULL CHECK (target_max >= target_min),
    n8n_endpoint TEXT NOT NULL,
    n8n_api_key_hash TEXT,
    n8n_signature_secret TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(80) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    nama VARCHAR(120) NOT NULL,
    role VARCHAR(10) NOT NULL CHECK (role IN ('ADMIN', 'HRD', 'CS')),
    branch_id BIGINT REFERENCES branches(id) ON UPDATE CASCADE ON DELETE SET NULL,
    faktor_pengali NUMERIC(4,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT users_branch_required_for_non_admin CHECK (
      (role = 'ADMIN' AND branch_id IS NULL)
      OR (role IN ('HRD', 'CS') AND branch_id IS NOT NULL)
    ),
    CONSTRAINT users_cs_factor_check CHECK (
      (role <> 'CS' AND faktor_pengali IS NULL)
      OR (role = 'CS' AND faktor_pengali IN (0.75, 0.50, 0.25))
    )
);

CREATE TABLE branch_target_override (
    id BIGSERIAL PRIMARY KEY,
    branch_id BIGINT NOT NULL REFERENCES branches(id) ON UPDATE CASCADE ON DELETE CASCADE,
    month SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),
    year SMALLINT NOT NULL CHECK (year BETWEEN 2000 AND 9999),
    target_min NUMERIC(18,2) NOT NULL CHECK (target_min >= 0),
    target_max NUMERIC(18,2) NOT NULL CHECK (target_max >= target_min),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT bto_unique_branch_period UNIQUE (branch_id, month, year)
);

CREATE TABLE period_lock (
    id BIGSERIAL PRIMARY KEY,
    branch_id BIGINT NOT NULL REFERENCES branches(id) ON UPDATE CASCADE ON DELETE CASCADE,
    month SMALLINT NOT NULL CHECK (month BETWEEN 1 AND 12),
    year SMALLINT NOT NULL CHECK (year BETWEEN 2000 AND 9999),
    status VARCHAR(10) NOT NULL CHECK (status IN ('OPEN', 'LOCKED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT period_lock_unique_branch_period UNIQUE (branch_id, month, year)
);

CREATE TABLE omzet (
    id BIGSERIAL PRIMARY KEY,
    branch_id BIGINT NOT NULL REFERENCES branches(id) ON UPDATE CASCADE ON DELETE CASCADE,
    tanggal DATE NOT NULL,
    cash NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (cash >= 0),
    piutang NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (piutang >= 0),
    total NUMERIC(18,2) NOT NULL CHECK (total >= 0),
    source VARCHAR(20) NOT NULL DEFAULT 'n8n',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT omzet_unique_branch_date UNIQUE (branch_id, tanggal)
);

CREATE TABLE attendance (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    tanggal DATE NOT NULL,
    status NUMERIC(2,1) NOT NULL CHECK (status IN (1.0, 0.5, 0.0)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT attendance_unique_user_date UNIQUE (user_id, tanggal)
);

CREATE TABLE commissions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    tanggal DATE NOT NULL,
    omzet_id BIGINT NOT NULL REFERENCES omzet(id) ON UPDATE CASCADE ON DELETE CASCADE,
    nominal NUMERIC(18,2) NOT NULL CHECK (nominal >= 0),
    status VARCHAR(10) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'FINAL', 'LOCKED')),
    source VARCHAR(30) NOT NULL DEFAULT 'auto_recalculate',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT commissions_unique_user_date UNIQUE (user_id, tanggal)
);

CREATE TABLE commission_mutations (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    tanggal DATE NOT NULL,
    tipe VARCHAR(10) NOT NULL CHECK (tipe IN ('masuk', 'keluar')),
    nominal NUMERIC(18,2) NOT NULL CHECK (nominal >= 0),
    saldo_after NUMERIC(18,2) NOT NULL,
    is_auto BOOLEAN NOT NULL DEFAULT FALSE,
    reference_type VARCHAR(30),
    reference_id BIGINT,
    keterangan TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE withdrawal_requests (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    tanggal DATE NOT NULL,
    nominal NUMERIC(18,2) NOT NULL CHECK (nominal > 0),
    status VARCHAR(10) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    rejection_reason TEXT,
    approved_by BIGINT REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT withdrawal_approved_fields_chk CHECK (
      (status = 'approved' AND approved_by IS NOT NULL AND approved_at IS NOT NULL)
      OR (status IN ('pending', 'rejected'))
    )
);

CREATE TABLE commission_debts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE,
    tanggal DATE NOT NULL,
    nominal NUMERIC(18,2) NOT NULL CHECK (nominal > 0),
    status VARCHAR(10) NOT NULL CHECK (status IN ('active', 'resolved')),
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL,
    action VARCHAR(80) NOT NULL,
    entity VARCHAR(80) NOT NULL,
    entity_id BIGINT,
    before_data JSONB,
    after_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Performance indexes
CREATE INDEX idx_users_branch_id ON users(branch_id);
CREATE INDEX idx_bto_branch_period ON branch_target_override(branch_id, year, month);
CREATE INDEX idx_period_lock_branch_period ON period_lock(branch_id, year, month);
CREATE INDEX idx_omzet_branch_tanggal ON omzet(branch_id, tanggal);
CREATE INDEX idx_attendance_user_tanggal ON attendance(user_id, tanggal);
CREATE INDEX idx_commissions_user_tanggal ON commissions(user_id, tanggal);
CREATE INDEX idx_commissions_status ON commissions(status);
CREATE INDEX idx_mutations_user_tanggal ON commission_mutations(user_id, tanggal);
CREATE INDEX idx_mutations_ref ON commission_mutations(reference_type, reference_id);
CREATE INDEX idx_withdrawal_status ON withdrawal_requests(status);
CREATE INDEX idx_debts_user_status ON commission_debts(user_id, status);
CREATE INDEX idx_audit_entity_created ON audit_logs(entity, created_at);

-- Optional trigger: keep omzet.total synchronized
CREATE OR REPLACE FUNCTION set_omzet_total()
RETURNS TRIGGER AS $$
BEGIN
    NEW.total := COALESCE(NEW.cash,0) + COALESCE(NEW.piutang,0);
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_omzet_total
BEFORE INSERT OR UPDATE ON omzet
FOR EACH ROW
EXECUTE FUNCTION set_omzet_total();

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_touch_attendance
BEFORE UPDATE ON attendance
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_touch_commissions
BEFORE UPDATE ON commissions
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

-- Hard limit + valid combination rule for CS factor per branch:
-- max 2 CS per branch, and if 2 CS exist, factors must be 50:50 or 75:25.
CREATE OR REPLACE FUNCTION enforce_cs_factor_pair()
RETURNS TRIGGER AS $$
DECLARE
    cs_count INTEGER;
    factor_sum NUMERIC(4,2);
    factor_min NUMERIC(4,2);
    factor_max NUMERIC(4,2);
BEGIN
    IF NEW.role <> 'CS' THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(*), COALESCE(SUM(faktor_pengali),0), MIN(faktor_pengali), MAX(faktor_pengali)
      INTO cs_count, factor_sum, factor_min, factor_max
    FROM users
    WHERE role='CS' AND branch_id = NEW.branch_id
      AND (TG_OP = 'INSERT' OR id <> NEW.id);

    cs_count := cs_count + 1;
    factor_sum := factor_sum + NEW.faktor_pengali;
    factor_min := LEAST(COALESCE(factor_min, NEW.faktor_pengali), NEW.faktor_pengali);
    factor_max := GREATEST(COALESCE(factor_max, NEW.faktor_pengali), NEW.faktor_pengali);

    IF cs_count > 2 THEN
        RAISE EXCEPTION 'Maksimal 2 CS per cabang';
    END IF;

    IF cs_count = 2 THEN
        IF NOT (
            (factor_sum = 1.00 AND factor_min = 0.50 AND factor_max = 0.50)
            OR
            (factor_sum = 1.00 AND factor_min = 0.25 AND factor_max = 0.75)
        ) THEN
            RAISE EXCEPTION 'Kombinasi faktor CS harus 50:50 atau 75:25';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_cs_factor_pair
BEFORE INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION enforce_cs_factor_pair();
