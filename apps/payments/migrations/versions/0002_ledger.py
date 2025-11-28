from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision = '0002_ledger'
down_revision = '0001_initial'
branch_labels = None
depends_on = None


def _schema():
    return os.getenv('DB_SCHEMA')


def upgrade() -> None:
    schema = _schema()
    op.create_table(
        'ledger_entries',
        sa.Column('id', sa.String(length=36), primary_key=True),
        sa.Column('wallet_id', sa.String(length=36), nullable=True),
        sa.Column('amount_cents', sa.BigInteger(), nullable=False),
        sa.Column('txn_id', sa.String(length=36), nullable=True),
        sa.Column('description', sa.String(length=255), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
        schema=schema
    )
    op.create_index('ix_ledger_wallet_created', 'ledger_entries', ['wallet_id', 'created_at'], unique=False, schema=schema)


def downgrade() -> None:
    schema = _schema()
    op.drop_index('ix_ledger_wallet_created', table_name='ledger_entries', schema=schema)
    op.drop_table('ledger_entries', schema=schema)

