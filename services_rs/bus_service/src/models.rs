use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct CityIn {
    pub name: String,
    pub country: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
pub struct CityOut {
    pub id: String,
    pub name: String,
    pub country: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct OperatorIn {
    pub name: String,
    pub wallet_id: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
pub struct OperatorOut {
    pub id: String,
    pub name: String,
    pub wallet_id: Option<String>,
    pub is_online: bool,
}

#[derive(Debug, Deserialize)]
pub struct RouteIn {
    pub origin_city_id: String,
    pub dest_city_id: String,
    pub operator_id: String,
    pub id: Option<String>,
    pub bus_model: Option<String>,
    pub features: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
pub struct RouteOut {
    pub id: String,
    pub origin_city_id: String,
    pub dest_city_id: String,
    pub operator_id: String,
    pub bus_model: Option<String>,
    pub features: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct TripIn {
    pub route_id: String,
    pub depart_at_iso: String,
    pub arrive_at_iso: String,
    pub price_cents: i64,
    #[serde(default = "default_currency")]
    pub currency: String,
    #[serde(default = "default_seats_total")]
    pub seats_total: i32,
}

fn default_currency() -> String {
    "SYP".to_string()
}

fn default_seats_total() -> i32 {
    40
}

#[derive(Debug, Serialize, Clone)]
pub struct TripOut {
    pub id: String,
    pub route_id: String,
    pub depart_at: DateTime<Utc>,
    pub arrive_at: DateTime<Utc>,
    pub price_cents: i64,
    pub currency: String,
    pub seats_total: i32,
    pub seats_available: i32,
    pub status: String,
}

#[derive(Debug, Serialize)]
pub struct TripSearchOut {
    pub trip: TripOut,
    pub origin: CityOut,
    pub dest: CityOut,
    pub operator: OperatorOut,
    pub features: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct QuoteOut {
    pub trip_id: String,
    pub seats: i32,
    pub total_cents: i64,
    pub currency: String,
}

#[derive(Debug, Deserialize)]
pub struct BookReq {
    #[serde(default = "default_book_seats")]
    pub seats: i32,
    pub wallet_id: Option<String>,
    pub customer_phone: Option<String>,
    pub seat_numbers: Option<Vec<i32>>,
}

fn default_book_seats() -> i32 {
    1
}

#[derive(Debug, Serialize, Clone)]
pub struct TicketPayload {
    pub id: String,
    pub payload: String,
}

#[derive(Debug, Serialize, Clone)]
pub struct BookingOut {
    pub id: String,
    pub trip_id: String,
    pub seats: i32,
    pub status: String,
    pub payments_txn_id: Option<String>,
    pub created_at: Option<DateTime<Utc>>,
    pub wallet_id: Option<String>,
    pub customer_phone: Option<String>,
    pub tickets: Option<Vec<TicketPayload>>,
}

#[derive(Debug, Serialize)]
pub struct BookingCancelOut {
    pub booking: BookingOut,
    pub refund_cents: i64,
    pub refund_currency: String,
    pub refund_pct: i32,
}

#[derive(Debug, Serialize)]
pub struct BookingSearchOut {
    pub id: String,
    pub trip: TripOut,
    pub origin: CityOut,
    pub dest: CityOut,
    pub operator: OperatorOut,
    pub seats: i32,
    pub status: String,
    pub created_at: Option<DateTime<Utc>>,
    pub wallet_id: Option<String>,
    pub customer_phone: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct TicketOut {
    pub id: String,
    pub booking_id: String,
    pub trip_id: String,
    pub seat_no: Option<i32>,
    pub status: String,
    pub payload: String,
}

#[derive(Debug, Deserialize)]
pub struct BoardReq {
    pub payload: String,
}

#[derive(Debug, Serialize)]
pub struct OperatorStatsOut {
    pub operator_id: String,
    pub period: String,
    pub trips: i32,
    pub bookings: i32,
    pub confirmed_bookings: i32,
    pub seats_sold: i32,
    pub seats_total: i32,
    pub seats_boarded: i32,
    pub revenue_cents: i64,
}

#[derive(Debug, Serialize)]
pub struct AdminSummaryOut {
    pub operators: i64,
    pub routes: i64,
    pub trips_total: i64,
    pub trips_today: i64,
    pub bookings_total: i64,
    pub bookings_today: i64,
    pub bookings_confirmed_today: i64,
    pub revenue_cents_today: i64,
}
