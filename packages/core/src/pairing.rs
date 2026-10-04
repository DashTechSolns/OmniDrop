use crate::model::discovery::{DeviceType, ProtocolType};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use thiserror::Error;
use tokio::sync::{Mutex, broadcast};
use uuid::Uuid;

const UNUSED_SESSION_TTL: Duration = Duration::from_secs(5 * 60);
const EXPIRED_TOKEN_TTL: Duration = Duration::from_secs(5 * 60);
const EVENT_BUFFER_SIZE: usize = 64;

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

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PairingSessionEvent {
    DeviceJoined(JoinedPairingDevice),
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
    joined_devices: HashMap<String, JoinedPairingDevice>,
    closed: bool,
    transfer_started: bool,
    event_tx: broadcast::Sender<PairingSessionEvent>,
}

impl PairingSessionManager {
    pub async fn create(&self, mut sender: PairingDeviceInfo) -> String {
        sender.fingerprint = sender.fingerprint.trim().to_ascii_uppercase();
        sender.alias = sender.alias.trim().to_string();
        let now = Instant::now();
        let mut state = self.inner.lock().await;
        prune_expired(&mut state, now);
        let token = Uuid::new_v4().to_string();
        let (event_tx, _) = broadcast::channel(EVENT_BUFFER_SIZE);
        state.sessions.insert(
            token.clone(),
            PairingSession {
                sender,
                created_at: now,
                joined_devices: HashMap::new(),
                closed: false,
                transfer_started: false,
                event_tx,
            },
        );
        token
    }

    pub async fn join(
        &self,
        token: &str,
        mut device: PairingDeviceInfo,
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

        let session = state.sessions.get_mut(token).expect("session existence checked");
        if session.closed {
            return Err(PairingSessionError::Closed);
        }
        if device.fingerprint.trim().is_empty() || device.alias.trim().is_empty() || device.port == 0 {
            return Err(PairingSessionError::InvalidDevice);
        }

        device.fingerprint = device.fingerprint.trim().to_ascii_uppercase();
        let existed = session.joined_devices.contains_key(&device.fingerprint);
        let joined = if let Some(existing) = session.joined_devices.get(&device.fingerprint) {
            existing.clone()
        } else {
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
            joined
        };

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

fn prune_expired(state: &mut PairingSessionState, now: Instant) {
    let expired: Vec<_> = state
        .sessions
        .iter()
        .filter(|(_, session)| {
            session.joined_devices.is_empty()
                && now.duration_since(session.created_at) >= UNUSED_SESSION_TTL
        })
        .map(|(token, _)| token.clone())
        .collect();
    for token in expired {
        state.sessions.remove(&token);
        state
            .expired_tokens
            .insert(token, now + EXPIRED_TOKEN_TTL);
    }
    state.expired_tokens.retain(|_, expires_at| *expires_at > now);
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
        let token = manager.create(device("sender", "Sender")).await;
        let mut tasks = Vec::new();
        for index in 0..12 {
            let manager = manager.clone();
            let token = token.clone();
            tasks.push(tokio::spawn(async move {
                manager
                    .join(
                        &token,
                        device(&format!("receiver-{index}"), &format!("Receiver {index}")),
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
    async fn finalizing_stops_new_joins_but_preserves_snapshot() {
        let manager = PairingSessionManager::default();
        let token = manager.create(device("sender", "Sender")).await;
        manager
            .join(&token, device("receiver", "Receiver"))
            .await
            .unwrap();
        let finalized = manager.finalize(&token).await.unwrap();
        assert!(finalized.closed);
        assert_eq!(finalized.joined_devices.len(), 1);
        assert_eq!(
            manager.join(&token, device("another", "Another")).await,
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
        let token = manager.create(device("sender", "Sender")).await;
        {
            let mut state = manager.inner.lock().await;
            state.sessions.get_mut(&token).unwrap().created_at =
                Instant::now() - UNUSED_SESSION_TTL - Duration::from_secs(1);
        }
        assert_eq!(
            manager.snapshot(&token).await,
            Err(PairingSessionError::Expired)
        );
    }
}
