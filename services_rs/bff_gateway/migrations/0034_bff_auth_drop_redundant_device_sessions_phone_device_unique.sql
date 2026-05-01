DO $$
DECLARE
    legacy_constraint_name TEXT;
BEGIN
    SELECT con.conname
    INTO legacy_constraint_name
    FROM pg_constraint con
    WHERE con.conrelid = 'device_sessions'::regclass
      AND con.contype = 'u'
      AND ARRAY(
            SELECT att.attname
            FROM unnest(con.conkey) WITH ORDINALITY AS cols(attnum, ord)
            JOIN pg_attribute att
              ON att.attrelid = con.conrelid
             AND att.attnum = cols.attnum
            ORDER BY cols.ord
        ) = ARRAY['phone'::name, 'device_id'::name]
    LIMIT 1;

    IF legacy_constraint_name IS NOT NULL THEN
        EXECUTE format(
            'ALTER TABLE device_sessions DROP CONSTRAINT %I',
            legacy_constraint_name
        );
    END IF;
END $$;
