# ChickenShed
Arduino and wifi enabled chicken shed with automatic control and email notifications.

Blog: https://debugtopinpoint.wordpress.com/2017/04/08/iot-chicken-shed-arduino-wifi

Features

- Control the door and check how much water is left through a basic website hosted on the chip itself (HTML, and RESTful)
- Prevent over-closing or over-opening
- Can recover from power cut outs
- Can recover from wifi chip reboots or network disruption
- Flash LED every few seconds to indicate that the door is closed
- Fox proof: Can’t be pushed open while closed
- Automatically operated by a script (open 30 minutes after sunrise, close at sunset based on your location)
- Email alerts for open/closes, failures, water low and water empty
- Can be exposed over the internet via VPN
