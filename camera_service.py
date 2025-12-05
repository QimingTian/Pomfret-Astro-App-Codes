#!/usr/bin/env python3
"""
ASI Camera Service for Mac Mini
Provides HTTP API and MJPEG stream for remote access
"""

from flask import Flask, Response, jsonify, send_file
from flask_cors import CORS
import ctypes
import numpy as np
from PIL import Image
import io
import time
import threading
from datetime import datetime

app = Flask(__name__)
CORS(app)

# Load ASI Camera library
asi_lib = None
lib_paths = [
    '/Users/user/Desktop/ASI_linux_mac_SDK_V1.40/lib/mac/libASICamera2.dylib',
    '/Users/user/Desktop/ASI_linux_mac_SDK_V1.40/lib/mac_arm64/libASICamera2.dylib',
]

for lib_path in lib_paths:
    try:
        print(f"Trying to load: {lib_path}")
        asi_lib = ctypes.CDLL(lib_path)
        print(f"Successfully loaded: {lib_path}")
        break
    except Exception as e:
        print(f"Failed to load {lib_path}: {e}")

if asi_lib is None:
    print("ERROR: Could not load ASI Camera library")

# ASI Camera constants (from ASICamera2.h)
ASI_SUCCESS = 0
ASI_FALSE = 0
ASI_TRUE = 1

# Image types
ASI_IMG_RAW8 = 0
ASI_IMG_RGB24 = 1
ASI_IMG_RAW16 = 2
ASI_IMG_Y8 = 3

# Control types (IMPORTANT: Order from header file)
ASI_GAIN = 0
ASI_EXPOSURE = 1
ASI_GAMMA = 2
ASI_WB_R = 3
ASI_WB_B = 4
ASI_BRIGHTNESS = 5
ASI_BANDWIDTHOVERLOAD = 6
ASI_OVERCLOCK = 7
ASI_TEMPERATURE = 8
ASI_FLIP = 9
ASI_AUTO_MAX_GAIN = 10
ASI_AUTO_MAX_EXP = 11
ASI_AUTO_TARGET_BRIGHTNESS = 12
ASI_HARDWARE_BIN = 13
ASI_HIGH_SPEED_MODE = 14

# Camera state
camera_state = {
    'connected': False,
    'streaming': False,
    'camera_id': -1,
    'width': 1280,
    'height': 960,
    'exposure': 1000000,  # microseconds - for photo capture only
    'video_exposure': 100000,  # microseconds - max exposure for video streaming (controls frame rate)
    'gain': 50,
    'current_frame': None,
    'error': None
}

class ASICamera:
    def __init__(self):
        self.camera_id = -1
        self.is_open = False
        self.streaming = False
        self.frame_buffer = None
        self.capture_thread = None
        
    def connect(self):
        """Connect to the first available ASI camera"""
        if asi_lib is None:
            camera_state['error'] = "ASI library not loaded"
            return False
            
        try:
            # Get number of connected cameras
            num_cameras = asi_lib.ASIGetNumOfConnectedCameras()
            print(f"Found {num_cameras} camera(s)")
            
            if num_cameras == 0:
                camera_state['error'] = "No cameras found"
                return False
            
            # Get camera info
            class ASI_CAMERA_INFO(ctypes.Structure):
                _fields_ = [
                    ("Name", ctypes.c_char * 64),
                    ("CameraID", ctypes.c_int),
                    ("MaxHeight", ctypes.c_long),
                    ("MaxWidth", ctypes.c_long),
                    ("IsColorCam", ctypes.c_int),
                    ("BayerPattern", ctypes.c_int),
                    ("SupportedBins", ctypes.c_int * 16),
                    ("SupportedVideoFormat", ctypes.c_int * 8),
                    ("PixelSize", ctypes.c_double),
                    ("MechanicalShutter", ctypes.c_int),
                    ("ST4Port", ctypes.c_int),
                    ("IsCoolerCam", ctypes.c_int),
                    ("IsUSB3Host", ctypes.c_int),
                    ("IsUSB3Camera", ctypes.c_int),
                    ("ElecPerADU", ctypes.c_float),
                    ("BitDepth", ctypes.c_int),
                    ("IsTriggerCam", ctypes.c_int),
                ]
            
            camera_info = ASI_CAMERA_INFO()
            result = asi_lib.ASIGetCameraProperty(ctypes.byref(camera_info), 0)
            
            if result != ASI_SUCCESS:
                camera_state['error'] = f"Failed to get camera properties: {result}"
                return False
            
            self.camera_id = camera_info.CameraID
            camera_state['camera_id'] = self.camera_id
            camera_state['width'] = camera_info.MaxWidth
            camera_state['height'] = camera_info.MaxHeight
            
            print(f"Camera: {camera_info.Name.decode('utf-8')}")
            print(f"Resolution: {camera_info.MaxWidth} x {camera_info.MaxHeight}")
            print(f"Color: {'Yes' if camera_info.IsColorCam else 'No'}")
            
            # Open camera
            result = asi_lib.ASIOpenCamera(self.camera_id)
            if result != ASI_SUCCESS:
                camera_state['error'] = f"Failed to open camera: {result}"
                return False
            
            # Initialize camera
            result = asi_lib.ASIInitCamera(self.camera_id)
            if result != ASI_SUCCESS:
                camera_state['error'] = f"Failed to initialize camera: {result}"
                asi_lib.ASICloseCamera(self.camera_id)
                return False
            
            self.is_open = True
            
            # Set ROI format (full frame, RGB24)
            result = asi_lib.ASISetROIFormat(
                self.camera_id,
                camera_info.MaxWidth,
                camera_info.MaxHeight,
                1,  # bin
                ASI_IMG_RGB24
            )
            
            if result != ASI_SUCCESS:
                print(f"Warning: Failed to set ROI format: {result}")
            
            # Disable auto gain and auto exposure first (they might lock the values)
            asi_lib.ASISetControlValue(self.camera_id, ASI_GAIN, 0, ASI_TRUE)  # Turn OFF auto gain
            asi_lib.ASISetControlValue(self.camera_id, ASI_EXPOSURE, 0, ASI_TRUE)  # Turn OFF auto exposure
            time.sleep(0.1)
            
            # Set bandwidth
            asi_lib.ASISetControlValue(self.camera_id, ASI_BANDWIDTHOVERLOAD, 40, ASI_FALSE)
            
            # Set initial gain
            result_gain = asi_lib.ASISetControlValue(self.camera_id, ASI_GAIN, camera_state['gain'], ASI_FALSE)
            
            # Verify settings
            actual_gain = ctypes.c_long(0)
            auto_gain = ctypes.c_int(0)
            asi_lib.ASIGetControlValue(self.camera_id, ASI_GAIN, ctypes.byref(actual_gain), ctypes.byref(auto_gain))
            
            print(f"Initial settings:")
            print(f"  Gain: {camera_state['gain']} → actual: {actual_gain.value} (result: {result_gain})")
            print(f"  Exposure (for photo): {camera_state['exposure']} μs ({camera_state['exposure']/1000000:.3f} s)")
            
            camera_state['connected'] = True
            camera_state['error'] = None
            return True
            
        except Exception as e:
            camera_state['error'] = str(e)
            print(f"Error connecting to camera: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from camera"""
        self.stop_stream()
        if self.is_open and self.camera_id >= 0:
            asi_lib.ASICloseCamera(self.camera_id)
            self.is_open = False
        camera_state['connected'] = False
        camera_state['streaming'] = False
    
    def start_stream(self):
        """Start video streaming"""
        if not self.is_open:
            return False
        
        # Enable auto exposure for video mode, but limit max exposure time
        # This allows the camera to adjust exposure automatically while respecting the max limit
        video_exposure = camera_state['video_exposure']  # microseconds
        
        # Set ASI_AUTO_MAX_EXP to limit the maximum exposure time in video mode
        # This controls the frame rate: shorter max exposure = higher frame rate
        result_max_exp = asi_lib.ASISetControlValue(self.camera_id, ASI_AUTO_MAX_EXP, video_exposure, ASI_FALSE)
        
        # Enable auto exposure for video mode
        result_auto = asi_lib.ASISetControlValue(self.camera_id, ASI_EXPOSURE, 0, ASI_TRUE)
        
        print(f"[start_stream] Set video max exposure to {video_exposure} μs ({video_exposure/1000:.1f} ms)")
        print(f"[start_stream] ASI_AUTO_MAX_EXP result: {result_max_exp}, Auto exposure result: {result_auto}")
        
        print(f"[start_stream] Starting video capture")
        
        result = asi_lib.ASIStartVideoCapture(self.camera_id)
        if result != ASI_SUCCESS:
            camera_state['error'] = f"Failed to start video capture: {result}"
            return False
        
        self.streaming = True
        camera_state['streaming'] = True
        
        # Start capture thread
        self.capture_thread = threading.Thread(target=self._capture_loop, daemon=True)
        self.capture_thread.start()
        
        return True
    
    def stop_stream(self):
        """Stop video streaming"""
        self.streaming = False
        camera_state['streaming'] = False
        
        if self.capture_thread:
            self.capture_thread.join(timeout=2.0)
        
        if self.is_open and self.camera_id >= 0:
            asi_lib.ASIStopVideoCapture(self.camera_id)
    
    def _capture_loop(self):
        """Continuous capture loop for streaming"""
        width = camera_state['width']
        height = camera_state['height']
        buffer_size = width * height * 3  # RGB24
        buffer = (ctypes.c_ubyte * buffer_size)()
        consecutive_errors = 0
        
        while self.streaming and self.is_open:
            # Calculate timeout based on video exposure time
            # SDK recommends: exposure*2+500ms
            video_exposure_ms = camera_state['video_exposure'] / 1000.0  # Convert to ms
            timeout_ms = int(video_exposure_ms * 2 + 500)
            timeout_ms = max(1000, min(timeout_ms, 5000))  # Clamp between 1s and 5s
            
            drop_frames = ctypes.c_int(0)
            result = asi_lib.ASIGetVideoData(
                self.camera_id,
                ctypes.byref(buffer),
                buffer_size,
                timeout_ms,
                ctypes.byref(drop_frames)
            )
            
            if result == ASI_SUCCESS:
                consecutive_errors = 0  # Reset error counter
                # Convert to numpy array
                img_array = np.frombuffer(buffer, dtype=np.uint8)
                img_array = img_array.reshape((height, width, 3))
                
                # Convert to PIL Image
                img = Image.fromarray(img_array, mode='RGB')
                self.frame_buffer = img
                camera_state['current_frame'] = img
            elif result != 2:  # 2 = timeout, which is normal
                consecutive_errors += 1
                # Only print error if it persists
                if consecutive_errors == 1 or consecutive_errors % 10 == 0:
                    print(f"Error getting video data: {result} (consecutive: {consecutive_errors})")
            
            time.sleep(0.01)  # Small delay to prevent CPU overload
    
    def capture_snapshot(self):
        """Capture a single snapshot"""
        if not self.is_open:
            print("[capture_snapshot] Camera not open")
            return None
        
        # Wait for camera to be in IDLE state (in case previous exposure is still running)
        status = ctypes.c_int(0)
        asi_lib.ASIGetExpStatus(self.camera_id, ctypes.byref(status))
        
        if status.value != 0:  # Not IDLE
            print(f"[capture_snapshot] Camera not idle (status: {status.value}), waiting...")
            timeout = 0
            while status.value != 0 and timeout < 10000:  # Wait up to 10 seconds
                time.sleep(0.1)
                asi_lib.ASIGetExpStatus(self.camera_id, ctypes.byref(status))
                timeout += 100
            
            if status.value != 0:
                print(f"[capture_snapshot] Camera still not idle after timeout, forcing stop...")
                asi_lib.ASIStopExposure(self.camera_id)
                time.sleep(0.5)
        
        # Set exposure before capturing (can be long for detail)
        exposure = camera_state['exposure']
        gain_val = camera_state['gain']
        
        result_exp = asi_lib.ASISetControlValue(self.camera_id, ASI_EXPOSURE, exposure, ASI_FALSE)
        result_gain = asi_lib.ASISetControlValue(self.camera_id, ASI_GAIN, gain_val, ASI_FALSE)
        
        print(f"[capture_snapshot] Set exposure: {exposure} μs ({exposure/1000000:.3f} s) (result: {result_exp})")
        print(f"[capture_snapshot] Set gain: {gain_val} (result: {result_gain})")
        print(f"[capture_snapshot] Camera is idle, starting exposure...")
        
        # Start exposure
        result = asi_lib.ASIStartExposure(self.camera_id, 0)  # 0 = not dark frame (ASI_FALSE)
        if result != ASI_SUCCESS:
            error_names = {
                1: "ASI_ERROR_INVALID_INDEX",
                2: "ASI_ERROR_INVALID_ID", 
                3: "ASI_ERROR_INVALID_CONTROL_TYPE",
                4: "ASI_ERROR_CAMERA_CLOSED",
                5: "ASI_ERROR_CAMERA_REMOVED",
                6: "ASI_ERROR_INVALID_PATH",
                7: "ASI_ERROR_INVALID_FILEFORMAT",
                8: "ASI_ERROR_INVALID_SIZE",
                9: "ASI_ERROR_INVALID_IMGTYPE",
                10: "ASI_ERROR_OUTOF_BOUNDARY",
                11: "ASI_ERROR_TIMEOUT",
                12: "ASI_ERROR_INVALID_SEQUENCE",
                13: "ASI_ERROR_BUFFER_TOO_SMALL",
                14: "ASI_ERROR_VIDEO_MODE_ACTIVE",
                15: "ASI_ERROR_EXPOSURE_IN_PROGRESS",
                16: "ASI_ERROR_GENERAL_ERROR",
                17: "ASI_ERROR_INVALID_MODE"
            }
            error_name = error_names.get(result, f"UNKNOWN_ERROR_{result}")
            print(f"[capture_snapshot] Failed to start exposure: {result} ({error_name})")
            return None
        
        # Wait for exposure to complete
        status = ctypes.c_int(0)
        timeout = 0
        max_timeout = (exposure // 1000) + 5000  # ms
        
        while timeout < max_timeout:
            asi_lib.ASIGetExpStatus(self.camera_id, ctypes.byref(status))
            if status.value == 2:  # ASI_EXP_SUCCESS
                break
            time.sleep(0.1)
            timeout += 100
        
        if status.value != 2:
            status_names = {0: "ASI_EXP_IDLE", 1: "ASI_EXP_WORKING", 2: "ASI_EXP_SUCCESS", 3: "ASI_EXP_FAILED"}
            status_name = status_names.get(status.value, f"UNKNOWN_{status.value}")
            print(f"[capture_snapshot] Exposure failed with status: {status.value} ({status_name})")
            return None
        
        # Get image data
        width = camera_state['width']
        height = camera_state['height']
        buffer_size = width * height * 3
        buffer = (ctypes.c_ubyte * buffer_size)()
        
        result = asi_lib.ASIGetDataAfterExp(self.camera_id, ctypes.byref(buffer), buffer_size)
        if result != ASI_SUCCESS:
            error_names = {
                1: "ASI_ERROR_INVALID_INDEX",
                2: "ASI_ERROR_INVALID_ID", 
                3: "ASI_ERROR_INVALID_CONTROL_TYPE",
                4: "ASI_ERROR_CAMERA_CLOSED",
                5: "ASI_ERROR_CAMERA_REMOVED",
                11: "ASI_ERROR_TIMEOUT",
                13: "ASI_ERROR_BUFFER_TOO_SMALL",
                16: "ASI_ERROR_GENERAL_ERROR"
            }
            error_name = error_names.get(result, f"UNKNOWN_ERROR_{result}")
            print(f"[capture_snapshot] Failed to get image data: {result} ({error_name})")
            return None
        
        # Convert to PIL Image
        img_array = np.frombuffer(buffer, dtype=np.uint8)
        img_array = img_array.reshape((height, width, 3))
        img = Image.fromarray(img_array, 'RGB')
        
        return img

# Global camera instance
camera = ASICamera()

# API Routes
@app.route('/status', methods=['GET'])
def get_status():
    """Get camera status - ONLY return camera data, nothing else"""
    # This controller ONLY handles cameras
    # Other controllers will handle roof, environment sensors, etc.
    return jsonify({
        'sensors': {
            'temperature': None,  # This controller doesn't have environment sensors
            'humidity': None,     # This controller doesn't have environment sensors
            'weatherCam': {
                'connected': camera_state['connected'],
                'streaming': camera_state['streaming'],
                'lastSnapshot': datetime.now().isoformat() if camera_state['current_frame'] else None,
                'fault': camera_state['error']
            },
            'meteorCam': {
                'connected': camera_state['connected'],
                'streaming': camera_state['streaming'],
                'lastSnapshot': datetime.now().isoformat() if camera_state['current_frame'] else None,
                'fault': camera_state['error']
            }
        }
        # No 'roof', 'safety', or 'alerts' - this controller doesn't handle those
    })

@app.route('/camera/connect', methods=['POST'])
def connect_camera():
    """Connect to camera"""
    if camera.connect():
        return jsonify({'success': True, 'message': 'Camera connected'})
    return jsonify({'success': False, 'message': camera_state['error']}), 500

@app.route('/camera/disconnect', methods=['POST'])
def disconnect_camera():
    """Disconnect camera"""
    camera.disconnect()
    return jsonify({'success': True, 'message': 'Camera disconnected'})

@app.route('/camera/stream/start', methods=['POST'])
def start_stream():
    """Start video stream"""
    if camera.start_stream():
        return jsonify({'success': True, 'message': 'Stream started'})
    return jsonify({'success': False, 'message': camera_state['error']}), 500

@app.route('/camera/stream/stop', methods=['POST'])
def stop_stream():
    """Stop video stream"""
    camera.stop_stream()
    return jsonify({'success': True, 'message': 'Stream stopped'})

@app.route('/camera/snapshot', methods=['GET'])
def snapshot():
    """Get a snapshot - automatically stops/resumes stream if needed"""
    print(f"[Snapshot] Request. Streaming: {camera_state['streaming']}")
    
    # Check if camera is connected
    if not camera_state['connected'] or not camera.is_open:
        error_msg = "Camera not connected"
        print(f"[Snapshot] Error: {error_msg}")
        return jsonify({'error': error_msg}), 500
    
    # Remember if we were streaming
    was_streaming = camera.streaming
    
    try:
        # MUST stop video capture before exposure mode
        if was_streaming:
            print("[Snapshot] Stopping stream for capture...")
            camera.stop_stream()
            time.sleep(0.5)
        
        print(f"[Snapshot] Capturing with exposure: {camera_state['exposure']} μs ({camera_state['exposure']/1000000:.3f} s)")
        img = camera.capture_snapshot()
        
        # Resume streaming if it was active
        if was_streaming:
            print("[Snapshot] Resuming stream...")
            time.sleep(0.3)
            camera.start_stream()
        
        if img:
            img_io = io.BytesIO()
            img.save(img_io, 'JPEG', quality=85)
            img_io.seek(0)
            print(f"[Snapshot] Success!")
            return send_file(img_io, mimetype='image/jpeg')
        else:
            error_msg = 'Failed to capture snapshot - camera returned None'
            print(f"[Snapshot] Error: {error_msg}")
            return jsonify({'error': error_msg}), 500
            
    except Exception as e:
        import traceback
        error_details = traceback.format_exc()
        print(f"[Snapshot] Exception: {e}")
        print(f"[Snapshot] Traceback:\n{error_details}")
        if was_streaming and not camera.streaming:
            try:
                camera.start_stream()
            except:
                pass
        return jsonify({'error': f'Exception: {str(e)}'}), 500

@app.route('/camera/stream', methods=['GET'])
def video_stream():
    """MJPEG video stream"""
    def generate():
        while camera_state['streaming']:
            frame = camera.frame_buffer
            if frame:
                img_io = io.BytesIO()
                frame.save(img_io, 'JPEG', quality=75)
                img_io.seek(0)
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n\r\n' + img_io.read() + b'\r\n')
            time.sleep(0.1)
    
    return Response(generate(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/camera/settings', methods=['POST'])
def update_settings():
    """Update camera settings"""
    from flask import request
    data = request.get_json()
    print(f"[Settings] Request received: {data}")
    
    updated = []
    
    if 'gain' in data:
        gain = int(data['gain'])
        camera_state['gain'] = gain
        
        # Remember if streaming (need to restart for gain to take effect)
        was_streaming = camera_state['streaming']
        print(f"[Settings] Current streaming state: {was_streaming}")
        
        if camera.is_open:
            # Stop stream if active (gain changes need stream restart)
            if was_streaming:
                print(f"[Settings] Stopping stream to apply gain...")
                camera.stop_stream()
                time.sleep(0.5)
                print(f"[Settings] Stream stopped. State: {camera_state['streaming']}")
            
            result = asi_lib.ASISetControlValue(camera.camera_id, ASI_GAIN, gain, ASI_FALSE)
            
            # Verify it was set
            actual_gain = ctypes.c_long(0)
            auto_gain = ctypes.c_int(0)
            asi_lib.ASIGetControlValue(camera.camera_id, ASI_GAIN, ctypes.byref(actual_gain), ctypes.byref(auto_gain))
            
            print(f"[Settings] Set gain to {gain} (result: {result})")
            print(f"[Settings] Verified gain: {actual_gain.value} (auto: {auto_gain.value})")
            updated.append(f"gain={gain}")
            
            # Restart stream if it was active
            if was_streaming:
                print(f"[Settings] Restarting stream with new gain...")
                time.sleep(0.5)
                success = camera.start_stream()
                print(f"[Settings] Stream restart result: {success}, State: {camera_state['streaming']}")
    
    if 'photo_exposure' in data:
        exposure_us = int(data['photo_exposure'])
        camera_state['exposure'] = exposure_us
        print(f"[Settings] Set photo exposure: {exposure_us} μs = {exposure_us/1000000:.3f} s")
        updated.append(f"photo_exposure={exposure_us}us")
    
    if 'video_exposure' in data:
        video_exposure_us = int(data['video_exposure'])
        camera_state['video_exposure'] = video_exposure_us
        
        # Remember if streaming (need to restart for video_exposure to take effect)
        was_streaming = camera_state['streaming']
        print(f"[Settings] Setting video exposure: {video_exposure_us} μs ({video_exposure_us/1000:.1f} ms)")
        
        if camera.is_open:
            # Stop stream if active (video_exposure changes need stream restart)
            if was_streaming:
                print(f"[Settings] Stopping stream to apply video exposure...")
                camera.stop_stream()
                time.sleep(0.5)
            
            # Set ASI_AUTO_MAX_EXP to limit max exposure time in video mode
            result = asi_lib.ASISetControlValue(camera.camera_id, ASI_AUTO_MAX_EXP, video_exposure_us, ASI_FALSE)
            
            # Verify it was set
            actual_max_exp = ctypes.c_long(0)
            auto_max_exp = ctypes.c_int(0)
            asi_lib.ASIGetControlValue(camera.camera_id, ASI_AUTO_MAX_EXP, ctypes.byref(actual_max_exp), ctypes.byref(auto_max_exp))
            
            print(f"[Settings] Set ASI_AUTO_MAX_EXP to {video_exposure_us} μs (result: {result})")
            print(f"[Settings] Verified ASI_AUTO_MAX_EXP: {actual_max_exp.value} μs")
            updated.append(f"video_exposure={video_exposure_us}us")
            
            # Restart stream if it was active
            if was_streaming:
                print(f"[Settings] Restarting stream with new video exposure...")
                time.sleep(0.5)
                success = camera.start_stream()
                print(f"[Settings] Stream restart result: {success}, State: {camera_state['streaming']}")
    
    print(f"[Settings] Updated: {', '.join(updated) if updated else 'nothing'}")
    print(f"[Settings] State now - Gain: {camera_state['gain']}, Photo Exposure: {camera_state['exposure']} μs, Video Exposure: {camera_state['video_exposure']} μs")
    
    return jsonify({
        'success': True,
        'gain': camera_state['gain'],
        'exposure': camera_state['exposure'],
        'video_exposure': camera_state['video_exposure']
    })

if __name__ == '__main__':
    print("Starting ASI Camera Service...")
    print("Attempting to connect to camera...")
    
    if camera.connect():
        print("Camera connected successfully!")
    else:
        print(f"Failed to connect to camera: {camera_state['error']}")
        print("Service will start anyway, you can try connecting via API")
    
    print("Starting HTTP server on port 8080...")
    app.run(host='0.0.0.0', port=8080, debug=False, threaded=True)

