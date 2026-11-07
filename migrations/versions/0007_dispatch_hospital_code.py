"""dispatch hospital_code

Revision ID: 0007
Revises: 0006
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = '0007'
down_revision = '0006'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Nullable: a dispatch whose hospital was told before this column has no code, and
    # its hospital can't CONFIRM or DIVERT by SMS. Arrival still completes it.
    op.add_column('dispatches', sa.Column('hospital_code', sa.String(length=8), nullable=True))
    op.create_index(
        op.f('ix_dispatches_hospital_code'), 'dispatches', ['hospital_code'], unique=False
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_dispatches_hospital_code'), table_name='dispatches')
    op.drop_column('dispatches', 'hospital_code')
