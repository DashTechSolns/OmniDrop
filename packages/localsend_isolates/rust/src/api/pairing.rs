use crate::api::model::{DeviceType, FileDto, ProtocolType};
use crate::api::server::RsHttpServer;
use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;
use localsend::http::client::{LsHttpClient, LsHttpClientVersion};
use localsend::http::dto::{PrepareUploadRequestDto, RegisterDto};
use localsend::model::transfer::FileContent;
pub use localsend::pairing::{
    JoinedPairingDevice, PairingDeviceInfo, PairingJoinRequest, PairingJoinResponse,
    PairingSendOffer, PairingSessionEvent, PairingSessionSnapshot,
};

#[frb(mirror(PairingSendOffer))]
pub struct _PairingSendOffer {
    pub alias: String,
    pub avatar_index: Option<u32>,
    pub session_id: String,
    pub join_token: String,
    pub expires_at_ms: u64,
}

#[frb(mirror(PairingJoinRequest))]
pub struct _PairingJoinRequest {
    pub session_token: String,
    pub fingerprint: String,
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub port: u16,
    pub protocol: ProtocolType,
    pub has_web_interface: bool,
}

#[frb(mirror(PairingJoinResponse))]
pub struct _PairingJoinResponse {
    pub success: bool,
    pub sender: PairingDeviceInfo,
}
use std::collections::HashMap;
use tokio::sync::mpsc;
use tokio::task::JoinSet;
use tokio_util::sync::CancellationToken;

#[cfg(target_os = "android")]
use std::os::fd::{FromRawFd, OwnedFd};
#[cfg(target_os = "android")]
use tokio::io::AsyncWriteExt;

impl RsHttpServer {
    /// Creates a short-lived pairing session associated with the sender's device details.
    pub async fn create_pairing_session(
        &self,
        sender: PairingDeviceInfo,
        discoverable: bool,
        avatar_index: Option<u32>,
    ) -> Result<String, String> {
        if sender.fingerprint.trim().is_empty()
            || sender.alias.trim().is_empty()
            || sender.ip.trim().is_empty()
            || sender.port == 0
        {
            return Err("Sender identity and connection details must be complete".to_string());
        }
        Ok(self.pairing.create(sender, discoverable, avatar_index).await)
    }

    /// Streams receiver joins until the sender finalizes the pairing session.
    ///
    /// Call this before requesting a snapshot: the stream does not replay
    /// events emitted before subscription, while snapshots include every join.
    pub async fn listen_pairing_session(
        &self,
        sink: StreamSink<RsPairingEvent>,
        session_token: String,
    ) {
        let mut events = match self.pairing.subscribe(&session_token).await {
            Ok(events) => events,
            Err(error) => {
                let _ = sink.add_error(anyhow::anyhow!(error.to_string()));
                return;
            }
        };

        loop {
            match events.recv().await {
                Ok(PairingSessionEvent::DeviceJoined(device)) => {
                    if sink
                        .add(RsPairingEvent::DeviceJoined { device })
                        .is_err()
                    {
                        return;
                    }
                }
                Ok(PairingSessionEvent::Finalized) => {
                    let _ = sink.add(RsPairingEvent::Finalized);
                    return;
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(count)) => {
                    let _ = sink.add_error(anyhow::anyhow!(
                        "Pairing event listener missed {count} event(s); retrieve a session snapshot"
                    ));
                    return;
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => return,
            }
        }
    }

    /// Returns the sender and all devices that have joined this pairing session.
    pub async fn pairing_session_snapshot(
        &self,
        session_token: String,
    ) -> Result<PairingSessionSnapshot, String> {
        self.pairing
            .snapshot(&session_token)
            .await
            .map_err(|error| error.to_string())
    }

    /// Closes the session to new joins and returns its final device list.
    pub async fn finalize_pairing_session(
        &self,
        session_token: String,
    ) -> Result<PairingSessionSnapshot, String> {
        self.pairing
            .finalize(&session_token)
            .await
            .map_err(|error| error.to_string())
    }

    /// Invalidates a pairing token, e.g. when the pairing UI is dismissed.
    pub async fn invalidate_pairing_session(&self, session_token: String) -> Result<(), String> {
        if self.pairing.invalidate(&session_token).await {
            Ok(())
        } else {
            Err("Pairing session not found".to_string())
        }
    }

    /// Sends the staged files to every joined device in parallel.
    ///
    /// This uses one existing v2 transfer session per recipient. It is
    /// concurrent-sessions fan-out, not protocol-level multi-recipient fan-out.
    pub async fn send_to_joined_devices(
        &self,
        sink: StreamSink<RsPairingTransferEvent>,
        session_token: String,
        private_key: String,
        certificate: String,
        files: Vec<RsPairingTransferFile>,
        pin: Option<String>,
    ) {
        let snapshot = match self.pairing.snapshot(&session_token).await {
            Ok(snapshot) => snapshot,
            Err(error) => {
                let _ = sink.add_error(anyhow::anyhow!(error.to_string()));
                return;
            }
        };
        if !snapshot.closed {
            let _ = sink.add_error(anyhow::anyhow!(
                "Finalize the pairing session before starting transfers"
            ));
            return;
        }
        if snapshot.joined_devices.is_empty() {
            let _ = sink.add_error(anyhow::anyhow!(
                "No devices joined this pairing session"
            ));
            return;
        }
        if files.is_empty() {
            let _ = sink.add_error(anyhow::anyhow!("No files were provided for transfer"));
            return;
        }
        let prepared = match prepare_transfer_files(files).await {
            Ok(files) => files,
            Err(error) => {
                let _ = sink.add_error(anyhow::anyhow!(error));
                return;
            }
        };
        let snapshot = match self.pairing.begin_transfer(&session_token).await {
            Ok(snapshot) => snapshot,
            Err(error) => {
                let _ = sink.add_error(anyhow::anyhow!(error.to_string()));
                return;
            }
        };

        let sender = snapshot.sender;
        let mut transfers = JoinSet::new();
        for joined in snapshot.joined_devices {
            let target = joined.device;
            let sender = sender.clone();
            let private_key = private_key.clone();
            let certificate = certificate.clone();
            let files = prepared.files.clone();
            let pin = pin.clone();
            let _ = sink.add(RsPairingTransferEvent::DeviceStarted {
                fingerprint: target.fingerprint.clone(),
                alias: target.alias.clone(),
            });
            transfers.spawn(async move {
                let result = send_to_device(sender, target.clone(), private_key, certificate, files, pin).await;
                (target, result)
            });
        }

        while let Some(result) = transfers.join_next().await {
            match result {
                Ok((target, Ok(files_sent))) => {
                    let _ = sink.add(RsPairingTransferEvent::DeviceFinished {
                        fingerprint: target.fingerprint,
                        alias: target.alias,
                        files_sent,
                    });
                }
                Ok((target, Err(error))) => {
                    let _ = sink.add(RsPairingTransferEvent::DeviceFailed {
                        fingerprint: target.fingerprint,
                        alias: target.alias,
                        error,
                    });
                }
                Err(error) => {
                    let _ = sink.add_error(anyhow::anyhow!(
                        "Pairing transfer task failed: {error}"
                    ));
                    return;
                }
            }
        }
        drop(prepared);
    }
}

async fn send_to_device(
    sender: PairingDeviceInfo,
    target: PairingDeviceInfo,
    private_key: String,
    certificate: String,
    files: Vec<PreparedTransferFile>,
    pin: Option<String>,
) -> Result<u32, String> {
    let client = LsHttpClient::new(
        &private_key,
        &certificate,
        LsHttpClientVersion::V2,
        Some(target.fingerprint.clone()),
        None,
    )
    .map_err(|error| error.to_string())?;

    let sender_info = RegisterDto {
        alias: sender.alias,
        version: sender.version,
        device_model: sender.device_model,
        device_type: sender.device_type,
        token: sender.fingerprint,
        port: sender.port,
        protocol: sender.protocol,
        has_web_interface: sender.has_web_interface,
    };
    let request = PrepareUploadRequestDto {
        info: sender_info,
        files: files
            .iter()
            .map(|file| (file.file.id.clone(), file.file.clone()))
            .collect(),
    };
    let response = client
        .prepare_upload(
            target.protocol,
            &target.ip,
            target.port,
            None,
            request,
            pin.as_deref(),
            CancellationToken::new(),
        )
        .await
        .map_err(|error| error.to_string())?;
    let Some(response) = response.response else {
        return Ok(0);
    };

    let files_by_id: HashMap<_, _> = files
        .into_iter()
        .map(|file| (file.file.id.clone(), file))
        .collect();
    let mut files_sent = 0_u32;
    for (file_id, token) in response.files {
        let Some(file) = files_by_id.get(&file_id) else {
            return Err(format!(
                "Receiver accepted an unknown file identifier: {file_id}"
            ));
        };
        let content = match &file.source {
            TransferSource::Path(path) => FileContent::Path(path.as_str().into()),
            TransferSource::Bytes(bytes) => {
                let (tx, rx) = mpsc::channel(1);
                tx.send(bytes::Bytes::copy_from_slice(bytes))
                    .await
                    .map_err(|_| "Could not stage in-memory file content".to_string())?;
                drop(tx);
                FileContent::Stream(rx)
            }
        };

        client
            .upload(
                target.protocol,
                &target.ip,
                target.port,
                None,
                &response.session_id,
                &file_id,
                &token,
                content,
                |_| {},
                CancellationToken::new(),
            )
            .await
            .map_err(|error| error.to_string())?;
        files_sent = files_sent.saturating_add(1);
    }

    Ok(files_sent)
}

async fn prepare_transfer_files(
    files: Vec<RsPairingTransferFile>,
) -> Result<PreparedTransferSet, String> {
    let mut ids = std::collections::HashSet::with_capacity(files.len());
    let mut descriptors = std::collections::HashSet::new();
    for file in &files {
        let has_path = file.path.as_ref().is_some_and(|path| !path.is_empty());
        let has_bytes = file.bytes.is_some();
        let has_descriptor = file.file_descriptor.is_some();
        if [has_path, has_bytes, has_descriptor]
            .into_iter()
            .filter(|exists| *exists)
            .count()
            != 1
        {
            return Err(format!(
                "File {} must provide exactly one path, byte buffer, or file descriptor",
                file.file.id
            ));
        }
        if !ids.insert(file.file.id.as_str()) {
            return Err(format!("Duplicate file identifier: {}", file.file.id));
        }
        if let Some(descriptor) = file.file_descriptor {
            if !descriptors.insert(descriptor) {
                return Err("Each file must use a distinct file descriptor".to_string());
            }
            #[cfg(not(target_os = "android"))]
            return Err("File descriptors are only supported on Android".to_string());
        }
    }

    let mut staged = StagedTempFiles::default();
    let mut prepared = Vec::with_capacity(files.len());
    for file in files {
        let source = if let Some(path) = file.path {
            TransferSource::Path(path)
        } else if let Some(bytes) = file.bytes {
            TransferSource::Bytes(bytes)
        } else if let Some(file_descriptor) = file.file_descriptor {
            #[cfg(target_os = "android")]
            {
                let path = spool_file_descriptor(file_descriptor, &mut staged).await?;
                TransferSource::Path(path)
            }
            #[cfg(not(target_os = "android"))]
            {
                let _ = file_descriptor;
                return Err("File descriptors are only supported on Android".to_string());
            }
        } else {
            return Err(format!(
                "File {} must provide exactly one content source",
                file.file.id
            ));
        };
        prepared.push(PreparedTransferFile {
            file: file.file,
            source,
        });
    }
    Ok(PreparedTransferSet {
        files: prepared,
        _temp_files: staged,
    })
}

#[cfg(target_os = "android")]
async fn spool_file_descriptor(
    file_descriptor: i32,
    staged: &mut StagedTempFiles,
) -> Result<String, String> {
    use std::os::unix::fs::OpenOptionsExt;

    // The incoming descriptor is consumed, as it is by the single-target upload API.
    let owned_descriptor = unsafe { OwnedFd::from_raw_fd(file_descriptor) };
    let path = std::env::temp_dir().join(format!("omnidrop-pairing-{}", uuid::Uuid::new_v4()));
    let mut output_options = std::fs::OpenOptions::new();
    output_options.write(true).create_new(true).mode(0o600);
    let output = output_options
        .open(&path)
        .map_err(|error| format!("Could not create a temporary staged file: {error}"))?;
    staged.paths.push(path.clone());

    let mut input = tokio::fs::File::from_std(std::fs::File::from(owned_descriptor));
    let mut output = tokio::fs::File::from_std(output);
    tokio::io::copy(&mut input, &mut output)
        .await
        .map_err(|error| format!("Could not stage Android file content: {error}"))?;
    output
        .flush()
        .await
        .map_err(|error| format!("Could not flush staged Android file content: {error}"))?;
    Ok(path.to_string_lossy().into_owned())
}

#[frb(opaque)]
#[derive(Default)]
pub struct StagedTempFiles {
    #[frb(ignore)]
    pub paths: Vec<std::path::PathBuf>,
}

impl Drop for StagedTempFiles {
    fn drop(&mut self) {
        for path in &self.paths {
            if let Err(error) = std::fs::remove_file(path) {
                if error.kind() != std::io::ErrorKind::NotFound {
                    tracing::warn!("Could not remove staged pairing file {}: {error}", path.display());
                }
            }
        }
    }
}

struct PreparedTransferSet {
    files: Vec<PreparedTransferFile>,
    _temp_files: StagedTempFiles,
}

#[derive(Clone)]
struct PreparedTransferFile {
    file: FileDto,
    source: TransferSource,
}

#[derive(Clone)]
enum TransferSource {
    Path(String),
    Bytes(Vec<u8>),
}

pub struct RsPairingTransferFile {
    pub file: FileDto,
    pub path: Option<String>,
    pub bytes: Option<Vec<u8>>,
    pub file_descriptor: Option<i32>,
}

pub enum RsPairingEvent {
    DeviceJoined { device: JoinedPairingDevice },
    Finalized,
}

pub enum RsPairingTransferEvent {
    DeviceStarted {
        fingerprint: String,
        alias: String,
    },
    DeviceFinished {
        fingerprint: String,
        alias: String,
        files_sent: u32,
    },
    DeviceFailed {
        fingerprint: String,
        alias: String,
        error: String,
    },
}

#[frb(mirror(PairingDeviceInfo))]
pub struct _PairingDeviceInfo {
    pub fingerprint: String,
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub ip: String,
    pub port: u16,
    pub protocol: ProtocolType,
    pub has_web_interface: bool,
}

#[frb(mirror(JoinedPairingDevice))]
pub struct _JoinedPairingDevice {
    pub device: PairingDeviceInfo,
    pub joined_at_ms: u64,
}

#[frb(mirror(PairingSessionSnapshot))]
pub struct _PairingSessionSnapshot {
    pub sender: PairingDeviceInfo,
    pub joined_devices: Vec<JoinedPairingDevice>,
    pub closed: bool,
}
