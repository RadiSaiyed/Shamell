from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision = '0001_initial'
down_revision = None
branch_labels = None
depends_on = None


def _schema():
    return os.getenv('DB_SCHEMA')


def upgrade() -> None:
    schema = _schema()
    op.create_table(
        'users',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('phone', sa.String(length=32), nullable=False, unique=True),
        sa.Column('kyc_level', sa.Integer(), nullable=False, server_default='0'),
        schema=schema
    )
    op.create_table(
        'wallets',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('user_id', sa.String(length=36), nullable=False, unique=True),
        sa.Column('balance_cents', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('currency', sa.String(length=3), nullable=False, server_default='SYP'),
        sa.ForeignKeyConstraint(['user_id'], [f"{schema}.users.id" if schema else 'users.id']),
        schema=schema
    )
    op.create_table(
        'txns',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('from_wallet_id', sa.String(length=36), nullable=True),
        sa.Column('to_wallet_id', sa.String(length=36), nullable=False),
        sa.Column('amount_cents', sa.BigInteger(), nullable=False),
        sa.Column('kind', sa.String(length=16), nullable=False),
        sa.Column('fee_cents', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        schema=schema
    )
    op.create_table(
        'idempotency',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('ikey', sa.String(length=128), nullable=False, unique=True),
        sa.Column('endpoint', sa.String(length=32), nullable=False),
        sa.Column('txn_id', sa.String(length=36), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        schema=schema
    )


def downgrade() -> None:
    schema = _schema()
    op.drop_table('idempotency', schema=schema)
    op.drop_table('txns', schema=schema)
    op.drop_table('wallets', schema=schema)
    op.drop_table('users', schema=schema)

