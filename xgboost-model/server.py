from flask import Flask, request, jsonify
from flask_cors import CORS
import pandas as pd
from datetime import date, timedelta
import joblib
import os

from my_restaurant_advisor import predict, load_model, ITEM_CATEGORY, ALL_ITEMS, AREA_MAP, WEATHER_MAP

app = Flask(__name__)
CORS(app)

# Load model on startup
print("Loading XGBoost model...")
try:
    model, encoders = load_model()
    print("Model loaded successfully!")
except Exception as e:
    print(f"Error loading model: {e}")
    model, encoders = None, None

@app.route('/predict', methods=['POST'])
def predict_endpoint():
    if model is None or encoders is None:
        return jsonify({"error": "Model not loaded on server."}), 500

    data = request.json
    if not data or 'items' not in data:
        return jsonify({"error": "Invalid payload. 'items' list required."}), 400

    predictions = {}
    items_list = data['items']

    for item_data in items_list:
        item_name = item_data.get('name')
        qty_prep = item_data.get('qty_prep', 0)
        avg_wastage_7d = item_data.get('avg_wastage_7d', 0)

        # Default to some category if not found
        food_category = ITEM_CATEGORY.get(item_name, 'North Indian Curry') 

        # Build input dict
        # Hardcoded: Malleshwaram (Area 7), Sunny (Weather 1 -> Clear)
        area_name, area_type_name = AREA_MAP['7']
        weather_name = WEATHER_MAP['1']

        inputs = {
            'area_name': area_name,
            'area_type_name': area_type_name,
            'food_item': item_name,
            'food_category': food_category,
            'qty_prep': int(qty_prep),
            'avg_wastage_7d': float(avg_wastage_7d),
            'weather_name': weather_name,
        }

        try:
            # If the item wasn't in the original training data's label encoder, it will throw an error
            # We can skip or return 0
            if item_name not in ALL_ITEMS:
                print(f"Item '{item_name}' not in training data vocabulary. Skipping prediction.")
                continue

            result = predict(model, encoders, inputs)
            predictions[item_name] = result['ideal_prep']
        except Exception as e:
            print(f"Prediction failed for {item_name}: {e}")
            continue

    return jsonify({"predictions": predictions})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
