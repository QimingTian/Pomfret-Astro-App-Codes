# Pomfret VISTA Observatory - Technical Documentation

**Document Purpose:** Technical architecture documentation for IT Office review  
**Date:** December 2025  
**Project:** Pomfret School VISTA Observatory Control System

---

## Executive Summary

The Pomfret VISTA Observatory project consists of a distributed system for remotely controlling astronomical cameras and monitoring equipment. The system uses a client-server architecture with remote access capabilities via Cloudflare Tunnel, enabling secure access from anywhere without requiring port forwarding or VPN configuration.

---

## System Architecture Overview

### Components

1. **macOS Client Application** (Swift/SwiftUI)
   - Runs on any Mac (macOS 13.0+)
   - Provides user interface for camera control
   - Communicates with camera service via HTTP/HTTPS

2. **Camera Service** (Python/Flask)
   - Runs on Raspberry Pi at observatory site
   - Controls ASI cameras via native SDK
   - Provides HTTP API and MJPEG video streaming
   - Listens on `0.0.0.0:8080` (all network interfaces)

3. **Cloudflare Tunnel** (cloudflared)
   - Runs on Raspberry Pi as a service
   - Creates secure outbound connection to Cloudflare
   - Exposes local service via public HTTPS URL

---

## 1. Cloudflare Tunnel Architecture

### What is Cloudflare Tunnel?

Cloudflare Tunnel (formerly Argo Tunnel) is a secure tunneling service that creates an outbound connection from the local network to Cloudflare's edge network. Unlike traditional VPNs or port forwarding, it requires **no inbound firewall rules** and works behind NAT without public IP addresses.

### How It Works

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Raspberry Pi   │         │  Cloudflare      │         │  Client Mac      │
│  (Observatory)  │         │  Edge Network    │         │  (Anywhere)      │
│                 │         │                  │         │                  │
│  camera_service │◄───HTTPS───►│  Tunnel        │◄───HTTPS───►│  macOS App      │
│  :8080          │         │  Proxy           │         │                  │
│                 │         │                  │         │                  │
│  cloudflared    │───Outbound──►│  (Public URL)  │         │                  │
│  (tunnel)       │  Connection │                  │         │                  │
└─────────────────┘         └──────────────────┘         └─────────────────┘
```

### Key Technical Details

1. **Outbound-Only Connection**
   - The Raspberry Pi initiates an outbound connection to Cloudflare
   - No inbound ports need to be opened on the school firewall
   - Works through NAT and firewalls automatically

2. **TLS/SSL Encryption**
   - All traffic is encrypted end-to-end via HTTPS
   - Cloudflare provides SSL certificates automatically
   - No certificate management required on local server

3. **Two Deployment Options**

   **Option A: Temporary Tunnel (Quick Setup)**
   ```bash
   cloudflared tunnel --url http://localhost:8080
   ```
   - Generates random URL: `https://random-name-1234.trycloudflare.com`
   - URL changes each time tunnel restarts
   - No Cloudflare account required
   - Suitable for testing

   **Option B: Permanent Tunnel (Production)**
   - Requires Cloudflare Zero Trust account (free tier available)
   - Configured via Cloudflare Dashboard
   - Permanent URL: `https://pomfret-obs.pomfretastro.org`
   - Runs as Linux systemd service, auto-starts on boot
   - Installation: `sudo cloudflared service install <TOKEN>`

### Network Flow

1. **Tunnel Establishment**
   - `cloudflared` daemon on Raspberry Pi connects to Cloudflare edge
   - Establishes persistent WebSocket/HTTP2 connection
   - Registers local service: `http://localhost:8080`

2. **Client Request**
   - Client app requests: `https://pomfret-obs.pomfretastro.org/status`
   - Request goes to Cloudflare edge (standard HTTPS)
   - Cloudflare routes through tunnel to Raspberry Pi
   - Raspberry Pi responds through tunnel back to Cloudflare
   - Cloudflare forwards response to client

3. **Security Benefits**
   - No exposed ports on school network
   - All traffic encrypted (HTTPS)
   - Cloudflare DDoS protection
   - No need for firewall rule changes

### Configuration Files

**Tunnel Configuration** (if using permanent tunnel):
- Location: `~/.cloudflared/config.yml`
- Contains tunnel ID, credentials, routing rules
- Managed by Cloudflare Dashboard

**Service Configuration** (Linux/Raspberry Pi):
- Installed as systemd service
- Auto-starts on system boot
- Logs available via `journalctl -u cloudflared`
- Service management: `sudo systemctl [start|stop|restart|status] cloudflared`

---

## 2. Local IP Address Configuration

### Network Architecture

The system supports **dual connectivity modes**:

1. **Local Network Access** (Same Subnet)
   - Direct connection: `http://172.18.2.101:8080`
   - No tunnel required
   - Lower latency
   - Requires same network segment

2. **Remote Access** (Via Cloudflare Tunnel)
   - Tunnel URL: `https://pomfret-obs.pomfretastro.org`
   - Works from anywhere
   - Higher latency (routed through Cloudflare)
   - No network configuration required

### IP Address Handling in Application

The macOS client application (`APIClient.swift`) handles both local and remote URLs:

```swift
// URL normalization logic
var urlString = baseURL.trimmingCharacters(in: .whitespaces)
if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
    urlString = "http://" + urlString  // Auto-add protocol
}
```

**Key Features:**
- Supports both `http://` (local) and `https://` (tunnel) URLs
- Automatic protocol detection
- URL validation and normalization
- Timeout configuration:
  - Request timeout: 60 seconds
  - Resource timeout: 300 seconds (for long operations)

### Network Requirements

**For Local Access:**
- Raspberry Pi must be on same network segment as client
- Default gateway/router must allow local traffic
- Firewall should allow outbound connections (standard)

**For Remote Access:**
- Raspberry Pi needs outbound HTTPS (443) to Cloudflare
- No inbound rules required
- Works through NAT/firewall automatically

### IP Address Discovery

The Raspberry Pi's local IP (e.g., `172.18.2.101`) is:
- Configured via DHCP or static assignment
- Set in client app's Settings view
- Can be discovered via:
  ```bash
  hostname -I
  # or
  ip addr show | grep "inet " | grep -v 127.0.0.1
  ```

---

## 3. Camera Control System

### Hardware

- **Camera Model:** ZWO ASI 120MC / ASI 676MC
- **Interface:** USB 3.0
- **Connection:** Direct USB connection to Raspberry Pi
- **Resolution:** 
  - ASI 120MC: 1280×960
  - ASI 676MC: 3008×3008 (future)

### ASI Camera SDK

The camera is controlled using the **ASI Camera SDK** (version 1.40), a proprietary library provided by ZWO.

#### SDK Architecture

**Library Files:**
- Raspberry Pi (ARMv6): `lib/armv6/libASICamera2.so`
- Raspberry Pi 2 (ARMv7): `lib/armv7/libASICamera2.so`
- Raspberry Pi 3/4/5 64-bit (ARMv8): `lib/armv8/libASICamera2.so`
- x86_64 Linux: `lib/x64/libASICamera2.so`
- Header: `include/ASICamera2.h`

**Integration Method:**
- Python service uses `ctypes` to load dynamic library
- Direct C function calls to SDK
- No wrapper library required
- Automatic architecture detection

#### SDK Loading Process

```python
# camera_service.py
import ctypes
import platform
import os

# Automatic architecture detection
machine = platform.machine().lower()
if 'aarch64' in machine or 'arm64' in machine:
    lib_path = 'ASI_linux_mac_SDK_V1.40/lib/armv8/libASICamera2.so'
elif 'armv7' in machine:
    lib_path = 'ASI_linux_mac_SDK_V1.40/lib/armv7/libASICamera2.so'
else:
    lib_path = 'ASI_linux_mac_SDK_V1.40/lib/armv6/libASICamera2.so'

asi_lib = ctypes.CDLL(lib_path)  # Load dynamic library
```

**Dependencies:**
- `libusb-1.0` (via apt): USB communication layer
- Linux USB drivers (built-in, requires udev rules)
- Python 3 with ctypes support
- udev rules installed for non-root camera access

### Camera Control Flow

#### 1. Camera Initialization

```python
# Connect to camera
asi_lib.ASIGetNumOfConnectedCameras()  # Check for cameras
asi_lib.ASIGetCameraProperty()         # Get camera info
asi_lib.ASIOpenCamera(camera_id)       # Open connection
asi_lib.ASIInitCamera(camera_id)       # Initialize hardware
```

**Process:**
1. Enumerate connected cameras
2. Get camera properties (resolution, color capability, etc.)
3. Open camera connection
4. Initialize camera hardware
5. Configure ROI (Region of Interest) format
6. Set initial control values (gain, exposure)

#### 2. Video Streaming Mode

**SDK Functions Used:**
- `ASIStartVideoCapture()` - Start continuous capture
- `ASIGetVideoData()` - Retrieve frame data
- `ASIStopVideoCapture()` - Stop streaming

**Implementation:**
```python
# Start video mode
asi_lib.ASISetControlValue(camera_id, ASI_AUTO_MAX_EXP, video_exposure, ASI_FALSE)
asi_lib.ASISetControlValue(camera_id, ASI_EXPOSURE, 0, ASI_TRUE)  # Enable auto-exposure
asi_lib.ASIStartVideoCapture(camera_id)

# Capture loop (background thread)
while streaming:
    buffer = (ctypes.c_ubyte * buffer_size)()
    asi_lib.ASIGetVideoData(camera_id, buffer, buffer_size, timeout_ms, drop_frames)
    # Convert to image and serve via MJPEG
```

**Video Streaming Characteristics:**
- Format: RGB24 (always, for real-time performance)
- Frame rate: Controlled by `video_exposure` (max exposure time)
- MJPEG encoding: JPEG frames at 75% quality
- Stream endpoint: `/camera/stream` (multipart/x-mixed-replace)

#### 3. Photo Capture Mode

**SDK Functions Used:**
- `ASIStopVideoCapture()` - Must stop video first
- `ASISetControlValue()` - Set manual exposure/gain
- `ASIStartExposure()` - Start single exposure
- `ASIGetExpStatus()` - Check exposure status
- `ASIGetDataAfterExp()` - Retrieve image data

**Implementation:**
```python
# Stop video if running
if streaming:
    asi_lib.ASIStopVideoCapture(camera_id)
    time.sleep(0.5)

# Set manual exposure settings
asi_lib.ASISetControlValue(camera_id, ASI_EXPOSURE, exposure_us, ASI_FALSE)
asi_lib.ASISetControlValue(camera_id, ASI_GAIN, gain, ASI_FALSE)

# Start exposure
asi_lib.ASIStartExposure(camera_id, 0)  # 0 = not dark frame

# Wait for completion
while status != ASI_EXP_SUCCESS:
    asi_lib.ASIGetExpStatus(camera_id, status_ref)
    time.sleep(0.1)

# Retrieve image
asi_lib.ASIGetDataAfterExp(camera_id, buffer, buffer_size)
```

**Image Format Support:**
- RGB24: Color, 24-bit (default for video)
- RAW8: Raw Bayer pattern, 8-bit
- RAW16: Raw Bayer pattern, 16-bit
- Y8: Grayscale, 8-bit

**Format Selection:**
- Video stream: Always RGB24 (for performance)
- Photo capture: User-selectable (RGB24, RAW8, RAW16, Y8)
- Format change requires `ASISetROIFormat()` call

#### 4. Camera Control Parameters

**Gain Control:**
- Range: 0-300 (camera-dependent maximum)
- Control Type: `ASI_GAIN`
- Auto mode: Disabled for manual control
- Requires stream restart to apply changes

**Exposure Control:**
- Photo exposure: 0.001-10 seconds (1,000-10,000,000 microseconds)
- Video exposure: 0.001-1 second (max exposure time, controls frame rate)
- Control Type: `ASI_EXPOSURE`
- Auto mode: Enabled for video, disabled for photos

**Other Controls:**
- `ASI_BANDWIDTHOVERLOAD`: USB bandwidth limit (set to 40)
- `ASI_AUTO_MAX_EXP`: Maximum exposure in auto mode
- `ASI_TEMPERATURE`: Camera sensor temperature (read-only)

### Camera State Management

**State Variables:**
```python
camera_state = {
    'connected': False,      # Camera connection status
    'streaming': False,      # Video streaming active
    'camera_id': -1,         # SDK camera ID
    'width': 1280,           # Image width
    'height': 960,           # Image height
    'exposure': 1000000,     # Photo exposure (microseconds)
    'video_exposure': 100000, # Video max exposure (microseconds)
    'gain': 50,              # Gain value
    'image_format': ASI_IMG_RGB24,  # Current format
    'current_frame': None,   # Latest video frame
    'error': None            # Error message if any
}
```

**State Transitions:**
1. **Disconnected → Connected:** Camera initialization
2. **Connected → Streaming:** Start video capture
3. **Streaming → Photo Mode:** Stop video, start exposure
4. **Photo Mode → Streaming:** Resume video capture

### Error Handling

**SDK Error Codes:**
- `ASI_SUCCESS = 0`: Operation successful
- `ASI_ERROR_VIDEO_MODE_ACTIVE = 14`: Cannot start exposure while streaming
- `ASI_ERROR_EXPOSURE_IN_PROGRESS = 15`: Exposure already in progress
- `ASI_EXP_FAILED = 3`: Exposure failed (hardware error)

**Recovery Mechanisms:**
- Automatic stream restart on gain changes
- Camera reset function for stuck states
- Timeout handling for exposure operations
- Error logging and user notification

---

## 4. HTTP API Architecture

### API Endpoints

The camera service exposes a RESTful HTTP API:

**Status Endpoint:**
- `GET /status` - Get camera and system status
- Response: JSON with connection state, streaming status, errors

**Camera Control:**
- `POST /camera/stream/start` - Start video streaming
- `POST /camera/stream/stop` - Stop video streaming
- `GET /camera/stream` - MJPEG video stream (multipart)

**Photo Capture:**
- `GET /camera/snapshot` - Capture single photo
- `POST /camera/sequence/start` - Start sequence capture (background)
- `POST /camera/sequence/stop` - Stop sequence capture
- `GET /camera/sequence/status` - Get sequence status
- `POST /camera/sequence/capture` - Capture multiple photos (synchronous)

**Settings:**
- `POST /camera/settings` - Update gain, exposure, image format

### API Implementation

**Framework:** Flask (Python web framework)
- Lightweight, suitable for embedded/IoT applications
- CORS enabled for cross-origin requests
- Threaded mode for concurrent requests

**Request/Response Format:**
- Content-Type: `application/json`
- User-Agent: `Pomfret Observatory/1.1 (macOS)`
- Optional Bearer token authentication

**Example Request:**
```http
POST /camera/settings HTTP/1.1
Host: pomfret-obs.pomfretastro.org
Content-Type: application/json
User-Agent: Pomfret Observatory/1.1 (macOS)

{
  "gain": 100,
  "photo_exposure": 2000000,
  "video_exposure": 50000,
  "image_format": "RAW16"
}
```

**Example Response:**
```json
{
  "success": true,
  "gain": 100,
  "exposure": 2000000,
  "video_exposure": 50000,
  "image_format": "RAW16"
}
```

### MJPEG Video Streaming

**Protocol:** Multipart/x-mixed-replace (MJPEG)
- Continuous stream of JPEG frames
- No buffering, low latency
- Compatible with standard video players

**Implementation:**
```python
def generate():
    while camera_state['streaming']:
        frame = camera.frame_buffer
        if frame:
            img_io = io.BytesIO()
            frame.save(img_io, 'JPEG', quality=75)
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + 
                   img_io.read() + b'\r\n')
        time.sleep(0.1)

return Response(generate(), mimetype='multipart/x-mixed-replace; boundary=frame')
```

**Client Display:**
- macOS app uses `MJPEGStreamView` component
- Displays stream in real-time
- Auto-refreshes on connection

---

## 5. Security Considerations

### Network Security

1. **HTTPS/TLS Encryption**
   - All remote traffic encrypted via Cloudflare Tunnel
   - Automatic certificate management
   - No self-signed certificates required

2. **No Inbound Ports**
   - Cloudflare Tunnel uses outbound-only connections
   - No firewall rules needed
   - Reduces attack surface

3. **Local Network Access**
   - HTTP (not HTTPS) for local connections
   - Assumes trusted local network
   - Can be upgraded to HTTPS with self-signed certs if needed

### Application Security

1. **SSL Certificate Validation**
   - Client app accepts Cloudflare certificates
   - Custom `URLSessionDelegate` for certificate handling
   - Accepts all server trust (for Cloudflare compatibility)

2. **Authentication**
   - Optional Bearer token support
   - Currently using simple password protection
   - Can be enhanced with OAuth/JWT

3. **Input Validation**
   - API validates all parameters
   - Range checking for gain/exposure values
   - Path validation for file operations

### Access Control

**Current Implementation:**
- Password-protected login screen
- No role-based access control
- All authenticated users have full control

**Future Enhancements:**
- User roles (admin, operator, viewer)
- Audit logging
- Rate limiting

---

## 6. System Requirements

### Raspberry Pi (Server)

**Hardware:**
- Raspberry Pi 4 or newer (recommended)
- Raspberry Pi 3 also works but may have performance limitations
- USB 3.0 port (recommended for ASI cameras, USB 2.0 also works but slower)
- Network connection (Ethernet recommended, Wi-Fi also works)
- Minimum 2GB RAM (4GB+ recommended)
- 10GB free disk space (microSD card)

**Software:**
- Raspberry Pi OS (Debian-based Linux)
- Python 3.8+
- Flask, Flask-CORS, Pillow, NumPy
- ASI Camera SDK for Linux
- libusb-1.0 (via apt)
- cloudflared (for remote access)
- udev rules for camera access

**Network:**
- Outbound HTTPS (443) to Cloudflare
- Local network access (for local clients)

**Additional Setup:**
- udev rules must be installed for non-root camera access
- USB memory limit should be set to 200MB

### Client Mac

**Hardware:**
- Any Mac (macOS 13.0+)
- Network connection

**Software:**
- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for building)
- Swift 5.9+

---

## 7. Deployment Architecture

### Current Deployment

**Observatory Site:**
- Raspberry Pi running camera service
- USB-connected ASI camera
- cloudflared tunnel service
- Local IP: `172.18.2.101:8080` (example)
- Public URL: `https://pomfret-obs.pomfretastro.org`

**Client Access:**
- Local: Direct connection to `[RASPBERRY_PI_IP]:8080`
- Remote: Via Cloudflare Tunnel URL

### Service Management

**Camera Service:**
- Runs as Python script
- Can be managed via:
  - Terminal: `python3 camera_service.py`
  - systemd service (for auto-start)
  - Supervisor or similar process manager

**Cloudflare Tunnel:**
- Installed as Linux systemd service
- Auto-starts on boot
- Managed via: `sudo systemctl [start|stop|restart|status] cloudflared`
- Logs: `journalctl -u cloudflared`

### Monitoring and Logging

**Application Logs:**
- Built-in logging system in macOS app
- Viewable in app's Logs tab
- Includes API requests, errors, status updates

**Service Logs:**
- Python service: stdout/stderr or systemd journal
- Cloudflare Tunnel: systemd journal (`journalctl -u cloudflared`)
- Camera SDK: Console output
- System logs: `/var/log/syslog` or `journalctl`

---

## 8. Technical Specifications Summary

### Network Protocols
- **HTTP/HTTPS:** REST API communication
- **MJPEG:** Video streaming (multipart/x-mixed-replace)
- **WebSocket/HTTP2:** Cloudflare Tunnel protocol

### Data Formats
- **JSON:** API requests/responses
- **JPEG:** Video frames, photo snapshots
- **RAW8/RAW16:** Scientific image formats
- **PNG/TIFF:** Alternative photo formats

### Performance Characteristics
- **Video Frame Rate:** 1-30 FPS (depends on exposure)
- **Photo Capture Time:** ~1-10 seconds (depends on exposure)
- **API Latency:** 
  - Local: <10ms
  - Remote (via tunnel): 50-200ms
- **Video Stream Latency:** 100-500ms

### Scalability
- **Current:** Single camera, single client
- **Future:** Multiple cameras, multiple clients
- **Limitations:** USB bandwidth, network bandwidth

---

## 9. Troubleshooting Guide

### Common Issues

**Camera Not Connecting:**
- Check USB connection
- Verify `libusb` installation: `brew list libusb`
- Check camera service logs
- Verify camera is powered

**Tunnel Not Working:**
- Check cloudflared service: `sudo systemctl status cloudflared`
- Verify Cloudflare Dashboard configuration
- Check network connectivity: `ping cloudflare.com`
- Review tunnel logs: `journalctl -u cloudflared -f`

**Video Stream Not Displaying:**
- Verify camera is streaming: `GET /status`
- Test stream URL in browser
- Check network connection
- Verify MJPEG format compatibility

**High Latency:**
- Use local IP for lower latency
- Check network congestion
- Verify Cloudflare tunnel region
- Consider local caching

---

## 10. Future Enhancements

### Planned Improvements

1. **Multi-Camera Support**
   - Support for multiple ASI cameras
   - Camera selection/switching
   - Synchronized capture

2. **Enhanced Security**
   - OAuth 2.0 authentication
   - Role-based access control
   - Audit logging

3. **Performance Optimization**
   - Image compression options
   - Adaptive quality based on bandwidth
   - Local caching

4. **Monitoring**
   - System health dashboard
   - Alert notifications
   - Performance metrics

---

## Appendix: Key Files and Locations

### Source Code
- **Client App:** `Sources/APIClient.swift` - HTTP client implementation
- **Camera Service:** `camera_service.py` - Python service with SDK integration
- **Bridging Header:** `Sources/Bridging/ASICamera2-Bridging-Header.h` - SDK header reference

### Configuration
- **App Settings:** Stored in UserDefaults (macOS preferences)
- **Tunnel Config:** `~/.cloudflared/config.yml` (if using permanent tunnel)
- **Service Config:** Linux systemd service files (`/etc/systemd/system/cloudflared.service`)

### Documentation
- **README.md:** User-facing documentation
- **This Document:** Technical architecture (IT Office)

---

## Contact Information

**Project Maintainer:**  
Pomfret School  
Email: qtian.28@pomfret.org

**Technical Questions:**  
Please refer to this document or contact the project maintainer.

---

*Document Version: 1.0*  
*Last Updated: December 2025*

