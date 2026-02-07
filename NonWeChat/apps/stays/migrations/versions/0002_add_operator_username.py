from alembic import op
import sqlalchemy as sa

revision = '0002_add_operator_username'
down_revision = '0001_initial_stays'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add nullable username column, then unique index
    with op.batch_alter_table('operators') as batch_op:
        batch_op.add_column(sa.Column('username', sa.String(length=64), nullable=True))
    try:
        op.create_unique_constraint('ux_operators_username', 'operators', ['username'])
    except Exception:
        # Some DBs may not support unique constraint on nullable; fall back to unique index
        try:
            op.create_index('ux_operators_username', 'operators', ['username'], unique=True)
        except Exception:
            pass


def downgrade() -> None:
    try:
        op.drop_constraint('ux_operators_username', 'operators')
    except Exception:
        try:
            op.drop_index('ux_operators_username', table_name='operators')
        except Exception:
            pass
    with op.batch_alter_table('operators') as batch_op:
        batch_op.drop_column('username')

