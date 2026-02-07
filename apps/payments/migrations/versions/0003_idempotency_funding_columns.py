from alembic import op
import sqlalchemy as sa
import os

# revision identifiers, used by Alembic.
revision = '0003_idempotency_funding_columns'
down_revision = '0002_ledger'
branch_labels = None
depends_on = None


def _schema():
    return os.getenv('DB_SCHEMA')


def _has_column(bind, table: str, column: str, schema: str | None) -> bool:
    insp = sa.inspect(bind)
    cols = [col['name'] for col in insp.get_columns(table, schema=schema)]
    return column in cols


def upgrade() -> None:
    schema = _schema()
    bind = op.get_bind()
    # topup_vouchers.funding_wallet_id
    if not _has_column(bind, 'topup_vouchers', 'funding_wallet_id', schema):
        op.add_column('topup_vouchers', sa.Column('funding_wallet_id', sa.String(length=36), nullable=True), schema=schema)
    # idempotency enriched columns
    for col, col_type in [
        ('amount_cents', sa.BigInteger()),
        ('currency', sa.String(length=3)),
        ('wallet_id', sa.String(length=36)),
        ('balance_cents', sa.BigInteger()),
    ]:
        if not _has_column(bind, 'idempotency', col, schema):
            op.add_column('idempotency', sa.Column(col, col_type, nullable=True), schema=schema)


def downgrade() -> None:
    schema = _schema()
    bind = op.get_bind()
    # Drop in reverse order if present
    for col in ['balance_cents', 'wallet_id', 'currency', 'amount_cents']:
        if _has_column(bind, 'idempotency', col, schema):
            op.drop_column('idempotency', col, schema=schema)
    if _has_column(bind, 'topup_vouchers', 'funding_wallet_id', schema):
        op.drop_column('topup_vouchers', 'funding_wallet_id', schema=schema)
