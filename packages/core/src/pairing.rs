use crate::model::discovery::{DeviceType, ProtocolType};
use rand::RngExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use subtle::ConstantTimeEq;
use thiserror::Error;
use tokio::sync::{broadcast, Mutex};
use uuid::Uuid;

const PENDING_SESSION_TTL: Duration = Duration::from_secs(2 * 60);
const EXPIRED_TOKEN_TTL: Duration = Duration::from_secs(5 * 60);
const EVENT_BUFFER_SIZE: usize = 64;
const PIN_LENGTH: usize = 6;
const MAX_PIN_ATTEMPTS: u8 = 5;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingDeviceInfo {
    pub fingerprint: String,
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    #[serde(
        default,
        with = "crate::model::discovery::device_type_v2",
        skip_serializing_if = "Option::is_none"
    )]
    pub device_type: Option<DeviceType>,
    pub ip: String,
    pub port: u16,
    #[serde(with = "crate::model::discovery::protocol_type_v2")]
    pub protocol: ProtocolType,
    pub has_web_interface: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct JoinedPairingDevice {
    pub device: PairingDeviceInfo,
    pub joined_at_ms: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingSessionSnapshot {
    pub sender: PairingDeviceInfo,
    pub joined_devices: Vec<JoinedPairingDevice>,
    pub closed: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingSendOffer {
    pub alias: String,
    pub avatar_index: Option<u32>,
    pub session_id: String,
    pub join_token: String,
    pub expires_at_ms: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingJoinRequest {
    pub session_token: String,
    pub fingerprint: String,
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    #[serde(
        default,
        with = "crate::model::discovery::device_type_v2",
        skip_serializing_if = "Option::is_none"
    )]
    pub device_type: Option<DeviceType>,
    pub port: u16,
    #[serde(with = "crate::model::discovery::protocol_type_v2")]
    pub protocol: ProtocolType,
    pub has_web_interface: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PairingJoinPayload {
    #[serde(flatten)]
    pub request: PairingJoinRequest,
    #[serde(default)]
    pub pin: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PairingJoinRequestWithPin<'a> {
    #[serde(flatten)]
    pub request: &'a PairingJoinRequest,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pin: Option<&'a str>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingJoinResponse {
    pub success: bool,
    pub sender: PairingDeviceInfo,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PairingSessionEvent {
    DeviceJoined(JoinedPairingDevice),
    Paired,
    LockedOut,
    Finalized,
}

#[derive(Debug, Error, Clone, Copy, Eq, PartialEq)]
pub enum PairingSessionError {
    #[error("Pairing session not found")]
    NotFound,
    #[error("Pairing session expired")]
    Expired,
    #[error("Pairing session is closed")]
    Closed,
    #[error("Pairing session must be finalized before transfer starts")]
    NotFinalized,
    #[error("Transfer has already started for this pairing session")]
    TransferStarted,
    #[error("No devices joined this pairing session")]
    NoJoinedDevices,
    #[error("Pairing device fingerprint is invalid")]
    InvalidDevice,
    #[error("Pairing PIN must contain exactly six digits")]
    InvalidPin,
    #[error("Pairing PIN is incorrect")]
    IncorrectPin,
    #[error("Pairing session is not accepting joins")]
    NotAcceptingJoins,
    #[error("Pairing session is locked after too many incorrect PIN attempts")]
    LockedOut,
}

#[derive(Clone, Default)]
pub struct PairingSessionManager {
    inner: Arc<Mutex<PairingSessionState>>,
}

#[derive(Default)]
struct PairingSessionState {
    sessions: HashMap<String, PairingSession>,
    expired_tokens: HashMap<String, Instant>,
}

struct PairingSession {
    sender: PairingDeviceInfo,
    created_at: Instant,
    expires_at: Instant,
    expires_at_ms: u64,
    discoverable: bool,
    avatar_index: Option<u32>,
    pin: Option<[u8; PIN_LENGTH]>,
    multi_recipient: bool,
    accepting_joins: bool,
    failed_pin_attempts: u8,
    pin_locked_out: bool,
    joined_devices: HashMap<String, JoinedPairingDevice>,
    closed: bool,
    transfer_started: bool,
    event_tx: broadcast::Sender<PairingSessionEvent>,
}

impl PairingSessionManager {
    pub async fn create(
        &self,
        mut sender: PairingDeviceInfo,
        discoverable: bool,
        avatar_index: Option<u32>,
        pin: Option<String>,
        multi_recipient: bool,
    ) -> Result<String, PairingSessionError> {
        let pin = pin
            .map(|pin| pin_bytes(&pin).ok_or(PairingSessionError::InvalidPin))
            .transpose()?;
        sender.fingerprint = sender.fingerprint.trim().to_ascii_uppercase();
        sender.alias = sender.alias.trim().to_string();
        let now = Instant::now();
        let expires_at = now + PENDING_SESSION_TTL;
        let expires_at_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
            .saturating_add(PENDING_SESSION_TTL.as_millis())
            .min(u64::MAX as u128) as u64;
        let mut state = self.inner.lock().await;
        prune_expired(&mut state, now);
        let token = Uuid::new_v4().to_string();
        let (event_tx, _) = broadcast::channel(EVENT_BUFFER_SIZE);
        state.sessions.insert(
            token.clone(),
            PairingSession {
                sender,
                created_at: now,
                expires_at,
                expires_at_ms,
                discoverable,
                avatar_index,
                pin,
                multi_recipient,
                accepting_joins: true,
                failed_pin_attempts: 0,
                pin_locked_out: false,
                joined_devices: HashMap::new(),
                closed: false,
                transfer_started: false,
                event_tx,
            },
        );
        Ok(token)
    }

    pub async fn active_send_offer(&self) -> Option<PairingSendOffer> {
        let now = Instant::now();
        let mut state = self.inner.lock().await;
        prune_expired(&mut state, now);
        state
            .sessions
            .iter()
            .filter(|(_, session)| {
                session.discoverable && session.accepting_joins && !session.closed
            })
            .max_by_key(|(_, session)| session.created_at)
            .map(|(token, session)| PairingSendOffer {
                alias: session.sender.alias.clone(),
                avatar_index: session.avatar_index,
                session_id: token.clone(),
                join_token: token.clone(),
                expires_at_ms: session.expires_at_ms,
            })
    }

    pub async fn join(
        &self,
        token: &str,
        mut device: PairingDeviceInfo,
        pin: Option<&str>,
    ) -> Result<(PairingSessionSnapshot, bool), PairingSessionError> {
        let now = Instant::now();
        let mut state = self.inner.lock().await;
        prune_expired(&mut state, now);
        if !state.sessions.contains_key(token) {
            return Err(if state.expired_tokens.contains_key(token) {
                PairingSessionError::Expired
            } else {
                PairingSessionError::NotFound
            });
        }

        let session = state
            .sessions
            .get_mut(token)
            .expect("session existence checked");
        if session.closed {
            return Err(PairingSessionError::Closed);
        }
        if session.pin_locked_out {
            return Err(PairingSessionError::LockedOut);
        }
        if !session.accepting_joins {
            return Err(PairingSessionError::NotAcceptingJoins);
        }
        if let Some(expected_pin) = session.pin {
            if !pin.is_some_and(|pin| constant_time_pin_eq(pin, &expected_pin)) {
                session.failed_pin_attempts = session.failed_pin_attempts.saturating_add(1);
                if session.failed_pin_attempts >= MAX_PIN_ATTEMPTS {
                    session.pin_locked_out = true;
                    session.accepting_joins = false;
                    let _ = session.event_tx.send(PairingSessionEvent::LockedOut);
                    return Err(PairingSessionError::LockedOut);
                }
                return Err(PairingSessionError::IncorrectPin);
            }
        }
        if device.fingerprint.trim().is_empty()
            || device.alias.trim().is_empty()
            || device.port == 0
        {
            return Err(PairingSessionError::InvalidDevice);
        }

        device.fingerprint = device.fingerprint.trim().to_ascii_uppercase();
        let existed = session.joined_devices.contains_key(&device.fingerprint);
        if !session.joined_devices.contains_key(&device.fingerprint) {
            device.alias = device.alias.trim().to_string();
            let joined = JoinedPairingDevice {
                device,
                joined_at_ms: SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis()
                    .min(u64::MAX as u128) as u64,
            };
            session
                .joined_devices
                .insert(joined.device.fingerprint.clone(), joined.clone());
            let _ = session
                .event_tx
                .send(PairingSessionEvent::DeviceJoined(joined.clone()));
            if !session.multi_recipient {
                session.accepting_joins = false;
                let _ = session.event_tx.send(PairingSessionEvent::Paired);
            }
        }

        Ok((snapshot(session), !existed))
    }

    pub async fn snapshot(
        &self,
        token: &str,
    ) -> Result<PairingSessionSnapshot, PairingSessionError> {
        let now = Instant::now();
        let mut state = self.inner.lock().await;
        prune_expired(&mut state, now);
        if !state.sessions.contains_key(token) {
            return Err(if state.expired_tokens.contains_key(token) {
                PairingSessionError::Expired
            } else {
                PairingSessionError::NotFound
            });
        }

        Ok(snapshot(
            state
                .sessions
                .get(token)
                .expect("session existence checked"),
        ))
    }

    pub async fn subscribe(
        &self,
        token: &str,
    ) -> Result<broadcast::Receiver<PairingSessionEvent>, PairingSessionError> {
        let now = Instant::now();
        let mut state = self.inner.lock().await;
        prune_expired(&mut state, now);
        if !state.sessions.contains_key(token) {
            return Err(if state.expired_tokens.contains_key(token) {
                PairingSessionError::Expired
            } else {
                PairingSessionError::NotFound
            });
        }
        let session = state
            .sessions
            .get(token)
            .expect("session existence checked");
        if session.closed {
            return Err(PairingSessionError::Closed);
        }
        Ok(session.event_tx.subscribe())
    }

    pub async fn finalize(
        &self,
        token: &str,
    ) -> Result<PairingSessionSnapshot, PairingSessionError> {
        let now = Instant::now();
        let mut state = self.inner.lock().await;
        prune_expired(&mut state, now);
        if !state.sessions.contains_key(token) {
            return Err(if state.expired_tokens.contains_key(token) {
                PairingSessionError::Expired
            } else {
                PairingSessionError::NotFound
            });
        }
        let session = state
            .sessions
            .get_mut(token)
            .expect("session existence checked");
        if !session.closed {
            session.closed = true;
            let _ = session.event_tx.send(PairingSessionEvent::Finalized);
        }
        Ok(snapshot(session))
    }

    pub async fn begin_transfer(
        &self,
        token: &str,
    ) -> Result<PairingSessionSnapshot, PairingSessionError> {
        let now = Instant::now();
        let mut state = self.inner.lock().await;
        prune_expired(&mut state, now);
        if !state.sessions.contains_key(token) {
            return Err(if state.expired_tokens.contains_key(token) {
                PairingSessionError::Expired
            } else {
                PairingSessionError::NotFound
            });
        }
        let session = state
            .sessions
            .get_mut(token)
            .expect("session existence checked");
        if !session.closed {
            return Err(PairingSessionError::NotFinalized);
        }
        if session.transfer_started {
            return Err(PairingSessionError::TransferStarted);
        }
        if session.joined_devices.is_empty() {
            return Err(PairingSessionError::NoJoinedDevices);
        }
        session.transfer_started = true;
        Ok(snapshot(session))
    }

    pub async fn invalidate(&self, token: &str) -> bool {
        let mut state = self.inner.lock().await;
        state.sessions.remove(token).is_some()
    }
}

fn snapshot(session: &PairingSession) -> PairingSessionSnapshot {
    let mut joined_devices: Vec<_> = session.joined_devices.values().cloned().collect();
    joined_devices.sort_by(|a, b| {
        a.joined_at_ms
            .cmp(&b.joined_at_ms)
            .then_with(|| a.device.fingerprint.cmp(&b.device.fingerprint))
    });
    PairingSessionSnapshot {
        sender: session.sender.clone(),
        joined_devices,
        closed: session.closed,
    }
}

pub fn generate_pairing_pin() -> String {
    let mut rng = rand::rng();
    (0..PIN_LENGTH)
        .map(|_| char::from(b'0' + rng.random_range(0..10)))
        .collect()
}

fn pin_bytes(pin: &str) -> Option<[u8; PIN_LENGTH]> {
    if pin.len() != PIN_LENGTH || !pin.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    pin.as_bytes().try_into().ok()
}

fn constant_time_pin_eq(candidate: &str, expected: &[u8; PIN_LENGTH]) -> bool {
    let mut candidate_bytes = [0; PIN_LENGTH];
    for (target, source) in candidate_bytes.iter_mut().zip(candidate.as_bytes()) {
        *target = *source;
    }
    let bytes_match = bool::from(candidate_bytes.ct_eq(expected));
    bytes_match & (candidate.len() == PIN_LENGTH)
}

fn prune_expired(state: &mut PairingSessionState, now: Instant) {
    let expired: Vec<_> = state
        .sessions
        .iter()
        .filter(|(_, session)| {
            now >= session.expires_at
                && session.joined_devices.is_empty()
                && !session.transfer_started
        })
        .map(|(token, _)| token.clone())
        .collect();
    for token in expired {
        state.sessions.remove(&token);
        state.expired_tokens.insert(token, now + EXPIRED_TOKEN_TTL);
    }
    state
        .expired_tokens
        .retain(|_, expires_at| *expires_at > now);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(fingerprint: &str, alias: &str) -> PairingDeviceInfo {
        PairingDeviceInfo {
            fingerprint: fingerprint.to_string(),
            alias: alias.to_string(),
            version: "2.2".to_string(),
            device_model: None,
            device_type: Some(DeviceType::Mobile),
            ip: "192.168.4.2".to_string(),
            port: 53317,
            protocol: ProtocolType::Http,
            has_web_interface: false,
        }
    }

    #[tokio::test]
    async fn concurrent_joins_are_all_recorded() {
        let manager = PairingSessionManager::default();
        let token = manager
            .create(device("sender", "Sender"), false, None, None, true)
            .await
            .unwrap();
        let mut tasks = Vec::new();
        for index in 0..12 {
            let manager = manager.clone();
            let token = token.clone();
            tasks.push(tokio::spawn(async move {
                manager
                    .join(
                        &token,
                        device(&format!("receiver-{index}"), &format!("Receiver {index}")),
                        None,
                    )
                    .await
                    .unwrap();
            }));
        }
        for task in tasks {
            task.await.unwrap();
        }
        let snapshot = manager.snapshot(&token).await.unwrap();
        assert_eq!(snapshot.joined_devices.len(), 12);
    }

    #[tokio::test]
    async fn send_offer_only_exposes_active_open_sessions() {
        let manager = PairingSessionManager::default();
        manager
            .create(device("qr-sender", "QR sender"), false, None, None, true)
            .await
            .unwrap();
        let open_token = manager
            .create(
                device("open-sender", "Open sender"),
                true,
                Some(3),
                None,
                true,
            )
            .await
            .unwrap();

        let offer = manager.active_send_offer().await.unwrap();
        assert_eq!(offer.alias, "Open sender");
        assert_eq!(offer.avatar_index, Some(3));
        assert_eq!(offer.session_id, open_token);
        assert_eq!(offer.join_token, open_token);
        assert!(offer.expires_at_ms > 0);

        manager.finalize(&open_token).await.unwrap();
        assert!(manager.active_send_offer().await.is_none());
    }

    #[tokio::test]
    async fn finalizing_stops_new_joins_but_preserves_snapshot() {
        let manager = PairingSessionManager::default();
        let token = manager
            .create(device("sender", "Sender"), false, None, None, true)
            .await
            .unwrap();
        manager
            .join(&token, device("receiver", "Receiver"), None)
            .await
            .unwrap();
        let finalized = manager.finalize(&token).await.unwrap();
        assert!(finalized.closed);
        assert_eq!(finalized.joined_devices.len(), 1);
        assert_eq!(
            manager
                .join(&token, device("another", "Another"), None)
                .await,
            Err(PairingSessionError::Closed)
        );
        manager.begin_transfer(&token).await.unwrap();
        assert_eq!(
            manager.begin_transfer(&token).await,
            Err(PairingSessionError::TransferStarted)
        );
    }

    #[tokio::test]
    async fn unused_sessions_expire_lazily_on_access() {
        let manager = PairingSessionManager::default();
        let token = manager
            .create(device("sender", "Sender"), false, None, None, true)
            .await
            .unwrap();
        {
            let mut state = manager.inner.lock().await;
            let session = state.sessions.get_mut(&token).unwrap();
            session.created_at = Instant::now() - PENDING_SESSION_TTL - Duration::from_secs(1);
            session.expires_at = Instant::now() - Duration::from_secs(1);
        }
        assert_eq!(
            manager.snapshot(&token).await,
            Err(PairingSessionError::Expired)
        );
    }

    #[tokio::test]
    async fn pin_accepts_correct_value_and_rejects_wrong_values_until_lockout() {
        let manager = PairingSessionManager::default();
        let token = manager
            .create(
                device("sender", "Sender"),
                false,
                None,
                Some("012345".to_string()),
                true,
            )
            .await
            .unwrap();
        let mut events = manager.subscribe(&token).await.unwrap();

        assert_eq!(
            manager
                .join(&token, device("wrong-1", "Wrong 1"), Some("999999"))
                .await,
            Err(PairingSessionError::IncorrectPin)
        );
        assert_eq!(
            manager
                .join(&token, device("wrong-2", "Wrong 2"), None)
                .await,
            Err(PairingSessionError::IncorrectPin)
        );
        assert_eq!(
            manager
                .join(&token, device("wrong-3", "Wrong 3"), Some("999999"))
                .await,
            Err(PairingSessionError::IncorrectPin)
        );
        assert_eq!(
            manager
                .join(&token, device("wrong-4", "Wrong 4"), Some("999999"))
                .await,
            Err(PairingSessionError::IncorrectPin)
        );
        assert_eq!(
            manager
                .join(&token, device("wrong-5", "Wrong 5"), Some("999999"))
                .await,
            Err(PairingSessionError::LockedOut)
        );
        assert_eq!(events.recv().await.unwrap(), PairingSessionEvent::LockedOut);
        assert_eq!(
            manager
                .join(&token, device("correct", "Correct"), Some("012345"))
                .await,
            Err(PairingSessionError::LockedOut)
        );
    }

    #[tokio::test]
    async fn correct_pin_allows_join() {
        let manager = PairingSessionManager::default();
        let token = manager
            .create(
                device("sender", "Sender"),
                false,
                None,
                Some("012345".to_string()),
                true,
            )
            .await
            .unwrap();

        let (_, is_new) = manager
            .join(&token, device("receiver", "Receiver"), Some("012345"))
            .await
            .unwrap();

        assert!(is_new);
    }

    #[tokio::test]
    async fn single_recipient_stops_after_first_join_but_multi_stays_open() {
        let single_manager = PairingSessionManager::default();
        let single_token = single_manager
            .create(device("single-sender", "Sender"), false, None, None, false)
            .await
            .unwrap();
        let mut single_events = single_manager.subscribe(&single_token).await.unwrap();
        single_manager
            .join(&single_token, device("single-receiver", "Receiver"), None)
            .await
            .unwrap();
        assert!(matches!(
            single_events.recv().await.unwrap(),
            PairingSessionEvent::DeviceJoined(_)
        ));
        assert_eq!(
            single_events.recv().await.unwrap(),
            PairingSessionEvent::Paired
        );
        assert_eq!(
            single_manager
                .join(&single_token, device("second-receiver", "Second"), None)
                .await,
            Err(PairingSessionError::NotAcceptingJoins)
        );
        assert!(!single_manager.snapshot(&single_token).await.unwrap().closed);

        let multi_manager = PairingSessionManager::default();
        let multi_token = multi_manager
            .create(device("multi-sender", "Sender"), false, None, None, true)
            .await
            .unwrap();
        let mut multi_events = multi_manager.subscribe(&multi_token).await.unwrap();
        multi_manager
            .join(&multi_token, device("first-receiver", "First"), None)
            .await
            .unwrap();
        multi_manager
            .join(&multi_token, device("second-receiver", "Second"), None)
            .await
            .unwrap();
        assert!(matches!(
            multi_events.recv().await.unwrap(),
            PairingSessionEvent::DeviceJoined(_)
        ));
        assert!(matches!(
            multi_events.recv().await.unwrap(),
            PairingSessionEvent::DeviceJoined(_)
        ));
        assert_eq!(
            multi_manager
                .snapshot(&multi_token)
                .await
                .unwrap()
                .joined_devices
                .len(),
            2
        );
    }

    #[tokio::test]
    async fn transfer_started_session_survives_pairing_expiry() {
        let manager = PairingSessionManager::default();
        let token = manager
            .create(device("sender", "Sender"), false, None, None, true)
            .await
            .unwrap();
        manager
            .join(&token, device("receiver", "Receiver"), None)
            .await
            .unwrap();
        manager.finalize(&token).await.unwrap();
        manager.begin_transfer(&token).await.unwrap();

        {
            let mut state = manager.inner.lock().await;
            state.sessions.get_mut(&token).unwrap().expires_at = Instant::now() - Duration::from_secs(1);
        }
        assert_eq!(
            manager.snapshot(&token).await.unwrap().joined_devices.len(),
            1
        );
    }

    #[tokio::test]
    async fn paired_session_survives_pending_pairing_expiry() {
        let manager = PairingSessionManager::default();
        let token = manager
            .create(device("sender", "Sender"), false, None, None, true)
            .await
            .unwrap();
        manager
            .join(&token, device("receiver", "Receiver"), None)
            .await
            .unwrap();

        {
            let mut state = manager.inner.lock().await;
            state.sessions.get_mut(&token).unwrap().expires_at = Instant::now() - Duration::from_secs(1);
        }

        assert_eq!(
            manager.snapshot(&token).await.unwrap().joined_devices.len(),
            1
        );
    }

    #[test]
    fn pin_comparison_is_correct_for_valid_and_invalid_lengths() {
        let expected = *b"012345";
        assert!(constant_time_pin_eq("012345", &expected));
        assert!(!constant_time_pin_eq("012346", &expected));
        assert!(!constant_time_pin_eq("12345", &expected));
        assert!(!constant_time_pin_eq("0012345", &expected));
    }

    #[test]
    fn pin_is_included_in_join_request_payload_when_configured() {
        let request = PairingJoinRequest {
            session_token: "session".to_string(),
            fingerprint: "fingerprint".to_string(),
            alias: "Receiver".to_string(),
            version: "2.2".to_string(),
            device_model: None,
            device_type: None,
            port: 53317,
            protocol: ProtocolType::Http,
            has_web_interface: false,
        };
        let payload = serde_json::to_value(PairingJoinRequestWithPin {
            request: &request,
            pin: Some("012345"),
        })
        .unwrap();

        assert_eq!(payload["sessionToken"], "session");
        assert_eq!(payload["pin"], "012345");
    }

    #[test]
    fn generated_pin_is_six_ascii_digits() {
        let pin = generate_pairing_pin();
        assert_eq!(pin.len(), PIN_LENGTH);
        assert!(pin.bytes().all(|byte| byte.is_ascii_digit()));
    }

    #[tokio::test]
    async fn invalid_pin_configuration_is_rejected() {
        let manager = PairingSessionManager::default();
        assert_eq!(
            manager
                .create(
                    device("sender", "Sender"),
                    false,
                    None,
                    Some("12345a".to_string()),
                    true,
                )
                .await,
            Err(PairingSessionError::InvalidPin)
        );
    }
}
