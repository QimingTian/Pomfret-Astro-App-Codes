# Version 1.1 Release Notes
**December 4, 2025**

## New Features

1. **Permanent Remote Access** - Access observatory from anywhere using `https://pomfret-obs.pomfretastro.org` (Cloudflare Tunnel)
2. **Real-Time FPS Display** - Monitor stream performance (shown in top-left corner)
3. **Photo Metadata Display** - View Gain and Exposure settings on captured photos
4. **Auto-Refresh Stream** - Video automatically refreshes when adjusting Gain
5. **Settings Persistence** - Gain and Exposure values saved across sessions
6. **Simplified Exposure Control** - Single Exposure slider (0.001-10s) for photo capture
7. **SSL/TLS Support** - Secure HTTPS connections with certificate handling

## Improvements

- Gain range adjusted to 0-100 (hardware maximum)
- Increased video capture timeout for better stability
- Reduced error log spam
- Stream view no longer shows stale photo after capture
- Enhanced debugging logs for troubleshooting

## Bug Fixes

- Fixed settings resetting when switching tabs
- Fixed stream view stuck on photo after capture
- Fixed SSL certificate validation errors
- Fixed gain changes not applying to video stream

## Setup

**Remote Access:** Base URL = `https://pomfret-obs.pomfretastro.org`  
**Local Access:** Base URL = `http://172.18.2.101:8080` (faster when at school)

