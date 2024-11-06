from flask import Flask, request, jsonify
import numpy as np
import cv2

from test import classNames

app = Flask(__name__)

# Load model configuration and weights
whT = 320
confThreshold = 0.5
nmsThreshold = 0.3

modelConfig = 'yolov3.cfg'
modelWeights = 'yolov3.weights'
net = cv2.dnn.readNetFromDarknet(modelConfig, modelWeights)
net.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
net.setPreferableTarget(cv2.dnn.DNN_TARGET_CPU)

# List of living beings
living_beings = ["person", "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe"]


@app.route('/detect', methods=['POST'])
def detect():
    if 'image' not in request.files:
        return jsonify({'error': 'No image part'}), 400

    file = request.files['image']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    if file:
        img = np.frombuffer(file.read(), np.uint8)
        img = cv2.imdecode(img, cv2.IMREAD_COLOR)

        if img is None:
            return jsonify({'error': 'Invalid image format'}), 400

        blob = cv2.dnn.blobFromImage(img, 1 / 255, (whT, whT), [0, 0, 0], 1, crop=False)
        net.setInput(blob)
        layernames = net.getLayerNames()
        outputNames = [layernames[i - 1] for i in net.getUnconnectedOutLayers()]

        outputs = net.forward(outputNames)
        findObject(outputs, img)

        _, img_encoded = cv2.imencode('.jpg', img)
        return img_encoded.tobytes(), 200, {'Content-Type': 'image/jpeg'}

    return jsonify({'error': 'Invalid request'}), 400


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

    for i in indices:
        box = bbox[i]
        x, y, w, h = box
        className = classNames[classIds[i]]

        if className in living_beings:
            detected_living_being = className

        cv2.rectangle(img, (x, y), (x + w, y + h), (255, 0, 255), 2)
        cv2.putText(img, f'{className.upper()} {int(confs[i] * 100)}%', (x, y - 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 255), 2)

    if detected_living_being:
        cv2.putText(img, f"WARNING: {detected_living_being.upper()} is nearby!", (50, 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 255), 3)

        # Save the image with detections
        image_path = f"detected_{detected_living_being}.jpg"
        cv2.imwrite(image_path, img)

        # Optionally send email notification here


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
