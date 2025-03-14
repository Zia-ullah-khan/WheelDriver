# WheelDriver

A system that connects physical racing wheels or joysticks to Roblox vehicles through a Python web server middleware.

## Overview

WheelDriver enables players to use real gaming hardware like steering wheels, joysticks, and other controllers to drive vehicles in Roblox. This system bridges the hardware inputs with Roblox's vehicle system using a local web server as middleware.

## Components

### 1. Python Server (`Server.py`)
- Flask web server with Socket.IO for real-time communication
- Joystick/wheel input detection and mapping
- Vehicle state management and input processing
- Connection status monitoring

### 2. Web Interface (`templates/index.html`)
- Control device selection
- Button and axis mapping interface
- Real-time vehicle status display
- Connection monitoring for Roblox and the controller
- Debug information panel

### 3. Roblox Client Script (`Client.lua`)
- HTTP communication with the Python server
- Vehicle control application
- Smooth input handling
- Heartbeat system for connection monitoring

## Setup Instructions

### Prerequisites
- Python 3.8+
- Flask and Flask-SocketIO
- PyGame library
- Web browser
- Roblox Studio
- A supported joystick or steering wheel

### Installation

1. Install required Python packages:
   ```
   pip install flask flask-socketio pygame
   ```

2. Clone or download this repository to your local machine.

3. Configure the server address:
   - Edit `Client.lua` and update the `serverUrl` to match your computer's local IP address.

### Usage

1. Start the Python server:
   ```
   python Server.py
   ```

2. Open a web browser and navigate to `http://localhost:5000`

3. Insert the `Client.lua` script into a Roblox VehicleSeat in Studio.

4. Select your joystick/wheel from the dropdown menu in the web interface.

5. Map the controls by clicking the mapping buttons and moving the corresponding axis or pressing the desired button.

6. Test drive in Roblox!

## Control Mapping

The system supports mapping:
- **Steering**: Maps to a joystick axis (usually horizontal movement)
- **Throttle**: Maps to a joystick axis (usually vertical movement)
- **Brake/Handbrake**: Maps to a button press

## Troubleshooting

### Connection Issues
- Verify your firewall allows connections to the port (default: 5000)
- Check that Roblox HTTP requests are enabled in your game
- Ensure the server IP address is correctly set in the Lua script

### Input Lag or Freezing
- Reduce polling frequency in the Lua script by increasing `pollRate`
- Use `threading` mode if `eventlet` causes issues
- Check if multiple Roblox instances are connecting simultaneously

### Mapping Problems
- Some controllers may have axis numbering that differs from what's expected
- Use the debug info panel to see detected axes and buttons
- Try disconnecting and reconnecting your controller if it's not detected

## Technical Details

### Network Protocol
- HTTP for basic state exchange
- Socket.IO for real-time updates and connection status
- Throttled requests to prevent Roblox HTTP service limits

### Input Processing
- Input smoothing for joystick movements
- Change detection to minimize network traffic
- Request queue system to prevent overwhelming the server

## Credits

Created by Zia

## License

This project is licensed under the MIT License - see the LICENSE file for details.
