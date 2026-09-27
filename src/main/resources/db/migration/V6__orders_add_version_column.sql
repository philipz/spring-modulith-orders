SET search_path TO orders;

-- Optimistic locking version for orders.orders (issue #58).
-- Existing rows are migrated with version 0 so already persisted orders stay loadable.
ALTER TABLE orders
    ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 0;
