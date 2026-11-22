"""
EvenBill Database Cross-Platform Types
Provides database column types compatible with both PostgreSQL and SQLite.
"""

from sqlalchemy import String
from sqlalchemy.dialects import postgresql

# Cross-platform UUID type: native UUID on PostgreSQL, VARCHAR(36) on SQLite
UID_TYPE = String(36).with_variant(postgresql.UUID(as_uuid=False), "postgresql")
