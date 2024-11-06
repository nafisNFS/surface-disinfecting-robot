import cv2
import numpy as np
import urllib.request
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import time
import os

# Constants
url = 'http://192.168.159.138/cam-hi.jpg'
whT = 320
confThreshold = 0.5
nmsThreshold = 0.3

# Email Configuration for Outlook
smtp_server = 'smtp-mail.outlook.com'
smtp_port = 587
sender_email = 'smnafisofficial@outlook.com'
sender_password = 'use your pass'  # Use your Outlook account password or an app-specific password if available.
receiver_email = 'smnafisofficial@gmail.com'

# Load class names
classesfile = 'coco.names'
classNames = []
with open(classesfile, 'rt') as f:
    classNames = f.read().rstrip('\n').split('\n')

# Load model configuration and weights
modelConfig = 'yolov3.cfg'
modelWeights = 'yolov3.weights'
net = cv2.dnn.readNetFromDarknet(modelConfig, modelWeights)
net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)

# List of living beings
living_beings = ["person", "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe"]

# Timestamp to track the last email sent time
last_email_time = 0


# Function to send an email notification with an image attachment
def send_email_notification(living_being, image_path):
    global last_email_time
    current_time = time.time()

    # Check if the last email was sent within the last minute
    if current_time - last_email_time < 60:
        print(f"Email not sent. Waiting for cooldown period to pass.")
        return

    subject = f"Alert: {living_being.upper()} Detected!"
    body = f"A {living_being.upper()} has been detected by your camera."

    # Create the email
    msg = MIMEMultipart()
    msg['From'] = sender_email
    msg['To'] = receiver_email
    msg['Subject'] = subject
    msg.attach(MIMEText(body, 'plain'))

    # Attach the image file
    attachment = open(image_path, 'rb')
    part = MIMEBase('application', 'octet-stream')
    part.set_payload(attachment.read())
    encoders.encode_base64(part)
    part.add_header('Content-Disposition', f'attachment; filename= {os.path.basename(image_path)}')
    msg.attach(part)
    attachment.close()

    # Send the email
    try:
        server = smtplib.SMTP(smtp_server, smtp_port)
        server.starttls()
        server.login(sender_email, sender_password)
        text = msg.as_string()
        server.sendmail(sender_email, receiver_email, text)
        server.quit()
        last_email_time = current_time
        print(f"Notification sent for {living_being} with image attached")
    except Exception as e:
        print(f"Failed to send email notification: {str(e)}")


def findObject(outputs, img):
    hT, wT, _ = img.shape
    bbox = []
    classIds = []
    confs = []
    detected_living_being = None

    for output in outputs:
        for det in output:
            scores = det[5:]
            classId = np.argmax(scores)
            confidence = scores[classId]
            if confidence > confThreshold:
                w, h = int(det[2] * wT), int(det[3] * hT)
                x, y = int((det[0] * wT) - w / 2), int((det[1] * hT) - h / 2)
                bbox.append([x, y, w, h])
                classIds.append(classId)
                confs.append(float(confidence))

    indices = cv2.dnn.NMSBoxes(bbox, confs, confThreshold, nmsThreshold)
    print(indices)

    for i in indices:
        box = bbox[i]
        x, y, w, h = box
        className = classNames[classIds[i]]

        if className in living_beings:
            detected_living_being = className

        cv2.rectangle(img, (x, y), (x + w, y + h), (255, 0, 255), 2)
        cv2.putText(img, f'{className.upper()} {int(confs[i] * 100)}%', (x, y - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 255), 2)

    # Display warning and send email if a living being is detected
    if detected_living_being:
        cv2.putText(img, f"WARNING: {detected_living_being.upper()} is nearby!", (50, 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 3)

        # Save the image with detections
        image_path = f"detected_{detected_living_being}.jpg"
        cv2.imwrite(image_path, img)

        # Send email with the image attached
        send_email_notification(detected_living_being, image_path)


while True:
    img_resp = urllib.request.urlopen(url)
    imgnp = np.array(bytearray(img_resp.read()), dtype=np.uint8)
    img = cv2.imdecode(imgnp, -1)

    blob = cv2.dnn.blobFromImage(img, 1 / 255, (whT, whT), [0, 0, 0], 1, crop=False)
    net.setInput(blob)
    layernames = net.getLayerNames()
    outputNames = [layernames[i - 1] for i in net.getUnconnectedOutLayers()]

    outputs = net.forward(outputNames)

    findObject(outputs, img)

    cv2.imshow('Image', img)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cv2.destroyAllWindows()
