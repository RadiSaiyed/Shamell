from alembic import op
import sqlalchemy as sa

revision = '0003_room_rate_restrictions'
down_revision = '0002_add_operator_username'
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table('room_rates') as batch_op:
        batch_op.add_column(sa.Column('min_los', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('max_los', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('cta', sa.Integer(), nullable=False, server_default='0'))
        batch_op.add_column(sa.Column('ctd', sa.Integer(), nullable=False, server_default='0'))


def downgrade() -> None:
    with op.batch_alter_table('room_rates') as batch_op:
        batch_op.drop_column('ctd')
        batch_op.drop_column('cta')
        batch_op.drop_column('max_los')
        batch_op.drop_column('min_los')

