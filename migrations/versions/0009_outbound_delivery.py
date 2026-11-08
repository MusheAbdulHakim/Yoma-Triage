"""outbound message delivery reports

Revision ID: 0009
Revises: 0008
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = '0009'
down_revision = '0008'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'outbound_messages', sa.Column('provider_message_id', sa.String(length=64), nullable=True)
    )
    op.add_column(
        'outbound_messages', sa.Column('delivery_status', sa.String(length=32), nullable=True)
    )
    op.add_column(
        'outbound_messages',
        sa.Column('delivery_updated_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        op.f('ix_outbound_messages_provider_message_id'),
        'outbound_messages',
        ['provider_message_id'],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_outbound_messages_provider_message_id'), table_name='outbound_messages')
    op.drop_column('outbound_messages', 'delivery_updated_at')
    op.drop_column('outbound_messages', 'delivery_status')
    op.drop_column('outbound_messages', 'provider_message_id')
