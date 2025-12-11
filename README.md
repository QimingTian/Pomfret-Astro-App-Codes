# Pomfret Astro

macOS application for controlling the Pomfret School VISTA Observatory, including camera control and environmental monitoring.

## Version History

### Version 3.0
**Release Date:** December 2025

**Major Changes:**
- **Time-Lapse Photography** - New interval-based sequence capture mode for time-lapse photography
- **Significant FPS Improvements** - Video streaming frame rate dramatically increased (from 6-8 FPS to 20-30+ FPS)
- **Enhanced Camera Controls** - Direct numerical input for all camera settings
- **Extended Exposure Range** - Photo exposure range expanded to 0.01s - 1000s
- **Fixed Video Exposure Control** - Video exposure now correctly affects both brightness and frame rate
- **Code Optimization** - Removed redundant ASI_AUTO_MAX_EXP settings in manual exposure mode

**New Features:**
- **Time-Lapse Mode** - Sequence capture with configurable interval (0 = fast mode, >0 = time-lapse)
  - Fast mode: Continuous capture with minimal delay
  - Time-lapse mode: Capture photos at fixed intervals (e.g., every 30 seconds)
  - All photos saved locally on Mac
  - Local progress bar calculation based on exposure and interval
- **Text Input Fields** - Direct numerical input for Gain, Photo Exposure, and Video Exposure (similar to Interval)
- **Improved UI** - Cleaner interface with "Set" buttons for all settings
- **Better Control** - All camera parameters now support both slider and text input for precise adjustments
- **Local Progress Bars** - Smooth progress tracking for both single photo and sequence capture, calculated locally without server polling

**Performance Improvements:**
- **FPS Optimization** - Removed artificial frame rate limits:
  - Video stream generation: sleep reduced from 100ms → 5ms (removed ~10 FPS limit)
  - Capture loop: sleep reduced from 10ms → 1ms (reduced latency)
  - Timeout minimum: reduced from 1000ms → 100ms (faster response)
  - Frame rate now dynamically adjusts with video_exposure settings (1ms exposure ≈ 30+ FPS, 100ms exposure ≈ 10 FPS)

**Technical Improvements:**
- Fixed video_exposure update logic: now correctly sets ASI_EXPOSURE in manual mode
- Removed unnecessary ASI_AUTO_MAX_EXP settings (only needed in auto exposure mode)
- Simplified code by removing redundant parameter settings
- Enhanced exposure control accuracy and responsiveness
- Local progress calculation for better responsiveness and smoother UI updates

**Bug Fixes:**
- Fixed issue where video_exposure affected brightness but not frame rate
- Corrected manual exposure mode implementation
- Improved gain and exposure control consistency

### Version 2.1
**Release Date:** December 2025

**Major Changes:**
- **Raspberry Pi Support** - Full migration from Mac Mini to Raspberry Pi
- **Linux/ARM Architecture** - Automatic detection and support for ARMv6, ARMv7, and ARMv8 (64-bit)
- **Cross-Platform SDK** - Unified SDK loading for both macOS and Linux
- **Improved Setup** - Simplified installation process for Raspberry Pi OS

**Technical Improvements:**
- Automatic architecture detection in camera service
- Support for Raspberry Pi OS (Debian-based Linux)
- Updated installation instructions for apt package manager
- Enhanced error messages for Linux-specific issues
- USB memory limit configuration for optimal camera performance

**Migration Notes:**
- Server platform changed from macOS to Raspberry Pi OS
- Installation uses `apt` instead of Homebrew
- Requires udev rules for non-root camera access
- USB memory limit must be set to 200MB

### Version 2.0
**Release Date:** December 6, 2025

**Major Changes:**
-  **Rebranded to "Pomfret Astro"** - New name and simplified focus on camera control
-  **Dramatically Improved Photo Capture Speed** - Removed unnecessary waits, instant photo capture
-  **Advanced Image Format Support** - Select camera format (RGB24, RAW8, RAW16, Y8) before capture
-  **Flexible File Format Options** - Save photos as JPEG, PNG, or TIFF
-  **Sequence Capture** - Take multiple photos continuously with progress tracking

**New Features:**
-  **Photo Saving** - Save captured photos to local machine with format selection
-  **Camera Format Selection** - Choose RGB24, RAW8, RAW16, or Y8 before taking photos
-  **File Format Selection** - Save photos as JPEG (100% quality), PNG, or TIFF
-  **Sequence Capture** - Capture multiple photos in sequence with:
  - Customizable count (1-100+)
  - Progress bar with time estimation
  - Persistent state across tab switches
  - Local file saving with security-scoped bookmarks
-  **Instant Photo Capture** - Optimized camera control logic, no unnecessary delays

**Technical Improvements:**
- Simplified camera control logic based on asicap implementation
- Removed complex state management and unnecessary waits
- Streamlined API endpoints
- Improved error handling and logging
- Better camera state transitions

### Version 1.1
**Release Date:** December 4, 2025

**Major Features:**
- **Remote Access via Cloudflare Tunnel** - Access observatory from anywhere with permanent URL `https://pomfret-obs.pomfretastro.org`
- **Dual Exposure Controls** - Separate settings for video streaming (0.001-1s) and photo capture (0.001-10s)
- **Settings Persistence** - Camera settings saved across app restarts
- **HTTPS Support** - Full SSL/TLS certificate handling
- **Improved Gain Control** - Automatic stream restart when adjusting gain

**Technical Improvements:**
- Info.plist configuration for App Transport Security
- URLSession delegate for SSL certificate validation
- Enhanced Python service with dual exposure state management
- User-Agent headers for Cloudflare compatibility
- Comprehensive error logging and debugging

### Version 1.0
**Release Date:** December 2, 2025

**Initial Features:**
- SwiftUI application for macOS 13.0+
- ASI camera control (ZWO 120MC/676MC)
- Real-time MJPEG video streaming
- Camera settings adjustment (Gain, Exposure)
- Photo capture functionality
- Multi-controller architecture
- Local network access

## System Architecture

### Components

1. **SwiftUI Application** (this project)
   - Runs on any Mac (macOS 13.0+)
   - Provides unified control interface
   - Displays real-time camera feeds
   - Monitors environmental conditions
   - Controls observatory roof and equipment

2. **Camera Service** (`camera_service.py`)
   - Runs on Raspberry Pi at observatory site (Raspberry Pi 4 or newer recommended for 24/7 operation)
   - Controls ASI all-sky cameras (120MC/676MC)
   - Provides HTTP API and MJPEG video stream
   - **System Requirements:**
     - Raspberry Pi (Raspberry Pi OS / Debian-based Linux)
     - USB 3.0 interface for ASI camera (USB 2.0 also works but slower)
     - Python 3, Flask, NumPy, Pillow
     - ASI Camera SDK for Linux
     - libusb-1.0 (via apt)

3. **Hardware Controllers**
   - Camera control system
   - ASI camera support (ZWO 120MC/676MC)

## Quick Start

### Running the Application

1. Open `Pomfret Astro.xcodeproj` in Xcode
2. Build and run (⌘R)
3. Login with password: `VISTAobs`
4. Configure controllers in Settings

### Setting up Camera Service (Raspberry Pi)

**Note:** Raspberry Pi 4 or newer is recommended for 24/7 operation. Raspberry Pi 3 also works but may have performance limitations. The service automatically detects the Pi architecture (armv6/armv7/armv8).

1. Install system dependencies:
```bash
sudo apt update
sudo apt install -y python3-pip python3-numpy libusb-1.0-0
```

2. Install Python dependencies:
```bash
pip3 install flask flask-cors pillow
```

3. Install ASI Camera SDK udev rules (required for non-root access):
```bash
# Copy udev rules
sudo cp ASI_linux_mac_SDK_V1.40/lib/asi.rules /etc/udev/rules.d/
# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
# Reconnect camera or reboot
```

4. Verify USB memory limit (should be 200MB):
```bash
cat /sys/module/usbcore/parameters/usbfs_memory_mb
# If not 200, set it:
echo 200 | sudo tee /sys/module/usbcore/parameters/usbfs_memory_mb
# To make it permanent, add to /etc/modprobe.d/usbcore.conf:
# options usbcore usbfs_memory_mb=200
```

5. Run the service:
```bash
cd ~/Desktop
python3 camera_service.py
```

6. The service will automatically detect your Raspberry Pi architecture and load the correct SDK library. Service will run on `http://[RASPBERRY_PI_IP]:8080`

### Setting up Remote Access (Cloudflare Tunnel)

#### Option 1: Temporary URL (Quick Setup)

For quick temporary access without configuration:

1. Install cloudflared on Raspberry Pi:
```bash
# Download and install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
# For 32-bit Pi, use: cloudflared-linux-arm
sudo mv cloudflared-linux-arm64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
```

2. Run cloudflared tunnel in terminal:
```bash
cloudflared tunnel --url http://localhost:8080
```

3. Cloudflared will generate a temporary URL like:
   ```
   https://random-name-1234.trycloudflare.com
   ```

4. Use this temporary URL in the app's Settings:
   - **Base URL**: `https://random-name-1234.trycloudflare.com`
   - This URL is valid until you close the terminal or stop cloudflared

**Note:** The temporary URL changes each time you restart cloudflared.

#### Option 2: Permanent URL (Requires Cloudflare Account)

For permanent remote access with a fixed URL:

1. Install cloudflared on Raspberry Pi:
```bash
# Download and install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
# For 32-bit Pi, use: cloudflared-linux-arm
sudo mv cloudflared-linux-arm64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
```

2. Create and configure tunnel:
   - Login to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
   - Navigate to **Networks** → **Tunnels**
   - Create a new tunnel, get the token
   - Install on Raspberry Pi:
```bash
sudo cloudflared service install <YOUR_TOKEN>
```

3. Configure Public Hostname:
   - Add hostname in Cloudflare Dashboard
   - Service: `http://localhost:8080`
   - Your permanent URL: `https://pomfret-obs.pomfretastro.org`

4. The tunnel service will auto-start on Raspberry Pi boot

### Adding Controllers

**For Local Access (same network):**
1. Go to **Settings** tab
2. Click **Add Controller** or edit existing
3. Configure:
   - **Name**: Camera Service
   - **Base URL**: `http://172.18.2.101:8080` (Raspberry Pi local IP)
   - **Roles**: Check "Cameras"
4. Click **Connect**

**For Remote Access (from anywhere):**

**Using Temporary URL:**
1. On Raspberry Pi, run: `cloudflared tunnel --url http://localhost:8080`
2. Copy the generated URL (e.g., `https://random-name-1234.trycloudflare.com`)
3. In app Settings, set **Base URL** to the temporary URL
4. Click **Connect**
5. **Note:** URL changes each time you restart cloudflared

**Using Permanent URL:**
1. Use the permanent Cloudflare URL:
   - **Base URL**: `https://pomfret-obs.pomfretastro.org`
2. Same roles configuration as above
3. Works from any internet connection

## Features

### Camera System
- ASI 120MC / 676MC all-sky cameras
- Real-time MJPEG video streaming with adjustable stream exposure (0.001-1s)
- High-quality photo capture with separate exposure control (0.001-10s)
- **Camera format selection** - RGB24, RAW8, RAW16, Y8
- **File format selection** - JPEG (100% quality), PNG, TIFF
- **Sequence capture** - Take multiple photos continuously with progress tracking
- Adjustable gain (0-300, camera-dependent maximum)
- Settings persist across sessions
- Automatic stream restart when adjusting gain
- **Instant photo capture** - Optimized for speed, no unnecessary delays

### Multi-Controller Support
- Connect to multiple camera controllers
- Camera role only (simplified architecture)
- Automatic status refresh every 5 seconds
- Comprehensive logging system

## Project Structure

```
Sources/
├── APIClient.swift              # HTTP API client
├── AppState.swift               # Application state management
├── ObservatoryApp.swift         # Main app entry point
├── ContentView.swift            # Main navigation
├── MenuBarPresenter.swift       # Menu bar status
├── Models/
│   ├── ControllerState.swift   # Controller management
│   └── WeatherClient.swift     # Weather data fetching
├── Views/
│   ├── LoginView.swift          # Authentication
│   ├── SensorsView.swift        # Camera control (Camera tab)
│   ├── WeatherView.swift        # Weather display
│   ├── LogsView.swift           # System logs
│   ├── SettingsView.swift       # Configuration
│   └── Components/
│       ├── MJPEGStreamView.swift  # Video stream display
│       └── StatusBadge.swift      # Status indicators
└── Bridging/
    └── ASICamera2-Bridging-Header.h

camera_service.py                # Camera control service (for Raspberry Pi)

ThirdParty/
└── ASISDK/                      # ASI Camera SDK
    ├── include/
    └── lib/
```

## Camera Service API

### Endpoints

- `GET /status` - Get camera status
- `POST /camera/stream/start` - Start video streaming
- `POST /camera/stream/stop` - Stop video streaming
- `GET /camera/snapshot` - Capture single image
- `GET /camera/stream` - MJPEG video stream
- `POST /camera/settings` - Update camera settings (gain, exposure, image format)
- `POST /camera/sequence/capture` - Capture multiple photos in sequence

### Status Response Format

```json
{
  "sensors": {
    "weatherCam": {
      "connected": true,
      "streaming": false,
      "lastSnapshot": "2025-12-02T20:00:00Z",
      "fault": null
    },
    "meteorCam": {
      "connected": true,
      "streaming": false,
      "lastSnapshot": "2025-12-02T20:00:00Z",
      "fault": null
    }
  }
}
```

## Hardware

### Current Setup
- **Camera**: ZWO ASI 120MC (1280x960, color)
- **Future**: ZWO ASI 676MC (3008x3008, color)
- **Server**: Raspberry Pi 4 (or newer) running camera service
- **Network**: Local network connection required

**Server Requirements:**
- Raspberry Pi 4 or newer (Raspberry Pi 3 also works but may have performance limitations)
- Raspberry Pi OS (Debian-based Linux)
- USB 3.0 interface (recommended for ASI cameras, USB 2.0 also works but slower)
- ASI Camera SDK for Linux installed
- Python 3 with required dependencies
- libusb-1.0 installed

### Camera Specifications

**ASI 120MC**
- Resolution: 1280 x 960
- Pixel Size: 3.75μm
- Color sensor
- USB 3.0 interface

**ASI 676MC** (when available)
- Resolution: 3008 x 3008
- Pixel Size: 2.0μm
- Color sensor
- USB 3.0 interface

## Development

### Requirements
- Xcode 15.0+
- macOS 13.0+ (deployment target)
- Swift 5.9+

### Building
```bash
open "Pomfret Astro.xcodeproj"
# Build in Xcode (⌘B)
```

## Troubleshooting

### Camera Not Connecting
- Check USB connection to Raspberry Pi
- Verify `libusb-1.0` is installed: `sudo apt install libusb-1.0-0`
- Verify udev rules are installed: `ls /etc/udev/rules.d/asi.rules`
- Reload udev rules: `sudo udevadm control --reload-rules && sudo udevadm trigger`
- Check camera service is running
- Verify network connectivity
- Check USB memory limit: `cat /sys/module/usbcore/parameters/usbfs_memory_mb` (should be 200)

### Video Stream Not Displaying
- Ensure camera is streaming (check status)
- Test stream in browser: `http://[RASPBERRY_PI_IP]:8080/camera/stream`
- Check network connection
- Review logs in application
- Check Raspberry Pi CPU/memory usage (may need to reduce video quality for older Pi)

### Application Crashes on Login
- Ensure no controllers are configured to auto-connect
- Check network connectivity
- Review crash logs

## License

Pomfret School VISTA Observatory Project

## Contact

Pomfret School
qtian.28@pomfret.org
