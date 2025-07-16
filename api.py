from flask import Flask, request, jsonify
from tensorflow.keras.preprocessing import image
from tensorflow.keras.models import load_model
import numpy as np
from io import BytesIO
import sqlite3
from datetime import datetime

app = Flask(__name__)

# Load model and breed names
model = load_model("dog_breed_classifier.h5")
with open("breed_names.txt", "r") as f:
    breed_names = [line.strip() for line in f]

# Initialize SQLite database
def init_db():
    conn = sqlite3.connect('feedback.db')
    c = conn.cursor()
    
    # Create table if it doesn't exist
    c.execute('''CREATE TABLE IF NOT EXISTS feedback
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  image BLOB,
                  correct_breed TEXT,
                  timestamp TEXT)''')
    
    # Check if original_top_breed column exists and add it if not
    c.execute("PRAGMA table_info(feedback)")
    columns = [col[1] for col in c.fetchall()]
    if 'original_top_breed' not in columns:
        c.execute('''ALTER TABLE feedback ADD COLUMN original_top_breed TEXT''')
    
    conn.commit()
    conn.close()

init_db()

img_size = 224

@app.route('/predict', methods=['POST'])
def predict_breed():
    try:
        # Check if an image file was uploaded
        if 'image' not in request.files:
            return jsonify({'error': 'No image file provided'}), 400
        
        file = request.files['image']
        if file.filename == '':
            return jsonify({'error': 'No image selected'}), 400

        # Process the image directly from memory
        img = image.load_img(BytesIO(file.read()), target_size=(img_size, img_size))
        img_array = image.img_to_array(img) / 255.0
        img_array = np.expand_dims(img_array, axis=0)

        # Make prediction
        preds = model.predict(img_array)[0]
        top_indices = preds.argsort()[-5:][::-1]

        # Check if top prediction is below 50%
        top_confidence = preds[top_indices[0]] * 100
        if top_confidence < 50:
            return jsonify({
                'status': 'error',
                'error': 'Top prediction confidence is below 50%'
            }), 400

        # Format predictions as JSON with 2 decimal places
        predictions = [
            {
                'breed': breed_names[i],
                'confidence': round(float(preds[i] * 100), 2)
            } for i in top_indices
        ]

        return jsonify({
            'status': 'success',
            'predictions': predictions
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/feedback', methods=['POST'])
def submit_feedback():
    try:
        # Check if required data is provided
        if 'image' not in request.files or 'correct_breed' not in request.form:
            return jsonify({'error': 'Image and correct breed are required'}), 400

        file = request.files['image']
        correct_breed = request.form['correct_breed']
        original_top_breed = request.form.get('original_top_breed', '')

        # Validate breed
        if correct_breed not in breed_names:
            return jsonify({'error': 'Invalid breed name'}), 400

        # Read image as bytes
        image_data = file.read()

        # Store feedback in SQLite
        conn = sqlite3.connect('feedback.db')
        c = conn.cursor()
        c.execute('''INSERT INTO feedback (image, correct_breed, original_top_breed, timestamp)
                     VALUES (?, ?, ?, ?)''',
                  (image_data, correct_breed, original_top_breed, datetime.now().isoformat()))
        conn.commit()
        conn.close()

        return jsonify({'status': 'success', 'message': 'Feedback submitted successfully'})

    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', debug=True)