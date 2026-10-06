use crate::http::server::common::collect_to_json::CollectToJson;
use crate::http::server::common::error::AppError;
use crate::http::server::common::response::{BoxedBody, JsonResponse};
use crate::http::server::{AppState, RequestClientInfo};
use crate::pairing::{PairingDeviceInfo, PairingJoinRequest, PairingJoinResponse, PairingSessionError};
use hyper::body::Incoming;
use hyper::{Response, StatusCode};

pub(crate) async fn join(
    body: Incoming,
    state: AppState,
    client_info: RequestClientInfo,
) -> Result<Response<BoxedBody>, AppError> {
    let request = body.collect_to_json::<PairingJoinRequest>().await?;
    if request.session_token.trim().is_empty() {
        return Err(AppError::BadRequest(
            "Pairing session token must not be empty".to_string(),
        ));
    }

    if let Some(cert_fingerprint) = client_info.cert_fingerprint() {
        if request.fingerprint.to_ascii_uppercase() != cert_fingerprint {
            return Err(AppError::Message(
                StatusCode::FORBIDDEN,
                "Device fingerprint does not match the client certificate".to_string(),
            ));
        }
    }

    let device = PairingDeviceInfo {
        fingerprint: request.fingerprint,
        alias: request.alias,
        version: request.version,
        device_model: request.device_model,
        device_type: request.device_type,
        ip: client_info.ip.to_string(),
        port: request.port,
        protocol: request.protocol,
        has_web_interface: request.has_web_interface,
    };

    match state.pairing.join(&request.session_token, device).await {
        Ok((snapshot, _)) => Ok(JsonResponse {
            status: StatusCode::OK,
            body: PairingJoinResponse {
                success: true,
                sender: snapshot.sender,
            },
        }
        .into_response()),
        Err(error) => Err(pairing_error(error)),
    }
}

pub(crate) async fn send_offer(state: AppState) -> Result<Response<BoxedBody>, AppError> {
    let Some(offer) = state.pairing.active_send_offer().await else {
        return Err(AppError::Status(StatusCode::NOT_FOUND));
    };

    Ok(JsonResponse {
        status: StatusCode::OK,
        body: offer,
    }
    .into_response())
}

fn pairing_error(error: PairingSessionError) -> AppError {
    let (status, message) = match error {
        PairingSessionError::NotFound => {
            (StatusCode::NOT_FOUND, "Pairing session not found")
        }
        PairingSessionError::Expired => {
            (StatusCode::GONE, "Pairing session expired")
        }
        PairingSessionError::Closed => (StatusCode::CONFLICT, "Pairing session is closed"),
        PairingSessionError::NotFinalized => {
            (StatusCode::CONFLICT, "Pairing session is not finalized")
        }
        PairingSessionError::TransferStarted => {
            (StatusCode::CONFLICT, "Transfer has already started")
        }
        PairingSessionError::NoJoinedDevices => {
            (StatusCode::BAD_REQUEST, "No devices joined this pairing session")
        }
        PairingSessionError::InvalidDevice => {
            (StatusCode::BAD_REQUEST, "Invalid joining device information")
        }
    };
    AppError::Message(status, message.to_string())
}
