use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;

#[derive(Debug)]
pub struct ApiError {
    pub status: StatusCode,
    pub detail: String,
}

impl ApiError {
    pub fn new(status: StatusCode, detail: impl Into<String>) -> Self {
        Self {
            status,
            detail: detail.into(),
        }
    }

    pub fn bad_request(detail: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, detail)
    }

    pub fn internal(detail: impl Into<String>) -> Self {
        Self::new(StatusCode::INTERNAL_SERVER_ERROR, detail)
    }

    pub fn upstream(status: StatusCode, detail: impl Into<String>) -> Self {
        Self::new(status, detail)
    }
}

#[derive(Serialize)]
struct ErrorBody<'a> {
    detail: &'a str,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let body = axum::Json(ErrorBody {
            detail: self.detail.as_str(),
        });
        (self.status, body).into_response()
    }
}

pub type ApiResult<T> = Result<T, ApiError>;
