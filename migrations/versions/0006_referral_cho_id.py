"""referral cho_id

Revision ID: 0006
Revises: 0005
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = '0006'
down_revision = '0005'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Nullable: there's no way to know who sent referrals made before this column.
    op.add_column('referrals', sa.Column('cho_id', sa.Integer(), nullable=True))
    op.create_foreign_key('fk_referrals_cho_id_chos', 'referrals', 'chos', ['cho_id'], ['id'])


def downgrade() -> None:
    op.drop_constraint('fk_referrals_cho_id_chos', 'referrals', type_='foreignkey')
    op.drop_column('referrals', 'cho_id')
