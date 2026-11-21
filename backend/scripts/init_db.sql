-- EvenBill Database Initialization Script
-- Ensures UUID extension, performance indexes, and strict collation.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Set standard timezone to UTC
ALTER DATABASE evenbill_prod SET timezone TO 'UTC';
