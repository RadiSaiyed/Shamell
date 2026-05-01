use std::borrow::Cow;
use std::future::Future;

use sqlx::postgres::PgPool;
use sqlx::Row;

pub fn normalize_check_predicate(input: &str) -> String {
    let lowered = input.to_lowercase();
    let without_casts = strip_sql_casts(&lowered);
    normalize_layout_and_catalog_tokens(&without_casts)
}

pub fn normalize_index_definition_fragment(input: &str) -> String {
    let lowered = input.to_lowercase();
    normalize_index_layout(&lowered)
}

#[derive(Clone, Copy)]
pub enum CatalogScope<'a> {
    Exact(&'a str),
    CurrentSchemas,
}

#[derive(Clone, Copy)]
pub struct IndexFragmentSpec<'a> {
    pub index_name: &'a str,
    pub table: &'a str,
    pub columns_fragment: &'a str,
}

#[derive(Clone, Copy)]
pub struct PartialIndexFragmentSpec<'a> {
    pub index_name: &'a str,
    pub table: &'a str,
    pub columns_fragment: &'a str,
    pub predicate: &'a str,
}

#[derive(Clone, Copy)]
pub struct TwoColumnIndexSpec<'a> {
    pub index_name: &'a str,
    pub table: &'a str,
    pub first_column: &'a str,
    pub second_column: &'a str,
}

#[derive(Clone, Copy)]
pub struct TwoColumnPartialIndexSpec<'a> {
    pub index_name: &'a str,
    pub table: &'a str,
    pub first_column: &'a str,
    pub second_column: &'a str,
    pub predicate: &'a str,
}

#[derive(Clone, Copy)]
pub struct SingleColumnForeignKeySpec<'a> {
    pub table: &'a str,
    pub constraint: &'a str,
    pub column: &'a str,
    pub referenced_table: &'a str,
    pub referenced_column: &'a str,
    pub delete_action: &'a str,
}

#[derive(Clone, Copy)]
pub struct TableColumnSpec<'a> {
    pub table: &'a str,
    pub column: &'a str,
}

#[derive(Clone)]
pub struct RegclassSpec<'a> {
    pub qualified_name: Cow<'a, str>,
}

#[derive(Clone, Copy)]
pub struct NamedConstraintSpec<'a> {
    pub table: &'a str,
    pub constraint: &'a str,
}

#[derive(Clone, Copy)]
pub struct ColumnNullabilitySpec<'a> {
    pub table: &'a str,
    pub column: &'a str,
    pub is_nullable: bool,
}

#[derive(Clone, Copy)]
pub struct ColumnTypeSpec<'a> {
    pub table: &'a str,
    pub column: &'a str,
    pub data_type: &'a str,
}

#[derive(Clone, Copy)]
pub struct TwoColumnConstraintSpec<'a> {
    pub table: &'a str,
    pub first_column: &'a str,
    pub second_column: &'a str,
}

#[derive(Clone)]
pub struct CheckConstraintSpec<'a> {
    pub table: &'a str,
    pub constraint: &'a str,
    pub predicate: Cow<'a, str>,
}

pub async fn ensure_contracts<I, T, F, Fut, M>(
    requirements: I,
    mut check: F,
    mut error_message: M,
) -> Result<(), sqlx::Error>
where
    I: IntoIterator<Item = T>,
    T: Clone,
    F: FnMut(T) -> Fut,
    Fut: Future<Output = Result<bool, sqlx::Error>>,
    M: FnMut(T) -> String,
{
    for requirement in requirements {
        if !check(requirement.clone()).await? {
            return Err(sqlx::Error::Protocol(error_message(requirement)));
        }
    }

    Ok(())
}

pub fn contains_table_column(columns: &[TableColumnSpec<'_>], table: &str, column: &str) -> bool {
    columns
        .iter()
        .any(|spec| spec.table == table && spec.column == column)
}

pub fn contains_column_type(
    columns: &[ColumnTypeSpec<'_>],
    table: &str,
    column: &str,
    data_type: &str,
) -> bool {
    columns
        .iter()
        .any(|spec| spec.table == table && spec.column == column && spec.data_type == data_type)
}

pub fn contains_column_nullability(
    columns: &[ColumnNullabilitySpec<'_>],
    table: &str,
    column: &str,
    is_nullable: bool,
) -> bool {
    columns
        .iter()
        .any(|spec| spec.table == table && spec.column == column && spec.is_nullable == is_nullable)
}

pub fn contains_exact_foreign_key_constraint(
    constraints: &[SingleColumnForeignKeySpec<'_>],
    table: &str,
    constraint: &str,
    column: &str,
    referenced_table: &str,
    referenced_column: &str,
    delete_action: &str,
) -> bool {
    constraints.iter().any(|spec| {
        spec.table == table
            && spec.constraint == constraint
            && spec.column == column
            && spec.referenced_table == referenced_table
            && spec.referenced_column == referenced_column
            && spec.delete_action == delete_action
    })
}

pub fn contains_index_fragment(
    indexes: &[IndexFragmentSpec<'_>],
    index_name: &str,
    table: &str,
    columns_fragment: &str,
) -> bool {
    indexes.iter().any(|spec| {
        spec.index_name == index_name
            && spec.table == table
            && spec.columns_fragment == columns_fragment
    })
}

pub fn missing_index_fragments(
    indexes: &[IndexFragmentSpec<'_>],
    expected: &[IndexFragmentSpec<'_>],
) -> Vec<String> {
    expected
        .iter()
        .filter(|spec| {
            !contains_index_fragment(indexes, spec.index_name, spec.table, spec.columns_fragment)
        })
        .map(|spec| {
            format!(
                "{}.{} [{}]",
                spec.table, spec.index_name, spec.columns_fragment
            )
        })
        .collect()
}

pub fn contains_partial_index_fragment(
    indexes: &[PartialIndexFragmentSpec<'_>],
    index_name: &str,
    table: &str,
    columns_fragment: &str,
    predicate: &str,
) -> bool {
    indexes.iter().any(|spec| {
        spec.index_name == index_name
            && spec.table == table
            && spec.columns_fragment == columns_fragment
            && spec.predicate == predicate
    })
}

pub fn missing_partial_index_fragments(
    indexes: &[PartialIndexFragmentSpec<'_>],
    expected: &[PartialIndexFragmentSpec<'_>],
) -> Vec<String> {
    expected
        .iter()
        .filter(|spec| {
            !contains_partial_index_fragment(
                indexes,
                spec.index_name,
                spec.table,
                spec.columns_fragment,
                spec.predicate,
            )
        })
        .map(|spec| {
            format!(
                "{}.{} [{} WHERE {}]",
                spec.table, spec.index_name, spec.columns_fragment, spec.predicate
            )
        })
        .collect()
}

pub fn contains_named_check_constraint(
    constraints: &[CheckConstraintSpec<'_>],
    table: &str,
    constraint: &str,
) -> bool {
    constraints
        .iter()
        .any(|spec| spec.table == table && spec.constraint == constraint)
}

pub fn missing_named_check_constraints(
    constraints: &[CheckConstraintSpec<'_>],
    expected: &[NamedConstraintSpec<'_>],
) -> Vec<String> {
    expected
        .iter()
        .filter(|spec| !contains_named_check_constraint(constraints, spec.table, spec.constraint))
        .map(|spec| format!("{}.{}", spec.table, spec.constraint))
        .collect()
}

pub fn unexpected_named_check_constraints(
    constraints: &[CheckConstraintSpec<'_>],
    excluded: &[NamedConstraintSpec<'_>],
) -> Vec<String> {
    excluded
        .iter()
        .filter(|spec| contains_named_check_constraint(constraints, spec.table, spec.constraint))
        .map(|spec| format!("{}.{}", spec.table, spec.constraint))
        .collect()
}

pub fn contains_exact_check_constraint(
    constraints: &[CheckConstraintSpec<'_>],
    table: &str,
    constraint: &str,
    predicate: &str,
) -> bool {
    constraints.iter().any(|spec| {
        spec.table == table && spec.constraint == constraint && spec.predicate.as_ref() == predicate
    })
}

pub fn missing_exact_foreign_key_constraints(
    constraints: &[SingleColumnForeignKeySpec<'_>],
    expected: &[SingleColumnForeignKeySpec<'_>],
) -> Vec<String> {
    expected
        .iter()
        .filter(|spec| {
            !contains_exact_foreign_key_constraint(
                constraints,
                spec.table,
                spec.constraint,
                spec.column,
                spec.referenced_table,
                spec.referenced_column,
                spec.delete_action,
            )
        })
        .map(|spec| {
            format!(
                "{}.{}({} -> {}.{} ON DELETE {})",
                spec.table,
                spec.constraint,
                spec.column,
                spec.referenced_table,
                spec.referenced_column,
                spec.delete_action,
            )
        })
        .collect()
}

pub fn missing_exact_check_constraints(
    constraints: &[CheckConstraintSpec<'_>],
    expected: &[CheckConstraintSpec<'_>],
) -> Vec<String> {
    expected
        .iter()
        .filter(|spec| {
            !contains_exact_check_constraint(
                constraints,
                spec.table,
                spec.constraint,
                spec.predicate.as_ref(),
            )
        })
        .map(|spec| format!("{}.{} [{}]", spec.table, spec.constraint, spec.predicate))
        .collect()
}

pub fn contains_two_column_index(
    indexes: &[TwoColumnIndexSpec<'_>],
    index_name: &str,
    table: &str,
    first_column: &str,
    second_column: &str,
) -> bool {
    indexes.iter().any(|spec| {
        spec.index_name == index_name
            && spec.table == table
            && spec.first_column == first_column
            && spec.second_column == second_column
    })
}

pub fn missing_two_column_indexes(
    indexes: &[TwoColumnIndexSpec<'_>],
    expected: &[TwoColumnIndexSpec<'_>],
) -> Vec<String> {
    expected
        .iter()
        .filter(|spec| {
            !contains_two_column_index(
                indexes,
                spec.index_name,
                spec.table,
                spec.first_column,
                spec.second_column,
            )
        })
        .map(|spec| {
            format!(
                "{}.{} ({}, {})",
                spec.table, spec.index_name, spec.first_column, spec.second_column
            )
        })
        .collect()
}

pub fn contains_two_column_partial_index(
    indexes: &[TwoColumnPartialIndexSpec<'_>],
    index_name: &str,
    table: &str,
    first_column: &str,
    second_column: &str,
    predicate: &str,
) -> bool {
    indexes.iter().any(|spec| {
        spec.index_name == index_name
            && spec.table == table
            && spec.first_column == first_column
            && spec.second_column == second_column
            && spec.predicate == predicate
    })
}

pub fn missing_two_column_partial_indexes(
    indexes: &[TwoColumnPartialIndexSpec<'_>],
    expected: &[TwoColumnPartialIndexSpec<'_>],
) -> Vec<String> {
    expected
        .iter()
        .filter(|spec| {
            !contains_two_column_partial_index(
                indexes,
                spec.index_name,
                spec.table,
                spec.first_column,
                spec.second_column,
                spec.predicate,
            )
        })
        .map(|spec| {
            format!(
                "{}.{} ({}, {} WHERE {})",
                spec.table, spec.index_name, spec.first_column, spec.second_column, spec.predicate
            )
        })
        .collect()
}

pub async fn regclass_exists(pool: &PgPool, qualified_name: &str) -> Result<bool, sqlx::Error> {
    let row = sqlx::query("SELECT to_regclass($1) IS NOT NULL AS ok")
        .bind(qualified_name)
        .fetch_one(pool)
        .await?;
    Ok(row.try_get::<bool, _>("ok").unwrap_or(false))
}

pub async fn constraint_exists(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    table: &str,
    constraint: &str,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM pg_constraint c \
                    JOIN pg_class t ON t.oid = c.conrelid \
                    JOIN pg_namespace n ON n.oid = t.relnamespace \
                    WHERE n.nspname = $1 AND t.relname = $2 AND c.conname = $3 \
                 ) AS ok",
            )
            .bind(schema)
            .bind(table)
            .bind(constraint)
            .fetch_one(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM pg_constraint c \
                    JOIN pg_class t ON t.oid = c.conrelid \
                    JOIN pg_namespace n ON n.oid = t.relnamespace \
                    WHERE n.nspname = ANY(current_schemas(false)) \
                      AND t.relname = $1 \
                      AND c.conname = $2 \
                 ) AS ok",
            )
            .bind(table)
            .bind(constraint)
            .fetch_one(pool)
            .await?
        }
    };

    Ok(row.try_get::<bool, _>("ok").unwrap_or(false))
}

pub async fn has_named_check_constraint_with_predicate(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: CheckConstraintSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT pg_get_expr(c.conbin, c.conrelid) AS predicate \
                 FROM pg_constraint c \
                 JOIN pg_class t ON t.oid = c.conrelid \
                 JOIN pg_namespace n ON n.oid = t.relnamespace \
                 WHERE n.nspname = $1 \
                   AND t.relname = $2 \
                   AND c.conname = $3 \
                   AND c.contype = 'c'",
            )
            .bind(schema)
            .bind(spec.table)
            .bind(spec.constraint)
            .fetch_optional(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT pg_get_expr(c.conbin, c.conrelid) AS predicate \
                 FROM pg_constraint c \
                 JOIN pg_class t ON t.oid = c.conrelid \
                 JOIN pg_namespace n ON n.oid = t.relnamespace \
                 WHERE n.nspname = ANY(current_schemas(false)) \
                   AND t.relname = $1 \
                   AND c.conname = $2 \
                   AND c.contype = 'c'",
            )
            .bind(spec.table)
            .bind(spec.constraint)
            .fetch_optional(pool)
            .await?
        }
    };

    let Some(row) = row else {
        return Ok(false);
    };

    let actual = row.try_get::<String, _>("predicate").unwrap_or_default();
    Ok(normalize_check_predicate(&actual) == normalize_check_predicate(spec.predicate.as_ref()))
}

pub async fn column_exists(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: TableColumnSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 FROM information_schema.columns \
                    WHERE table_schema = $1 AND table_name = $2 AND column_name = $3 \
                 ) AS ok",
            )
            .bind(schema)
            .bind(spec.table)
            .bind(spec.column)
            .fetch_one(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 FROM information_schema.columns \
                    WHERE table_schema = ANY(current_schemas(false)) \
                      AND table_name = $1 \
                      AND column_name = $2 \
                 ) AS ok",
            )
            .bind(spec.table)
            .bind(spec.column)
            .fetch_one(pool)
            .await?
        }
    };

    Ok(row.try_get::<bool, _>("ok").unwrap_or(false))
}

pub async fn column_is_nullable(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: TableColumnSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT is_nullable \
                 FROM information_schema.columns \
                 WHERE table_schema = $1 AND table_name = $2 AND column_name = $3",
            )
            .bind(schema)
            .bind(spec.table)
            .bind(spec.column)
            .fetch_optional(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT is_nullable \
                 FROM information_schema.columns \
                 WHERE table_schema = ANY(current_schemas(false)) \
                   AND table_name = $1 \
                   AND column_name = $2",
            )
            .bind(spec.table)
            .bind(spec.column)
            .fetch_optional(pool)
            .await?
        }
    };

    Ok(row
        .and_then(|r| r.try_get::<String, _>("is_nullable").ok())
        .map(|v| v.eq_ignore_ascii_case("YES"))
        .unwrap_or(false))
}

pub async fn column_data_type(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: TableColumnSpec<'_>,
) -> Result<Option<String>, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT data_type \
                 FROM information_schema.columns \
                 WHERE table_schema = $1 AND table_name = $2 AND column_name = $3",
            )
            .bind(schema)
            .bind(spec.table)
            .bind(spec.column)
            .fetch_optional(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT data_type \
                 FROM information_schema.columns \
                 WHERE table_schema = ANY(current_schemas(false)) \
                   AND table_name = $1 \
                   AND column_name = $2",
            )
            .bind(spec.table)
            .bind(spec.column)
            .fetch_optional(pool)
            .await?
        }
    };

    Ok(row.and_then(|r| r.try_get::<String, _>("data_type").ok()))
}

pub async fn column_matches_nullability(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: ColumnNullabilitySpec<'_>,
) -> Result<bool, sqlx::Error> {
    Ok(column_is_nullable(
        pool,
        scope,
        TableColumnSpec {
            table: spec.table,
            column: spec.column,
        },
    )
    .await?
        == spec.is_nullable)
}

pub async fn column_matches_type(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: ColumnTypeSpec<'_>,
) -> Result<bool, sqlx::Error> {
    Ok(column_data_type(
        pool,
        scope,
        TableColumnSpec {
            table: spec.table,
            column: spec.column,
        },
    )
    .await?
    .as_deref()
        == Some(spec.data_type))
}

pub async fn has_single_column_primary_key(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: TableColumnSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM information_schema.table_constraints tc \
                    JOIN information_schema.key_column_usage kcu \
                      ON tc.constraint_name = kcu.constraint_name \
                     AND tc.table_schema = kcu.table_schema \
                     AND tc.table_name = kcu.table_name \
                    WHERE tc.constraint_type = 'PRIMARY KEY' \
                      AND tc.table_schema = $1 \
                      AND tc.table_name = $2 \
                    GROUP BY tc.constraint_name \
                    HAVING COUNT(*) = 1 AND MIN(kcu.column_name) = $3 \
                 ) AS ok",
            )
            .bind(schema)
            .bind(spec.table)
            .bind(spec.column)
            .fetch_one(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM information_schema.table_constraints tc \
                    JOIN information_schema.key_column_usage kcu \
                      ON tc.constraint_name = kcu.constraint_name \
                     AND tc.table_schema = kcu.table_schema \
                     AND tc.table_name = kcu.table_name \
                    WHERE tc.constraint_type = 'PRIMARY KEY' \
                      AND tc.table_schema = ANY(current_schemas(false)) \
                      AND tc.table_name = $1 \
                    GROUP BY tc.constraint_name \
                    HAVING COUNT(*) = 1 AND MIN(kcu.column_name) = $2 \
                 ) AS ok",
            )
            .bind(spec.table)
            .bind(spec.column)
            .fetch_one(pool)
            .await?
        }
    };

    Ok(row.try_get::<bool, _>("ok").unwrap_or(false))
}

pub async fn has_single_column_unique_constraint(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: TableColumnSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM information_schema.table_constraints tc \
                    JOIN information_schema.key_column_usage kcu \
                      ON tc.constraint_name = kcu.constraint_name \
                     AND tc.table_schema = kcu.table_schema \
                     AND tc.table_name = kcu.table_name \
                    WHERE tc.constraint_type = 'UNIQUE' \
                      AND tc.table_schema = $1 \
                      AND tc.table_name = $2 \
                    GROUP BY tc.constraint_name \
                    HAVING COUNT(*) = 1 AND MIN(kcu.column_name) = $3 \
                 ) AS ok",
            )
            .bind(schema)
            .bind(spec.table)
            .bind(spec.column)
            .fetch_one(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM information_schema.table_constraints tc \
                    JOIN information_schema.key_column_usage kcu \
                      ON tc.constraint_name = kcu.constraint_name \
                     AND tc.table_schema = kcu.table_schema \
                     AND tc.table_name = kcu.table_name \
                    WHERE tc.constraint_type = 'UNIQUE' \
                      AND tc.table_schema = ANY(current_schemas(false)) \
                      AND tc.table_name = $1 \
                    GROUP BY tc.constraint_name \
                    HAVING COUNT(*) = 1 AND MIN(kcu.column_name) = $2 \
                 ) AS ok",
            )
            .bind(spec.table)
            .bind(spec.column)
            .fetch_one(pool)
            .await?
        }
    };

    Ok(row.try_get::<bool, _>("ok").unwrap_or(false))
}

pub async fn has_two_column_unique_constraint(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: TwoColumnConstraintSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM information_schema.table_constraints tc \
                    JOIN information_schema.key_column_usage kcu \
                      ON tc.constraint_name = kcu.constraint_name \
                     AND tc.table_schema = kcu.table_schema \
                     AND tc.table_name = kcu.table_name \
                    WHERE tc.constraint_type = 'UNIQUE' \
                      AND tc.table_schema = $1 \
                      AND tc.table_name = $2 \
                    GROUP BY tc.constraint_name \
                    HAVING COUNT(*) = 2 \
                       AND MIN(CASE WHEN kcu.ordinal_position = 1 THEN kcu.column_name END) = $3 \
                       AND MIN(CASE WHEN kcu.ordinal_position = 2 THEN kcu.column_name END) = $4 \
                 ) AS ok",
            )
            .bind(schema)
            .bind(spec.table)
            .bind(spec.first_column)
            .bind(spec.second_column)
            .fetch_one(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM information_schema.table_constraints tc \
                    JOIN information_schema.key_column_usage kcu \
                      ON tc.constraint_name = kcu.constraint_name \
                     AND tc.table_schema = kcu.table_schema \
                     AND tc.table_name = kcu.table_name \
                    WHERE tc.constraint_type = 'UNIQUE' \
                      AND tc.table_schema = ANY(current_schemas(false)) \
                      AND tc.table_name = $1 \
                    GROUP BY tc.constraint_name \
                    HAVING COUNT(*) = 2 \
                       AND MIN(CASE WHEN kcu.ordinal_position = 1 THEN kcu.column_name END) = $2 \
                       AND MIN(CASE WHEN kcu.ordinal_position = 2 THEN kcu.column_name END) = $3 \
                 ) AS ok",
            )
            .bind(spec.table)
            .bind(spec.first_column)
            .bind(spec.second_column)
            .fetch_one(pool)
            .await?
        }
    };

    Ok(row.try_get::<bool, _>("ok").unwrap_or(false))
}

pub async fn has_named_index_with_columns_fragment(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: IndexFragmentSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let Some((indexdef, _)) = fetch_named_index_contract(
        pool,
        scope,
        spec.index_name,
        spec.table,
        IndexContractKind::Any,
    )
    .await?
    else {
        return Ok(false);
    };

    Ok(normalize_index_definition_fragment(&indexdef)
        .contains(&normalize_index_definition_fragment(spec.columns_fragment)))
}

pub async fn has_named_unique_index_with_columns_fragment(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: IndexFragmentSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let Some((indexdef, _)) = fetch_named_index_contract(
        pool,
        scope,
        spec.index_name,
        spec.table,
        IndexContractKind::UniqueNonPartial,
    )
    .await?
    else {
        return Ok(false);
    };

    Ok(normalize_index_definition_fragment(&indexdef)
        .contains(&normalize_index_definition_fragment(spec.columns_fragment)))
}

pub async fn has_named_partial_index_with_columns_and_predicate(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: PartialIndexFragmentSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let Some((indexdef, predicate)) = fetch_named_index_contract(
        pool,
        scope,
        spec.index_name,
        spec.table,
        IndexContractKind::NonUniquePartial,
    )
    .await?
    else {
        return Ok(false);
    };

    Ok(normalize_index_definition_fragment(&indexdef)
        .contains(&normalize_index_definition_fragment(spec.columns_fragment))
        && normalize_check_predicate(&predicate.unwrap_or_default())
            == normalize_check_predicate(spec.predicate))
}

pub async fn has_named_unique_partial_index_with_columns_and_predicate(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: PartialIndexFragmentSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let Some((indexdef, predicate)) = fetch_named_index_contract(
        pool,
        scope,
        spec.index_name,
        spec.table,
        IndexContractKind::UniquePartial,
    )
    .await?
    else {
        return Ok(false);
    };

    Ok(normalize_index_definition_fragment(&indexdef)
        .contains(&normalize_index_definition_fragment(spec.columns_fragment))
        && normalize_check_predicate(&predicate.unwrap_or_default())
            == normalize_check_predicate(spec.predicate))
}

pub async fn has_named_two_column_unique_index(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: TwoColumnIndexSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    JOIN LATERAL unnest(ind.indkey) WITH ORDINALITY AS cols(attnum, ord) ON TRUE \
                    JOIN pg_attribute att \
                      ON att.attrelid = tbl.oid \
                     AND att.attnum = cols.attnum \
                    WHERE idx_ns.nspname = $1 \
                      AND tbl_ns.nspname = $1 \
                      AND idx.relname = $2 \
                      AND tbl.relname = $3 \
                      AND ind.indisunique \
                      AND ind.indpred IS NULL \
                    GROUP BY idx.relname, tbl.relname \
                    HAVING COUNT(*) = 2 \
                       AND MIN(CASE WHEN cols.ord = 1 THEN att.attname END) = $4 \
                       AND MIN(CASE WHEN cols.ord = 2 THEN att.attname END) = $5 \
                 ) AS ok",
            )
            .bind(schema)
            .bind(spec.index_name)
            .bind(spec.table)
            .bind(spec.first_column)
            .bind(spec.second_column)
            .fetch_one(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    JOIN LATERAL unnest(ind.indkey) WITH ORDINALITY AS cols(attnum, ord) ON TRUE \
                    JOIN pg_attribute att \
                      ON att.attrelid = tbl.oid \
                     AND att.attnum = cols.attnum \
                    WHERE idx_ns.nspname = ANY(current_schemas(false)) \
                      AND tbl_ns.nspname = ANY(current_schemas(false)) \
                      AND idx.relname = $1 \
                      AND tbl.relname = $2 \
                      AND ind.indisunique \
                      AND ind.indpred IS NULL \
                    GROUP BY idx.relname, tbl.relname \
                    HAVING COUNT(*) = 2 \
                       AND MIN(CASE WHEN cols.ord = 1 THEN att.attname END) = $3 \
                       AND MIN(CASE WHEN cols.ord = 2 THEN att.attname END) = $4 \
                 ) AS ok",
            )
            .bind(spec.index_name)
            .bind(spec.table)
            .bind(spec.first_column)
            .bind(spec.second_column)
            .fetch_one(pool)
            .await?
        }
    };

    Ok(row.try_get::<bool, _>("ok").unwrap_or(false))
}

pub async fn has_named_two_column_partial_index(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    spec: TwoColumnPartialIndexSpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match scope {
        CatalogScope::Exact(schema) => {
            sqlx::query(
                "SELECT pg_get_expr(ind.indpred, ind.indrelid) AS predicate \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = $1 \
                      AND tbl_ns.nspname = $1 \
                      AND idx.relname = $2 \
                      AND tbl.relname = $3 \
                      AND NOT ind.indisunique \
                      AND ind.indpred IS NOT NULL \
                      AND ( \
                            SELECT ARRAY_AGG(att.attname ORDER BY cols.ord) \
                            FROM unnest(ind.indkey) WITH ORDINALITY AS cols(attnum, ord) \
                            JOIN pg_attribute att \
                              ON att.attrelid = tbl.oid \
                             AND att.attnum = cols.attnum \
                          ) = ARRAY[$4::name, $5::name]",
            )
            .bind(schema)
            .bind(spec.index_name)
            .bind(spec.table)
            .bind(spec.first_column)
            .bind(spec.second_column)
            .fetch_optional(pool)
            .await?
        }
        CatalogScope::CurrentSchemas => {
            sqlx::query(
                "SELECT pg_get_expr(ind.indpred, ind.indrelid) AS predicate \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = ANY(current_schemas(false)) \
                      AND tbl_ns.nspname = ANY(current_schemas(false)) \
                      AND idx.relname = $1 \
                      AND tbl.relname = $2 \
                      AND NOT ind.indisunique \
                      AND ind.indpred IS NOT NULL \
                      AND ( \
                            SELECT ARRAY_AGG(att.attname ORDER BY cols.ord) \
                            FROM unnest(ind.indkey) WITH ORDINALITY AS cols(attnum, ord) \
                            JOIN pg_attribute att \
                              ON att.attrelid = tbl.oid \
                             AND att.attnum = cols.attnum \
                          ) = ARRAY[$3::name, $4::name]",
            )
            .bind(spec.index_name)
            .bind(spec.table)
            .bind(spec.first_column)
            .bind(spec.second_column)
            .fetch_optional(pool)
            .await?
        }
    };

    let Some(row) = row else {
        return Ok(false);
    };

    let actual = row.try_get::<String, _>("predicate").unwrap_or_default();
    Ok(normalize_check_predicate(&actual) == normalize_check_predicate(spec.predicate))
}

pub async fn has_named_single_column_foreign_key_with_delete_action(
    pool: &PgPool,
    table_scope: CatalogScope<'_>,
    referenced_scope: CatalogScope<'_>,
    spec: SingleColumnForeignKeySpec<'_>,
) -> Result<bool, sqlx::Error> {
    let row = match (table_scope, referenced_scope) {
        (CatalogScope::Exact(schema), CatalogScope::Exact(referenced_schema)) => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM pg_constraint c \
                    JOIN pg_class t ON t.oid = c.conrelid \
                    JOIN pg_namespace n ON n.oid = t.relnamespace \
                    JOIN pg_class rt ON rt.oid = c.confrelid \
                    JOIN pg_namespace rn ON rn.oid = rt.relnamespace \
                    WHERE n.nspname = $1 \
                      AND t.relname = $2 \
                      AND c.conname = $3 \
                      AND c.contype = 'f' \
                      AND rn.nspname = $5 \
                      AND rt.relname = $6 \
                      AND ( \
                            SELECT ARRAY_AGG(att.attname ORDER BY cols.ord) \
                            FROM unnest(c.conkey) WITH ORDINALITY AS cols(attnum, ord) \
                            JOIN pg_attribute att \
                              ON att.attrelid = t.oid \
                             AND att.attnum = cols.attnum \
                          ) = ARRAY[$4::name] \
                      AND ( \
                            SELECT ARRAY_AGG(att.attname ORDER BY cols.ord) \
                            FROM unnest(c.confkey) WITH ORDINALITY AS cols(attnum, ord) \
                            JOIN pg_attribute att \
                              ON att.attrelid = rt.oid \
                             AND att.attnum = cols.attnum \
                          ) = ARRAY[$7::name] \
                      AND CASE c.confdeltype \
                            WHEN 'a' THEN 'NO ACTION' \
                            WHEN 'r' THEN 'RESTRICT' \
                            WHEN 'c' THEN 'CASCADE' \
                            WHEN 'n' THEN 'SET NULL' \
                            WHEN 'd' THEN 'SET DEFAULT' \
                          END = $8 \
                 ) AS ok",
            )
            .bind(schema)
            .bind(spec.table)
            .bind(spec.constraint)
            .bind(spec.column)
            .bind(referenced_schema)
            .bind(spec.referenced_table)
            .bind(spec.referenced_column)
            .bind(spec.delete_action)
            .fetch_one(pool)
            .await?
        }
        (CatalogScope::CurrentSchemas, CatalogScope::CurrentSchemas) => {
            sqlx::query(
                "SELECT EXISTS( \
                    SELECT 1 \
                    FROM pg_constraint c \
                    JOIN pg_class t ON t.oid = c.conrelid \
                    JOIN pg_namespace n ON n.oid = t.relnamespace \
                    JOIN pg_class rt ON rt.oid = c.confrelid \
                    JOIN pg_namespace rn ON rn.oid = rt.relnamespace \
                    WHERE n.nspname = ANY(current_schemas(false)) \
                      AND t.relname = $1 \
                      AND c.conname = $2 \
                      AND c.contype = 'f' \
                      AND rn.nspname = ANY(current_schemas(false)) \
                      AND rt.relname = $4 \
                      AND ( \
                            SELECT ARRAY_AGG(att.attname ORDER BY cols.ord) \
                            FROM unnest(c.conkey) WITH ORDINALITY AS cols(attnum, ord) \
                            JOIN pg_attribute att \
                              ON att.attrelid = t.oid \
                             AND att.attnum = cols.attnum \
                          ) = ARRAY[$3::name] \
                      AND ( \
                            SELECT ARRAY_AGG(att.attname ORDER BY cols.ord) \
                            FROM unnest(c.confkey) WITH ORDINALITY AS cols(attnum, ord) \
                            JOIN pg_attribute att \
                              ON att.attrelid = rt.oid \
                             AND att.attnum = cols.attnum \
                          ) = ARRAY[$5::name] \
                      AND CASE c.confdeltype \
                            WHEN 'a' THEN 'NO ACTION' \
                            WHEN 'r' THEN 'RESTRICT' \
                            WHEN 'c' THEN 'CASCADE' \
                            WHEN 'n' THEN 'SET NULL' \
                            WHEN 'd' THEN 'SET DEFAULT' \
                          END = $6 \
                 ) AS ok",
            )
            .bind(spec.table)
            .bind(spec.constraint)
            .bind(spec.column)
            .bind(spec.referenced_table)
            .bind(spec.referenced_column)
            .bind(spec.delete_action)
            .fetch_one(pool)
            .await?
        }
        _ => unreachable!("mixed catalog scopes are not supported"),
    };

    Ok(row.try_get::<bool, _>("ok").unwrap_or(false))
}

#[derive(Clone, Copy)]
enum IndexContractKind {
    Any,
    UniqueNonPartial,
    NonUniquePartial,
    UniquePartial,
}

async fn fetch_named_index_contract(
    pool: &PgPool,
    scope: CatalogScope<'_>,
    index_name: &str,
    table: &str,
    kind: IndexContractKind,
) -> Result<Option<(String, Option<String>)>, sqlx::Error> {
    let row = match (scope, kind) {
        (CatalogScope::Exact(schema), IndexContractKind::Any) => {
            sqlx::query(
                "SELECT pg_get_indexdef(idx.oid) AS indexdef \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = $1 \
                      AND tbl_ns.nspname = $1 \
                      AND idx.relname = $2 \
                      AND tbl.relname = $3",
            )
            .bind(schema)
            .bind(index_name)
            .bind(table)
            .fetch_optional(pool)
            .await?
        }
        (CatalogScope::CurrentSchemas, IndexContractKind::Any) => {
            sqlx::query(
                "SELECT pg_get_indexdef(idx.oid) AS indexdef \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = ANY(current_schemas(false)) \
                      AND tbl_ns.nspname = ANY(current_schemas(false)) \
                      AND idx.relname = $1 \
                      AND tbl.relname = $2",
            )
            .bind(index_name)
            .bind(table)
            .fetch_optional(pool)
            .await?
        }
        (CatalogScope::Exact(schema), IndexContractKind::UniqueNonPartial) => {
            sqlx::query(
                "SELECT pg_get_indexdef(idx.oid) AS indexdef \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = $1 \
                      AND tbl_ns.nspname = $1 \
                      AND idx.relname = $2 \
                      AND tbl.relname = $3 \
                      AND ind.indisunique \
                      AND ind.indpred IS NULL",
            )
            .bind(schema)
            .bind(index_name)
            .bind(table)
            .fetch_optional(pool)
            .await?
        }
        (CatalogScope::CurrentSchemas, IndexContractKind::UniqueNonPartial) => {
            sqlx::query(
                "SELECT pg_get_indexdef(idx.oid) AS indexdef \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = ANY(current_schemas(false)) \
                      AND tbl_ns.nspname = ANY(current_schemas(false)) \
                      AND idx.relname = $1 \
                      AND tbl.relname = $2 \
                      AND ind.indisunique \
                      AND ind.indpred IS NULL",
            )
            .bind(index_name)
            .bind(table)
            .fetch_optional(pool)
            .await?
        }
        (CatalogScope::Exact(schema), IndexContractKind::NonUniquePartial) => {
            sqlx::query(
                "SELECT pg_get_indexdef(idx.oid) AS indexdef, \
                        pg_get_expr(ind.indpred, ind.indrelid) AS predicate \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = $1 \
                      AND tbl_ns.nspname = $1 \
                      AND idx.relname = $2 \
                      AND tbl.relname = $3 \
                      AND NOT ind.indisunique \
                      AND ind.indpred IS NOT NULL",
            )
            .bind(schema)
            .bind(index_name)
            .bind(table)
            .fetch_optional(pool)
            .await?
        }
        (CatalogScope::CurrentSchemas, IndexContractKind::NonUniquePartial) => {
            sqlx::query(
                "SELECT pg_get_indexdef(idx.oid) AS indexdef, \
                        pg_get_expr(ind.indpred, ind.indrelid) AS predicate \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = ANY(current_schemas(false)) \
                      AND tbl_ns.nspname = ANY(current_schemas(false)) \
                      AND idx.relname = $1 \
                      AND tbl.relname = $2 \
                      AND NOT ind.indisunique \
                      AND ind.indpred IS NOT NULL",
            )
            .bind(index_name)
            .bind(table)
            .fetch_optional(pool)
            .await?
        }
        (CatalogScope::Exact(schema), IndexContractKind::UniquePartial) => {
            sqlx::query(
                "SELECT pg_get_indexdef(idx.oid) AS indexdef, \
                        pg_get_expr(ind.indpred, ind.indrelid) AS predicate \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = $1 \
                      AND tbl_ns.nspname = $1 \
                      AND idx.relname = $2 \
                      AND tbl.relname = $3 \
                      AND ind.indisunique \
                      AND ind.indpred IS NOT NULL",
            )
            .bind(schema)
            .bind(index_name)
            .bind(table)
            .fetch_optional(pool)
            .await?
        }
        (CatalogScope::CurrentSchemas, IndexContractKind::UniquePartial) => {
            sqlx::query(
                "SELECT pg_get_indexdef(idx.oid) AS indexdef, \
                        pg_get_expr(ind.indpred, ind.indrelid) AS predicate \
                    FROM pg_class idx \
                    JOIN pg_namespace idx_ns ON idx_ns.oid = idx.relnamespace \
                    JOIN pg_index ind ON ind.indexrelid = idx.oid \
                    JOIN pg_class tbl ON tbl.oid = ind.indrelid \
                    JOIN pg_namespace tbl_ns ON tbl_ns.oid = tbl.relnamespace \
                    WHERE idx_ns.nspname = ANY(current_schemas(false)) \
                      AND tbl_ns.nspname = ANY(current_schemas(false)) \
                      AND idx.relname = $1 \
                      AND tbl.relname = $2 \
                      AND ind.indisunique \
                      AND ind.indpred IS NOT NULL",
            )
            .bind(index_name)
            .bind(table)
            .fetch_optional(pool)
            .await?
        }
    };

    Ok(row.map(|row| {
        (
            row.try_get::<String, _>("indexdef").unwrap_or_default(),
            row.try_get::<String, _>("predicate").ok(),
        )
    }))
}

fn strip_sql_casts(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(input.len());
    let mut i = 0;

    while i < bytes.len() {
        if bytes[i] == b':' && i + 1 < bytes.len() && bytes[i + 1] == b':' {
            let mut j = i + 2;
            let mut consumed = false;

            while j < bytes.len() {
                if bytes[j].is_ascii_whitespace() {
                    let ws_start = j;
                    while j < bytes.len() && bytes[j].is_ascii_whitespace() {
                        j += 1;
                    }

                    let word_start = j;
                    while j < bytes.len() && is_type_ident_char(bytes[j]) {
                        j += 1;
                    }

                    if word_start == j || !is_type_continuation_keyword(&input[word_start..j]) {
                        j = ws_start;
                        break;
                    }

                    consumed = true;
                    continue;
                }

                if bytes[j] == b'[' && j + 1 < bytes.len() && bytes[j + 1] == b']' {
                    j += 2;
                    consumed = true;
                    continue;
                }

                if is_type_ident_char(bytes[j]) {
                    while j < bytes.len() && is_type_ident_char(bytes[j]) {
                        j += 1;
                    }
                    consumed = true;
                    continue;
                }

                break;
            }

            if consumed {
                i = j;
                continue;
            }
        }

        out.push(bytes[i] as char);
        i += 1;
    }

    out
}

fn is_type_ident_char(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'.' | b'"')
}

fn is_type_continuation_keyword(word: &str) -> bool {
    matches!(
        word.trim_matches('"'),
        "with"
            | "without"
            | "time"
            | "zone"
            | "double"
            | "precision"
            | "character"
            | "varying"
            | "bit"
            | "national"
    )
}

fn normalize_layout_and_catalog_tokens(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(input.len());
    let mut i = 0;
    let mut trim_state = TrimState::None;
    let mut any_pending = false;
    let mut pending_equals = false;

    while i < bytes.len() {
        if bytes[i] == b'\'' {
            trim_state = TrimState::None;
            any_pending = false;
            pending_equals = false;
            out.push('\'');
            i += 1;
            while i < bytes.len() {
                out.push(bytes[i] as char);
                if bytes[i] == b'\'' {
                    i += 1;
                    if i < bytes.len() && bytes[i] == b'\'' {
                        out.push('\'');
                        i += 1;
                        continue;
                    }
                    break;
                }
                i += 1;
            }
            continue;
        }

        if bytes[i].is_ascii_whitespace() || matches!(bytes[i], b'(' | b')') {
            i += 1;
            continue;
        }

        if is_catalog_token_char(bytes[i]) {
            let start = i;
            while i < bytes.len() && is_catalog_token_char(bytes[i]) {
                i += 1;
            }

            let token = &input[start..i];
            match trim_state {
                TrimState::MaybeBoth if token == "both" => {
                    trim_state = TrimState::ExpectFrom;
                    any_pending = false;
                    pending_equals = false;
                    continue;
                }
                TrimState::ExpectFrom if token == "from" => {
                    trim_state = TrimState::None;
                    any_pending = false;
                    pending_equals = false;
                    continue;
                }
                TrimState::MaybeBoth | TrimState::ExpectFrom => {
                    trim_state = TrimState::None;
                }
                TrimState::None => {}
            }

            if any_pending {
                if token == "array" && next_significant_char(bytes, i) == Some(b'[') {
                    any_pending = false;
                    continue;
                }
                any_pending = false;
            }

            if pending_equals && token == "true" {
                if out.ends_with('=') {
                    out.pop();
                }
                pending_equals = false;
                trim_state = TrimState::None;
                continue;
            }

            match token {
                "btrim" | "trim" => {
                    out.push_str("trim");
                    trim_state = TrimState::MaybeBoth;
                    pending_equals = false;
                }
                "any" => {
                    out.push_str("any");
                    any_pending = true;
                    pending_equals = false;
                }
                _ => {
                    out.push_str(token);
                    trim_state = TrimState::None;
                    pending_equals = false;
                }
            }
            continue;
        }

        trim_state = TrimState::None;
        if bytes[i] != b'[' {
            any_pending = false;
        }
        if bytes[i] == b'=' {
            pending_equals = true;
        } else if !matches!(bytes[i], b'<' | b'>' | b'!') {
            pending_equals = false;
        }
        out.push(bytes[i] as char);
        i += 1;
    }

    out
}

fn next_significant_char(bytes: &[u8], mut i: usize) -> Option<u8> {
    while i < bytes.len() {
        if bytes[i].is_ascii_whitespace() || matches!(bytes[i], b'(' | b')') {
            i += 1;
            continue;
        }
        return Some(bytes[i]);
    }
    None
}

fn is_catalog_token_char(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
}

fn normalize_index_layout(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = String::with_capacity(input.len());
    let mut i = 0;
    let mut last_was_space = false;

    while i < bytes.len() {
        if bytes[i] == b'\'' {
            if last_was_space && out.ends_with(' ') {
                last_was_space = false;
            }
            out.push('\'');
            i += 1;
            while i < bytes.len() {
                out.push(bytes[i] as char);
                if bytes[i] == b'\'' {
                    i += 1;
                    if i < bytes.len() && bytes[i] == b'\'' {
                        out.push('\'');
                        i += 1;
                        continue;
                    }
                    break;
                }
                i += 1;
            }
            continue;
        }

        if matches!(bytes[i], b'(' | b')') {
            i += 1;
            continue;
        }

        if bytes[i].is_ascii_whitespace() {
            if !out.is_empty() && !last_was_space {
                out.push(' ');
                last_was_space = true;
            }
            i += 1;
            continue;
        }

        out.push(bytes[i] as char);
        last_was_space = false;
        i += 1;
    }

    out.trim().to_string()
}

#[derive(Clone, Copy)]
enum TrimState {
    None,
    MaybeBoth,
    ExpectFrom,
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    use super::{
        contains_column_nullability, contains_column_type, contains_exact_check_constraint,
        contains_exact_foreign_key_constraint, contains_index_fragment,
        contains_named_check_constraint, contains_partial_index_fragment, contains_table_column,
        contains_two_column_index, contains_two_column_partial_index, ensure_contracts,
        missing_exact_check_constraints, missing_exact_foreign_key_constraints,
        missing_index_fragments, missing_named_check_constraints, missing_partial_index_fragments,
        missing_two_column_indexes, missing_two_column_partial_indexes, normalize_check_predicate,
        normalize_index_definition_fragment, unexpected_named_check_constraints,
        CheckConstraintSpec, ColumnNullabilitySpec, ColumnTypeSpec, IndexFragmentSpec,
        NamedConstraintSpec, PartialIndexFragmentSpec, SingleColumnForeignKeySpec, TableColumnSpec,
        TwoColumnIndexSpec, TwoColumnPartialIndexSpec,
    };

    #[tokio::test]
    async fn ensure_contracts_returns_protocol_error_for_first_missing_requirement() {
        let err = ensure_contracts(
            [1_u8, 2, 3],
            |value| async move { Ok(value != 2) },
            |value| format!("missing {value}"),
        )
        .await
        .unwrap_err();

        match err {
            sqlx::Error::Protocol(message) => assert_eq!(message, "missing 2"),
            other => panic!("expected protocol error, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn ensure_contracts_stops_after_first_missing_requirement() {
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_in_check = Arc::clone(&calls);

        let err = ensure_contracts(
            [1_u8, 2, 3],
            move |value| {
                let calls = Arc::clone(&calls_in_check);
                async move {
                    calls.fetch_add(1, Ordering::Relaxed);
                    Ok(value != 2)
                }
            },
            |value| format!("missing {value}"),
        )
        .await
        .unwrap_err();

        match err {
            sqlx::Error::Protocol(message) => assert_eq!(message, "missing 2"),
            other => panic!("expected protocol error, got {other:?}"),
        }
        assert_eq!(calls.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn normalizes_casts_and_boolean_suffixes() {
        assert_eq!(
            normalize_check_predicate("((enabled = TRUE) AND (kind)::text = 'welcome'::text)"),
            "enabledandkind='welcome'"
        );
        assert_eq!(
            normalize_check_predicate("enabled = true AND other = false"),
            "enabledandother=false"
        );
    }

    #[test]
    fn normalizes_trim_and_any_array_catalog_forms() {
        assert_eq!(
            normalize_check_predicate("btrim(title) <> ''::text"),
            normalize_check_predicate("TRIM(title) <> ''")
        );
        assert_eq!(
            normalize_check_predicate("role = ANY (ARRAY['admin'::text, 'ops'::text])"),
            normalize_check_predicate("role = ANY(ARRAY['admin', 'ops'])")
        );
        assert_eq!(
            normalize_check_predicate("(kind IS NULL OR TRIM(BOTH FROM kind)='' OR kind='sealed')"),
            normalize_check_predicate("(kind IS NULL OR TRIM(kind)='' OR kind='sealed')")
        );
    }

    #[test]
    fn preserves_expression_context_after_casts() {
        assert_eq!(
            normalize_check_predicate(
                "btrim(title) <> ''::text AND role = ANY (ARRAY['admin'::text, 'ops'::text])"
            ),
            normalize_check_predicate("TRIM(title) <> '' AND role = ANY(ARRAY['admin', 'ops'])")
        );
    }

    #[test]
    fn normalizes_multiword_cast_types() {
        assert_eq!(
            normalize_check_predicate("created_at::timestamp with time zone >= now()"),
            normalize_check_predicate("created_at >= now()")
        );
    }

    #[test]
    fn rewrites_only_exact_catalog_tokens() {
        assert_eq!(
            normalize_check_predicate("btrim(title) <> '' AND btrimmed = 1"),
            "trimtitle<>''andbtrimmed=1"
        );
        assert_eq!(
            normalize_check_predicate("role = ANY(ARRAY['admin']) AND anyarray_count = 1"),
            "role=any['admin']andanyarray_count=1"
        );
    }

    #[test]
    fn does_not_rewrite_inside_string_literals() {
        assert_eq!(
            normalize_check_predicate("kind = 'btrim' AND note = 'trimbothfrom anyarray['"),
            "kind='btrim'andnote='trimbothfrom anyarray['"
        );
        assert_eq!(
            normalize_check_predicate("kind = 'true' AND enabled = true"),
            "kind='true'andenabled"
        );
    }

    #[test]
    fn normalizes_index_definition_fragments() {
        let actual = normalize_index_definition_fragment(
            "CREATE UNIQUE INDEX idx_service_inbox ON auth_official_service_sessions \
             USING btree (account_id, COALESCE(last_message_ts, created_at) DESC, id DESC)",
        );
        let fragment = normalize_index_definition_fragment(
            "(account_id, coalesce(last_message_ts, created_at) desc, id desc)",
        );
        assert!(actual.contains(&fragment));
    }

    #[test]
    fn contains_column_helpers_match_exact_specs() {
        let columns = [TableColumnSpec {
            table: "sessions",
            column: "account_id",
        }];
        let types = [ColumnTypeSpec {
            table: "sessions",
            column: "expires_at",
            data_type: "timestamp with time zone",
        }];
        let nullability = [ColumnNullabilitySpec {
            table: "sessions",
            column: "phone",
            is_nullable: true,
        }];

        assert!(contains_table_column(&columns, "sessions", "account_id"));
        assert!(!contains_table_column(&columns, "sessions", "phone"));
        assert!(contains_column_type(
            &types,
            "sessions",
            "expires_at",
            "timestamp with time zone"
        ));
        assert!(!contains_column_type(
            &types,
            "sessions",
            "expires_at",
            "text"
        ));
        assert!(contains_column_nullability(
            &nullability,
            "sessions",
            "phone",
            true
        ));
        assert!(!contains_column_nullability(
            &nullability,
            "sessions",
            "phone",
            false
        ));
    }

    #[test]
    fn contains_index_constraint_and_foreign_key_helpers_match_exact_specs() {
        let indexes = [IndexFragmentSpec {
            index_name: "idx_sessions_account",
            table: "sessions",
            columns_fragment: "(account_id)",
        }];
        let partial_indexes = [PartialIndexFragmentSpec {
            index_name: "idx_sessions_active",
            table: "sessions",
            columns_fragment: "(account_id, last_seen_at DESC)",
            predicate: "revoked_at IS NULL",
        }];
        let two_column_indexes = [TwoColumnIndexSpec {
            index_name: "idx_tokens_account_device",
            table: "tokens",
            first_column: "account_id",
            second_column: "device_id",
        }];
        let two_column_partial_indexes = [TwoColumnPartialIndexSpec {
            index_name: "idx_tokens_account_device_active",
            table: "tokens",
            first_column: "account_id",
            second_column: "device_id",
            predicate: "revoked_at IS NULL",
        }];
        let foreign_keys = [SingleColumnForeignKeySpec {
            table: "sessions",
            constraint: "fk_sessions_account_id",
            column: "account_id",
            referenced_table: "accounts",
            referenced_column: "account_id",
            delete_action: "SET NULL",
        }];
        let checks = [CheckConstraintSpec {
            table: "sessions",
            constraint: "chk_sessions_kind_known",
            predicate: "kind = ANY(ARRAY['web','mobile'])".into(),
        }];

        assert!(contains_index_fragment(
            &indexes,
            "idx_sessions_account",
            "sessions",
            "(account_id)"
        ));
        assert!(contains_partial_index_fragment(
            &partial_indexes,
            "idx_sessions_active",
            "sessions",
            "(account_id, last_seen_at DESC)",
            "revoked_at IS NULL"
        ));
        assert!(contains_two_column_index(
            &two_column_indexes,
            "idx_tokens_account_device",
            "tokens",
            "account_id",
            "device_id"
        ));
        assert!(contains_two_column_partial_index(
            &two_column_partial_indexes,
            "idx_tokens_account_device_active",
            "tokens",
            "account_id",
            "device_id",
            "revoked_at IS NULL"
        ));
        assert!(contains_exact_foreign_key_constraint(
            &foreign_keys,
            "sessions",
            "fk_sessions_account_id",
            "account_id",
            "accounts",
            "account_id",
            "SET NULL"
        ));
        assert!(contains_named_check_constraint(
            &checks,
            "sessions",
            "chk_sessions_kind_known"
        ));
        assert!(contains_exact_check_constraint(
            &checks,
            "sessions",
            "chk_sessions_kind_known",
            "kind = ANY(ARRAY['web','mobile'])"
        ));
    }

    #[test]
    fn missing_exact_fk_and_check_helpers_report_unmatched_specs() {
        let foreign_keys = [SingleColumnForeignKeySpec {
            table: "sessions",
            constraint: "fk_sessions_account_id",
            column: "account_id",
            referenced_table: "accounts",
            referenced_column: "account_id",
            delete_action: "SET NULL",
        }];
        let missing_fks = missing_exact_foreign_key_constraints(
            &foreign_keys,
            &[
                SingleColumnForeignKeySpec {
                    table: "sessions",
                    constraint: "fk_sessions_account_id",
                    column: "account_id",
                    referenced_table: "accounts",
                    referenced_column: "account_id",
                    delete_action: "SET NULL",
                },
                SingleColumnForeignKeySpec {
                    table: "sessions",
                    constraint: "fk_sessions_owner_id",
                    column: "owner_id",
                    referenced_table: "accounts",
                    referenced_column: "account_id",
                    delete_action: "CASCADE",
                },
            ],
        );
        assert_eq!(
            missing_fks,
            vec![
                "sessions.fk_sessions_owner_id(owner_id -> accounts.account_id ON DELETE CASCADE)"
            ]
        );

        let checks = [CheckConstraintSpec {
            table: "sessions",
            constraint: "chk_sessions_kind_known",
            predicate: "kind = ANY(ARRAY['web','mobile'])".into(),
        }];
        let missing_checks = missing_exact_check_constraints(
            &checks,
            &[
                CheckConstraintSpec {
                    table: "sessions",
                    constraint: "chk_sessions_kind_known",
                    predicate: "kind = ANY(ARRAY['web','mobile'])".into(),
                },
                CheckConstraintSpec {
                    table: "sessions",
                    constraint: "chk_sessions_active_boolean",
                    predicate: "active = ANY(ARRAY[0,1])".into(),
                },
            ],
        );
        assert_eq!(
            missing_checks,
            vec!["sessions.chk_sessions_active_boolean [active = ANY(ARRAY[0,1])]"]
        );
    }

    #[test]
    fn missing_index_helpers_report_unmatched_specs() {
        let indexes = [IndexFragmentSpec {
            index_name: "idx_sessions_account",
            table: "sessions",
            columns_fragment: "(account_id)",
        }];
        let missing_indexes = missing_index_fragments(
            &indexes,
            &[
                IndexFragmentSpec {
                    index_name: "idx_sessions_account",
                    table: "sessions",
                    columns_fragment: "(account_id)",
                },
                IndexFragmentSpec {
                    index_name: "idx_sessions_last_seen",
                    table: "sessions",
                    columns_fragment: "(last_seen_at DESC, id DESC)",
                },
            ],
        );
        assert_eq!(
            missing_indexes,
            vec!["sessions.idx_sessions_last_seen [(last_seen_at DESC, id DESC)]"]
        );

        let partial_indexes = [PartialIndexFragmentSpec {
            index_name: "idx_sessions_active",
            table: "sessions",
            columns_fragment: "(account_id, last_seen_at DESC)",
            predicate: "revoked_at IS NULL",
        }];
        let missing_partial = missing_partial_index_fragments(
            &partial_indexes,
            &[
                PartialIndexFragmentSpec {
                    index_name: "idx_sessions_active",
                    table: "sessions",
                    columns_fragment: "(account_id, last_seen_at DESC)",
                    predicate: "revoked_at IS NULL",
                },
                PartialIndexFragmentSpec {
                    index_name: "idx_sessions_expiring",
                    table: "sessions",
                    columns_fragment: "(expires_at)",
                    predicate: "expires_at IS NOT NULL",
                },
            ],
        );
        assert_eq!(
            missing_partial,
            vec!["sessions.idx_sessions_expiring [(expires_at) WHERE expires_at IS NOT NULL]"]
        );

        let two_column_indexes = [TwoColumnIndexSpec {
            index_name: "idx_tokens_account_device",
            table: "tokens",
            first_column: "account_id",
            second_column: "device_id",
        }];
        let missing_two_column = missing_two_column_indexes(
            &two_column_indexes,
            &[
                TwoColumnIndexSpec {
                    index_name: "idx_tokens_account_device",
                    table: "tokens",
                    first_column: "account_id",
                    second_column: "device_id",
                },
                TwoColumnIndexSpec {
                    index_name: "idx_tokens_owner_device",
                    table: "tokens",
                    first_column: "owner_id",
                    second_column: "device_id",
                },
            ],
        );
        assert_eq!(
            missing_two_column,
            vec!["tokens.idx_tokens_owner_device (owner_id, device_id)"]
        );

        let two_column_partial_indexes = [TwoColumnPartialIndexSpec {
            index_name: "idx_tokens_account_device_active",
            table: "tokens",
            first_column: "account_id",
            second_column: "device_id",
            predicate: "revoked_at IS NULL",
        }];
        let missing_two_column_partial = missing_two_column_partial_indexes(
            &two_column_partial_indexes,
            &[
                TwoColumnPartialIndexSpec {
                    index_name: "idx_tokens_account_device_active",
                    table: "tokens",
                    first_column: "account_id",
                    second_column: "device_id",
                    predicate: "revoked_at IS NULL",
                },
                TwoColumnPartialIndexSpec {
                    index_name: "idx_tokens_owner_device_active",
                    table: "tokens",
                    first_column: "owner_id",
                    second_column: "device_id",
                    predicate: "revoked_at IS NULL",
                },
            ],
        );
        assert_eq!(
            missing_two_column_partial,
            vec!["tokens.idx_tokens_owner_device_active (owner_id, device_id WHERE revoked_at IS NULL)"]
        );
    }

    #[test]
    fn missing_and_unexpected_named_check_helpers_report_name_only_drift() {
        let checks = [CheckConstraintSpec {
            table: "messages",
            constraint: "chk_messages_delivered_at_after_created_at",
            predicate: "delivered_at >= created_at".into(),
        }];
        let missing = missing_named_check_constraints(
            &checks,
            &[
                NamedConstraintSpec {
                    table: "messages",
                    constraint: "chk_messages_delivered_at_after_created_at",
                },
                NamedConstraintSpec {
                    table: "messages",
                    constraint: "chk_messages_read_at_after_created_at",
                },
            ],
        );
        assert_eq!(
            missing,
            vec!["messages.chk_messages_read_at_after_created_at"]
        );

        let unexpected = unexpected_named_check_constraints(
            &checks,
            &[
                NamedConstraintSpec {
                    table: "messages",
                    constraint: "chk_messages_delivered_at_after_created_at",
                },
                NamedConstraintSpec {
                    table: "messages",
                    constraint: "chk_messages_legacy_text_timestamp",
                },
            ],
        );
        assert_eq!(
            unexpected,
            vec!["messages.chk_messages_delivered_at_after_created_at"]
        );
    }
}
