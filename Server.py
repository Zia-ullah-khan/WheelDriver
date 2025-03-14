from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit # type: ignore
import pygame
import threading
import time
import queue

app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

pygame.init()
pygame.joystick.init()

selected_joystick = None
control_mapping = {"steering": None, "throttle": None, "brake": None}
latest_controls = {"Throttle": 0, "Steering": 0, "Handbrake": False}
last_roblox_heartbeat = None

last_roblox_heartbeat = time.time()
print("Server initialized with default heartbeat timestamp")

vehicle_state_queue = queue.Queue(maxsize=5)

@app.route("/")
def index():
    return render_template("index.html", joysticks=get_available_joysticks())

def get_available_joysticks():
    pygame.joystick.quit()
    pygame.joystick.init()
    return [pygame.joystick.Joystick(i).get_name() for i in range(pygame.joystick.get_count())]

@app.route("/roblox_heartbeat", methods=["POST"])
def roblox_heartbeat():
    global last_roblox_heartbeat
    last_roblox_heartbeat = time.time()
    print(f"Received heartbeat from Roblox at {time.strftime('%H:%M:%S')}")
    return jsonify({"status": "ok", "timestamp": last_roblox_heartbeat})

@socketio.on("check_roblox_connection")
def check_roblox_connection():
    global last_roblox_heartbeat
    now = time.time()
    
    if last_roblox_heartbeat is None:
        last_roblox_heartbeat = now
        
    connected = (now - last_roblox_heartbeat < 10)
    
    emit("roblox_connection_status", {
        "connected": connected, 
        "last_heartbeat": last_roblox_heartbeat,
        "now": now,
        "diff": now - last_roblox_heartbeat
    })
    
    print(f"Roblox connection status check: {'Connected' if connected else 'Disconnected'} (Last heartbeat: {round(now - last_roblox_heartbeat, 2)}s ago)")

@app.route("/controls", methods=["GET"])
def get_controls():
    if not hasattr(get_controls, 'counter'):
        get_controls.counter = 0
    get_controls.counter += 1
    
    if get_controls.counter % 50 == 0:
        print(f"Served {get_controls.counter} control requests")
    
    return jsonify(latest_controls)

def process_vehicle_updates():
    while True:
        try:
            data = vehicle_state_queue.get(timeout=0.2)
            socketio.emit("vehicle_state", data)
            vehicle_state_queue.task_done()
        except queue.Empty:
            pass
        time.sleep(0.01)

@app.route("/update_controls", methods=["POST"])
def update_controls():
    global latest_controls
    try:
        data = request.get_json()
        
        if not hasattr(update_controls, 'counter'):
            update_controls.counter = 0
            update_controls.last_log = time.time()
        update_controls.counter += 1
        
        if time.time() - update_controls.last_log > 10:
            print(f"Received {update_controls.counter} vehicle updates in the last 10 seconds")
            update_controls.counter = 0
            update_controls.last_log = time.time()
        
        if 'CurrentSpeed' in data or 'Occupied' in data:
            try:
                if not vehicle_state_queue.full():
                    vehicle_state_queue.put_nowait(data)
            except queue.Full:
                pass
        else:
            latest_controls.update(data)
            
        return jsonify({"status": "updated"})
    except Exception as e:
        print(f"Error processing update: {str(e)}")
        return jsonify({"error": str(e)}), 400

@socketio.on("select_joystick")
def select_joystick(index):
    global selected_joystick
    selected_joystick = int(index)
    print(f"Joystick {selected_joystick} selected")
    
    global control_mapping
    control_mapping = {"steering": None, "throttle": None, "brake": None}
    
    try:
        joystick = pygame.joystick.Joystick(selected_joystick)
        joystick.init()
        print(f"Joystick has {joystick.get_numaxes()} axes and {joystick.get_numbuttons()} buttons")
        
        socketio.emit("joystick_info", {
            "name": joystick.get_name(),
            "axes": joystick.get_numaxes(),
            "buttons": joystick.get_numbuttons()
        })
    except Exception as e:
        print(f"Error initializing joystick: {str(e)}")

@socketio.on("update_mapping")
def update_mapping(data):
    global control_mapping
    
    valid_types = ["steering", "throttle", "brake"]
    for map_type, value in data.items():
        if map_type in valid_types:
            try:
                value = int(value)
                
                if map_type == "brake":
                    if selected_joystick is not None:
                        joystick = pygame.joystick.Joystick(selected_joystick)
                        if value < joystick.get_numbuttons():
                            control_mapping[map_type] = value
                            print(f"Mapped {map_type} to button {value}")
                        else:
                            print(f"Invalid button index: {value}")
                else:
                    if selected_joystick is not None:
                        joystick = pygame.joystick.Joystick(selected_joystick)
                        if value < joystick.get_numaxes():
                            control_mapping[map_type] = value
                            print(f"Mapped {map_type} to axis {value}")
                        else:
                            print(f"Invalid axis index: {value}")
            except (ValueError, pygame.error) as e:
                print(f"Error validating mapping: {str(e)}")
    
    print("Updated control mapping:", control_mapping)
    socketio.emit("mapping_updated", control_mapping)

def joystick_listener():
    global latest_controls
    last_values = {"Steering": 0, "Throttle": 0, "Brake": 0, "Handbrake": False}
    
    while True:
        pygame.event.pump()
        if selected_joystick is not None:
            try:
                joystick = pygame.joystick.Joystick(selected_joystick)
                joystick.init()

                changed = False
                
                if control_mapping["steering"] is not None:
                    try:
                        new_steering = round(joystick.get_axis(control_mapping["steering"]), 2)
                        if abs(new_steering - last_values["Steering"]) > 0.01:
                            latest_controls["Steering"] = new_steering
                            last_values["Steering"] = new_steering
                            changed = True
                    except Exception as e:
                        print(f"Error reading steering: {e}")

                if control_mapping["throttle"] is not None:
                    try:
                        raw_value = joystick.get_axis(control_mapping["throttle"])
                        
                        new_throttle = max(0, round(raw_value, 2))
                        
                        new_brake = max(0, round(-raw_value, 2)) 
                        
                        if abs(new_throttle - last_values["Throttle"]) > 0.01:
                            latest_controls["Throttle"] = new_throttle
                            last_values["Throttle"] = new_throttle
                            changed = True
                            
                        if abs(new_brake - last_values["Brake"]) > 0.01:
                            latest_controls["Brake"] = new_brake
                            last_values["Brake"] = new_brake
                            changed = True
                    except Exception as e:
                        print(f"Error reading throttle/brake: {e}")

                if control_mapping["brake"] is not None:
                    try:
                        new_handbrake = bool(joystick.get_button(control_mapping["brake"]))
                        if new_handbrake != last_values["Handbrake"]:
                            latest_controls["Handbrake"] = new_handbrake
                            last_values["Handbrake"] = new_handbrake
                            changed = True
                    except Exception as e:
                        print(f"Error reading brake button: {e}")
                        
                if changed:
                    if hasattr(joystick_listener, 'debug_counter'):
                        joystick_listener.debug_counter += 1
                    else:
                        joystick_listener.debug_counter = 0
                        
                    if joystick_listener.debug_counter % 100 == 0:
                        print(f"Current controls: {latest_controls}, Mapping: {control_mapping}")
                        
                    socketio.emit("control_update", latest_controls)
                    
            except pygame.error as e:
                print(f"Joystick error: {e}, resetting...")
                pygame.joystick.quit()
                pygame.joystick.init()
            
        time.sleep(0.01)

joystick_thread = threading.Thread(target=joystick_listener, daemon=True)
joystick_thread.start()

vehicle_processor_thread = threading.Thread(target=process_vehicle_updates, daemon=True)
vehicle_processor_thread.start()

def cleanup():
    pygame.quit()
    print("Pygame cleaned up. Exiting safely.")

import atexit
atexit.register(cleanup)

if __name__ == "__main__":
    print("Starting server with threading mode...")
    socketio.run(app, host="0.0.0.0", port=5000, debug=False)
