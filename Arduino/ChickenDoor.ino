/* 
    Remote controlled chicken shed door
    (*) Magnetic relay for sensing door closed
    (*) LED indicating door closed
    (*) Adafruit Motorshield v2 with step motor to control door
    (*) Relay to control external power supply to the motorshield, since the step motor heats up excessively even when idle
    (*) Load sensor for detecting water level
	
	Hardware:
	(*) Arduino Uno
	(*) Adafruit Motorshield v2 (Adafruit)
	(*) Adafruit Huzzah ESP8266 breakout
	(*) Sparkfun HX711 Load Cell Amplifier
	(*) Generic 10kg Load Cell
	(*) Mercury Motor SM-42BYG011-25 1812010
	(*) PCB Relay
	(*) Magnetic Relay
	
	Referenced libraries:
	(*) Adafruit MotorShield v2 library (https://learn.adafruit.com/adafruit-motor-shield-v2-for-arduino/install-software): Interfacing with the Adafruit Motorshield v2
	(*) Sparkfun HX711 code samples for calibrating and using the load sensor (https://github.com/sparkfun/HX711-Load-Cell-Amplifier):  Class for interfacing with the load cell amplifier
	(*) TimerObject (http://playground.arduino.cc/Code/ArduinoTimerObject): Setting interval timers. Useful for an LED that flashes very briefly every few seconds
	
	
	Author: Ryan Steller
	Blog: https://debugtopinpoint.wordpress.com/
*/
#include <SoftwareSerial.h>
#include <Wire.h>
#include <Adafruit_MotorShield.h>
#include "utility/Adafruit_MS_PWMServoDriver.h"
#include "TimerObject.h"
#include "HX711.h"

// Create the motor shield object with the default I2C address
Adafruit_MotorShield AFMS = Adafruit_MotorShield();

// Connect a stepper motor with 200 steps per revolution (1.8 degree) to motor port #1 (M1 and M2)
Adafruit_StepperMotor *myMotor = AFMS.getStepper(200, 1);

// MotorShield power pin (controls the relay)
int afmsPowerPin = 6;

// Magnetic relay switch - for detecting door closed
int isDoorClosedPin = 4;
bool isDoorClosed = true;

// LED flashes regularly to indicate that the door is closed
int ledPin = 5;
bool isLedOn = false;
TimerObject *ledOnTimer = new TimerObject(2000); // will call the callback in the interval
TimerObject *ledOffTimer = new TimerObject(50); // will call the callback in the interval

// Load sensor - water level (the load cell amplifier chip communicates through the DOUT and CLK pins
#define water_calibration_factor -213000 // This value is obtained using the SparkFun_HX711_Calibration sketch
#define water_zero_factor -135386 // This large value is obtained using the SparkFun_HX711_Calibration sketch
#define water_DOUT  2
#define water_CLK  7
HX711 waterscale(water_DOUT, water_CLK);
float currentWaterKg = 0;
TimerObject *sensorCheckerTimer = new TimerObject(100); // Check sensors like water level (load sensor), door closed relay, ...

// Serial interface for talking to the HUZZAH ESP8266 wifi chip
SoftwareSerial wifiSerial(10, 11); // RX, TX
TimerObject *updateWifiChipTimer = new TimerObject(5000); // Wifi chip variable updater -- pushes the state of variables to the wifi chip to keep it updated

// Incoming commands (from PC hardware serial OR from the wifi chip SoftwareSerial)
String cmd = "";

int stepsPerRotation = 200;
float stepsToOpenDoor = (float(stepsPerRotation)*float(200)); //200 steps per rotation -- (290 rotations is about 37cm).
String currentStatus = "Idle";
float currentPosition = 0; // The number of steps opened from a closed position (0)

void setup() {
  // Standard serial port
  Serial.begin(9600);           // set up Serial library at 9600 bps
  Serial.println("START Chicken door test");
  
  // Wifi serial port
  wifiSerial.begin(9600);

  AFMS.begin(200);  // default frequency 1.6KHz (1600)

  // Magnetic relay switch
  pinMode(isDoorClosedPin, INPUT_PULLUP);

  // AFMS Power pin (controls the relay switch providing power to the AFMS)
  pinMode(afmsPowerPin, OUTPUT);
  digitalWrite(afmsPowerPin, HIGH); // Off by default
  
  // Door closed indicator LED
  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW); // Off by default

  // Load sensor - water level
  waterscale.set_scale(water_calibration_factor); //This value is obtained by using the SparkFun_HX711_Calibration sketch
  waterscale.set_offset(water_zero_factor); //Zero out the scale using a previously known zero_factor
  
  myMotor->setSpeed(250);  // rpm

  // Check door position on startup: is it closed?
  isDoorClosed = digitalRead(isDoorClosedPin) == LOW;
  if(!isDoorClosed) {
    // On startup if the door is not closed, then assume there was a power failure and it was left fully open
    currentPosition = stepsToOpenDoor;
  }

  ledOnTimer->setOnTimer(&ToggleDoorStatusLed);
  ledOnTimer->Start(); // start the thread.
  ledOffTimer->setOnTimer(&ToggleDoorStatusLed);

  sensorCheckerTimer->setOnTimer(&CheckSensors);
  sensorCheckerTimer->Start();

  
  updateWifiChipTimer->setOnTimer(&SendVariablesToWifi);

  Serial.println("stepsToOpenDoor: " + String(stepsToOpenDoor));
  
  // Restart wifi on startup. This is done in case the arduino restarts but the wifi chip doesn't.
  // It would need the wifi chip to reboot as well, so then the wifi chip will request updated variables, and this kicks off the interval to keep updating the variables on the wifi chip
  Serial.println("Send nodeMCU script to restart wifi");
  SendCmdToWifi("node.restart()");
}

void loop() { 
  // LED Flashing to indicate the door is closed
  ledOnTimer->Update();
  ledOffTimer->Update();
  updateWifiChipTimer->Update();
  sensorCheckerTimer->Update();
   
  cmd = "";
  // Output to serial for debuging (commands from the wifi chip or from PC)
  if (wifiSerial.available()) {
    cmd = wifiSerial.readString();
    Serial.println("Wifi: " + cmd);
  }
  else if (Serial.available()) {
    cmd = Serial.readString();
    Serial.println("PC: " + cmd);
  }
  
  // Process the commands (normally coming from wifi)
  // (*) Update the wifi chip with the latest status
  // (*) Move the motor according to the command
  if(cmd.startsWith("OpenDoor")) {
    MoveDoor(FORWARD, stepsToOpenDoor);
  }
  else if(cmd.startsWith("CloseDoor")) {
    MoveDoor(BACKWARD, stepsToOpenDoor);
  }
  else if(cmd.startsWith("CloseHalfRotation")) {
    MoveDoor(BACKWARD, 100); // Half rotation
  }
  else if(cmd.startsWith("OpenHalfRotation")) {
    MoveDoor(FORWARD, 100); // Half rotation
  }
  else if(cmd.startsWith("RestartWifi")) {
    Serial.println("Restart wifi");
    SendCmdToWifi("node.restart()");
  }
  else if(cmd.startsWith("SendCurrentVariablesToWifi")) {
    // The wifi chip sends this command 10 seconds after it is ready. After this point, keep pushing updated variables to the chip at a regular interval
    Serial.println("Update the variables on the wifi");
    updateWifiChipTimer->Start();
    SendVariablesToWifi();
  }
  else if(cmd.startsWith("GetStatus")) {
    Serial.println("Position: " + String(currentPosition/stepsToOpenDoor*100) + "% (" + String(currentPosition) + ")");
  }
  else if(cmd.startsWith("GetWaterlevel")) {
    Serial.println(String(currentWaterKg) + " kg");
  }
  else {
    // Pass this message to the wifi chip
    //SendCmdToWifi(cmd);
  }
}

// Move door open or closed and keep the wifi chip informed
// (*) If the door reaches the closed position it will not close any further
void MoveDoor(uint8_t dir, float steps) {
  String strDirection = "";
  if (dir == FORWARD) { 
    strDirection = "open";
    currentStatus = "Opening";
  }
  else if (dir == BACKWARD) {
    strDirection = "close";
    currentStatus = "Closing";
  }
  if(dir == FORWARD || dir == BACKWARD) {
    SendVariablesToWifi();
    Serial.flush();
    
    // Enable power on the AFMS motor shield
    digitalWrite(afmsPowerPin, LOW);
    delay(1000);

    // Every 10 steps, perform checks
  // (*) Check if the door has reached a closed position with the magnetic relay (while closing)
  // (*) Check if the StopDoor command has been received
    int stepsPerChunk = 10;
    int moveChunks = steps / stepsPerChunk; // Steps must be multiples of 10, otherwise the door could be out by a few steps each time since this is dividing integers
    Serial.println("Move " + strDirection + " - chunks: " + String(moveChunks));
    
    for(int i = 0; i < moveChunks; i++) {
      if(i > 0 && i % 200 == 0) {
        // Keep the wifi chip updated on the current position every 200*10 steps (every 5%)
        Serial.println(String(currentPosition/stepsToOpenDoor*100) + "% open");
        SendVariablesToWifi(false);
      }
    
    //Serial.println(String(i));
    sensorCheckerTimer->Update(); // Ensure the sensor checks are still occuring during this loop as we need to know if the door closed
    
      if(i % 10 == 0) {
        // Check if the StopDoor command has been received (it would be sitting in the serial buffer)
        cmd = "";
        if (wifiSerial.available()) {
          cmd = wifiSerial.readString();
        }
    else if (Serial.available()) {
      cmd = Serial.readString();
    }
        if(cmd.startsWith("StopDoor")) {
          Serial.println("Stopped.");
          break;
        }
      }
      if(isDoorClosed && dir == BACKWARD) {
        Serial.println("Close detected.");
        // The door reached a closed position while closing. Stop moving, and ensure that the currentPosition variable is set to zero.
        currentPosition = 0;
        break;
      }
      else {
        // Not closed while closing? continue with stepper rotation.
        if(dir == FORWARD && currentPosition >= stepsToOpenDoor) {
          // Has the door reached the fully open position?
          Serial.println("Fully open.");
          break;
        }
        else {
          // Door is neither open nor closed. Continue rotating.
          myMotor->step(stepsPerChunk, dir, DOUBLE);
          if(dir == FORWARD) {
            currentPosition = currentPosition + stepsPerChunk;
          }
          else if(dir == BACKWARD) {
            currentPosition = currentPosition - stepsPerChunk;
          }
        }
      }
    }
    
    // Release the stepper from holding its position
    myMotor->release();

    // Disable power on the AFMS motor shield
    delay(500);
    digitalWrite(afmsPowerPin, HIGH);

    // While the motor was in motion, commands may have been sent to arduino and are sitting in the serial buffer. Clear it as repeat commands may have been sent by mistake.
    if (wifiSerial.available()) {
      wifiSerial.readString();
    }
    
    Serial.println("Complete. " + String(currentPosition/stepsToOpenDoor*100) + "% open");
    currentStatus = "Idle";
    SendVariablesToWifi();
  }
}

// This function enables the LED to flash briefly every x milliseconds
void ToggleDoorStatusLed() {
  if(isLedOn) {
    digitalWrite(ledPin, LOW);
    isLedOn = false;
    ledOffTimer->Stop();
  }
  else if(!isLedOn && isDoorClosed) {
    // Start LED indications if the door is closed only
    digitalWrite(ledPin, HIGH);
    isLedOn = true;
    ledOffTimer->Start(); // Start the thread to ensure the light is turned off again
  }
}

// Check sensors - called at a regular interval. It is done like this beacuse some sensors may return a false positive e.g. the magnetic door sensor. This way we can minimise it by keeping track of previous readings.
// (*) Water level (load sensor)
// (*) Door closed (magnetic relay)
bool isDoorClosedReadings[10] = { false, true, false, true, false, false, true, false, true, false };
uint8_t isDoorClosedReadingIndex = 0;

void CheckSensors() {
  // Water level
  currentWaterKg = waterscale.get_units();
  
  // Door closed detection: because the wire is so long (1m), interference can cause false positives. This occurs more in hotter weather e.g. at 39 degrees C false positives occur many times a second.
  // Therefore, a state change will only be recorded if the same result occurs 10 times in a row (1 full second).
  isDoorClosedReadings[isDoorClosedReadingIndex] = digitalRead(isDoorClosedPin) == LOW;
  
  //Serial.println(String(isDoorClosedReadingIndex) + " - " + String(isDoorClosedReadings[isDoorClosedReadingIndex]));
  
  // Check the last second of readings and if they are all the same, change state
  bool wasDoorClosed = isDoorClosed;
  bool isOpen = true;
  bool isClosed = true;
  for(int i=0; i<10; i++) {
    int checkIndex = isDoorClosedReadingIndex - i;
    if(checkIndex < 0) {
      checkIndex += 10;
    }
    isOpen = isOpen && !isDoorClosedReadings[checkIndex];
    isClosed = isClosed && isDoorClosedReadings[checkIndex];
  }
  
  // Did the state change?
  if(!wasDoorClosed && isClosed) {
    isDoorClosed = true;
    currentPosition = 0;
    Serial.println("Door close detected.");
  }
  else if(wasDoorClosed && isOpen) {
    isDoorClosed = false;
    Serial.println("Door open detected.");
  }
  // Increment the index for the next reading capture
  if(isDoorClosedReadingIndex >=9) {
    isDoorClosedReadingIndex = 0;
  }
  else {
    isDoorClosedReadingIndex++;
  }
}

void SendVariablesToWifi() {
  SendVariablesToWifi(false);
}

// SendCurrentVariablesToWifi
void SendVariablesToWifi(bool withDelay) {
  // Send variables to wifi: status, door position, water level kg, water level %
  SendCmdToWifi("updateVariables(\"" + currentStatus + "\", \"" + String(currentPosition/stepsToOpenDoor*100) + "\", \"" + String(currentWaterKg) + "\", \"" + String(currentWaterKg) + "\")", withDelay);
}

void SendCmdToWifi(String str) {
  SendCmdToWifi(str, true);
}

// Send command to wifi chip. Allow some delay time for it to read each command from serial as a separate string.
void SendCmdToWifi(String str, bool withDelay) {
  Serial.println("* RAM: " + String(freeRam()));
  Serial.println("Send to wifi:");
  Serial.println(str);
  wifiSerial.print(str);
  wifiSerial.write("\r\n");
  if(withDelay){
    delay(500);
  }
}

int freeRam () {
    extern int __heap_start, *__brkval;
    int v;
    return (int) &v - (__brkval == 0 ? (int) &__heap_start : (int) __brkval);
}

