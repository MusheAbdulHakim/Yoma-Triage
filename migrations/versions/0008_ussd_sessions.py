"""ussd sessions

Revision ID: 0008
Revises: 0007
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = '0008'
down_revision = '0007'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'ussd_sessions',
        sa.Column('session_id', sa.String(length=64), nullable=False),
        sa.Column('phone', sa.String(length=32), nullable=False),
        sa.Column('mode', sa.String(length=16), nullable=False),
        sa.Column('ref', sa.Integer(), nullable=True),
        sa.Column('prefix', sa.String(length=32), nullable=False),
        sa.Column(
            'created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint('session_id'),
    )
    op.create_index(
        op.f('ix_ussd_sessions_created_at'), 'ussd_sessions', ['created_at'], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_ussd_sessions_created_at'), table_name='ussd_sessions')
    op.drop_table('ussd_sessions')
