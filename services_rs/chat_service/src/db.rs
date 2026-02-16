use sqlx::postgres::{PgPool, PgPoolOptions};

fn table_name(schema: &Option<String>, name: &str) -> String {
    match schema {
        Some(s) => format!("{s}.{name}"),
        None => name.to_string(),
    }
}

pub async fn connect(db_url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(10)
        .connect(db_url)
        .await
}

pub async fn ensure_schema(pool: &PgPool, db_schema: &Option<String>) -> Result<(), sqlx::Error> {
    if let Some(schema) = db_schema {
        let ddl = format!("CREATE SCHEMA IF NOT EXISTS {schema}");
        let _ = sqlx::query(&ddl).execute(pool).await;
    }

    let devices = table_name(db_schema, "devices");
    let device_auth = table_name(db_schema, "device_auth");
    let messages = table_name(db_schema, "messages");
    let groups = table_name(db_schema, "groups");
    let group_members = table_name(db_schema, "group_members");
    let group_messages = table_name(db_schema, "group_messages");
    let group_key_events = table_name(db_schema, "group_key_events");
    let device_key_events = table_name(db_schema, "device_key_events");
    let chat_identity_keys = table_name(db_schema, "chat_identity_keys");
    let chat_signed_prekeys = table_name(db_schema, "chat_signed_prekeys");
    let chat_one_time_prekeys = table_name(db_schema, "chat_one_time_prekeys");
    let chat_device_protocol_state = table_name(db_schema, "chat_device_protocol_state");
    let chat_mailboxes = table_name(db_schema, "chat_mailboxes");
    let chat_mailbox_messages = table_name(db_schema, "chat_mailbox_messages");
    let push_tokens = table_name(db_schema, "push_tokens");
    let contact_rules = table_name(db_schema, "contact_rules");
    let group_prefs = table_name(db_schema, "group_prefs");

    let ddls = [
        format!(
            "CREATE TABLE IF NOT EXISTS {devices} (\
             id VARCHAR(24) PRIMARY KEY,\
             public_key VARCHAR(255) NOT NULL,\
             key_version INTEGER NOT NULL DEFAULT 0,\
             name VARCHAR(120),\
             created_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {device_auth} (\
             device_id VARCHAR(24) PRIMARY KEY,\
             token_hash VARCHAR(64) NOT NULL,\
             rotated_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {messages} (\
             id VARCHAR(36) PRIMARY KEY,\
             sender_id VARCHAR(24) NOT NULL,\
             recipient_id VARCHAR(24) NOT NULL,\
             protocol_version VARCHAR(24) NOT NULL DEFAULT 'v1_legacy',\
             sender_pubkey VARCHAR(255) NOT NULL,\
             sender_dh_pub VARCHAR(255),\
             nonce_b64 VARCHAR(64) NOT NULL,\
             box_b64 VARCHAR(8192) NOT NULL,\
             created_at TEXT NOT NULL,\
             delivered_at TEXT,\
             read_at TEXT,\
             expire_at TEXT,\
             sealed_sender INTEGER NOT NULL DEFAULT 0,\
             sender_hint VARCHAR(64),\
             prev_key_id VARCHAR(64),\
             key_id VARCHAR(64)\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {groups} (\
             id VARCHAR(36) PRIMARY KEY,\
             name VARCHAR(120) NOT NULL,\
             creator_id VARCHAR(24) NOT NULL,\
             key_version INTEGER NOT NULL DEFAULT 0,\
             avatar_b64 TEXT,\
             avatar_mime VARCHAR(64),\
             created_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {group_members} (\
             group_id VARCHAR(36) NOT NULL,\
             device_id VARCHAR(24) NOT NULL,\
             role VARCHAR(20) NOT NULL DEFAULT 'member',\
             joined_at TEXT NOT NULL,\
             PRIMARY KEY (group_id, device_id)\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {group_messages} (\
             id VARCHAR(36) PRIMARY KEY,\
             group_id VARCHAR(36) NOT NULL,\
             sender_id VARCHAR(24) NOT NULL,\
             protocol_version VARCHAR(24) NOT NULL DEFAULT 'v1_legacy',\
             text VARCHAR(4096) NOT NULL DEFAULT '',\
             kind VARCHAR(20),\
             nonce_b64 VARCHAR(64),\
             box_b64 TEXT,\
             attachment_b64 TEXT,\
             attachment_mime VARCHAR(64),\
             voice_secs INTEGER,\
             created_at TEXT NOT NULL,\
             expire_at TEXT\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {group_key_events} (\
             group_id VARCHAR(36) NOT NULL,\
             version INTEGER NOT NULL,\
             actor_id VARCHAR(24) NOT NULL,\
             key_fp VARCHAR(64),\
             created_at TEXT NOT NULL,\
             PRIMARY KEY (group_id, version)\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {device_key_events} (\
             device_id VARCHAR(24) NOT NULL,\
             version INTEGER NOT NULL,\
             old_key_fp VARCHAR(64),\
             new_key_fp VARCHAR(64),\
             created_at TEXT NOT NULL,\
             PRIMARY KEY (device_id, version)\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {chat_identity_keys} (\
             device_id VARCHAR(24) PRIMARY KEY,\
             identity_key_b64 TEXT NOT NULL,\
             identity_signing_key_b64 TEXT,\
             updated_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {chat_signed_prekeys} (\
             device_id VARCHAR(24) PRIMARY KEY,\
             key_id BIGINT NOT NULL,\
             public_key_b64 TEXT NOT NULL,\
             signature_b64 TEXT NOT NULL,\
             updated_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {chat_one_time_prekeys} (\
             device_id VARCHAR(24) NOT NULL,\
             key_id BIGINT NOT NULL,\
             key_b64 TEXT NOT NULL,\
             created_at TEXT NOT NULL,\
             consumed_at TEXT,\
             PRIMARY KEY (device_id, key_id)\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {chat_device_protocol_state} (\
             device_id VARCHAR(24) PRIMARY KEY,\
             protocol_floor VARCHAR(24) NOT NULL DEFAULT 'v1_legacy',\
             supports_v2 INTEGER NOT NULL DEFAULT 0,\
             v2_only INTEGER NOT NULL DEFAULT 0,\
             updated_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {chat_mailboxes} (\
             token_hash VARCHAR(64) PRIMARY KEY,\
             owner_device_id VARCHAR(24) NOT NULL,\
             created_at TEXT NOT NULL,\
             rotated_at TEXT,\
             active INTEGER NOT NULL DEFAULT 1\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {chat_mailbox_messages} (\
             id VARCHAR(36) PRIMARY KEY,\
             token_hash VARCHAR(64) NOT NULL,\
             envelope_b64 TEXT NOT NULL,\
             sender_hint VARCHAR(64),\
             created_at TEXT NOT NULL,\
             expire_at TEXT,\
             consumed_at TEXT\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {push_tokens} (\
             token VARCHAR(512) PRIMARY KEY,\
             device_id VARCHAR(24) NOT NULL,\
             platform VARCHAR(30),\
             created_at TEXT NOT NULL,\
             last_seen_at TEXT NOT NULL\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {contact_rules} (\
             device_id VARCHAR(24) NOT NULL,\
             peer_id VARCHAR(24) NOT NULL,\
             blocked INTEGER NOT NULL DEFAULT 0,\
             hidden INTEGER NOT NULL DEFAULT 0,\
             muted INTEGER NOT NULL DEFAULT 0,\
             starred INTEGER NOT NULL DEFAULT 0,\
             pinned INTEGER NOT NULL DEFAULT 0,\
             created_at TEXT NOT NULL,\
             updated_at TEXT NOT NULL,\
             PRIMARY KEY (device_id, peer_id)\
             )"
        ),
        format!(
            "CREATE TABLE IF NOT EXISTS {group_prefs} (\
             device_id VARCHAR(24) NOT NULL,\
             group_id VARCHAR(36) NOT NULL,\
             muted INTEGER NOT NULL DEFAULT 0,\
             pinned INTEGER NOT NULL DEFAULT 0,\
             created_at TEXT NOT NULL,\
             updated_at TEXT NOT NULL,\
             PRIMARY KEY (device_id, group_id)\
             )"
        ),
        format!(
            "CREATE INDEX IF NOT EXISTS idx_messages_recipient_created ON {messages}(recipient_id, created_at)"
        ),
        format!(
            "CREATE INDEX IF NOT EXISTS idx_messages_sender_recipient ON {messages}(sender_id, recipient_id)"
        ),
        format!("CREATE INDEX IF NOT EXISTS idx_group_members_device ON {group_members}(device_id)"),
        format!(
            "CREATE INDEX IF NOT EXISTS idx_group_messages_group_created ON {group_messages}(group_id, created_at)"
        ),
        format!(
            "CREATE INDEX IF NOT EXISTS idx_chat_otk_available ON {chat_one_time_prekeys}(device_id, consumed_at, created_at)"
        ),
        format!(
            "CREATE INDEX IF NOT EXISTS idx_chat_mailboxes_owner_active ON {chat_mailboxes}(owner_device_id, active)"
        ),
        format!(
            "CREATE INDEX IF NOT EXISTS idx_chat_mailbox_messages_poll ON {chat_mailbox_messages}(token_hash, consumed_at, created_at)"
        ),
        format!("CREATE INDEX IF NOT EXISTS idx_push_tokens_device ON {push_tokens}(device_id)"),
        format!("CREATE INDEX IF NOT EXISTS idx_contact_rules_device ON {contact_rules}(device_id)"),
        format!("CREATE INDEX IF NOT EXISTS idx_group_prefs_device ON {group_prefs}(device_id)"),
    ];

    for ddl in ddls {
        let _ = sqlx::query(&ddl).execute(pool).await;
    }

    let _ = sqlx::query(&format!(
        "ALTER TABLE {messages} ADD COLUMN IF NOT EXISTS protocol_version VARCHAR(24) DEFAULT 'v1_legacy'"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "UPDATE {messages} SET protocol_version='v1_legacy' WHERE protocol_version IS NULL OR TRIM(protocol_version)=''"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {group_messages} ADD COLUMN IF NOT EXISTS protocol_version VARCHAR(24) DEFAULT 'v1_legacy'"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "UPDATE {group_messages} SET protocol_version='v1_legacy' WHERE protocol_version IS NULL OR TRIM(protocol_version)=''"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_device_protocol_state} ADD COLUMN IF NOT EXISTS protocol_floor VARCHAR(24) DEFAULT 'v1_legacy'"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_device_protocol_state} ADD COLUMN IF NOT EXISTS supports_v2 INTEGER DEFAULT 0"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_device_protocol_state} ADD COLUMN IF NOT EXISTS v2_only INTEGER DEFAULT 0"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_device_protocol_state} ADD COLUMN IF NOT EXISTS updated_at TEXT"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_mailboxes} ADD COLUMN IF NOT EXISTS rotated_at TEXT"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_mailboxes} ADD COLUMN IF NOT EXISTS active INTEGER DEFAULT 1"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_mailbox_messages} ADD COLUMN IF NOT EXISTS sender_hint VARCHAR(64)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_mailbox_messages} ADD COLUMN IF NOT EXISTS consumed_at TEXT"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {chat_identity_keys} ADD COLUMN IF NOT EXISTS identity_signing_key_b64 TEXT"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "UPDATE {chat_device_protocol_state} SET protocol_floor='v1_legacy' WHERE protocol_floor IS NULL OR TRIM(protocol_floor)=''"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "UPDATE {chat_device_protocol_state} SET supports_v2=0 WHERE supports_v2 IS NULL"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "UPDATE {chat_device_protocol_state} SET v2_only=0 WHERE v2_only IS NULL"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "UPDATE {chat_device_protocol_state} SET updated_at=NOW()::text WHERE updated_at IS NULL OR TRIM(updated_at)=''"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {contact_rules} ADD COLUMN IF NOT EXISTS muted INTEGER DEFAULT 0"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {contact_rules} ADD COLUMN IF NOT EXISTS starred INTEGER DEFAULT 0"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {contact_rules} ADD COLUMN IF NOT EXISTS pinned INTEGER DEFAULT 0"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {group_messages} ADD COLUMN IF NOT EXISTS attachment_b64 TEXT"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {group_messages} ADD COLUMN IF NOT EXISTS attachment_mime VARCHAR(64)"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {group_messages} ADD COLUMN IF NOT EXISTS voice_secs INTEGER"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {groups} ADD COLUMN IF NOT EXISTS avatar_b64 TEXT"
    ))
    .execute(pool)
    .await;
    let _ = sqlx::query(&format!(
        "ALTER TABLE {groups} ADD COLUMN IF NOT EXISTS avatar_mime VARCHAR(64)"
    ))
    .execute(pool)
    .await;

    Ok(())
}
