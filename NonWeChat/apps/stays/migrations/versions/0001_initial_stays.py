from alembic import op
import sqlalchemy as sa

revision = '0001_initial_stays'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'operators',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('name', sa.String(length=160), nullable=False),
        sa.Column('phone', sa.String(length=32), nullable=False),
        sa.Column('city', sa.String(length=64), nullable=True),
        sa.Column('wallet_id', sa.String(length=64), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('(CURRENT_TIMESTAMP)')),
    )

    op.create_table(
        'operator_tokens',
        sa.Column('token', sa.String(length=64), primary_key=True),
        sa.Column('operator_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('(CURRENT_TIMESTAMP)')),
    )

    op.create_table(
        'idempotency',
        sa.Column('key', sa.String(length=120), primary_key=True),
        sa.Column('ref_id', sa.String(length=64), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('(CURRENT_TIMESTAMP)')),
    )

    op.create_table(
        'listings',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('city', sa.String(length=64), nullable=True),
        sa.Column('address', sa.String(length=255), nullable=True),
        sa.Column('price_per_night_cents', sa.BigInteger(), nullable=False),
        sa.Column('currency', sa.String(length=3), nullable=False, server_default='SYP'),
        sa.Column('operator_id', sa.Integer(), nullable=True),
        sa.Column('owner_wallet_id', sa.String(length=64), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('(CURRENT_TIMESTAMP)')),
    )

    op.create_table(
        'bookings',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('listing_id', sa.Integer(), nullable=False),
        sa.Column('guest_name', sa.String(length=120), nullable=True),
        sa.Column('guest_phone', sa.String(length=32), nullable=True),
        sa.Column('guest_wallet_id', sa.String(length=36), nullable=True),
        sa.Column('from_date', sa.Date(), nullable=True),
        sa.Column('to_date', sa.Date(), nullable=True),
        sa.Column('nights', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('amount_cents', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('status', sa.String(length=16), nullable=False, server_default='requested'),
        sa.Column('payments_txn_id', sa.String(length=64), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('(CURRENT_TIMESTAMP)')),
    )


def downgrade() -> None:
    op.drop_table('bookings')
    op.drop_table('listings')
    op.drop_table('idempotency')
    op.drop_table('operator_tokens')
    op.drop_table('operators')

