CREATE TABLE IF NOT EXISTS auth_ride_pricing_policies (
  ride_class TEXT PRIMARY KEY,
  base_fare_minor_units BIGINT NOT NULL CHECK (base_fare_minor_units > 0),
  per_km_minor_units BIGINT NOT NULL CHECK (per_km_minor_units >= 0),
  per_minute_minor_units BIGINT NOT NULL CHECK (per_minute_minor_units >= 0),
  traffic_delay_per_minute_minor_units BIGINT NOT NULL CHECK (traffic_delay_per_minute_minor_units >= 0),
  booking_fee_minor_units BIGINT NOT NULL CHECK (booking_fee_minor_units >= 0),
  minimum_fare_minor_units BIGINT NOT NULL CHECK (minimum_fare_minor_units > 0),
  driver_share_bps BIGINT NOT NULL CHECK (driver_share_bps BETWEEN 1000 AND 9900),
  updated_by_account_id TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    ride_class IN (
      'economy',
      'xl',
      'premium',
      'delivery',
      'corporate'
    )
  )
);

INSERT INTO auth_ride_pricing_policies (
  ride_class,
  base_fare_minor_units,
  per_km_minor_units,
  per_minute_minor_units,
  traffic_delay_per_minute_minor_units,
  booking_fee_minor_units,
  minimum_fare_minor_units,
  driver_share_bps,
  updated_by_account_id
)
VALUES
  ('economy', 700, 130, 35, 18, 150, 1100, 8200, 'migration:0047'),
  ('xl', 1100, 180, 50, 28, 220, 1800, 8400, 'migration:0047'),
  ('premium', 1600, 260, 70, 40, 320, 2600, 8650, 'migration:0047'),
  ('delivery', 900, 150, 40, 22, 180, 1400, 8000, 'migration:0047'),
  ('corporate', 1900, 300, 85, 48, 360, 3200, 8850, 'migration:0047')
ON CONFLICT (ride_class) DO NOTHING;

