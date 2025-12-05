# Pomfret VISTA Observatory Control System

macOS application for controlling the Pomfret School VISTA Observatory, including roof control, environmental monitoring, and all-sky camera systems.

## Version History

### Version 1.1 (Current)
**Release Date:** December 4, 2025

**Major Features:**
- ✅ **Remote Access via Cloudflare Tunnel** - Access observatory from anywhere with permanent URL `https://pomfret-obs.pomfretastro.org`
- ✅ **Dual Exposure Controls** - Separate settings for video streaming (0.001-1s) and photo capture (0.001-10s)
- ✅ **Settings Persistence** - Camera settings saved across app restarts
- ✅ **HTTPS Support** - Full SSL/TLS certificate handling
- ✅ **Improved Gain Control** - Automatic stream restart when adjusting gain

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
   - Runs on Mac Mini at observatory site
   - Controls ASI all-sky cameras (120MC/676MC)
   - Provides HTTP API and MJPEG video stream
   - Requires: Python 3, Flask, NumPy, Pillow

3. **Hardware Controllers**
   - Roof control system
   - Environmental sensors (temperature, humidity)
   - Side-wall panels (future)

## Quick Start

### Running the Application

1. Open `Pomfret VISTA Observatory.xcodeproj` in Xcode
2. Build and run (⌘R)
3. Login with password: `VISTAobs`
4. Configure controllers in Settings

### Setting up Camera Service (Mac Mini)

1. Install dependencies:
```bash
pip3 install flask flask-cors pillow numpy
brew install libusb
```

2. Run the service:
```bash
cd ~/Desktop
python3 camera_service.py
```

3. Service will run on `http://[MAC_MINI_IP]:8080`

### Setting up Remote Access (Cloudflare Tunnel)

For permanent remote access from anywhere:

1. Install cloudflared on Mac Mini:
```bash
brew install cloudflare/cloudflare/cloudflared
```

2. Create and configure tunnel:
   - Login to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
   - Navigate to **Networks** → **Tunnels**
   - Create a new tunnel, get the token
   - Install on Mac Mini:
```bash
cloudflared service install <YOUR_TOKEN>
```

3. Configure Public Hostname:
   - Add hostname in Cloudflare Dashboard
   - Service: `http://localhost:8080`
   - Your permanent URL: `https://pomfret-obs.pomfretastro.org`

4. The tunnel service will auto-start on Mac Mini boot

### Adding Controllers

**For Local Access (same network):**
1. Go to **Settings** tab
2. Click **Add Controller** or edit existing
3. Configure:
   - **Name**: Camera Service
   - **Base URL**: `http://172.18.2.101:8080` (Mac Mini local IP)
   - **Roles**: Check "Cameras" and "Environment Sensors"
4. Click **Connect**

**For Remote Access (from anywhere):**
1. Use the permanent Cloudflare URL:
   - **Base URL**: `https://pomfret-obs.pomfretastro.org`
2. Same roles configuration as above
3. Works from any internet connection

## Features

### Roof Control
- Open/close observatory roof
- Emergency stop
- Magnetic lock control
- Real-time status monitoring

### Camera System
- ASI 120MC / 676MC all-sky cameras
- Real-time MJPEG video streaming with adjustable stream exposure (0.001-1s)
- High-quality photo capture with separate exposure control (0.001-10s)
- Adjustable gain (0-300, camera-dependent maximum)
- Settings persist across sessions
- Automatic stream restart when adjusting gain

### Environmental Monitoring
- Temperature and humidity sensors
- Weather data integration
- Safety checks (rain, wind, door status)

### Multi-Controller Support
- Connect to multiple hardware controllers
- Each controller can have multiple roles
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
│   ├── RoofView.swift           # Roof control interface
│   ├── SensorsView.swift        # Sensors & cameras
│   ├── WeatherView.swift        # Weather display
│   ├── LogsView.swift           # System logs
│   ├── SettingsView.swift       # Configuration
│   └── Components/
│       ├── MJPEGStreamView.swift  # Video stream display
│       ├── StatusBadge.swift      # Status indicators
│       └── ConfirmDialog.swift    # Confirmation dialogs
└── Bridging/
    └── ASICamera2-Bridging-Header.h

camera_service.py                # Camera control service (for Mac Mini)

ThirdParty/
└── ASISDK/                      # ASI Camera SDK
    ├── include/
    └── lib/
```

## Camera Service API

### Endpoints

- `GET /status` - Get camera and sensor status
- `POST /camera/stream/start` - Start video streaming
- `POST /camera/stream/stop` - Stop video streaming
- `GET /camera/snapshot` - Capture single image
- `GET /camera/stream` - MJPEG video stream

### Status Response Format

```json
{
  "sensors": {
    "temperature": null,
    "humidity": null,
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
- **Mac Mini**: Intel, running camera service
- **Network**: Local network connection required

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
open "Pomfret VISTA Observatory.xcodeproj"
# Build in Xcode (⌘B)
```

## Troubleshooting

### Camera Not Connecting
- Check USB connection to Mac Mini
- Verify `libusb` is installed: `brew install libusb`
- Check camera service is running
- Verify network connectivity

### Video Stream Not Displaying
- Ensure camera is streaming (check status)
- Test stream in browser: `http://[MAC_MINI_IP]:8080/camera/stream`
- Check network connection
- Review logs in application

### Application Crashes on Login
- Ensure no controllers are configured to auto-connect
- Check network connectivity
- Review crash logs

## License

Pomfret School VISTA Observatory Project

## Contact

Pomfret School
qtian.28@pomfret.org
