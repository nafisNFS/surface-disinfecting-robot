int ledPin = 13;    // Pin for the LED
int pirPin = 2;     // Pin for the PIR sensor
int inputPin = 8;   // Pin to receive the signal from Arduino 1
int motorPin = 9;   // Pin to control the motor via relay
int pirState = LOW; // Start with no motion detected
int val;            // Variable to store PIR sensor reading

void setup() {
  pinMode(ledPin, OUTPUT);      
  pinMode(pirPin, INPUT);    
  pinMode(inputPin, INPUT);    
  pinMode(motorPin, OUTPUT);   // Motor control pin
  Serial.begin(9600);          // For Bluetooth communication via TX/RX
}

void loop() {
  int signalFromArduino1 = digitalRead(inputPin); // Read the signal from Arduino 1
  val = digitalRead(pirPin);                      // Read the PIR sensor

  String carStatus = "Not at Home";
  String motionStatus = "No Motion";

  if (signalFromArduino1 == LOW) {
    // Signal from Arduino 1 is LOW, car is at home, turn OFF the motor
    digitalWrite(motorPin, LOW);  // Motor OFF
    carStatus = "At Home";

    if (pirState == LOW) {
      pirState = HIGH;
    }
  } else {
    // Signal from Arduino 1 is HIGH, car is not at home, turn ON the motor
    digitalWrite(motorPin, HIGH);  // Motor ON
    carStatus = "Not at Home";

    if (val == HIGH) {
      digitalWrite(ledPin, LOW);  // Turn off the LED if motion is detected
      motionStatus = "Motion Detected";
      if (pirState == LOW) {
        pirState = HIGH;
      }
    } else {
      digitalWrite(ledPin, HIGH); // Keep the LED on if no motion is detected
      motionStatus = "No Motion";
      if (pirState == HIGH) {
        pirState = LOW;
      }
    }
  }

  // Transmit car status and motion status via Bluetooth
  Serial.print("CarStatus:");
  Serial.print(carStatus);
  Serial.print(",MotionStatus:");
  Serial.println(motionStatus);

  delay(1000); // Delay to reduce the frequency of transmissions
}